import Foundation

/// Runs a tool-using agent on top of any `AIService`, then decodes a structured result.
///
/// The loop (max `AIConfig.maxAgentIterations` = 5):
/// 1. Send the conversation plus tool declarations.
/// 2. If the model asks for function calls, run each tool in Swift, append the model's turn
///    (unchanged) and a user turn with `functionResponse` parts, then go to 1.
/// 3. When it answers with text, decode it as JSON into `Output`.
///
/// If the provider can't combine tools with JSON-schema output, step 3 becomes one extra call
/// without tools that asks for JSON only. If anything fails, the error propagates and the caller uses
/// its non-AI fallback.
@MainActor
struct AgentRunner {
    let service: any AIService

    func run<Output: Decodable>(
        _ type: Output.Type,
        task: AIConfig.Task = .planning,
        system: String,
        prompt: String,
        tools: [AITool],
        schema: JSONValue,
        temperature: Double = 0.4,
        cacheTTL: TimeInterval = 0,
        onStep: (String) -> Void = { _ in }
    ) async throws -> Output {
        var messages: [AIMessage] = [.user(prompt)]
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        for iteration in 1...AIConfig.maxAgentIterations {
            let request = AIRequest(task: task, system: system, messages: messages, tools: tools,
                                    responseSchema: schema, temperature: temperature, maxOutputTokens: 2048,
                                    cacheTTL: cacheTTL)
            let response = try await service.generate(request)
            let calls = response.functionCalls

            if calls.isEmpty {
                // Final answer. Decode, or ask once more for JSON only if the text isn't valid JSON.
                if let output = try? Self.decode(Output.self, from: response.text) { return output }
                messages.append(response.message)
                return try await finalJSON(Output.self, task: task, system: system, messages: messages, schema: schema)
            }

            // Run every requested tool, then feed the results back.
            messages.append(response.message)
            var resultParts: [JSONValue] = []
            for call in calls {
                onStep("Step \(iteration): \(call.name)")
                let result: JSONValue
                if let tool = toolsByName[call.name] {
                    result = await tool.handler(call.args)
                } else {
                    result = ["error": .string("Unknown tool \(call.name)")]
                }
                var functionResponse: [String: JSONValue] = ["name": .string(call.name), "response": ["result": result]]
                if let id = call.id { functionResponse["id"] = .string(id) }
                resultParts.append(["functionResponse": .object(functionResponse)])
            }
            messages.append(AIMessage(role: "user", parts: resultParts))
        }
        throw AIError.tooManyToolCalls
    }

    /// Asks for the final answer as schema-constrained JSON, without tools.
    private func finalJSON<Output: Decodable>(_ type: Output.Type, task: AIConfig.Task, system: String,
                                              messages: [AIMessage], schema: JSONValue) async throws -> Output {
        var messages = messages
        messages.append(.user("Now give your final answer as JSON only, matching the response schema."))
        let response = try await service.generate(AIRequest(task: task, system: system, messages: messages,
                                                            responseSchema: schema, temperature: 0.2,
                                                            maxOutputTokens: 2048))
        return try Self.decode(Output.self, from: response.text)
    }

    /// Decodes JSON, tolerating ```json fences or stray text around the object.
    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = candidate.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = candidate.lastIndex(where: { $0 == "}" || $0 == "]" }), start <= end {
            candidate = String(candidate[start...end])
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(candidate.utf8))
        } catch {
            throw AIError.badJSON(String(describing: error).prefix(120).description)
        }
    }
}

/// One-shot structured call without tools (recommendations, narration batches).
extension AIService {
    func generateJSON<Output: Decodable>(_ type: Output.Type, task: AIConfig.Task, system: String, prompt: String,
                                         schema: JSONValue, temperature: Double = 0.5,
                                         maxOutputTokens: Int = 1024, cacheTTL: TimeInterval = 0) async throws -> Output {
        let response = try await generate(AIRequest(task: task, system: system, messages: [.user(prompt)],
                                                    responseSchema: schema, temperature: temperature,
                                                    maxOutputTokens: maxOutputTokens, cacheTTL: cacheTTL))
        return try AgentRunner.decode(Output.self, from: response.text)
    }
}

/// Runs an AI path and falls back to a non-AI result on any failure. Reports which one was used.
@MainActor
func withAIFallback<T>(_ ai: () async throws -> T, fallback: () -> T) async -> (value: T, usedAI: Bool, error: AIError?) {
    do {
        return (try await ai(), true, nil)
    } catch is CancellationError {
        return (fallback(), false, nil)          // cancelled because the user moved on: no "AI unavailable" note
    } catch {
        return (fallback(), false, error as? AIError ?? .invalidResponse)
    }
}
