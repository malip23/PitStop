import CoreLocation

/// A PARTNER business: the only kind that can offer rewards and create Off-Peak Quests.
///
/// The field names mirror the planned Firestore document `businesses/{id}`, so moving from the
/// local JSON file to the cloud is a straight copy.
struct Business: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var category: BusinessCategory
    var latitude: Double
    var longitude: Double
    var address: String?
    /// True for demo/test businesses created in Business mode. Shown with a "Demo" badge.
    var isMock: Bool = true
    /// Set when the mock business was created from a real MapKit place.
    var linkedRealPlaceName: String?
    var isSlow: Bool = false
    var reward: String
    var slowSince: Date?
    var createdAt: Date = .now
    /// Firebase uid of the owner (filled in once accounts exist).
    var ownerUid: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
