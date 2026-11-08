import SwiftUI

/// App settings and developer tools.
struct SettingsScreen: View {
    @Environment(AppState.self) private var app
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var developer = app.developer
        @Bindable var preferences = app.preferences
        NavigationStack {
            Form {
                accountSection

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
                    Text("Anti-cheat")
                } footer: {
                    Text("Turn anti-cheat off when simulating locations from Xcode. \"Fake run at car speed\" plays the selected route at 30 mph with no steps, so anti-cheat rejects it. Pick a destination and route on the map first.")
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
                    Toggle(isOn: $preferences.runSuggestions) {
                        Label("Quick-stop suggestions on runs", systemImage: "cup.and.saucer.fill")
                    }
                    .tint(Theme.coral)
                    Toggle(isOn: $preferences.narration) {
                        Label("City-guide narration", systemImage: "text.bubble.fill")
                    }
                    .tint(Theme.coral)
                    if preferences.narration {
                        Toggle(isOn: $preferences.narrationVoice) {
                            Label("Speak narration aloud", systemImage: "speaker.wave.2.fill")
                        }
                        .tint(Theme.coral)
                    }
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
            .confirmationDialog("Sign out of PitStop?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    app.previewAsRunner = false
                    app.auth.signOut()
                }
            }
        }
    }
}

extension SettingsScreen {
    /// Name, email, role (from Firestore), admin "preview as runner", and sign out.
    @ViewBuilder var accountSection: some View {
        @Bindable var app = app
        Section {
            HStack(spacing: 12) {
                Text(String((app.auth.profile?.displayName ?? "?").prefix(1)).uppercased())
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.coral.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.auth.profile?.displayName ?? "Loading…").font(.headline)
                    Text(app.auth.email ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text((app.auth.profile?.role ?? .runner).displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.coral.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.coral)
            }
            if let problem = app.auth.profileProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let uid = app.auth.uid {
                // Matches the users/{uid} document ID in Firestore (handy when setting a role by hand).
                LabeledContent("User ID") {
                    Text(uid).font(.caption2.monospaced()).textSelection(.enabled)
                }
            }
            if app.auth.profile?.role.canManageBusinesses == true {
                Toggle(isOn: $app.previewAsRunner) {
                    Label("Preview as runner", systemImage: "eye")
                }
                .tint(Theme.coral)
            }
            Button("Sign out", role: .destructive) { confirmSignOut = true }
        } header: {
            Text("Account")
        } footer: {
            if app.auth.profile?.role.canManageBusinesses == true {
                Text("Your role comes from Firestore. \"Preview as runner\" only changes this phone's tabs so you can demo both sides.")
            } else {
                Text("New accounts are runners. An admin can change your role.")
            }
        }
    }
}
