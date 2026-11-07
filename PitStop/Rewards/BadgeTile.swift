import SwiftUI

/// One milestone badge: colorful when earned, gray with a progress bar when locked.
struct BadgeTile: View {
    let kind: BadgeKind
    let stats: RewardStats
    let earnedAt: Date?

    var body: some View {
        let earned = earnedAt != nil
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(earned ? AnyShapeStyle(kind.color.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                    .frame(width: 58, height: 58)
                Image(systemName: earned ? kind.symbol : "lock.fill")
                    .font(.system(size: earned ? 24 : 18, weight: .bold))
                    .foregroundStyle(earned ? .white : .secondary)
            }
            .overlay(Circle().stroke(.white.opacity(earned ? 0.9 : 0), lineWidth: 3))
            .shadow(color: earned ? kind.color.opacity(0.45) : .clear, radius: 8, y: 3)

            Text(kind.title).font(.subheadline.weight(.bold)).lineLimit(1)
            Text(kind.detail).font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(2)

            if let earnedAt {
                Text(earnedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.semibold)).foregroundStyle(kind.color)
            } else {
                VStack(spacing: 3) {
                    ProgressView(value: min(kind.value(in: stats) / kind.target, 1))
                        .tint(kind.color)
                    Text(kind.progressText(stats))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
