import SwiftUI

/// The runner's view of Off-Peak Quests: the accepted one, then all offers ranked by score.
struct QuestsScreen: View {
    @Environment(AppState.self) private var app
    /// Switches to the Run tab after accepting.
    var onAccepted: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                if let accepted = app.acceptedQuest {
                    Section("On your way") {
                        AcceptedQuestCard(quest: accepted.quest, business: accepted.business)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                let offers = app.offers
                if !offers.isEmpty {
                    Section {
                        ForEach(offers) { offer in
                            QuestOfferRow(offer: offer) {
                                app.accept(offer)
                                onAccepted()
                            } onDismiss: {
                                app.dismiss(offer)
                            }
                        }
                    } header: {
                        Text("Available near you")
                    } footer: {
                        Text("Ranked by detour distance (50%), how long the business has been slow (25%), and a fair-discovery boost for less-visited spots (25%). Max detour 1.5 mi.")
                    }
                }
            }
            .overlay {
                if app.offers.isEmpty && app.acceptedQuest == nil {
                    ContentUnavailableView("No quests right now", systemImage: "flag.checkered",
                                           description: Text("When a partner business within 1.5 mi is slow, its Off-Peak Quest shows up here."))
                }
            }
            .navigationTitle("Quests")
            .onAppear { NotificationService.requestAuthorizationIfNeeded() }
        }
    }
}
