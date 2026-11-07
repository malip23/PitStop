import Foundation

/// Turns verified run history into stats and milestone badges.
///
/// Only runs that passed anti-cheat count. A stamp is awarded at check-in time (in AppState) for a
/// place that has no stamp yet; badges are re-checked every time a run is saved.
enum RewardsEngine {
    static func stats(runs: [RunRecord], stampCount: Int) -> RewardStats {
        let verified = runs.filter(\.verification.passed)
        var stats = RewardStats()
        stats.verifiedRuns = verified.count
        stats.uniquePlaces = stampCount
        stats.verifiedMiles = verified.reduce(0) { $0 + $1.distanceMeters } / Units.metersPerMile
        stats.questsCompleted = verified.filter { $0.checkedIn && $0.questId != nil }.count
        stats.bestStreakDays = bestStreak(dates: verified.map(\.date))
        return stats
    }

    /// Longest run of consecutive calendar days with at least one verified run.
    static func bestStreak(dates: [Date], calendar: Calendar = .current) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, current = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }

    /// Badges reached by `stats` that aren't in `earned` yet.
    static func newBadges(stats: RewardStats, earned: Set<String>) -> [BadgeKind] {
        BadgeKind.allCases.filter { !earned.contains($0.rawValue) && $0.value(in: stats) >= $0.target }
    }
}
