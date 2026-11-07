import CoreLocation

/// A real nearby place found with MapKit search.
///
/// Real places have NOT agreed to offer rewards, so they're display-only: the map shows them muted
/// as "Not on PitStop yet". They're never used for quests, matching, or routing. Only partner
/// businesses (`Business`) are.
struct RealPlace: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let category: BusinessCategory
    let address: String?
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
