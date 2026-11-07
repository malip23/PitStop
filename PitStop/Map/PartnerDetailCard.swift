import SwiftUI

/// Detail card for a tapped partner business. Shows its live quest and reward when it's slow.
struct PartnerDetailCard: View {
    @Environment(AppState.self) private var app
    let business: Business
    let onClose: () -> Void

    var body: some View {
        MaterialCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: business.category.symbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(business.name).font(.headline)
                            if business.isMock { DemoBadge(compact: true) }
                        }
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        if let address = business.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                        Label("PitStop partner", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    CloseButton(action: onClose)
                }
                questSection
                HStack(spacing: 8) {
                    DestinationButton(isCurrent: app.destination?.id == business.id) {
                        app.setDestination(PlannedDestination(business: business))
                    }
                    SaveForLaterButton(destination: PlannedDestination(business: business))
                }
            }
        }
    }

    @ViewBuilder private var questSection: some View {
        if let accepted = app.acceptedQuest, accepted.business.id == business.id {
            Label("Quest accepted: \(accepted.quest.reward)", systemImage: "figure.run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else if let offer = app.offers.first(where: { $0.business.id == business.id }) {
            HStack {
                Label(offer.quest.reward, systemImage: "gift.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button("Accept Quest") { app.accept(offer) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        } else if business.isSlow {
            Text("Quest is live, but it's more than a 1.5 mi detour from you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Not slow right now. No active quest.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        guard let here = app.currentLocation else { return business.category.displayName }
        return "\(business.category.displayName) · \(Format.shortDistance(here.distance(from: business.location))) away"
    }
}
