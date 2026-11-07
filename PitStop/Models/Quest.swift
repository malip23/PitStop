import Foundation

/// An Off-Peak Quest: "run to this slow business and unlock its reward."
/// Mirrors the planned Firestore document `quests/{id}`.
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
    var createdAt: Date = .now
    var completedAt: Date?

    var isOpen: Bool { status == .active || status == .accepted }
}
