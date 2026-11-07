import CoreLocation
import Observation

/// Demo Mode: plays back a run along a route, so the app can be demoed indoors.
///
/// Once a second it moves a virtual runner `speed × multiplier` meters further along the route's
/// polyline, then emits a CLLocation with a realistic accuracy, course, and speed. That fix goes to
/// `onLocation`, which AppState routes through the same pipeline as real GPS (run tracker,
/// navigation, quest matching), so everything downstream behaves exactly like a real run.
@Observable
final class DemoRunSimulator {
    private(set) var isPlaying = false
    private(set) var isPaused = false

    @ObservationIgnored var onLocation: ((CLLocation) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var coordinates: [CLLocationCoordinate2D] = []
    @ObservationIgnored private var cumulative: [Double] = []
    @ObservationIgnored private var travelled = 0.0
    @ObservationIgnored private var dwellAt: Double?
    @ObservationIgnored private var dwellRemaining = 0

    /// - Parameters:
    ///   - metersPerSecond: running speed (from the user's pace)
    ///   - multiplier: playback speed-up (Developer Settings)
    ///   - dwellAt: distance along the route where playback pauses for `dwellSeconds` (the destination),
    ///     so the 10-second check-in can happen even mid-route (out-and-back).
    func start(along route: [CLLocationCoordinate2D], metersPerSecond: Double, multiplier: Double,
               dwellAt: Double? = nil, dwellSeconds: Int = 12) {
        stop()
        guard route.count > 1 else { return }
        coordinates = route
        cumulative = [0]
        for (a, b) in zip(route, route.dropFirst()) { cumulative.append(cumulative.last! + a.distance(to: b)) }
        travelled = 0
        isPlaying = true
        isPaused = false

        let step = metersPerSecond * multiplier
        self.dwellAt = dwellAt
        dwellRemaining = dwellAt == nil ? 0 : dwellSeconds
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.isPlaying {
                if let dwellAt = self.dwellAt, self.dwellRemaining > 0, self.travelled >= dwellAt {
                    // Standing at the destination: keep reporting the same spot.
                    self.dwellRemaining -= 1
                    self.emit(speed: 0)
                } else if !self.isPaused {
                    var next = min(self.travelled + step, self.cumulative.last ?? 0)
                    if let dwellAt = self.dwellAt, self.dwellRemaining > 0, self.travelled < dwellAt { next = min(next, dwellAt) }
                    self.travelled = next
                    self.emit(speed: metersPerSecond * multiplier)
                    if self.travelled >= (self.cumulative.last ?? 0) {
                        self.isPlaying = false
                        break
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func stop() {
        task?.cancel()
        task = nil
        isPlaying = false
        isPaused = false
    }

    private func emit(speed: Double) {
        // Find the segment we're on, then interpolate along it.
        guard let index = cumulative.lastIndex(where: { $0 <= travelled }), index < coordinates.count else { return }
        let a = coordinates[index]
        let b = coordinates[min(index + 1, coordinates.count - 1)]
        let segment = (cumulative[min(index + 1, cumulative.count - 1)] - cumulative[index])
        let t = segment > 0 ? (travelled - cumulative[index]) / segment : 0
        let point = NavigationEngine.interpolate(a, b, t)

        let fix = CLLocation(coordinate: point, altitude: 0,
                             horizontalAccuracy: 5, verticalAccuracy: 5,
                             course: a.bearing(to: b), speed: speed, timestamp: .now)
        onLocation?(fix)
    }
}
