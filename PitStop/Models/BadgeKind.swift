import SwiftUI

/// Milestone badges. Each has a target, and progress is measured from verified runs only.
enum BadgeKind: String, CaseIterable, Identifiable, Codable {
    case firstRun, places5, places10, miles10, miles25, streak3, firstQuest

    var id: Self { self }

    var title: String {
        switch self {
        case .firstRun: "First Steps"
        case .places5: "Explorer"
        case .places10: "Trailblazer"
        case .miles10: "10-Mile Club"
        case .miles25: "25-Mile Club"
        case .streak3: "On a Roll"
        case .firstQuest: "Off-Peak Hero"
        }
    }

    var detail: String {
        switch self {
        case .firstRun: "Finish your first verified run"
        case .places5: "Check in at 5 different places"
        case .places10: "Check in at 10 different places"
        case .miles10: "Cover 10 verified miles"
        case .miles25: "Cover 25 verified miles"
        case .streak3: "Verified runs 3 days in a row"
        case .firstQuest: "Complete your first Off-Peak Quest"
        }
    }

    var symbol: String {
        switch self {
        case .firstRun: "shoeprints.fill"
        case .places5: "map.fill"
        case .places10: "globe.americas.fill"
        case .miles10: "10.circle.fill"
        case .miles25: "25.circle.fill"
        case .streak3: "flame.fill"
        case .firstQuest: "storefront.fill"
        }
    }

    var color: Color {
        switch self {
        case .firstRun: Theme.sky
        case .places5, .places10: Theme.lime
        case .miles10, .miles25: Theme.coral
        case .streak3: Theme.sun
        case .firstQuest: Theme.coralDeep
        }
    }

    /// The number to reach.
    var target: Double {
        switch self {
        case .firstRun, .firstQuest: 1
        case .places5: 5
        case .places10: 10
        case .miles10: 10
        case .miles25: 25
        case .streak3: 3
        }
    }

    /// The matching value from the user's stats.
    func value(in stats: RewardStats) -> Double {
        switch self {
        case .firstRun: Double(stats.verifiedRuns)
        case .places5, .places10: Double(stats.uniquePlaces)
        case .miles10, .miles25: stats.verifiedMiles
        case .streak3: Double(stats.bestStreakDays)
        case .firstQuest: Double(stats.questsCompleted)
        }
    }

    /// "7 of 10 places", "3.2 of 10 mi"
    func progressText(_ stats: RewardStats) -> String {
        let value = min(value(in: stats), target)
        switch self {
        case .firstRun: return value >= 1 ? "Done" : "0 of 1 run"
        case .places5, .places10: return "\(Int(value)) of \(Int(target)) places"
        case .miles10, .miles25: return String(format: "%.1f of %.0f mi", value, target)
        case .streak3: return "\(Int(value)) of 3 days"
        case .firstQuest: return value >= 1 ? "Done" : "0 of 1 quest"
        }
    }
}

/// Totals that badges are measured against (verified runs only).
struct RewardStats: Equatable {
    var verifiedRuns = 0
    var uniquePlaces = 0
    var verifiedMiles = 0.0
    var bestStreakDays = 0
    var questsCompleted = 0
}
