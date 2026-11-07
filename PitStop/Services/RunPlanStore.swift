import Foundation
import Observation

/// Remembers the last run plan (as the sheet's defaults) and the user's recent pace per activity.
/// Stored in UserDefaults because it's a few small values.
@Observable
final class RunPlanStore {
    private(set) var lastPlan: RunPlan
    /// Recent paces in seconds per meter, newest last, max 5 per activity.
    private var paceHistory: [Activity: [Double]]

    private let planKey = "runPlan.last"
    private let paceKey = "runPlan.paceHistory"

    enum PaceSource { case history, defaultPace }

    init() {
        let defaults = UserDefaults.standard
        lastPlan = defaults.data(forKey: planKey).flatMap { try? JSONDecoder().decode(RunPlan.self, from: $0) } ?? RunPlan()
        paceHistory = defaults.data(forKey: paceKey).flatMap { try? JSONDecoder().decode([Activity: [Double]].self, from: $0) } ?? [:]
    }

    func save(_ plan: RunPlan) {
        lastPlan = plan
        UserDefaults.standard.set(try? JSONEncoder().encode(plan), forKey: planKey)
    }

    /// Average of recent runs for this activity, or the activity's default pace.
    /// (HealthKit's past workouts will feed this once HealthKit is wired in.)
    func pace(for activity: Activity) -> (secondsPerMeter: Double, source: PaceSource) {
        if let recent = paceHistory[activity], !recent.isEmpty {
            return (recent.reduce(0, +) / Double(recent.count), .history)
        }
        return (activity.defaultSecondsPerMile / Units.metersPerMile, .defaultPace)
    }

    /// Records a finished run's pace. Ignores very short runs, which give noisy paces.
    func recordPace(_ secondsPerMeter: Double, distance: Double, activity: Activity) {
        guard distance >= 800, secondsPerMeter.isFinite, secondsPerMeter > 0 else { return }
        var recent = paceHistory[activity] ?? []
        recent.append(secondsPerMeter)
        paceHistory[activity] = Array(recent.suffix(5))
        UserDefaults.standard.set(try? JSONEncoder().encode(paceHistory), forKey: paceKey)
    }
}
