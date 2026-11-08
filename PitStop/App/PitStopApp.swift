import SwiftData
import SwiftUI

@main
struct PitStopApp: App {
    /// One shared app state, injected into the whole view tree.
    @State private var app: AppState

    init() {
        // Firebase must be configured before anything uses it.
        FirebaseBootstrap.configure()
        _app = State(initialValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(app)
                // SwiftData container owned by HistoryStore, so @Query in views and writes share one store.
                .modelContainer(app.history.container)
        }
    }
}
