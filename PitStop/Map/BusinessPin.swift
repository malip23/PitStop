import SwiftUI

/// Map annotation for a PARTNER business: large, coral, and impossible to miss.
///
/// - Live quest: glowing pulse plus a reward badge above the pin
/// - Corner badges: ✨ new / ⭐ recommended (top-left), 🏁 destination / ✓ visited (top-right)
/// - Mock businesses carry a "DEMO" tag at the bottom
struct BusinessPin: View {
    let business: Business
    var status = PinStatus()

    private var size: CGFloat { status.isSelected ? 48 : 40 }
    private var fill: Color { status.isRecommended && !status.hasQuest ? Theme.sky : Theme.coral }

    var body: some View {
        VStack(spacing: 3) {
            if let label = status.matchLabel {
                MatchLabel(text: label)
            }
            if status.hasQuest {
                rewardBadge
            }
            ZStack {
                if status.hasQuest {
                    PulseRing(color: Theme.coral, size: size)
                }
                Image(systemName: business.category.symbol)
                    .font(.system(size: status.isSelected ? 20 : 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(fill.gradient, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: fill.opacity(status.hasQuest ? 0.9 : 0.45), radius: status.hasQuest ? 12 : 5)
                    .overlay(alignment: .topLeading) {
                        if status.isRecommended { PinBadge.recommended.offset(x: -6, y: -6) }
                        else if status.isNew { PinBadge.new.offset(x: -6, y: -6) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if status.isDestination { PinBadge.destination.offset(x: 7, y: -7) }
                        else if status.isVisited { PinBadge.visited.offset(x: 6, y: -6) }
                    }
                    .overlay(alignment: .bottom) {
                        if business.isMock { DemoBadge(compact: true).offset(y: 7) }
                    }
            }
            // Pointer under the bubble.
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .rotationEffect(.degrees(180))
                .foregroundStyle(fill)
                .offset(y: -3)
        }
        .animation(.spring(duration: 0.3), value: status)
    }

    private var rewardBadge: some View {
        Label(business.reward, systemImage: "gift.fill")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            .frame(maxWidth: 150)
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.sun, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}
