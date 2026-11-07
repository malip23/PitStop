import MapKit

/// One turn-by-turn instruction placed along a route.
struct NavStep: Hashable {
    let instruction: String
    /// Where the maneuver happens (start of the step).
    let coordinate: CLLocationCoordinate2D
    /// Distance from the route's start to this maneuver, meters.
    let distanceFromStart: Double
    /// Marks the "you reached your destination" step in the middle of an out-and-back route.
    var isDestination = false

    static func == (a: NavStep, b: NavStep) -> Bool {
        a.instruction == b.instruction && a.distanceFromStart == b.distanceFromStart
    }
    func hash(into h: inout Hasher) { h.combine(instruction); h.combine(distanceFromStart) }

    /// SF Symbol guessed from the instruction text.
    var symbol: String {
        let text = instruction.lowercased()
        if isDestination || text.contains("arrive") || text.contains("destination") { return "flag.checkered" }
        if text.contains("u-turn") || text.contains("turn around") { return "arrow.uturn.down" }
        if text.contains("slight left") || text.contains("bear left") { return "arrow.up.left" }
        if text.contains("slight right") || text.contains("bear right") { return "arrow.up.right" }
        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// A complete candidate route: one or more MapKit legs chained end to end
/// (e.g. start → waypoint → destination → waypoint → start).
struct RouteOption: Identifiable, Hashable {
    enum Kind: String { case direct, alternate, generated, reroute, ai }

    let id = UUID()
    let title: String
    let kind: Kind
    /// Total length in meters (sum of the legs' real route distances).
    let distance: Double
    /// Full polyline, all legs merged.
    let coordinates: [CLLocationCoordinate2D]
    let steps: [NavStep]
    /// Intermediate waypoints the generator inserted (empty for direct routes).
    let waypoints: [CLLocationCoordinate2D]
    /// Distance from start at which the destination is reached (equals `distance` for one-way).
    let destinationDistance: Double
    /// Where the route actually arrives at the destination (on the street, which can be tens of meters
    /// from the business's own coordinate). Used for check-in.
    let destinationArrival: CLLocationCoordinate2D?
    /// Number of turns, used by the AI route agent later.
    var turnCount: Int { steps.filter { $0.symbol.contains("turn") || $0.symbol.contains("up.left") || $0.symbol.contains("up.right") }.count }

    static func == (a: RouteOption, b: RouteOption) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// 0–1 closeness to the goal distance.
    func fit(target: Double) -> Double {
        guard target > 0 else { return 1 }
        return max(0, 1 - abs(distance - target) / target)
    }

    /// Chains MapKit routes into one option.
    /// `destinationLegIndex` is the index of the leg that ENDS at the destination.
    init(title: String, kind: Kind, legs: [MKRoute], waypoints: [CLLocationCoordinate2D] = [],
         destinationLegIndex: Int? = nil, destinationName: String? = nil) {
        self.title = title
        self.kind = kind
        self.waypoints = waypoints

        var coords: [CLLocationCoordinate2D] = []
        var steps: [NavStep] = []
        var offset = 0.0
        var destinationDistance = 0.0
        var arrival: CLLocationCoordinate2D?
        for (index, leg) in legs.enumerated() {
            let points = leg.polyline.coordinates
            coords += coords.isEmpty ? points : Array(points.dropFirst())
            var stepStart = offset
            for step in leg.steps {
                let text = step.instructions.trimmingCharacters(in: .whitespaces)
                // Skip empty steps and the "arrive" step of intermediate (waypoint) legs.
                let isLegEnd = step === leg.steps.last
                if !text.isEmpty, !(isLegEnd && index < legs.count - 1),
                   let first = step.polyline.coordinates.first {
                    steps.append(NavStep(instruction: text, coordinate: first, distanceFromStart: stepStart))
                }
                stepStart += step.distance
            }
            offset += leg.distance
            if index == destinationLegIndex {
                destinationDistance = offset
                arrival = points.last
                // In an out-and-back route, the destination sits in the middle, so announce it.
                if index < legs.count - 1, let end = points.last {
                    steps.append(NavStep(instruction: "You've reached \(destinationName ?? "your destination"). Head back home.",
                                         coordinate: end, distanceFromStart: offset, isDestination: true))
                }
            }
        }
        self.coordinates = coords
        self.steps = steps.sorted { $0.distanceFromStart < $1.distanceFromStart }
        self.distance = offset
        self.destinationDistance = destinationLegIndex == nil ? offset : destinationDistance
        self.destinationArrival = arrival
    }
}

extension MKPolyline {
    /// The polyline's points as an array.
    var coordinates: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
