import SwiftUI

/// Floating top banner announcing a new Off-Peak Quest, with Accept / Dismiss.
struct QuestOfferBanner: View {
    let offer: QuestOffer
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: offer.business.category.symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("OFF-PEAK QUEST")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.accentColor)
                        if offer.business.isMock { DemoBadge(compact: true) }
                    }
                    Text(offer.quest.reward)
                        .font(.headline)
                    Text("\(offer.business.name) · \(Format.shortDistance(offer.extraDistance)) detour")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button(action: onAccept) {
                    Label("Accept", systemImage: "figure.run").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
