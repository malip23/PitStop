import SwiftUI

/// The five top-level tabs. The map (Run) is the hero.
/// The quest-offer banner floats above every tab except Business (where you're the business).
struct RootTabView: View {
    enum TabID: Hashable { case run, quests, rewards, business, settings }

    @Environment(AppState.self) private var app
    @State private var selection: TabID = .run

    var body: some View {
        TabView(selection: $selection) {
            RunMapScreen()
                .tabItem { Label("Run", systemImage: "figure.run") }
                .tag(TabID.run)

            QuestsScreen(onAccepted: { selection = .run })
                .tabItem { Label("Quests", systemImage: "flag.checkered") }
                .tag(TabID.quests)
                .badge(app.offers.count)

            RewardsScreen()
                .tabItem { Label("Rewards", systemImage: "gift.fill") }
                .tag(TabID.rewards)

            BusinessScreen()
                .tabItem { Label("Business", systemImage: "storefront.fill") }
                .tag(TabID.business)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(TabID.settings)
        }
        .overlay(alignment: .top) {
            if let offer = app.bannerOffer, selection != .business {
                QuestOfferBanner(offer: offer) {
                    app.accept(offer)
                    selection = .run
                } onDismiss: {
                    app.dismiss(offer)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: app.bannerOffer?.id)
    }
}
