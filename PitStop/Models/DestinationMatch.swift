import Foundation

/// A destination that fits the run goal, with the real route numbers behind it.
struct DestinationMatch: Identifiable, Hashable {
    let destination: PlannedDestination
    /// Route distance start → destination, meters.
    let legDistance: Double
    /// Whole run: one leg for one-way, two legs for out-and-back.
    let totalDistance: Double
    /// 0–1: how close `totalDistance` is to the goal (1 = exact).
    let fit: Double
    /// Only partners with a live Off-Peak Quest have a reward. Real places never do.
    let reward: String?
    let questID: Quest.ID?
    /// true = MapKit routing failed, so distance is a straight-line estimate.
    let isEstimate: Bool
    /// Direct route is shorter than the goal. The RouteGenerator adds waypoints to make up the distance.
    let needsLongerRoute: Bool

    var id: String { destination.id }
    var hasQuest: Bool { reward != nil }

    /// Real-place matches can come from ring searches far from the cached nearby places, so the map
    /// and detail card rebuild a RealPlace from the match.
    var realPlace: RealPlace? {
        guard destination.kind == .realPlace else { return nil }
        return RealPlace(id: destination.id, name: destination.name, category: destination.category,
                         address: destination.address, latitude: destination.latitude, longitude: destination.longitude)
    }
}
