import CoreLocation

/// Where the current run is headed: a partner business or a real place.
/// Partners can carry quests and rewards; real places never do.
struct PlannedDestination: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case partner, realPlace }

    let id: String
    let kind: Kind
    let name: String
    let category: BusinessCategory
    let latitude: Double
    let longitude: Double
    let address: String?

    init(business: Business) {
        id = business.id
        kind = .partner
        name = business.name
        category = business.category
        latitude = business.latitude
        longitude = business.longitude
        address = business.address
    }

    init(place: RealPlace) {
        id = place.id
        kind = .realPlace
        name = place.name
        category = place.category
        latitude = place.latitude
        longitude = place.longitude
        address = place.address
    }

    var isPartner: Bool { kind == .partner }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}
