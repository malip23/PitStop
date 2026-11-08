import SwiftUI

/// Top-level tabs, depending on role:
/// - Runner: Run · My Places · Rewards · Settings
/// - Business / Admin: Run · Business · Settings (+ Admin tab for admins)
///
/// Popups: on the Run tab the map hosts them (so the camera keeps the route clear of them); on other
/// tabs they float here, above the tab bar. The check-in celebration covers everything.
struct RootTabView: View {
    @Environment(AppState.self) private var app
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        @Bindable var app = app
        let role = app.role
        TabView(selection: $app.selectedTab) {
            RunMapScreen()
                .tabItem { Label("Run", systemImage: "figure.run") }
                .tag(AppTab.run)

            if role == .runner {
                MyPlacesScreen(onPlanRun: { app.selectedTab = .run })
                    .tabItem { Label("My Places", systemImage: "mappin.and.ellipse") }
                    .tag(AppTab.myPlaces)

                RewardsScreen()
                    .tabItem { Label("Rewards", systemImage: "gift.fill") }
                    .tag(AppTab.rewards)
            } else {
                BusinessScreen()
                    .tabItem { Label("Business", systemImage: "storefront.fill") }
                    .tag(AppTab.business)

                if role == .admin {
                    AdminScreen()
                        .tabItem { Label("Admin", systemImage: "person.badge.key.fill") }
                        .tag(AppTab.admin)
                }
            }

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .onChange(of: role) { _, _ in app.selectedTab = .run }
        .overlay(alignment: .top) {
            if app.selectedTab != .run {
                PopupHost(placement: .top).padding(.horizontal, 12).padding(.top, 4)
            }
        }
        .overlay(alignment: .bottom) {
            if app.selectedTab != .run {
                PopupHost(placement: .bottom).padding(.horizontal, 12).padding(.bottom, 56) // above the tab bar
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
        .fullScreenCover(isPresented: Binding(get: { !didOnboard }, set: { didOnboard = !$0 })) {
            OnboardingView { didOnboard = true }
        }
        .animation(.easeInOut(duration: 0.25), value: app.celebration?.id)
        .animation(.easeInOut(duration: 0.25), value: app.badgeCelebration)
    }
}
