import SwiftUI

/// App settings and developer tools. (Built out in Milestones 7–8.)
struct SettingsScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
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
            }
            .navigationTitle("Settings")
        }
    }
}
