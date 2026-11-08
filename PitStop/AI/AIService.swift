import Foundation

/// The provider-agnostic AI interface. Features (route agent, recommender, narration) depend only on
/// this, so Gemini can be swapped for another provider by writing one new conforming type.
@MainActor
protocol AIService: AnyObject {
    /// False when no key or proxy is configured, or the service is cooling down after rate limits.
    var isAvailable: Bool { get }
    /// One model call. Implementations handle transport, caching, throttling, retries, and model fallback.
    func generate(_ request: AIRequest) async throws -> AIResponse
}

/// A tool the model may call. The handler runs in Swift and returns JSON for the model.
struct AITool {
    let name: String
    let description: String
    /// Gemini Schema (see `Schema` builders) describing the arguments.
    let parameters: JSONValue
    let handler: @MainActor (JSONValue) async -> JSONValue
}

/// One conversation turn in Gemini's shape: `{ "role": "user" | "model", "parts": [...] }`.
/// Model turns are kept as raw JSON so thought signatures etc. survive the round trip.
struct AIMessage: Sendable, Hashable {
    let role: String
    let parts: [JSONValue]

    static func user(_ text: String) -> AIMessage { AIMessage(role: "user", parts: [["text": .string(text)]]) }
}

struct AIRequest {
    var task: AIConfig.Task
    var system: String?
    var messages: [AIMessage]
    var tools: [AITool] = []
    /// When set, the model must answer with JSON matching this schema.
    var responseSchema: JSONValue?
    var temperature: Double = 0.6
    var maxOutputTokens: Int = 1024
    /// Seconds to cache the answer (0 = never). Identical requests within this window reuse it.
    var cacheTTL: TimeInterval = 0
}

struct AIResponse: Sendable {
    /// The model's full turn, raw (to append to the conversation as-is).
    let message: AIMessage
    let modelUsed: String
    let fromCache: Bool

    /// Concatenated text parts (thought parts excluded).
    var text: String {
        message.parts.compactMap { part -> String? in
            guard part["thought"] != .bool(true) else { return nil }
            return part["text"]?.stringValue
        }.joined()
    }

    /// Function calls the model wants us to run.
    var functionCalls: [(name: String, args: JSONValue, id: String?)] {
        message.parts.compactMap { part in
            guard let call = part["functionCall"], let name = call["name"]?.stringValue else { return nil }
            return (name, call["args"] ?? [:], call["id"]?.stringValue)
        }
    }
}

enum AIError: LocalizedError, Equatable {
    case notConfigured
    case rateLimited(retryAfter: TimeInterval?)
    case dailyLimitReached
    case http(status: Int, message: String)
    case blocked(String)
    case invalidResponse
    case badJSON(String)
    case tooManyToolCalls
    case offline
    case timedOut(model: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "AI isn't set up (no Worker or API key)."
        case .rateLimited: "AI is busy (free-tier rate limit)."
        case .dailyLimitReached: "Today's AI budget is used up."
        case .http(let status, let message): "AI error \(status): \(message)"
        case .blocked(let reason): "AI declined to answer (\(reason))."
        case .invalidResponse: "AI returned an unexpected response."
        case .badJSON(let detail): "AI returned invalid JSON (\(detail))."
        case .tooManyToolCalls: "AI agent didn't finish within 5 steps."
        case .offline: "No internet connection."
        case .timedOut(let model): "AI didn't reply in time (last tried \(model))."
        }
    }

    /// Short note for the UI ("AI unavailable" banners).
    var shortNote: String {
        switch self {
        case .notConfigured: "AI unavailable: not configured"
        case .rateLimited, .dailyLimitReached: "AI unavailable: rate limit, using standard picks"
        case .offline: "AI unavailable: offline"
        case .timedOut: "AI took too long, using standard picks"
        default: "AI unavailable, using standard picks"
        }
    }
}
