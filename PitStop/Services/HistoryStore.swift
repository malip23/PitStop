import Foundation
import Observation
import SwiftData

/// Owns the SwiftData container: run history, Future Places, and partner rewards.
///
/// Views read with `@Query`; everything that writes goes through here, so the Firestore sync can
/// later hook in at one place.
@Observable
final class HistoryStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// IDs of every place the user has checked in at. Drives the ✓ stamps on the map.
    private(set) var visitedIDs: Set<String> = []
    /// IDs saved to Future Places.
    private(set) var savedIDs: Set<String> = []

    init() {
        do {
            container = try ModelContainer(for: RunRecord.self, SavedPlace.self, EarnedReward.self, Stamp.self, EarnedBadge.self)
        } catch {
            // A schema change during development can make the old store unreadable: fall back to memory
            // so the app still runs, and say so in the console.
            print("HistoryStore: persistent store failed (\(error)); using in-memory store.")
            container = try! ModelContainer(for: RunRecord.self, SavedPlace.self, EarnedReward.self, Stamp.self, EarnedBadge.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        refresh()
    }

    // MARK: Runs

    func save(_ run: RunRecord) {
        context.insert(run)
        try? context.save()
        refresh()
    }

    func delete(_ run: RunRecord) {
        context.delete(run)
        try? context.save()
        refresh()
    }

    func runs() -> [RunRecord] {
        (try? context.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    // MARK: Future Places

    func isSaved(_ id: String) -> Bool { savedIDs.contains(id) }

    func savePlace(_ destination: PlannedDestination, source: SavedPlace.Source) {
        guard !isSaved(destination.id) else { return }
        context.insert(SavedPlace(destination: destination, source: source))
        try? context.save()
        refresh()
    }

    func removeSavedPlace(id: String) {
        let descriptor = FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.id == id })
        for place in (try? context.fetch(descriptor)) ?? [] { context.delete(place) }
        try? context.save()
        refresh()
    }

    // MARK: Rewards

    func saveReward(_ reward: EarnedReward) {
        context.insert(reward)
        try? context.save()
    }

    // MARK: Stamps & badges

    func hasStamp(for placeID: String) -> Bool {
        let descriptor = FetchDescriptor<Stamp>(predicate: #Predicate { $0.id == placeID })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func saveStamp(_ stamp: Stamp) {
        context.insert(stamp)
        try? context.save()
    }

    var stampCount: Int { (try? context.fetchCount(FetchDescriptor<Stamp>())) ?? 0 }

    var earnedBadgeIDs: Set<String> {
        Set(((try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? []).map(\.id))
    }

    func currentStats() -> RewardStats {
        RewardsEngine.stats(runs: runs(), stampCount: stampCount)
    }

    /// Saves and returns any badges the latest history has unlocked.
    func awardNewBadges() -> [BadgeKind] {
        let fresh = RewardsEngine.newBadges(stats: currentStats(), earned: earnedBadgeIDs)
        for kind in fresh { context.insert(EarnedBadge(kind: kind)) }
        if !fresh.isEmpty { try? context.save() }
        return fresh
    }

    // MARK: Derived sets

    func refresh() {
        let visited = (try? context.fetch(FetchDescriptor<RunRecord>(predicate: #Predicate { $0.checkedIn }))) ?? []
        visitedIDs = Set(visited.compactMap(\.destinationId))
        let saved = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        savedIDs = Set(saved.map(\.id))
    }
}
