import AVFoundation

/// Speaks alerts and (later) city-guide narration in the most natural voice available.
///
/// How it sounds more human:
/// - **Best voice:** a voice the user picked (including their own Personal Voice), otherwise the
///   highest-quality installed English voice: Premium › Enhanced › standard. Novelty voices are skipped.
/// - **Natural rhythm:** sentences are wrapped in SSML with short `<break>`s between phrases, plus a
///   slight pause before and after each line, so cues don't sound like one robotic run-on.
/// - **Warmer delivery:** a touch above default pitch, and a rate the user can tune in Settings.
/// - **Varied wording:** callers pass several phrasings (see `CrossingPoint.Kind.voiceCues`), and
///   `speak(oneOf:)` never repeats the same line twice in a row.
///
/// Other audio is ducked while speaking and restored afterwards.
@MainActor
final class SpeechService: NSObject {
    enum Style {
        /// Short safety cue: a little brisker.
        case alert
        /// City-guide narration: relaxed and warm.
        case narration
    }

    static let shared = SpeechService()

    /// UserDefaults keys (written by AppPreferences).
    static let voiceKey = "pref.voiceID"
    static let rateKey = "pref.speechRate"

    private let synthesizer = AVSpeechSynthesizer()
    private var lastLines: [String: String] = [:]

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Speaking

    /// Picks one phrasing at random (never the same as last time for this `key`) and speaks it.
    func speak(oneOf variants: [String], key: String, style: Style = .alert) {
        guard !variants.isEmpty else { return }
        let options = variants.count > 1 ? variants.filter { $0 != lastLines[key] } : variants
        let line = options.randomElement() ?? variants[0]
        lastLines[key] = line
        speak(line, style: style)
    }

    func speak(_ text: String, style: Style = .alert) {
        let session = AVAudioSession.sharedInstance()
        // .duckOthers lowers music while we talk; .interruptSpokenAudioAndMixWithOthers pauses podcasts.
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)

        let utterance = Self.makeUtterance(text)
        utterance.voice = Self.currentVoice()
        let userRate = UserDefaults.standard.double(forKey: Self.rateKey)
        let rateMultiplier = userRate > 0 ? userRate : 1
        switch style {
        case .alert:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(1.02 * rateMultiplier)
            utterance.pitchMultiplier = 1.04
            utterance.preUtteranceDelay = 0.05
            utterance.postUtteranceDelay = 0.15
        case .narration:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(0.96 * rateMultiplier)
            utterance.pitchMultiplier = 1.06
            utterance.preUtteranceDelay = 0.15
            utterance.postUtteranceDelay = 0.3
        }
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Plays a sample with a given voice (Settings → Voice).
    func preview(voiceID: String?) {
        stop()
        let previous = UserDefaults.standard.string(forKey: Self.voiceKey)
        UserDefaults.standard.set(voiceID ?? "", forKey: Self.voiceKey)
        speak("Hey! Crosswalk coming up. Take a quick look both ways, then keep that pace going.", style: .narration)
        UserDefaults.standard.set(previous ?? "", forKey: Self.voiceKey)
    }

    // MARK: Voices

    /// English voices worth offering, best quality first. Novelty voices are excluded.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
                let preferred = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
                if ($0.language == preferred) != ($1.language == preferred) { return $0.language == preferred }
                return $0.name < $1.name
            }
    }

    /// The chosen voice, or the best installed one.
    static func currentVoice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: voiceKey), !id.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        return availableVoices().first ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Display name for a chosen voice id (nil = automatic).
    static func voiceName(for id: String?) -> String {
        if let id, let voice = AVSpeechSynthesisVoice(identifier: id) { return voice.name }
        return "Automatic (\(availableVoices().first?.name ?? "System"))"
    }

    /// Asks permission to use the user's own Personal Voice (iOS 17+). Returns true if granted.
    static func requestPersonalVoice() async -> Bool {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static var personalVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.voiceTraits.contains(.isPersonalVoice) }
    }

    // MARK: SSML

    /// Wraps text in SSML with short pauses between sentences and after commas.
    private static func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let paced = escaped
            .replacingOccurrences(of: ". ", with: ".<break time=\"260ms\"/> ")
            .replacingOccurrences(of: "! ", with: "!<break time=\"240ms\"/> ")
            .replacingOccurrences(of: ", ", with: ",<break time=\"110ms\"/> ")
        let ssml = "<speak>\(paced)</speak>"
        return AVSpeechUtterance(ssmlRepresentation: ssml) ?? AVSpeechUtterance(string: text)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Give other apps their volume back once nothing is queued.
            if !self.synthesizer.isSpeaking {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}
