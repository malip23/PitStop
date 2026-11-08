import CoreLocation
import Observation

/// Decides whether a run looks real. It sees every location fix and the step count, and produces a
/// `VerificationResult` with human-readable reasons.
///
/// Checks:
/// 1. **Speed:** average speed too fast for the activity (on foot > 6.5 m/s ≈ 4:08 /mi).
/// 2. **Steps vs distance:** on foot, almost no steps while covering ground (< 0.35 steps/m;
///    real runners take about 1.2–1.6 steps/m).
/// 3. **Cadence vs speed:** running pace (> 2.2 m/s) with cadence under 90 steps/min.
/// 4. **Simulated location:** any fix with `sourceInformation.isSimulatedBySoftware`
///    (e.g. Xcode's Simulate Location or spoofing apps).
/// 5. **Impossible jumps:** two or more fix-to-fix jumps faster than a human (or bike) can move.
///
/// Demo Mode compresses time ×N, so all speeds are divided by `timeScale` first, and Demo supplies
/// matching synthetic steps. The "fake car run" supplies no steps, so it fails like a real cheat would.
@Observable
final class AntiCheatEngine {
    private(set) var simulatedFixCount = 0
    private(set) var jumpCount = 0

    @ObservationIgnored private var lastFix: CLLocation?
    @ObservationIgnored private var activity: Activity = .run
    @ObservationIgnored private var timeScale = 1.0
    /// When set (Demo Mode), steps are synthesized from distance instead of read from the pedometer.
    @ObservationIgnored private var syntheticStepsPerMeter: Double?
    @ObservationIgnored private var syntheticSteps = 0.0

    func start(activity: Activity, timeScale: Double, syntheticStepsPerMeter: Double?) {
        self.activity = activity
        self.timeScale = max(timeScale, 1)
        self.syntheticStepsPerMeter = syntheticStepsPerMeter
        syntheticSteps = 0
        simulatedFixCount = 0
        jumpCount = 0
        lastFix = nil
    }

    func ingest(_ fix: CLLocation) {
        if fix.sourceInformation?.isSimulatedBySoftware == true { simulatedFixCount += 1 }

        if let last = lastFix {
            let meters = fix.distance(from: last)
            let seconds = fix.timestamp.timeIntervalSince(last.timestamp)
            if let perMeter = syntheticStepsPerMeter { syntheticSteps += meters * perMeter }
            if seconds > 0, meters > 50 {
                let speed = meters / seconds / timeScale
                if speed > limits.jumpSpeed { jumpCount += 1 }
            }
        }
        lastFix = fix
    }

    /// Evaluates the run so far. Safe to call mid-run (check-in) and again at the end.
    func evaluate(distance: Double, duration: TimeInterval, pedometerSteps: Int?,
                  motionDenied: Bool, enabled: Bool) -> VerificationResult {
        guard enabled else {
            return VerificationResult(passed: true, reasons: [], notes: ["Anti-cheat disabled in Developer Settings"])
        }
        var reasons: [String] = []
        var notes: [String] = []
        let realSeconds = max(duration * timeScale, 1)   // undo Demo Mode time compression
        let speed = distance / realSeconds
        if timeScale > 1 { notes.append("Demo playback (\(Int(timeScale))× speed, normalized)") }

        // 1. Speed
        if distance > 200, speed > limits.maxAverageSpeed {
            reasons.append(String(format: "Average speed %.1f mph is too fast for %@", speed * 2.23694, activity.displayName.lowercased()))
        }

        // 2–3. Steps (on foot only)
        let steps = syntheticStepsPerMeter != nil ? Int(syntheticSteps) : pedometerSteps
        if activity != .bike {
            if let steps {
                let stepsPerMeter = distance > 0 ? Double(steps) / distance : 0
                let cadence = Double(steps) / (realSeconds / 60)
                if distance > 200, stepsPerMeter < 0.35 {
                    reasons.append("Almost no steps (\(steps)) while moving \(Format.distance(distance))")
                } else if speed > 2.2, cadence < 90, distance > 200 {
                    reasons.append("Step cadence \(Int(cadence)) spm is too low for this speed")
                }
            } else {
                notes.append(motionDenied ? "Motion access denied; steps not checked" : "Step data unavailable")
            }
        }

        // 4. Simulated location
        if simulatedFixCount > 0 {
            reasons.append("Location was simulated by software (\(simulatedFixCount) fixes)")
        }

        // 5. Jumps (one glitch is forgiven; GPS does that)
        if jumpCount >= 2 {
            reasons.append("\(jumpCount) impossible position jumps")
        }

        return VerificationResult(passed: reasons.isEmpty, reasons: reasons, notes: notes)
    }

    private var limits: (maxAverageSpeed: Double, jumpSpeed: Double) {
        activity == .bike ? (16, 30) : (6.5, 12)
    }
}
