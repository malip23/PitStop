import MapKit

/// What the user is doing. Each activity has its own default pace and MapKit transport type.
enum Activity: String, Codable, CaseIterable, Identifiable, Sendable {
    case run, walk, bike

    var id: Self { self }

    var displayName: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .bike: "Bike"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .bike: "figure.outdoor.cycle"
        }
    }

    /// Fallback pace when there's no history: 10 min/mi run, 18 min/mi walk, 5 min/mi (12 mph) bike.
    var defaultSecondsPerMile: Double {
        switch self {
        case .run: 600
        case .walk: 1080
        case .bike: 300
        }
    }

    /// Directions type for routing. Cycling directions have been available since iOS 14.
    var transportType: MKDirectionsTransportType {
        switch self {
        case .run, .walk: .walking
        case .bike: .cycling
        }
    }
}
