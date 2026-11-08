import Foundation

/// Picks the single best quick stop and writes its one-line pitch.
///
/// Gemini (Flash-Lite) gets ONLY place names, categories, the runner's interests, distance ahead, and
/// detour. It must choose by id; unknown ids are rejected. If AI is unavailable or rate-limited, the
/// closest match wins with a template line.
@MainActor
enum SuggestionWriter {
    private struct Answer: Decodable { let candidate_id: String; let message: String }

    static func pick(from candidates: [InterestSuggestionEngine.Candidate], progress: Double,
                     interests: Set<Interest>, ai: any AIService) async -> InterestSuggestion? {
        guard let closest = candidates.first else { return nil }
        guard candidates.count > 1 || ai.isAvailable else { return template(closest, progress: progress) }

        let outcome = await withAIFallback {
            try await askAI(Array(candidates.prefix(6)), progress: progress, interests: interests, ai: ai)
        } fallback: {
            template(closest, progress: progress)
        }
        return outcome.value
    }

    private static func askAI(_ candidates: [InterestSuggestionEngine.Candidate], progress: Double,
                              interests: Set<Interest>, ai: any AIService) async throws -> InterestSuggestion {
        let list: [JSONValue] = candidates.enumerated().map { index, c in
            [
                "id": .string("S\(index + 1)"),
                "name": .string(c.destination.name),
                "category": .string(c.destination.category.displayName),
                "matches_interest": .string(c.interest?.displayName ?? "none"),
                "meters_ahead": .number((c.alongRoute - progress).rounded()),
                "detour_miles": .number((c.detour / Units.metersPerMile * 10).rounded() / 10),
            ]
        }
        let system = """
        You suggest ONE quick stop to a runner mid-run. Choose from the list by id. Prefer the best \
        interest match with the smallest detour. Write ONE friendly line under 70 characters in this \
        style: "Smoothie shop 2 blocks ahead, +0.2 mi. Stop by?" (about 100 m per block). Use only the \
        given data; never invent facts, deals, hours, or ratings.
        """
        let prompt = "Runner interests: \(interests.map(\.displayName).sorted().joined(separator: ", ")). Places: \(compact(.array(list)))"
        let schema = Schema.object(["candidate_id": Schema.string(), "message": Schema.string()],
                                   required: ["candidate_id", "message"])
        let answer = try await ai.generateJSON(Answer.self, task: .narration, system: system, prompt: prompt,
                                               schema: schema, temperature: 0.7, maxOutputTokens: 200, cacheTTL: 3600)
        guard let index = Int(answer.candidate_id.dropFirst()), (1...candidates.count).contains(index) else {
            throw AIError.badJSON("unknown candidate id")
        }
        let chosen = candidates[index - 1]
        let message = answer.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return make(chosen, progress: progress, message: message.isEmpty ? templateLine(chosen, progress: progress) : String(message.prefix(90)), usedAI: true)
    }

    static func template(_ c: InterestSuggestionEngine.Candidate, progress: Double) -> InterestSuggestion {
        make(c, progress: progress, message: templateLine(c, progress: progress), usedAI: false)
    }

    /// "Smoothie Bar 2 blocks ahead, +0.2 mi. Stop by?"
    private static func templateLine(_ c: InterestSuggestionEngine.Candidate, progress: Double) -> String {
        let ahead = max(0, c.alongRoute - progress)
        let blocks = Int((ahead / 100).rounded())
        let when = blocks <= 1 ? "just ahead" : "\(blocks) blocks ahead"
        let what = c.interest == nil ? c.destination.name : c.destination.category.displayName
        return "\(what) \(when), +\(String(format: "%.1f", c.detour / Units.metersPerMile)) mi. Stop by?"
    }

    private static func make(_ c: InterestSuggestionEngine.Candidate, progress: Double, message: String, usedAI: Bool) -> InterestSuggestion {
        InterestSuggestion(destination: c.destination, interest: c.interest, alongRoute: c.alongRoute,
                           distanceAhead: max(0, c.alongRoute - progress), detour: c.detour,
                           message: message, usedAI: usedAI)
    }

    private static func compact(_ value: JSONValue) -> String {
        (try? String(data: JSONEncoder.sorted.encode(value), encoding: .utf8)) ?? "[]"
    }
}
