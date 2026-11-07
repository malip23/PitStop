import Foundation
import SwiftData

/// A real perk from a partner business, unlocked by a verified quest check-in.
/// Maps onto Firestore `users/{uid}/rewards/{id}` (kind "partner").
@Model
final class EarnedReward {
    @Attribute(.unique) var id: String
    var businessId: String
    var businessName: String
    var categoryRaw: String
    var reward: String
    var questId: String?
    var runId: String?
    var earnedAt: Date
    /// Shown to staff at the counter. Redeemed rewards stay in the list, marked used.
    var redeemed: Bool

    init(business: PlannedDestination, reward: String, questId: String?, runId: String?) {
        id = UUID().uuidString
        businessId = business.id
        businessName = business.name
        categoryRaw = business.category.rawValue
        self.reward = reward
        self.questId = questId
        self.runId = runId
        earnedAt = .now
        redeemed = false
    }

    var category: BusinessCategory { BusinessCategory(rawValue: categoryRaw) ?? .other }
}
