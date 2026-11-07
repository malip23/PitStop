import CoreLocation
import Observation

/// Turn-by-turn guidance along a RouteOption.
///
/// On every location fix it:
/// 1. **Snaps** the runner onto the route: finds the nearest segment, searching forward from the last
///    match so out-and-back routes (which overlap themselves) don't jump to the return leg.
/// 2. Computes **progress** (meters along the route), the **remaining** distance, and the **next step**.
/// 3. Flags **off-route** when the runner is more than `offRouteThreshold` meters away for 2+ fixes.
/// 4. Plays **turn haptics** once when a turn is 40 m away, and again at the turn.
@Observable
final class NavigationEngine {
    private(set) var route: RouteOption?
    private(set) var progress: Double = 0
    private(set) var nextStep: NavStep?
    private(set) var distanceToNextStep: Double = 0
    private(set) var isOffRoute = false
    private(set) var hasArrived = false
    private(set) var reachedDestination = false
    /// Covered part of the route (drawn lime) and what's left (drawn coral).
    private(set) var completedCoordinates: [CLLocationCoordinate2D] = []
    private(set) var remainingCoordinates: [CLLocationCoordinate2D] = []

    let offRouteThreshold: CLLocationDistance = 40
    let upcomingTurnDistance: CLLocationDistance = 40
    let arrivalDistance: CLLocationDistance = 25

    /// Called once when the runner reaches the destination (the midpoint of an out-and-back).
    @ObservationIgnored var onReachDestination: (() -> Void)?

    @ObservationIgnored private var cumulative: [Double] = []   // distance from start to each vertex
    @ObservationIgnored private var segmentIndex = 0
    @ObservationIgnored private var offRouteCount = 0
    @ObservationIgnored private var warnedSteps: Set<Double> = []
    @ObservationIgnored private var passedSteps: Set<Double> = []

    var isNavigating: Bool { route != nil }
    var remainingDistance: Double { max(0, (route?.distance ?? 0) - progress) }

    func start(_ route: RouteOption) {
        self.route = route
        cumulative = [0]
        for (a, b) in zip(route.coordinates, route.coordinates.dropFirst()) {
            cumulative.append(cumulative.last! + a.distance(to: b))
        }
        segmentIndex = 0
        progress = 0
        offRouteCount = 0
        isOffRoute = false
        hasArrived = false
        reachedDestination = false
        warnedSteps = []
        passedSteps = []
        completedCoordinates = []
        remainingCoordinates = route.coordinates
        nextStep = route.steps.first { $0.distanceFromStart > 1 }
        distanceToNextStep = nextStep?.distanceFromStart ?? 0
    }

    func stop() {
        route = nil
        completedCoordinates = []
        remainingCoordinates = []
        nextStep = nil
        isOffRoute = false
    }

    func update(with fix: CLLocation) {
        guard let route, route.coordinates.count > 1 else { return }
        let here = fix.coordinate

        // 1. Snap: search a window ahead of (and slightly behind) the last matched segment.
        let lower = max(0, segmentIndex - 3)
        let upper = min(route.coordinates.count - 2, segmentIndex + 80)
        var best = (index: segmentIndex, distance: Double.greatestFiniteMagnitude, fraction: 0.0)
        for i in lower...upper {
            let (d, t) = Self.distance(from: here, toSegment: route.coordinates[i], route.coordinates[i + 1])
            if d < best.distance { best = (i, d, t) }
        }

        // 3. Off-route check (two fixes in a row, so one noisy GPS point doesn't trigger it).
        if best.distance > offRouteThreshold {
            offRouteCount += 1
            if offRouteCount >= 2, !isOffRoute {
                isOffRoute = true
                Haptics.warning()
            }
            return
        }
        offRouteCount = 0
        isOffRoute = false

        // 2. Progress along the route.
        segmentIndex = best.index
        let segmentLength = cumulative[best.index + 1] - cumulative[best.index]
        progress = max(progress, cumulative[best.index] + segmentLength * best.fraction)
        let snapped = Self.interpolate(route.coordinates[best.index], route.coordinates[best.index + 1], best.fraction)
        completedCoordinates = Array(route.coordinates[0...best.index]) + [snapped]
        remainingCoordinates = [snapped] + Array(route.coordinates[(best.index + 1)...])

        // Next instruction = first step still ahead.
        nextStep = route.steps.first { $0.distanceFromStart > progress + 3 }
        distanceToNextStep = max(0, (nextStep?.distanceFromStart ?? route.distance) - progress)

        // 4. Turn haptics.
        if let step = nextStep {
            if distanceToNextStep < upcomingTurnDistance, !warnedSteps.contains(step.distanceFromStart) {
                warnedSteps.insert(step.distanceFromStart)
                Haptics.tap()
            }
        }
        for step in route.steps where step.distanceFromStart <= progress && !passedSteps.contains(step.distanceFromStart) {
            passedSteps.insert(step.distanceFromStart)
            if step.distanceFromStart > 1 { Haptics.success() }
        }

        if !reachedDestination, progress >= route.destinationDistance - arrivalDistance {
            reachedDestination = true
            onReachDestination?()
        }
        if !hasArrived, remainingDistance < arrivalDistance {
            hasArrived = true
        }
    }

    // MARK: Geometry (flat-earth approximation, fine at running scale)

    /// Distance (m) from point P to segment AB, and how far along AB (0–1) the closest point is.
    static func distance(from p: CLLocationCoordinate2D, toSegment a: CLLocationCoordinate2D,
                         _ b: CLLocationCoordinate2D) -> (Double, Double) {
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(a.latitude * .pi / 180)
        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * metersPerDegLon, by = (b.latitude - a.latitude) * metersPerDegLat
        let px = (p.longitude - a.longitude) * metersPerDegLon, py = (p.latitude - a.latitude) * metersPerDegLat
        let lengthSquared = bx * bx + by * by
        let t = lengthSquared > 0 ? min(max(((px - ax) * bx + (py - ay) * by) / lengthSquared, 0), 1) : 0
        let dx = px - t * bx, dy = py - t * by
        return ((dx * dx + dy * dy).squareRoot(), t)
    }

    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
}
