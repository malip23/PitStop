import CoreMotion
import Observation

/// Step counting with CMPedometer, used by anti-cheat to compare cadence with GPS speed.
/// The Motion permission prompt appears the first time a run starts.
@Observable
final class MotionService {
    private(set) var steps: Int?
    private(set) var isAvailable = CMPedometer.isStepCountingAvailable()
    @ObservationIgnored private let pedometer = CMPedometer()

    var isDenied: Bool {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted
    }

    func start() {
        steps = nil
        guard isAvailable else { return }
        pedometer.startUpdates(from: .now) { @Sendable [weak self] data, _ in
            let count = data?.numberOfSteps.intValue
            guard let self else { return }
            Task { @MainActor in self.steps = count }
        }
    }

    func stop() {
        pedometer.stopUpdates()
    }
}
