import SwiftData
import SwiftUI

@main
struct PitStopApp: App {
    /// One shared app state, injected into the whole view tree.
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(app)
                // SwiftData container owned by HistoryStore, so @Query in views and writes share one store.
                .modelContainer(app.history.container)
        }
    }
}
