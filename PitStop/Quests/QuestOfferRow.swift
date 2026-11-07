import SwiftUI

/// A ranked quest offer in the Quests list, with its score breakdown.
struct QuestOfferRow: View {
    let offer: QuestOffer
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: offer.business.category.symbol)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(offer.quest.reward).font(.headline)
                        if offer.business.isMock { DemoBadge(compact: true) }
                    }
                    Text("\(offer.business.name) · \(Format.shortDistance(offer.extraDistance)) detour")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(Int((offer.score * 100).rounded()))")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Match score \(Int(offer.score * 100))")
            }

            // Why it ranked here: closeness, urgency, fair discovery.
            HStack(spacing: 12) {
                ScorePill(label: "Close", value: offer.distanceScore, symbol: "location")
                ScorePill(label: "Slow", value: offer.slowScore, symbol: "clock")
                ScorePill(label: "Discover", value: offer.discoveryScore, symbol: "sparkles")
            }

            HStack {
                Button("Dismiss", action: onDismiss).buttonStyle(.bordered)
                Spacer()
                Button(action: onAccept) { Label("Accept", systemImage: "figure.run") }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

private struct ScorePill: View {
    let label: String
    let value: Double
    let symbol: String

    var body: some View {
        Label("\(label) \(Int((value * 100).rounded()))%", systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
