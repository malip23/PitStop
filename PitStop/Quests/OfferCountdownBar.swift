import SwiftUI

/// Shrinking bar along the bottom edge of a timed offer: full → empty over the countdown,
/// green → yellow (< 15 s) → red (< 5 s). Computed from the deadline on every frame, so it stays
/// exact even if the popup is hidden and shown again. With Reduce Motion it updates once a second
/// in steps instead of animating smoothly.
struct OfferCountdownBar: View {
    let deadline: Date
    var duration: TimeInterval = OfferTiming.countdown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : nil)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            // Reduce Motion: whole-second steps instead of a continuous shrink.
            let fraction = (reduceMotion ? remaining.rounded(.up) : remaining) / duration
            GeometryReader { geo in
                Capsule()
                    .fill(OfferTiming.color(remaining: remaining).gradient)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// "23s" next to the reward. Updates once per second.
struct OfferSecondsLabel: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Text("\(remaining)s")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(OfferTiming.color(remaining: Double(remaining)))
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("\(remaining) seconds left")
        }
    }
}
