import SwiftUI

/// Small circular badges that sit on the corner of a map pin.
enum PinBadge {
    /// "New" sparkle: a business that joined recently.
    static var new: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.black.opacity(0.8))
            .frame(width: 18, height: 18)
            .background(Theme.sun, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
    }

    /// Recommended for you: star.
    static var recommended: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Theme.sky, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
    }

    /// Already in My Places: checkmark stamp.
    static var visited: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Theme.lime, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .rotationEffect(.degrees(-12))
    }

    /// Current run destination.
    static var destination: some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.primary, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
    }
}

/// Everything about a pin's state that affects how it's drawn.
struct PinStatus: Equatable {
    var isSelected = false
    var hasQuest = false
    var isNew = false
    var isRecommended = false
    var isVisited = false
    var isDestination = false
    /// Set when the pin is a goal-matched destination ("2.9 mi · 96%").
    var matchLabel: String?
}

/// Capsule under a goal-matched pin.
struct MatchLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.coralDeep, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1))
            .fixedSize()
    }
}
