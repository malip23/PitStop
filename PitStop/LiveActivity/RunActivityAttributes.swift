import ActivityKit
import Foundation

/// Data for the run Live Activity (Lock Screen + Dynamic Island).
///
/// IMPORTANT: this exact type is defined twice, here (app) and in `PitStopWidgets/` (widget
/// extension), because the two targets don't share files. ActivityKit matches them by name and
/// encoding, so keep both copies identical.
nonisolated struct RunActivityAttributes: ActivityAttributes {
    /// Fixed for the whole run.
    var destinationName: String?
    var activitySymbol: String

    /// Changes during the run.
    struct ContentState: Codable, Hashable {
        /// Start of the timer, adjusted for pauses: elapsed = now − timerStart.
        var timerStart: Date
        var isPaused: Bool
        /// Elapsed seconds frozen while paused.
        var pausedElapsed: Double
        var distanceText: String
        var paceText: String
        /// "0.8 mi" left to the destination or goal, nil for a free run.
        var leftText: String?
        var nextInstruction: String?
        var nextSymbol: String?
        var nextDistanceText: String?
        /// Time-limited Off-Peak offer, with its deadline for a live countdown.
        var offer: Offer?

        struct Offer: Codable, Hashable {
            var businessName: String
            var reward: String
            var deadline: Date
        }
    }
}
