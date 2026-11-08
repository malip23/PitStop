import Foundation

/// An Off-Peak Quest: "run to this slow business and unlock its reward."
/// Firestore document `quests/{id}`.
struct Quest: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case active     // business is slow, offered to runners
        case accepted   // a runner is on the way
        case completed  // runner checked in
        case expired    // business is no longer slow
    }

    var id: String = UUID().uuidString
    var businessId: String
    var reward: String
    var status: Status = .active
    var runnerUid: String?
    var etaSeconds: Double?
    /// When the runner last reported the ETA (the business counts down from here).
    var etaUpdatedAt: Date?
    var createdAt: Date = .now
    var completedAt: Date?
    /// What happened to the timed offer popups for this quest (shown to the business).
    var offerStats: OfferStats?

    var isOpen: Bool { status == .active || status == .accepted }
}

/// Outcome counts for a quest's timed offers. Optional on Quest so older saved files still load.
/// Maps onto Firestore fields on `quests/{id}` later.
struct OfferStats: Codable, Hashable, Sendable {
    enum Outcome: String, Codable, Sendable { case shown, accepted, dismissed, expired }

    var shown = 0
    var accepted = 0
    var dismissed = 0
    var expired = 0
    var lastOutcome: Outcome?
    var lastOutcomeAt: Date?
}
