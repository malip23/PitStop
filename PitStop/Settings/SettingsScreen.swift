import SwiftUI

/// App settings and developer tools.
struct SettingsScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var developer = app.developer
        @Bindable var preferences = app.preferences
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Real places nearby", value: "\(app.places.places.count)")
                    Button {
                        app.refreshNearbyPlaces()
                    } label: {
                        HStack {
                            Text("Refresh nearby places")
                            if app.places.isSearching {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(app.currentLocation == nil || app.places.isSearching)
                } header: {
                    Text("Map")
                } footer: {
                    Text("Real places come from Apple Maps and refresh automatically when you move about 600 m.")
                }

                Section {
                    Toggle(isOn: $preferences.crossingAlerts) {
                        Label("Crosswalk & intersection alerts", systemImage: "exclamationmark.triangle.fill")
                    }
                    Toggle(isOn: $preferences.voiceCues) {
                        Label("Voice cues", systemImage: "speaker.wave.2.fill")
                    }
                    NavigationLink {
                        VoicePickerView()
                    } label: {
                        LabeledContent {
                            Text(SpeechService.voiceName(for: preferences.voiceIdentifier))
                        } label: {
                            Label("Voice", systemImage: "waveform")
                        }
                    }
                    .disabled(!preferences.voiceCues)
                } header: {
                    Text("Safety alerts")
                } footer: {
                    Text("Alerts are only helpers and can miss crossings or be out of date. Always watch traffic yourself and follow local signals. Crossing data © OpenStreetMap contributors.")
                }
                .tint(Theme.coral)

                Section {
                    NavigationLink {
                        RunHistoryView()
                    } label: {
                        Label("Run History", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    Picker(selection: $developer.role) {
                        ForEach(UserRole.allCases) { Text($0.displayName).tag($0) }
                    } label: {
                        Label("Role", systemImage: "person.crop.circle")
                    }
                    Toggle(isOn: $developer.antiCheatEnabled) {
                        Label("Anti-cheat", systemImage: "checkmark.shield.fill")
                    }
                    Button {
                        app.startFakeCarRun()
                    } label: {
                        Label("Fake run at car speed", systemImage: "car.fill")
                    }
                    .disabled(app.destination == nil || app.selectedRoute == nil || app.run.isActive)
                } header: {
                    Text("Roles & anti-cheat")
                } footer: {
                    Text("Role decides the tabs (runner: My Places + Rewards; admin: Business) until accounts exist. Turn anti-cheat off when simulating locations from Xcode. \"Fake run at car speed\" plays the selected route at 30 mph with no steps, so anti-cheat rejects it. Pick a destination and route on the map first.")
                }

                Section {
                    Toggle(isOn: $developer.demoMode) {
                        Label("Demo Mode", systemImage: "play.rectangle.fill")
                    }
                    .tint(Theme.coral)
                    if developer.demoMode {
                        Picker("Playback speed", selection: $developer.demoSpeed) {
                            Text("1× (real pace)").tag(1.0)
                            Text("3×").tag(3.0)
                            Text("6×").tag(6.0)
                            Text("12×").tag(12.0)
                        }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Demo Mode plays back a run along the chosen route at your pace, so you can demo navigation indoors. Pick a destination and route, then tap Start. Real GPS is ignored while playback runs.")
                }

                Section("AI") {
                    LabeledContent("Gemini API key") {
                        Label(AppSecrets.hasGeminiKey ? "Configured" : "Not set",
                              systemImage: AppSecrets.hasGeminiKey ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(AppSecrets.hasGeminiKey ? Theme.lime : .secondary)
                    }
                    Toggle(isOn: $preferences.aiRouteSuggestions) {
                        Label("AI route suggestions", systemImage: "sparkles")
                    }
                    .tint(Theme.coral)
                    NavigationLink {
                        InterestsPickerView()
                    } label: {
                        LabeledContent {
                            Text(preferences.interests.isEmpty ? "None" : "\(preferences.interests.count) selected")
                        } label: {
                            Label("Interests", systemImage: "heart.fill")
                        }
                    }
                    NavigationLink {
                        AIDiagnosticsView()
                    } label: {
                        LabeledContent("Connection", value: app.ai.connection.label)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
