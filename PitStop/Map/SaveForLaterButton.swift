import SwiftUI

/// Bookmark toggle on pin cards: adds the place to My Places → Future Places.
struct SaveForLaterButton: View {
    @Environment(AppState.self) private var app
    let destination: PlannedDestination

    var body: some View {
        let isSaved = app.history.isSaved(destination.id)
        Button {
            app.toggleSaved(destination)
        } label: {
            Label(isSaved ? "Saved" : "Save for later", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isSaved ? Theme.sky : .primary)
        .sensoryFeedback(.selection, trigger: isSaved)
    }
}
