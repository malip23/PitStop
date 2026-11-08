import Foundation

/// Every AI setting in one place: models, limits, and how the app connects.
///
/// Models (Google AI Studio free tier, checked against Google's model and pricing docs, Nov 2026):
/// - Planning (route agent, recommendations): `gemini-3.8-flash`, falling back to `gemini-3.6-flash`
/// - Narration (short, fast city-guide lines): `gemini-3.5-flash-lite`, falling back to `gemini-3.1-flash-lite`
/// (`gemini-2.5-flash` is deprecated and is rerouted from Dec 1, 2026, so it isn't used.)
/// Keep `proxy/src/index.js` ALLOWED_MODELS in sync with these.
enum AIConfig {
    enum Task: String, Sendable {
        case planning, narration

        var models: [String] {
            switch self {
            // Flash-Lite is the last resort: it supports function calling and answers fast,
            // so a slow or unavailable Flash model never costs the user the AI route.
            case .planning: ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite"]
            case .narration: ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]
            }
        }

        /// Gemini 3 thinking level: a little reasoning for agents, as little as possible for narration.
        var thinkingLevel: String { self == .planning ? "low" : "minimal" }

        /// Per-request timeout. Planning models "think" before answering, so they get longer.
        var timeout: TimeInterval { self == .planning ? 45 : 20 }

        /// Client-side throttle: minimum seconds between calls (stays well under free-tier RPM).
        var minInterval: TimeInterval { self == .planning ? 4 : 2 }

        /// Soft daily cap per task, so a demo day never burns the whole free quota.
        var dailyCap: Int { self == .planning ? 150 : 300 }
    }

    /// Agent tool-calling loop limit.
    static let maxAgentIterations = 5
    /// Upper bound on a 429 backoff before giving up and falling back.
    static let maxBackoff: TimeInterval = 8
    static let requestTimeout: TimeInterval = 45

    static let directBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    /// How requests reach Gemini.
    enum Connection: Equatable {
        /// Recommended: the Cloudflare Worker holds the key; the app only knows the Worker's host + token.
        case proxy(host: String, token: String?)
        /// Demo fallback: key from Secrets.xcconfig → Info.plist.
        case direct(apiKey: String)
        case unavailable

        var label: String {
            switch self {
            case .proxy(let host, _): "Cloudflare Worker (\(host))"
            case .direct: "Direct with API key (demo)"
            case .unavailable: "Not configured"
            }
        }
    }

    /// Proxy wins when configured; otherwise the direct key; otherwise AI is off (fallbacks only).
    static var connection: Connection {
        if let host = AppSecrets.aiProxyHost { return .proxy(host: host, token: AppSecrets.aiProxyToken) }
        if let key = AppSecrets.geminiAPIKey { return .direct(apiKey: key) }
        return .unavailable
    }
}

/// Privacy helpers. Free-tier requests may be used by Google to improve its products, so send the
/// minimum: never HealthKit data, names, or emails; coordinates rounded to ~100 m.
enum AIPrivacy {
    /// 3 decimal places ≈ 110 m.
    static func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
}
