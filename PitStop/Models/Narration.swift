import Foundation

/// A city-guide line about a place the runner is passing.
struct Narration: Identifiable, Hashable {
    let id: String
    let name: String
    /// "park", "museum", "Café", …
    let kindName: String
    let symbol: String
    /// The intro (Gemini, or a template), built only from data we provided.
    let text: String
    /// Businesses can be added to Future Places from the popup.
    let destination: PlannedDestination?
    let alongRoute: Double
    let usedAI: Bool
}
