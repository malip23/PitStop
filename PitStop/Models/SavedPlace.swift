import Foundation
import SwiftData

/// A "Future Place": somewhere the user saved to run to later.
/// Maps onto Firestore `users/{uid}/savedPlaces/{id}`.
@Model
final class SavedPlace {
    enum Source: String, Codable { case map, narration, recommendation }

    /// Same id as the business or real place, so a place can only be saved once.
    @Attribute(.unique) var id: String
    var name: String
    var categoryRaw: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var isPartner: Bool
    var savedAt: Date
    var sourceRaw: String

    init(destination: PlannedDestination, source: Source) {
        id = destination.id
        name = destination.name
        categoryRaw = destination.category.rawValue
        latitude = destination.latitude
        longitude = destination.longitude
        address = destination.address
        isPartner = destination.isPartner
        savedAt = .now
        sourceRaw = source.rawValue
    }

    var category: BusinessCategory { BusinessCategory(rawValue: categoryRaw) ?? .other }
    var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    /// Rebuilds a destination so "Plan a run here" can route to it.
    var destination: PlannedDestination {
        if isPartner {
            return PlannedDestination(business: Business(id: id, name: name, category: category, latitude: latitude,
                                                         longitude: longitude, address: address, reward: ""))
        }
        return PlannedDestination(place: RealPlace(id: id, name: name, category: category, address: address,
                                                   latitude: latitude, longitude: longitude))
    }
}
