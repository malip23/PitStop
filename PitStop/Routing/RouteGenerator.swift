import MapKit

/// Builds 2–3 real route options that hit a target distance.
///
/// ## The problem
/// `MKDirections` only routes A → B. It has no waypoints and no "make it 3 miles" option. So a
/// destination 0.8 mi away can't directly give a 3 mi run, and an out-and-back over the same streets
/// is dull.
///
/// ## The algorithm: chain segments through generated waypoints
/// 1. **Direct routes.** Ask MapKit for start → destination with `requestsAlternateRoutes`. For
///    out-and-back, also get destination → start, and pair a *different* alternate for the return so
///    it becomes a loop when possible.
/// 2. **Too short? Add a waypoint.** If the best direct option is more than 10% under the goal, insert
///    waypoint W so that `start → W → destination` is the right length.
///    *Where to put W:* every point whose straight-line distances satisfy |SW| + |WD| = L lies on an
///    **ellipse** with the start S and destination D as its foci. So we pick the straight-line budget
///    L = goal ÷ 1.25 (streets are ~25% longer than straight lines) and generate candidate points
///    on that ellipse, on both sides of the S–D line, at a few angles.
///    For loops (out-and-back), each half gets budget L/2: out via a waypoint on one side, back via a
///    waypoint on the other side.
/// 3. **Measure for real.** Each candidate's legs are routed with MapKit (cached, a few at a time to
///    respect throttling), and the real total distance is summed.
/// 4. **One correction step.** Streets rarely match the 1.25 guess, so we take the best candidate,
///    scale its budget by goal ÷ actual, and route it once more.
/// 5. **Pick.** Return up to 3 options, closest to the goal first (ties broken by fewer turns).
final class RouteGenerator {
    struct Request {
        let start: CLLocationCoordinate2D
        let destination: CLLocationCoordinate2D
        let destinationName: String
        let target: Double
        let shape: RunPlan.RouteShape
        let transport: MKDirectionsTransportType
    }

    let streetFactor = 1.25
    /// Ellipse angles (degrees from the S→D axis, measured at the ellipse center). 90 / 270 are the
    /// widest points, straight out to the side.
    let candidateAngles: [Double] = [60, 90, 120, 240, 270, 300]
    let maxOptions = 3
    let concurrentRequests = 3

    private var legCache: [String: MKRoute] = [:]

    // MARK: Public

    func options(for request: Request) async -> [RouteOption] {
        var options = await directOptions(for: request)
        let bestDirect = options.min { abs($0.distance - request.target) < abs($1.distance - request.target) }

        // Step 2: only generate waypoint routes when the direct route is clearly too short.
        if bestDirect.map({ $0.distance < request.target * 0.9 }) ?? true {
            options += await generatedOptions(for: request)
        }

        // Step 5: best fit first; fewer turns breaks ties.
        return Array(options
            .sorted {
                let a = abs($0.distance - request.target), b = abs($1.distance - request.target)
                return abs(a - b) < 50 ? $0.turnCount < $1.turnCount : a < b
            }
            .prefix(maxOptions))
    }

    /// Route from where the runner is now to the rest of the plan (used when they go off route).
    func reroute(from here: CLLocationCoordinate2D, via destination: CLLocationCoordinate2D?,
                 to finish: CLLocationCoordinate2D?, destinationName: String,
                 transport: MKDirectionsTransportType) async -> RouteOption? {
        var points = [here]
        if let destination { points.append(destination) }
        if let finish { points.append(finish) }
        guard points.count >= 2, let legs = await routeLegs(through: points, transport: transport) else { return nil }
        return RouteOption(title: "Rerouted", kind: .reroute, legs: legs,
                           destinationLegIndex: destination == nil ? nil : 0, destinationName: destinationName)
    }

