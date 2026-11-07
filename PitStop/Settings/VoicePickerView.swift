import AVFoundation
import SwiftUI

/// Settings → Voice: choose how PitStop sounds. Tap a voice to hear it; Personal Voice and
/// Premium/Enhanced voices sound far more human than the standard ones.
struct VoicePickerView: View {
    @Environment(AppState.self) private var app
    @State private var voices: [AVSpeechSynthesisVoice] = SpeechService.availableVoices()
    @State private var personalVoices: [AVSpeechSynthesisVoice] = SpeechService.personalVoices
    @State private var personalVoiceDenied = false

    var body: some View {
        @Bindable var preferences = app.preferences
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pace")
                        Spacer()
                        Text(paceLabel(preferences.speechRate)).foregroundStyle(.secondary)
                    }
                    Slider(value: $preferences.speechRate, in: 0.85...1.15, step: 0.05)
                        .tint(Theme.coral)
                }
                Button {
                    SpeechService.shared.preview(voiceID: preferences.voiceIdentifier)
                } label: {
                    Label("Play sample", systemImage: "play.circle.fill")
                }
            }

            Section {
                voiceRow(name: "Automatic", detail: "Best installed voice: \(SpeechService.availableVoices().first?.name ?? "System")",
                         id: nil, selected: preferences.voiceIdentifier == nil)
            }

            Section {
                if personalVoices.isEmpty {
                    Button {
                        Task {
                            let granted = await SpeechService.requestPersonalVoice()
                            personalVoices = SpeechService.personalVoices
                            personalVoiceDenied = !granted
                        }
                    } label: {
                        Label("Use my Personal Voice", systemImage: "person.wave.2.fill")
                    }
                } else {
                    ForEach(personalVoices, id: \.identifier) { voice in
                        voiceRow(name: voice.name, detail: "Your Personal Voice", id: voice.identifier,
                                 selected: preferences.voiceIdentifier == voice.identifier)
                    }
                }
            } header: {
                Text("Personal Voice")
            } footer: {
                Text(personalVoiceDenied
                     ? "Not available. Create one in Settings › Accessibility › Personal Voice, then allow PitStop to use it."
                     : "Hear alerts in your own voice. Requires a Personal Voice created in iOS Settings › Accessibility.")
            }

            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.voices, id: \.identifier) { voice in
                        voiceRow(name: voice.name, detail: languageName(voice.language), id: voice.identifier,
                                 selected: preferences.voiceIdentifier == voice.identifier)
                    }
                }
            }

            Section {
            } footer: {
                Text("For the most natural sound, download a Premium or Enhanced voice: iOS Settings › Accessibility › Spoken Content › Voices › English. Then come back here.")
            }
        }
        .navigationTitle("Voice")
        .onAppear { voices = SpeechService.availableVoices() }
    }

    private func voiceRow(name: String, detail: String, id: String?, selected: Bool) -> some View {
        Button {
            app.preferences.voiceIdentifier = id
            SpeechService.shared.preview(voiceID: id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.coral).fontWeight(.bold)
                }
            }
        }
    }

    private var groups: [(title: String, voices: [AVSpeechSynthesisVoice])] {
        let premium = voices.filter { $0.quality == .premium }
        let enhanced = voices.filter { $0.quality == .enhanced }
        let standard = voices.filter { $0.quality == .default }
        return [("Premium (most natural)", premium), ("Enhanced", enhanced), ("Standard", standard)]
            .filter { !$0.voices.isEmpty }
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func paceLabel(_ value: Double) -> String {
        value < 0.95 ? "Relaxed" : value > 1.05 ? "Brisk" : "Natural"
    }
}
