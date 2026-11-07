import SwiftUI

/// Detail card for a tapped real place. Shows real info only. Never rewards or quests,
/// because this place hasn't agreed to offer any.
struct RealPlaceDetailCard: View {
    @Environment(AppState.self) private var app
    let place: RealPlace
    let onClose: () -> Void

    var body: some View {
        MaterialCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: place.category.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name).font(.headline)
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        if let address = place.address {
                            Label(address, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label("Not on PitStop yet", systemImage: "hourglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .padding(.top, 4)
                        Text("No rewards or quests until this business joins PitStop.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    CloseButton(action: onClose)
                }
                // Real places can be a run destination, just never a reward.
                DestinationButton(isCurrent: app.destination?.id == place.id) {
                    app.setDestination(PlannedDestination(place: place))
                }
            }
        }
    }

    private var subtitle: String {
        guard let here = app.currentLocation else { return place.category.displayName }
        return "\(place.category.displayName) · \(Format.shortDistance(here.distance(from: place.location))) away"
    }
}
