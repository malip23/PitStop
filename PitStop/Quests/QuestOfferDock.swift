import SwiftUI

/// Compact Off-Peak Quest offer docked near the bottom: business, reward, extra distance, and
/// Accept / Dismiss in one row. The chevron expands the score breakdown and details.
struct QuestOfferDock: View {
    let offer: QuestOffer
    /// When the offer expires (nil = not timed yet).
    var deadline: Date? = nil
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: offer.business.category.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.coral.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(offer.business.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(offer.quest.reward).font(.subheadline.weight(.bold)).lineLimit(1)
                        Text("+\(Format.shortDistance(offer.extraDistance))")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.coral)
                        if let deadline { OfferSecondsLabel(deadline: deadline) }
                    }
                }
                Spacer(minLength: 4)

                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.caption.weight(.bold))
                }
                .frame(width: 32, height: 44)
                .accessibilityLabel(expanded ? "Fewer details" : "More details")

                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold))
                }
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.15), in: Circle())
                .accessibilityLabel("Dismiss offer")

                Button(action: onAccept) {
                    Text("Accept").font(.subheadline.weight(.bold)).padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Off-Peak Quest").font(.caption.weight(.heavy)).foregroundStyle(Theme.coral)
                        if offer.business.isMock { DemoBadge(compact: true) }
                    }
                    Text("\(offer.business.name) is quiet right now. Run there and check in to unlock \(offer.quest.reward.lowercased()).")
                        .font(.caption)
                    HStack(spacing: 10) {
                        Label("Close \(Int(offer.distanceScore * 100))%", systemImage: "location")
                        Label("Slow \(Int(offer.slowScore * 100))%", systemImage: "clock")
                        Label("Discover \(Int(offer.discoveryScore * 100))%", systemImage: "sparkles")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(10)
        .padding(.bottom, deadline == nil ? 0 : 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .bottom) {
            if let deadline {
                OfferCountdownBar(deadline: deadline)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 3)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.coral.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Off-Peak Quest: \(offer.quest.reward) at \(offer.business.name), \(Format.shortDistance(offer.extraDistance)) extra")
    }
}
