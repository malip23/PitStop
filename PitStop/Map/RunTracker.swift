import CoreLocation
import Observation

/// Tracks one run: state, elapsed time, distance, pace, and the GPS trace.
///
/// It's fed fixes by `AppState.handleLocation`, so it can't tell real GPS from Demo Mode playback.
@Observable
final class RunTracker {
    private(set) var state: RunState = .idle
    private(set) var distanceMeters: Double = 0
    private(set) var trace: [CLLocation] = []
    private(set) var startDate: Date?
    private(set) var endDate: Date?

    /// Goal distance for this run in meters, from the run plan. nil = free run.
    private(set) var targetDistance: Double?

    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    /// Last fix that counted toward distance. Cleared on pause so the gap isn't counted on resume.
    @ObservationIgnored private var lastCounted: CLLocation?

    /// Ignore fixes worse than this. Simulated fixes report ~5 m, so they pass.
    private let maxAccuracy: CLLocationAccuracy = 40

    var isActive: Bool { state == .running || state == .paused }

    // MARK: Controls

    func start(targetDistance: Double? = nil) {
        reset()
        self.targetDistance = targetDistance
        state = .running
        startDate = .now
        resumedAt = .now
    }

    func pause() {
        guard state == .running, let resumedAt else { return }
        accumulated += Date.now.timeIntervalSince(resumedAt)
        self.resumedAt = nil
        lastCounted = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        resumedAt = .now
        state = .running
    }

    func end() {
        guard isActive else { return }
        if let resumedAt { accumulated += Date.now.timeIntervalSince(resumedAt) }
        resumedAt = nil
        endDate = .now
        state = .finished
    }

    func reset() {
        state = .idle
        distanceMeters = 0
        trace = []
        startDate = nil
        endDate = nil
        accumulated = 0
        resumedAt = nil
        lastCounted = nil
        targetDistance = nil
    }

    /// 0–1 progress toward the goal distance.
    var goalProgress: Double? {
        guard let targetDistance, targetDistance > 0 else { return nil }
        return min(distanceMeters / targetDistance, 1)
    }

    // MARK: Data

    func ingest(_ location: CLLocation) {
        guard state == .running,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxAccuracy else { return }

        if let last = lastCounted {
            let step = location.distance(from: last)
            // Ignore sub-meter jitter while standing still.
            if step >= 1 { distanceMeters += step }
        }
        lastCounted = location
        trace.append(location)
    }

    /// Moving time (pauses excluded).
    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Average pace over the whole run, in seconds per meter.
    var averagePace: Double? {
        guard distanceMeters > 20 else { return nil }
        return elapsed() / distanceMeters
    }

    /// Rolling pace over roughly the last 30 seconds, in seconds per meter. Used for the live ETA.
    var currentPace: Double? {
        guard state == .running, let latest = trace.last else { return averagePace }
        let window = trace.reversed().prefix { latest.timestamp.timeIntervalSince($0.timestamp) <= 30 }
        guard let oldest = window.last, oldest !== latest else { return averagePace }
        var meters = 0.0
        var previous: CLLocation?
        for fix in window.reversed() {
            if let previous { meters += fix.distance(from: previous) }
            previous = fix
        }
        let seconds = latest.timestamp.timeIntervalSince(oldest.timestamp)
        guard meters > 10, seconds > 5 else { return averagePace }
        return seconds / meters
    }

    /// Current speed in m/s from the rolling pace.
    var currentSpeed: Double {
        guard let pace = currentPace, pace > 0 else { return 0 }
        return 1 / pace
    }
}
