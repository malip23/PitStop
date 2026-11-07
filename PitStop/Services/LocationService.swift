import CoreLocation
import Observation

/// Wraps `CLLocationManager`.
///
/// It only *produces* real GPS fixes. It doesn't decide what happens with them: `AppState` receives
/// each fix through `onLocation` and routes it, which lets Demo Mode inject simulated fixes into the
/// exact same pipeline.
@Observable
final class LocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastRealLocation: CLLocation?
    /// Compass heading in degrees from true north (nil until the compass reports).
    private(set) var heading: Double?

    /// Called on the main actor for every real GPS fix.
    @ObservationIgnored var onLocation: ((CLLocation) -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 2
        manager.headingFilter = 5
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    /// Upgrade to "Always" so check-in still works with the screen locked. Asked only once a run starts.
    func requestAlways() { manager.requestAlwaysAuthorization() }

    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    /// Keep GPS alive in the background during a run (needs the "Location updates" background mode).
    func setBackgroundTracking(_ enabled: Bool) {
        guard isAuthorized else { return }
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
        manager.pausesLocationUpdatesAutomatically = !enabled
    }
}

// Delegate callbacks are nonisolated (CoreLocation's protocol is), so we hop to the main actor.
extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                self.lastRealLocation = location
                self.onLocation?(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = degrees }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Transient errors (e.g. kCLErrorLocationUnknown) are expected indoors; keep going.
    }
}
