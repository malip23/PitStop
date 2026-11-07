import Foundation

/// The user's goal for one run, chosen on the "Plan your run" sheet.
/// Saved as the default for next time.
struct RunPlan: Codable, Equatable, Sendable {
    enum GoalType: String, Codable, CaseIterable, Identifiable, Sendable {
        case distance, time
        var id: Self { self }
        var displayName: String { self == .distance ? "Distance" : "Time" }
    }

    enum RouteShape: String, Codable, CaseIterable, Identifiable, Sendable {
        case oneWay, outAndBack
        var id: Self { self }
        var displayName: String { self == .oneWay ? "One-way" : "Out & back" }
        var detail: String { self == .oneWay ? "Finish at your destination" : "Reach it, then return home" }
        var symbol: String { self == .oneWay ? "arrow.right.circle.fill" : "arrow.uturn.left.circle.fill" }
    }

    static let distanceRange: ClosedRange<Double> = 1...10      // miles
    static let minutesRange: ClosedRange<Double> = 15...90

    var activity: Activity = .run
    var goalType: GoalType = .distance
    var goalMiles: Double = 3
    var goalMinutes: Double = 30
    var shape: RouteShape = .oneWay
    var surpriseMe = false

    /// Total distance to cover, in meters. Time goals convert using `secondsPerMeter`.
    func targetDistance(secondsPerMeter: Double) -> Double {
        switch goalType {
        case .distance: goalMiles * Units.metersPerMile
        case .time: goalMinutes * 60 / secondsPerMeter
        }
    }

    /// How far away a destination should be (route distance from start), as a fraction of the target:
    /// one-way 70–100% (the destination IS the finish), out-and-back 40–50% (there and back again).
    var destinationFraction: ClosedRange<Double> {
        shape == .oneWay ? 0.7...1.0 : 0.4...0.5
    }

    func destinationRange(target: Double) -> ClosedRange<Double> {
        (target * destinationFraction.lowerBound)...(target * destinationFraction.upperBound)
    }
}
