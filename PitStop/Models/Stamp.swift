import Foundation
import SwiftData

/// A digital passport stamp: earned by the first VERIFIED check-in at a place.
/// Collectible only, not a real perk. Maps onto Firestore `users/{uid}/rewards/{id}` (kind "stamp").
@Model
final class Stamp {
    /// The place's id, so each place can only be stamped once.
    @Attribute(.unique) var id: String
    var placeName: String
    var categoryRaw: String
    var latitude: Double
    var longitude: Double
    var isPartner: Bool
    var earnedAt: Date
    var runId: String?

    init(place: PlannedDestination, runId: String?) {
        id = place.id
        placeName = place.name
        categoryRaw = place.category.rawValue
        latitude = place.latitude
        longitude = place.longitude
        isPartner = place.isPartner
        earnedAt = .now
        self.runId = runId
    }

    var category: BusinessCategory { BusinessCategory(rawValue: categoryRaw) ?? .other }
}
