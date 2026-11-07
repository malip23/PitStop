import CoreLocation
import Observation

/// Check-in rule: stay within `radius` meters of the destination for `dwell` seconds.
///
/// "The destination" is the place itself OR the route's arrival point on the street (MapKit routes end
/// on the road, which can be tens of meters from a business's coordinate in the middle of a block).
///
/// GPS can stop sending fixes while you stand still, so a 1-second ticker (not incoming fixes)
/// measures the dwell time, based on the last known position.
@Observable
final class CheckInMonitor {
    let radius: CLLocationDistance = 30
    let dwell: TimeInterval = 10

    private(set) var target: PlannedDestination?
    /// When the runner entered the radius (nil = outside).
    private(set) var enteredAt: Date?
    private(set) var isCheckedIn = false

    @ObservationIgnored var onCheckIn: ((PlannedDestination) -> Void)?
    /// Street-side arrival point from the active route, if any.
    @ObservationIgnored var arrivalPoint: CLLocation?
    @ObservationIgnored private var lastFix: CLLocation?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// 0–1 progress of the dwell timer, for the "Checking in…" ring.
    var dwellProgress: Double {
        guard let enteredAt else { return 0 }
        return min(Date.now.timeIntervalSince(enteredAt) / dwell, 1)
    }

    func start(target: PlannedDestination?, arrival: CLLocationCoordinate2D? = nil) {
        stop()
        self.target = target
        arrivalPoint = arrival.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        isCheckedIn = false
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        target = nil
        enteredAt = nil
        lastFix = nil
    }

    func update(with fix: CLLocation) {
        guard let target, !isCheckedIn else { return }
        lastFix = fix
        let inside = isInside(fix, target: target)
        if inside, enteredAt == nil {
            enteredAt = .now
            startTicker()
        } else if !inside {
            enteredAt = nil
            ticker?.cancel()
        }
    }

    private func isInside(_ fix: CLLocation, target: PlannedDestination) -> Bool {
        if fix.distance(from: target.location) <= radius { return true }
        if let arrivalPoint, fix.distance(from: arrivalPoint) <= radius { return true }
        return false
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let entered = self.enteredAt, let target = self.target, !self.isCheckedIn else { return }
                if let fix = self.lastFix, !self.isInside(fix, target: target) {
                    self.enteredAt = nil
                    return
                }
                if Date.now.timeIntervalSince(entered) >= self.dwell {
                    self.isCheckedIn = true
                    self.onCheckIn?(target)
                    return
                }
            }
        }
    }
}
