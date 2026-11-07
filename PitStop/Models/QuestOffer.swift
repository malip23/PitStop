import Foundation

/// A quest matched to the current runner, with the numbers behind its ranking
/// (kept so the UI and judges can see *why* it ranked where it did).
struct QuestOffer: Identifiable, Hashable {
    let quest: Quest
    let business: Business
    /// Estimated extra meters the runner adds by going to this business.
    let extraDistance: Double
    /// 0–1 parts of the score.
    let distanceScore: Double
    let slowScore: Double
    let discoveryScore: Double
    /// Weighted total, 0–1. Higher = offered first.
    let score: Double

    var id: String { quest.id }
}
