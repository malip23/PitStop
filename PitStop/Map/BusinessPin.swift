import SwiftUI

/// Map annotation for a PARTNER business: large, accent-colored, and impossible to miss.
/// Pulses when the business has a live quest. Mock businesses carry a small "DEMO" badge.
struct BusinessPin: View {
    let business: Business
    var isSelected = false
    var hasQuest = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: business.category.symbol)
                .font(.system(size: isSelected ? 20 : 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: isSelected ? 46 : 38, height: isSelected ? 46 : 38)
                .background(Color.accentColor.gradient, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: Color.accentColor.opacity(hasQuest ? 0.8 : 0.4), radius: hasQuest ? 10 : 5)
                .symbolEffect(.pulse, isActive: hasQuest)
                .overlay(alignment: .topTrailing) {
                    if hasQuest {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18, height: 18)
                            .background(.white, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if business.isMock { DemoBadge(compact: true).offset(y: 7) }
                }

            // Little pointer under the bubble.
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color.accentColor)
                .offset(y: -5)
        }
        .animation(.spring(duration: 0.3), value: isSelected)
    }
}
