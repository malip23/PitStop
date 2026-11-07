import Foundation

/// What the celebration card shows after a check-in.
struct CheckInEvent: Identifiable {
    let id = UUID()
    let destination: PlannedDestination
    /// Partner reward unlocked (nil for real places, or if verification failed).
    let reward: String?
    /// The quest's reward text even when it stayed locked, to explain why.
    let lockedReward: String?
    let verification: VerificationResult
    let isFirstVisit: Bool
    /// A new passport stamp was earned at this check-in.
    let earnedStamp: Bool
}
