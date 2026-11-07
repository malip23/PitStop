import SwiftUI

/// Rewards earned from completed quests. (Built out in Milestone 4.)
struct RewardsScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("No rewards yet", systemImage: "gift",
                                   description: Text("Finish a quest run at a partner business to unlock its reward."))
                .navigationTitle("Rewards")
        }
    }
}
