import Foundation
import SwiftData

/// A milestone badge the user has earned. Maps onto Firestore `users/{uid}/rewards/{id}` (kind "badge").
@Model
final class EarnedBadge {
    /// `BadgeKind.rawValue`, so each badge is earned once.
    @Attribute(.unique) var id: String
    var earnedAt: Date

    init(kind: BadgeKind) {
        id = kind.rawValue
        earnedAt = .now
    }

    var kind: BadgeKind? { BadgeKind(rawValue: id) }
}
