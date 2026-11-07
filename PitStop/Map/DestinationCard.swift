import SwiftUI

/// Floating card for the run's destination (when it isn't an accepted quest, which has its own card).
struct DestinationCard: View {
    @Environment(AppState.self) private var app
    let destination: PlannedDestination

    var body: some View {
        MaterialCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.destinationNote ?? "Destination")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(destination.name).font(.headline).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                CloseButton {
                    app.clearDestination()
                    app.cancelPlan()
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [destination.category.displayName]
        if let here = app.currentLocation {
            parts.append("\(Format.shortDistance(here.distance(from: destination.location))) away")
        }
        if !destination.isPartner { parts.append("Not on PitStop yet") }
        return parts.joined(separator: " · ")
    }
}
