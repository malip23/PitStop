import SwiftUI

@main
struct PitStopApp: App {
    /// One shared app state, injected into the whole view tree.
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(app)
        }
    }
}
