import SwiftUI

/// Explains every pin and line type, drawn with the real pin views so it always matches the map.
struct MapLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let sample = Business(name: "Daybreak Coffee", category: .cafe, latitude: 0, longitude: 0,
                                  isMock: false, reward: "Free cold brew", createdAt: .distantPast)
    private let samplePlace = RealPlace(id: "sample", name: "Corner Café", category: .cafe,
                                        address: nil, latitude: 0, longitude: 0)

    var body: some View {
        NavigationStack {
            List {
                Section("Businesses") {
                    row("Off-Peak Quest live", "A partner is slow right now. Run there for the reward.") {
                        BusinessPin(business: sample, status: PinStatus(hasQuest: true)).scaleEffect(0.8)
                    }
                    row("PitStop partner", "On PitStop and able to offer rewards.") {
                        BusinessPin(business: sample)
                    }
                    row("New on PitStop", "Joined in the last 7 days.") {
                        BusinessPin(business: sample, status: PinStatus(isNew: true))
                    }
                    row("Demo business", "A mock partner created for testing and demos.") {
                        DemoBadge()
                    }
                }
                Section("Places") {
                    row("Recommended for you", "Picked for your interests and usual distance.") {
                        RealPlacePin(place: samplePlace, status: PinStatus(isRecommended: true))
                    }
                    row("Not on PitStop yet", "A real nearby place. No rewards or quests.") {
                        RealPlacePin(place: samplePlace)
                    }
                    row("In My Places", "You've run here and checked in.") {
                        PinBadge.visited.scaleEffect(1.4)
                    }
                    row("Your destination", "Where this run is headed.") {
                        PinBadge.destination.scaleEffect(1.4)
                    }
                }
                Section("Map") {
                    row("You", "The arrow shows which way you're facing.") {
                        UserLocationMarker(heading: 45).scaleEffect(0.8)
                    }
                    row("Planned route", "The path to follow.") {
                        lineSwatch(Theme.routeGradient)
                    }
                    row("Completed", "Where you've already been this run.") {
                        lineSwatch(Theme.completedGradient)
                    }
                }
            }
            .navigationTitle("Map legend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row<Icon: View>(_ title: String, _ detail: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func lineSwatch(_ colors: [Color]) -> some View {
        ZStack {
            Capsule().fill((colors.first ?? Theme.coral).opacity(0.28)).frame(width: 52, height: 16)
            Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 48, height: 6)
        }
    }
}
