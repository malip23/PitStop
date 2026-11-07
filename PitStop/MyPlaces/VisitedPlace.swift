import Foundation

/// A place the user has checked in at, aggregated from run history (one entry per destination).
struct VisitedPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let category: BusinessCategory
    let point: GeoPoint
    let isPartner: Bool
    let visitCount: Int
    let lastVisit: Date
    let firstVisit: Date

    /// Groups checked-in runs by destination.
    static func from(_ runs: [RunRecord]) -> [VisitedPlace] {
        Dictionary(grouping: runs.filter { $0.checkedIn && $0.destinationId != nil }, by: { $0.destinationId! })
            .compactMap { id, runs -> VisitedPlace? in
                guard let latest = runs.max(by: { $0.date < $1.date }), let point = latest.destinationPoint else { return nil }
                return VisitedPlace(id: id, name: latest.destinationName ?? "Place", category: latest.destinationCategory,
                                    point: point, isPartner: latest.isPartner, visitCount: runs.count,
                                    lastVisit: latest.date, firstVisit: runs.map(\.date).min() ?? latest.date)
            }
            .sorted { $0.lastVisit > $1.lastVisit }
    }

    var destination: PlannedDestination {
        let place = RealPlace(id: id, name: name, category: category, address: nil,
                              latitude: point.latitude, longitude: point.longitude)
        return PlannedDestination(place: place)
    }
}
