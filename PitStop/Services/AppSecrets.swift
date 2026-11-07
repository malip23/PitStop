import Foundation

/// Reads secrets injected at build time.
///
/// Chain: `Secrets.xcconfig` (git-ignored) → included by `Config.xcconfig` → build setting
/// `GEMINI_API_KEY` → Info.plist entry `$(GEMINI_API_KEY)` → read here.
///
/// The key is never written in Swift source. Note: a key in Info.plist ships inside the app bundle,
/// which is fine for a hackathon demo. For anything public, use the Cloudflare Worker proxy instead,
/// so the key stays on the server.
enum AppSecrets {
    /// The Gemini API key, or nil if it isn't configured (missing file, placeholder, or unexpanded).
    static var geminiAPIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders: Set<String> = ["", "YOUR_KEY_HERE", "$(GEMINI_API_KEY)"]
        return placeholders.contains(key) ? nil : key
    }

    static var hasGeminiKey: Bool { geminiAPIKey != nil }

    /// Host of the Cloudflare Worker proxy, e.g. "pitstop-gemini-proxy.you.workers.dev" (no https://,
    /// because "//" starts a comment in .xcconfig files).
    static var aiProxyHost: String? {
        value(for: "AI_PROXY_HOST", placeholders: ["YOUR_WORKER_HOST"])
            .map { $0.replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    }

    /// Shared token the Worker requires, so strangers can't use your proxy.
    static var aiProxyToken: String? { value(for: "AI_PROXY_TOKEN", placeholders: ["YOUR_TOKEN"]) }

    private static func value(for key: String, placeholders: Set<String>) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") || placeholders.contains(value) ? nil : value
    }
}
