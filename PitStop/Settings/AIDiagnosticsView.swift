import SwiftUI

/// Settings → AI: shows how the app connects to Gemini and runs live checks of the three building
/// blocks (structured JSON, function calling, and the fallback path), so setup problems surface
/// before the demo.
struct AIDiagnosticsView: View {
    @Environment(AppState.self) private var app
    @State private var results: [String: String] = [:]
    @State private var running: String?

    var body: some View {
        let ai = app.ai
        List {
            Section("Connection") {
                LabeledContent("Mode", value: ai.connection.label)
                LabeledContent("Planning model", value: AIConfig.Task.planning.models.joined(separator: " → "))
                LabeledContent("Narration model", value: AIConfig.Task.narration.models.joined(separator: " → "))
                LabeledContent("Calls today") {
                    Text("\(ai.limiter.callsToday(.planning))/\(AIConfig.Task.planning.dailyCap) planning · \(ai.limiter.callsToday(.narration))/\(AIConfig.Task.narration.dailyCap) narration")
                        .font(.caption.monospacedDigit())
                }
                if let error = ai.lastError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                testRow("JSON", "Structured output (responseSchema)") { await testJSON() }
                testRow("Tools", "Function calling loop (2 tools)") { await testTools() }
                testRow("Fallback", "Non-AI fallback path") { await testFallback() }
            } header: {
                Text("Live tests")
            } footer: {
                Text("Each test uses one or two free-tier calls. Results are cached for 10 minutes, so re-running is free.")
            }

            Section {
                Button("Clear AI cache", role: .destructive) { ai.clearCache(); results = [:] }
            } footer: {
                Text("Privacy: PitStop only sends rounded coordinates (~100 m), place names, categories, interests, and run goals. Never health data, your name, or your email.")
            }
        }
        .navigationTitle("AI")
    }

    private func testRow(_ id: String, _ title: String, action: @escaping () async -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if running == id {
                    ProgressView()
                } else {
                    Button("Run") {
                        running = id
                        Task {
                            let started = Date.now
                            let output = await action()
                            results[id] = "\(output)  (\(String(format: "%.1f", Date.now.timeIntervalSince(started))) s)"
                            running = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(running != nil)
                }
            }
            if let result = results[id] {
                Text(result).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    // MARK: Tests

    private struct Greeting: Decodable { let greeting: String; let emoji: String }

    private func testJSON() async -> String {
        let schema = Schema.object(["greeting": Schema.string("A one-line pep talk for a runner"),
                                    "emoji": Schema.string("One emoji")], required: ["greeting", "emoji"])
        do {
            let result = try await app.ai.generateJSON(Greeting.self, task: .narration,
                                                       system: "You are a friendly running coach.",
                                                       prompt: "Say hi to a runner starting a 3 mile run.",
                                                       schema: schema, cacheTTL: 600)
            return "✅ \(result.emoji) \(result.greeting)"
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }

    private struct ToolAnswer: Decodable { let answer: String; let toolsUsed: [String] }

    private func testTools() async -> String {
        let tools = [
            AITool(name: "get_run_goal", description: "Returns the runner's goal distance in miles.",
                   parameters: Schema.object([:])) { _ in ["miles": 3] },
            AITool(name: "get_pace", description: "Returns the runner's pace in minutes per mile.",
                   parameters: Schema.object([:])) { _ in ["minutesPerMile": 10] },
        ]
        let schema = Schema.object(["answer": Schema.string(), "toolsUsed": Schema.array(Schema.string())],
                                   required: ["answer", "toolsUsed"])
        var steps: [String] = []
        do {
            let result = try await AgentRunner(service: app.ai).run(
                ToolAnswer.self,
                system: "Use the tools to get facts. Never guess numbers.",
                prompt: "How many minutes will my run take? Call both tools first.",
                tools: tools, schema: schema, cacheTTL: 600,
                onStep: { steps.append($0) })
            return "✅ \(result.answer) · tools: \(result.toolsUsed.joined(separator: ", ")) · \(steps.count) tool step(s)"
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }

    private func testFallback() async -> String {
        let outcome = await withAIFallback {
            throw AIError.rateLimited(retryAfter: 10)
        } fallback: {
            "standard picks"
        }
        return outcome.usedAI ? "❌ fallback not used" : "✅ fell back to \(outcome.value): \"\(outcome.error?.shortNote ?? "")\""
    }
}
