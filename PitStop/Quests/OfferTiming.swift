import SwiftUI

/// Timing for time-limited offers (discounts / Off-Peak Quests).
enum OfferTiming {
    /// How long a runner has to accept an offer popup. Change this one value to tune it.
    static let countdown: TimeInterval = 30
    /// A light haptic (and VoiceOver reminder) when this many seconds remain.
    static let warningAt: TimeInterval = 10

    /// Bar color: green, then yellow under 15 s, then red under 5 s.
    static func color(remaining: TimeInterval) -> Color {
        remaining < 5 ? .red : remaining < 15 ? .yellow : .green
    }
}