    /// Routes through an explicit list of points (used by the AI route agent's `get_walking_routes` tool).
    /// `destinationLegIndex` is the index of the leg that ends at the destination.
    func route(through points: [CLLocationCoordinate2D], transport: MKDirectionsTransportType,
               title: String, kind: RouteOption.Kind, waypoints: [CLLocationCoordinate2D],
               destinationLegIndex: Int, destinationName: String) async -> RouteOption? {
        guard points.count >= 2, let legs = await routeLegs(through: points, transport: transport) else { return nil }
        return RouteOption(title: title, kind: kind, legs: legs, waypoints: waypoints,
                           destinationLegIndex: destinationLegIndex, destinationName: destinationName)
    }

    // MARK: Step 1: direct routes (with MapKit alternates)

    private func directOptions(for r: Request) async -> [RouteOption] {
        let outbound = await routes(from: r.start, to: r.destination, transport: r.transport, alternates: true)
        guard !outbound.isEmpty else { return [] }

        switch r.shape {
        case .oneWay:
            return outbound.prefix(maxOptions).enumerated().map { index, route in
                RouteOption(title: index == 0 ? "Direct" : "Alternate \(index)",
                            kind: index == 0 ? .direct : .alternate, legs: [route], destinationLegIndex: 0)
            }
        case .outAndBack:
            let inbound = await routes(from: r.destination, to: r.start, transport: r.transport, alternates: true)
            guard let back = inbound.first else { return [] }
            var options = [RouteOption(title: "Out & back", kind: .direct, legs: [outbound[0], back],
                                       destinationLegIndex: 0, destinationName: r.destinationName)]
            // Go one way, return another: a natural loop when MapKit offers an alternate.
            if inbound.count > 1 {
                options.append(RouteOption(title: "Loop", kind: .alternate, legs: [outbound[0], inbound[1]],
                                           destinationLegIndex: 0, destinationName: r.destinationName))
            } else if outbound.count > 1 {
                options.append(RouteOption(title: "Loop", kind: .alternate, legs: [outbound[1], back],
                                           destinationLegIndex: 0, destinationName: r.destinationName))
            }
            return options
        }
    }

    // MARK: Steps 2–4: waypoint (ellipse) routes

    private func generatedOptions(for r: Request) async -> [RouteOption] {
        let budget = r.target / streetFactor   // straight-line budget L

        // Build candidate waypoint plans (each plan = the list of points to route through).
        var plans: [(title: String, points: [CLLocationCoordinate2D], waypoints: [CLLocationCoordinate2D], angle: Double)] = []
        switch r.shape {
        case .oneWay:
            for angle in candidateAngles {
                guard let w = ellipsePoint(focusA: r.start, focusB: r.destination, sum: budget, angle: angle) else { continue }
                plans.append(("Detour \(side(angle))", [r.start, w, r.destination], [w], angle))
            }
        case .outAndBack:
            // Out via one side, back via the opposite side: a loop through the destination.
            for angle in candidateAngles where angle < 180 {
                guard let out = ellipsePoint(focusA: r.start, focusB: r.destination, sum: budget / 2, angle: angle),
                      let back = ellipsePoint(focusA: r.start, focusB: r.destination, sum: budget / 2, angle: 360 - angle)
                else { continue }
                plans.append(("Loop", [r.start, out, r.destination, back, r.start], [out, back], angle))
            }
        }
        guard !plans.isEmpty else { return [] }

        // Step 3: route every plan for real, a few at a time.
        var measured: [(option: RouteOption, angle: Double)] = []
        for batch in plans.chunked(into: concurrentRequests) {
            let tasks = batch.map { plan in
                Task { () -> (RouteOption, Double)? in
                    guard let legs = await self.routeLegs(through: plan.points, transport: r.transport) else { return nil }
                    // Leg 1 ends at the destination in both shapes: S→W→D and S→W1→D→W2→S.
                    let destinationLeg = 1
                    return (RouteOption(title: plan.title, kind: .generated, legs: legs, waypoints: plan.waypoints,
                                        destinationLegIndex: destinationLeg, destinationName: r.destinationName), plan.angle)
                }
            }
            for task in tasks { if let result = await task.value { measured.append(result) } }
        }

        // Step 4: one correction pass on the best candidate.
        if let best = measured.min(by: { abs($0.option.distance - r.target) < abs($1.option.distance - r.target) }),
           abs(best.option.distance - r.target) > r.target * 0.05, best.option.distance > 0 {
            let corrected = budget * (r.target / best.option.distance)
            if let refined = await refine(r, budget: corrected, angle: best.angle) {
                measured.append((refined, best.angle))
            }
        }

        // Keep the best two generated options so the direct route still gets a slot.
        return measured.map(\.option)
            .sorted { abs($0.distance - r.target) < abs($1.distance - r.target) }
            .prefix(2)
            .map { $0 }
    }

