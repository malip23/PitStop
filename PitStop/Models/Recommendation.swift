import Foundation

/// One "Suggested for you" place, chosen from candidates the app gathered.
struct Recommendation: Identifiable, Codable, Hashable {
    enum Label: String, Codable, CaseIterable {
        case promotion, new, interest

        var title: String {
            switch self {
            case .promotion: "Promotion"
            case .new: "New"
            case .interest: "Matches your interests"
            }
        }

        var symbol: String {
            switch self {
            case .promotion: "gift.fill"
            case .new: "sparkles"
            case .interest: "heart.fill"
            }
        }
    }

    let destination: PlannedDestination
    let label: Label
    /// One short, personal sentence (from Gemini, or a template when AI is unavailable).
    let reason: String
    /// Straight-line distance from where the user was when recommendations were made.
    let distance: Double
    /// Partner reward, only for promotions.
    let reward: String?

    var id: String { destination.id }

    /// Real-place suggestions can be outside the nearby cache, so the map rebuilds a RealPlace.
    var realPlace: RealPlace? {
        guard !destination.isPartner else { return nil }
        return RealPlace(id: destination.id, name: destination.name, category: destination.category,
                         address: destination.address, latitude: destination.latitude, longitude: destination.longitude)
    }
}
