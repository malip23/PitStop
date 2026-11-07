import Foundation

/// The anti-cheat verdict for a run. Stored with the run (no raw sensor or health data, just the verdict).
struct VerificationResult: Codable, Hashable, Sendable {
    /// true = the run looks real. Only verified runs unlock rewards, stamps, and badges.
    var passed: Bool
    /// Why it failed (empty when passed).
    var reasons: [String]
    /// Informational notes that don't fail the run (e.g. "Motion data unavailable").
    var notes: [String]

    static let unchecked = VerificationResult(passed: true, reasons: [], notes: ["Not checked"])
}
