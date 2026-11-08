import SwiftUI

/// Signed out → sign-in screen; signed in → the app. Keeps `lastActiveAt` fresh when the app opens.
struct AppRootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.auth.state {
            case .loading:
                ProgressView().controlSize(.large)
            case .signedOut:
                AuthView().transition(.opacity)
            case .signedIn:
                RootTabView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.auth.state)
        .task { app.auth.start() }
        // Tapping the Live Activity / Dynamic Island opens pitstop://run → back to the map.
        .onOpenURL { url in
            if url.scheme == "pitstop" { app.selectedTab = .run }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.auth.touchLastActive() }
        }
    }
}
