import CoreLocation

/// A spot on the route where the runner should watch for traffic.
struct CrossingPoint: Identifiable, Hashable {
    enum Kind: Int, Comparable {
        // Higher raw value = more important when merging nearby points.
        case turn = 0, crosswalk = 1, trafficSignal = 2

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .crosswalk: "Crosswalk ahead"
            case .trafficSignal: "Traffic signal ahead"
            case .turn: "Intersection ahead"
            }
        }

        var advice: String {
            switch self {
            case .crosswalk: "Look both ways"
            case .trafficSignal: "Wait for the walk signal"
            case .turn: "Watch for turning cars"
            }
        }

        /// Friendly spoken versions, so repeated alerts don't sound robotic.
        var voiceCues: [String] {
            switch self {
            case .crosswalk:
                ["Heads up, crosswalk coming up. Take a quick look both ways.",
                 "Crosswalk ahead. Look left, look right, then go.",
                 "Coming up on a crosswalk. Check for cars before you cross."]
            case .trafficSignal:
                ["Traffic light ahead. Wait for the walk signal.",
                 "Signal coming up. Hang tight for the walk light.",
                 "Light ahead. Only cross on the walk sign, okay?"]
            case .turn:
                ["Intersection coming up. Watch for turning cars.",
                 "Corner ahead. Keep an eye out for cars turning in.",
                 "Heads up, intersection ahead. Stay alert."]
            }
        }

        var symbol: String {
            switch self {
            case .crosswalk: "figure.walk"
            case .trafficSignal: "light.beacon.max.fill"
            case .turn: "arrow.triangle.turn.up.right.diamond.fill"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    let coordinate: CLLocationCoordinate2D
    /// Meters from the route's start, where the runner reaches this point.
    let distanceAlongRoute: Double

    static func == (a: CrossingPoint, b: CrossingPoint) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
