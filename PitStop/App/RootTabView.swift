import SwiftUI

/// Top-level tabs, depending on role:
/// - Runner: Run · My Places · Rewards · Settings
/// - Admin:  Run · Business · Settings (an Admin tab arrives with accounts)
///
/// The quest-offer banner floats over runner tabs; the check-in celebration covers everything.
struct RootTabView: View {
    enum TabID: Hashable { case run, myPlaces, rewards, business, settings }

    @Environment(AppState.self) private var app
    @State private var selection: TabID = .run

    var body: some View {
        let role = app.developer.role
        TabView(selection: $selection) {
            RunMapScreen()
                .tabItem { Label("Run", systemImage: "figure.run") }
                .tag(TabID.run)

            if role == .runner {
                MyPlacesScreen(onPlanRun: { selection = .run })
                    .tabItem { Label("My Places", systemImage: "mappin.and.ellipse") }
                    .tag(TabID.myPlaces)

                RewardsScreen()
                    .tabItem { Label("Rewards", systemImage: "gift.fill") }
                    .tag(TabID.rewards)
            } else {
                BusinessScreen()
                    .tabItem { Label("Business", systemImage: "storefront.fill") }
                    .tag(TabID.business)
            }

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(TabID.settings)
        }
        .onChange(of: role) { _, _ in selection = .run }
        .overlay(alignment: .top) {
            if let offer = app.bannerOffer, role == .runner {
                QuestOfferBanner(offer: offer) {
                    app.accept(offer)
                    selection = .run
                } onDismiss: {
                    app.dismiss(offer)
                }
                .padding(.horizontal)
                // While navigating on the Run tab, sit below the navigation banner.
                .padding(.top, app.navigation.isNavigating && selection == .run ? 170 : 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let event = app.celebration {
                RewardCelebrationView(event: event) { app.celebration = nil }
                    .transition(.opacity)
            } else if !app.badgeCelebration.isEmpty {
                // Badges wait until the check-in card is closed.
                BadgeCelebrationView(badges: app.badgeCelebration) { app.badgeCelebration = [] }
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4), value: app.bannerOffer?.id)
        .animation(.easeInOut(duration: 0.25), value: app.celebration?.id)
        .animation(.easeInOut(duration: 0.25), value: app.badgeCelebration)
    }
}
