import Foundation

/// "Smoothie shop 2 blocks ahead, +0.2 mi. Stop by?": a quick stop offered while navigating.
struct InterestSuggestion: Identifiable, Hashable {
    let destination: PlannedDestination
    /// Which interest it matches (nil = a demo-mode "nearby spot").
    let interest: Interest?
    /// Where along the route the runner passes it (meters from the route start).
    let alongRoute: Double
    /// Meters ahead of the runner when suggested.
    let distanceAhead: Double
    /// Estimated extra distance for the stop (there and back to the route).
    let detour: Double
    /// One line written by Gemini, or a template when AI is unavailable.
    let message: String
    let usedAI: Bool

    var id: String { destination.id }
}
