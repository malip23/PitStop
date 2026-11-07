import CoreLocation
import Observation

/// Crosswalk, traffic-signal, and intersection alerts along the active route.
///
/// **Prepare** (when a route is selected, before the run starts):
/// 1. Fetch OpenStreetMap crossings and signals in the route's bounding box plus a small buffer.
/// 2. Keep only nodes within `onRouteDistance` of the route, and record *every* place the route
///    passes them. An out-and-back passes the same crosswalk twice, so it alerts twice.
/// 3. Add each turn from the route steps as an intersection.
/// 4. Merge points less than `mergeDistance` apart along the route (keeping the most important kind),
///    so one busy corner gives one alert, not three.
/// If Overpass is unavailable, only the turn-based intersections are used.
///
/// **Update** (every fix, with the runner's progress along the route):
/// alert once when a point is ≤ `alertDistance` ahead. Points already behind are never alerted.
@Observable
final class CrossingAlertEngine {
    enum Source: Equatable {
        case none
        case loading
        case openStreetMap(crossings: Int)
        case turnsOnly
    }

    private(set) var points: [CrossingPoint] = []
    private(set) var activeAlert: CrossingPoint?
    private(set) var source: Source = .none
    private(set) var progress: Double = 0

    let alertDistance: Double = 30
    let mergeDistance: Double = 20
    let onRouteDistance: Double = 15
    let bboxBuffer: Double = 60   // meters around the route's bounding box

    /// Called once per alert (AppState speaks it if voice cues are on).
    @ObservationIgnored var onAlert: ((CrossingPoint) -> Void)?

    @ObservationIgnored private var preparedRouteID: RouteOption.ID?
    @ObservationIgnored private var alerted: Set<CrossingPoint.ID> = []
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Points coming up in the next 300 m (drawn on the map while navigating).
    var upcomingPoints: [CrossingPoint] {
        points.filter { $0.distanceAlongRoute >= progress - 5 && $0.distanceAlongRoute <= progress + 300 }
    }

    func reset() {
        task?.cancel()
        points = []
        activeAlert = nil
        source = .none
        progress = 0
        preparedRouteID = nil
        alerted = []
    }

    /// Fetches and builds alert points for a route. Does nothing if this route is already prepared.
    func prepare(_ route: RouteOption) {
        guard route.id != preparedRouteID else { return }
        task?.cancel()
        preparedRouteID = route.id
        alerted = []
        activeAlert = nil
        progress = 0
        let turns = turnPoints(for: route)
        points = turns
        source = .loading

        task = Task {
            let nodes = await fetchNodes(around: route)
            guard !Task.isCancelled, preparedRouteID == route.id else { return }
            guard let nodes else {
                points = turns
                source = .turnsOnly
                return
            }
            let crossings = project(nodes, onto: route)
            points = merge(crossings + turns)
            source = .openStreetMap(crossings: crossings.count)
        }
    }

    /// Call on each fix with the runner's distance along the route.
    func update(progress: Double) {
        self.progress = progress

        // Clear the banner once the point is behind the runner.
        if let active = activeAlert, progress > active.distanceAlongRoute + 10 {
            activeAlert = nil
        }

        // Next point ahead that hasn't alerted yet.
        guard let next = points.first(where: {
            !alerted.contains($0.id) && $0.distanceAlongRoute >= progress - 2
        }) else { return }

        // Anything we skipped past (e.g. a GPS jump) is marked so it never fires late.
        for point in points where point.distanceAlongRoute < progress - 2 { alerted.insert(point.id) }

        if next.distanceAlongRoute - progress <= alertDistance {
            alerted.insert(next.id)
            activeAlert = next
            Haptics.tap()
            onAlert?(next)
        }
    }

    // MARK: Building points

    private func turnPoints(for route: RouteOption) -> [CrossingPoint] {
        route.steps
            .filter { $0.distanceFromStart > 5 && !$0.isDestination && $0.symbol != "arrow.up" && $0.symbol != "flag.checkered" }
            .map { CrossingPoint(kind: .turn, coordinate: $0.coordinate, distanceAlongRoute: $0.distanceFromStart) }
    }

    private func fetchNodes(around route: RouteOption) async -> [OverpassService.Node]? {
        guard let first = route.coordinates.first else { return [] }
        var south = first.latitude, north = first.latitude, west = first.longitude, east = first.longitude
        for c in route.coordinates {
            south = min(south, c.latitude); north = max(north, c.latitude)
            west = min(west, c.longitude); east = max(east, c.longitude)
        }
        let dLat = bboxBuffer / 111_320
        let dLon = bboxBuffer / (111_320 * cos(first.latitude * .pi / 180))
        return try? await OverpassService.crossings(south: south - dLat, west: west - dLon,
                                                    north: north + dLat, east: east + dLon)
    }

    /// Every pass of the route within `onRouteDistance` of a node becomes one CrossingPoint.
    private func project(_ nodes: [OverpassService.Node], onto route: RouteOption) -> [CrossingPoint] {
        let coords = route.coordinates
        guard coords.count > 1 else { return [] }
        var cumulative: [Double] = [0]
        for (a, b) in zip(coords, coords.dropFirst()) { cumulative.append(cumulative.last! + a.distance(to: b)) }

        var result: [CrossingPoint] = []
        for node in nodes {
            let kind: CrossingPoint.Kind = node.isTrafficSignal ? .trafficSignal : .crosswalk
            var best: (distance: Double, along: Double)?
            var passes: [Double] = []
            for i in 0..<(coords.count - 1) {
                let (d, t) = NavigationEngine.distance(from: node.coordinate, toSegment: coords[i], coords[i + 1])
                if d <= onRouteDistance {
                    let along = cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t
                    if best == nil || d < best!.distance { best = (d, along) }
                } else if let pass = best {
                    passes.append(pass.along)   // left the node's vicinity: one pass complete
                    best = nil
                }
            }
            if let pass = best { passes.append(pass.along) }

            // Separate passes must be well apart along the route (an out-and-back's return leg).
            var lastPass = -Double.infinity
            for along in passes where along - lastPass > 40 {
                result.append(CrossingPoint(kind: kind, coordinate: node.coordinate, distanceAlongRoute: along))
                lastPass = along
            }
        }
        return result
    }

    /// Merges points closer than `mergeDistance` along the route, keeping the most important kind.
    private func merge(_ all: [CrossingPoint]) -> [CrossingPoint] {
        var merged: [CrossingPoint] = []
        for point in all.sorted(by: { $0.distanceAlongRoute < $1.distanceAlongRoute }) {
            if let last = merged.last, point.distanceAlongRoute - last.distanceAlongRoute < mergeDistance {
                if point.kind > last.kind { merged[merged.count - 1].kind = point.kind }
            } else {
                merged.append(point)
            }
        }
        return merged
    }
}
