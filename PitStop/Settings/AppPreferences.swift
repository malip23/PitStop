import Foundation
import Observation

/// User-facing preferences, persisted in UserDefaults.
@Observable
final class AppPreferences {
    /// Crosswalk / traffic-signal / intersection alerts while navigating.
    var crossingAlerts: Bool { didSet { defaults.set(crossingAlerts, forKey: "pref.crossingAlerts") } }
    /// Speak short voice cues (alerts now, narration later).
    var voiceCues: Bool { didSet { defaults.set(voiceCues, forKey: "pref.voiceCues") } }
    /// Chosen speech voice (nil = automatic: best installed voice).
    var voiceIdentifier: String? { didSet { defaults.set(voiceIdentifier ?? "", forKey: SpeechService.voiceKey) } }
    /// Speech pace multiplier, 0.85 (relaxed) to 1.15 (brisk).
    var speechRate: Double { didSet { defaults.set(speechRate, forKey: SpeechService.rateKey) } }
    /// What the runner enjoys (route agent + recommender).
    var interests: Set<Interest> { didSet { defaults.set(interests.map(\.rawValue), forKey: "pref.interests") } }
    /// Let Gemini suggest a scenic route (falls back to the standard routes when off or unavailable).
    var aiRouteSuggestions: Bool { didSet { defaults.set(aiRouteSuggestions, forKey: "pref.aiRoutes") } }
    /// Quick-stop suggestions for interest matches along the route while navigating.
    var runSuggestions: Bool { didSet { defaults.set(runSuggestions, forKey: "pref.runSuggestions") } }
    /// City-guide narration about places along the route.
    var narration: Bool { didSet { defaults.set(narration, forKey: "pref.narration") } }
    /// Speak narration aloud (otherwise banner only).
    var narrationVoice: Bool { didSet { defaults.set(narrationVoice, forKey: "pref.narrationVoice") } }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: ["pref.crossingAlerts": true, "pref.voiceCues": true, "pref.aiRoutes": true,
                                     "pref.runSuggestions": true, "pref.narration": true, "pref.narrationVoice": true])
        crossingAlerts = defaults.bool(forKey: "pref.crossingAlerts")
        voiceCues = defaults.bool(forKey: "pref.voiceCues")
        let voice = defaults.string(forKey: SpeechService.voiceKey) ?? ""
        voiceIdentifier = voice.isEmpty ? nil : voice
        let rate = defaults.double(forKey: SpeechService.rateKey)
        speechRate = rate > 0 ? rate : 1
        interests = Set((defaults.stringArray(forKey: "pref.interests") ?? []).compactMap(Interest.init(rawValue:)))
        aiRouteSuggestions = defaults.bool(forKey: "pref.aiRoutes")
        runSuggestions = defaults.bool(forKey: "pref.runSuggestions")
        narration = defaults.bool(forKey: "pref.narration")
        narrationVoice = defaults.bool(forKey: "pref.narrationVoice")
    }
}
