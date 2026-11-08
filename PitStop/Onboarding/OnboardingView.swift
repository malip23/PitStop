import SwiftUI

/// First-launch onboarding: what PitStop is, pick interests, then location.
/// Other permissions (Always location, Motion, notifications) are asked later, at the moment they
/// matter (first run start, first quest), not all at once here.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    let onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                interests.tag(1)
                location.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < 2 ? "Continue" : (app.location.isAuthorized ? "Start exploring" : "Allow location"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            if page == 2 && !app.location.isAuthorized {
                Button("Not now", action: onFinish)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
        .onChange(of: app.location.isAuthorized) { _, granted in
            if granted, page == 2 { onFinish() }
        }
    }

    private func finish() {
        if app.location.isAuthorized {
            onFinish()
        } else {
            app.location.requestWhenInUse()   // finishes automatically once granted (onChange above)
        }
    }

    // MARK: Pages

    private var welcome: some View {
        page(symbol: "figure.run.circle.fill", tint: Theme.coral, title: "Run somewhere worth it",
             text: "PitStop turns your run into a little adventure: routes that fit your goal, safety alerts, and stamps for every new place.") {
            VStack(alignment: .leading, spacing: 14) {
                feature("storefront.fill", Theme.coral, "Off-Peak Quests", "Local shops that are quiet right now offer real rewards if you run there.")
                feature("sparkles", Theme.sky, "AI routes", "Scenic paths checked with Apple Maps, sized to your goal.")
                feature("seal.fill", Theme.lime, "Passport", "Collect a stamp for every new place you reach.")
            }
        }
    }

    private var interests: some View {
        page(symbol: "heart.circle.fill", tint: Theme.sky, title: "What do you love?",
             text: "We'll use this to suggest places and scenic routes. Change it anytime in Settings.") {
            InterestGrid()
        }
    }

    private var location: some View {
        page(symbol: "location.circle.fill", tint: Theme.lime, title: "Find places near you",
             text: "PitStop uses your location to show nearby places, build routes, and track your runs. We'll ask about motion, health, and notifications later, when you need them.") {
            Label("Your location stays on your phone. AI only ever gets a rough area (about 100 m).", systemImage: "lock.shield.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func page<Content: View>(symbol: String, tint: Color, title: String, text: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 72))
                    .foregroundStyle(tint.gradient)
                    .padding(.top, 40)
                Text(title).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                content().padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
