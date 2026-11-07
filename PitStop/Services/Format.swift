import Foundation

/// Display formatting. Uses miles in the US locale, kilometers elsewhere.
enum Format {
    static var usesMiles: Bool { Locale.current.measurementSystem == .us }

    /// "1.24 mi" / "2.00 km"
    static func distance(_ meters: Double) -> String {
        if usesMiles {
            return String(format: "%.2f mi", meters / Units.metersPerMile)
        }
        return String(format: "%.2f km", meters / 1000)
    }

    /// Short distance for nearby things: "350 ft"/"0.4 mi" or "120 m"/"1.2 km".
    static func shortDistance(_ meters: Double) -> String {
        if usesMiles {
            let feet = meters * 3.28084
            return feet < 1000 ? "\(Int(feet.rounded())) ft" : String(format: "%.1f mi", meters / Units.metersPerMile)
        }
        return meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }

    /// Pace from seconds-per-meter: "8:30 /mi". Returns "--:--" when unknown.
    static func pace(secondsPerMeter: Double?) -> String {
        guard let spm = secondsPerMeter, spm.isFinite, spm > 0 else { return "--:--" }
        let perUnit = spm * (usesMiles ? Units.metersPerMile : 1000)
        guard perUnit < 60 * 60 else { return "--:--" } // slower than 60 min/unit = standing still
        let total = Int(perUnit.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static var paceUnit: String { usesMiles ? "/mi" : "/km" }

    /// "12:34" or "1:02:03"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "4 min" / "<1 min"
    static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return m < 1 ? "<1 min" : "\(m) min"
    }
}