    private func refine(_ r: Request, budget: Double, angle: Double) async -> RouteOption? {
        let points: [CLLocationCoordinate2D]
        let waypoints: [CLLocationCoordinate2D]
        switch r.shape {
        case .oneWay:
            guard let w = ellipsePoint(focusA: r.start, focusB: r.destination, sum: budget, angle: angle) else { return nil }
            points = [r.start, w, r.destination]; waypoints = [w]
        case .outAndBack:
            guard let out = ellipsePoint(focusA: r.start, focusB: r.destination, sum: budget / 2, angle: angle),
                  let back = ellipsePoint(focusA: r.start, focusB: r.destination, sum: budget / 2, angle: 360 - angle)
            else { return nil }
            points = [r.start, out, r.destination, back, r.start]; waypoints = [out, back]
        }
        guard let legs = await routeLegs(through: points, transport: r.transport) else { return nil }
        return RouteOption(title: r.shape == .oneWay ? "Best fit" : "Best-fit loop", kind: .generated, legs: legs,
                           waypoints: waypoints, destinationLegIndex: 1, destinationName: r.destinationName)
    }

    /// A point on the ellipse with foci A and B where |PA| + |PB| = `sum` (meters).
    /// `angle` is measured at the ellipse's center from the A→B axis. Returns nil if the ellipse can't
    /// exist (budget shorter than the A–B distance).
    func ellipsePoint(focusA: CLLocationCoordinate2D, focusB: CLLocationCoordinate2D,
                      sum: Double, angle: Double) -> CLLocationCoordinate2D? {
        let focalDistance = focusA.distance(to: focusB)
        let a = sum / 2                    // semi-major axis
        let c = focalDistance / 2          // center → focus
        guard a > c + 30 else { return nil }
        let b = (a * a - c * c).squareRoot()   // semi-minor axis

        let center = focusA.offset(bearingDegrees: focusA.bearing(to: focusB), meters: c)
        let theta = angle * .pi / 180
        let along = a * cos(theta)         // along the A→B axis
        let across = b * sin(theta)        // perpendicular (positive = right of A→B)
        let axisBearing = focusA.bearing(to: focusB)
        let distance = (along * along + across * across).squareRoot()
        let bearing = axisBearing + atan2(across, along) * 180 / .pi
        return center.offset(bearingDegrees: bearing, meters: distance)
    }

    /// Angles under 180° put the waypoint to the right of the start→destination line.
    private func side(_ angle: Double) -> String { angle < 180 ? "right" : "left" }

    // MARK: MapKit helpers (cached)

    /// Routes through every point in order, returning one MKRoute per leg (nil if any leg fails).
    private func routeLegs(through points: [CLLocationCoordinate2D], transport: MKDirectionsTransportType) async -> [MKRoute]? {
        var legs: [MKRoute] = []
        for (a, b) in zip(points, points.dropFirst()) {
            guard let leg = await routes(from: a, to: b, transport: transport, alternates: false).first else { return nil }
            legs.append(leg)
        }
        return legs
    }

    private func routes(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
                        transport: MKDirectionsTransportType, alternates: Bool) async -> [MKRoute] {
        let key = String(format: "%.4f,%.4f>%.4f,%.4f|%lu", a.latitude, a.longitude, b.latitude, b.longitude, transport.rawValue)
        if !alternates, let cached = legCache[key] { return [cached] }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = transport
        request.requestsAlternateRoutes = alternates
        guard let response = try? await MKDirections(request: request).calculate() else { return [] }
        if let first = response.routes.first { legCache[key] = first }
        return response.routes
    }
}
