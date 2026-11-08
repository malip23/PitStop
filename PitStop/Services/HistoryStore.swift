import Foundation
import Observation
import SwiftData

/// Owns the SwiftData container: run history, Future Places, and partner rewards.
///
/// Views read with `@Query`; everything that writes goes through here and is mirrored to the user's
/// Firestore subcollections (`CloudHistorySync`). SwiftData is the offline cache.
@Observable
final class HistoryStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// IDs of every place the user has checked in at. Drives the ✓ stamps on the map.
    private(set) var visitedIDs: Set<String> = []
    /// IDs saved to Future Places.
    private(set) var savedIDs: Set<String> = []

    /// Set while signed in; nil when signed out (local cache keeps working).
    @ObservationIgnored private(set) var cloud: CloudHistorySync?
    private let ownerKey = "history.ownerUid"

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
        cloud?.upload(run)
        refresh()
    }

    func delete(_ run: RunRecord) {
        cloud?.deleteRun(id: run.id)
        context.delete(run)
        try? context.save()
        refresh()
    }

    func runs() -> [RunRecord] {
        (try? context.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    // MARK: Future Places

    func isSaved(_ id: String) -> Bool { savedIDs.contains(id) }

    func savedPlaces() -> [SavedPlace] {
        (try? context.fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)]))) ?? []
    }

    func savePlace(_ destination: PlannedDestination, source: SavedPlace.Source) {
        guard !isSaved(destination.id) else { return }
        let place = SavedPlace(destination: destination, source: source)
        context.insert(place)
        try? context.save()
        cloud?.upload(place)
        refresh()
    }

    func removeSavedPlace(id: String) {
        let descriptor = FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.id == id })
        for place in (try? context.fetch(descriptor)) ?? [] { context.delete(place) }
        try? context.save()
        cloud?.deleteSavedPlace(id: id)
        refresh()
    }

    // MARK: Rewards

    func saveReward(_ reward: EarnedReward) {
        context.insert(reward)
        try? context.save()
        cloud?.upload(reward)
    }

    func markRedeemed(_ reward: EarnedReward) {
        reward.redeemed = true
        try? context.save()
        cloud?.upload(reward)
    }

    /// The stamp and partner reward earned on a given run (for the share card).
    func stamp(forRun runID: String) -> Stamp? {
        try? context.fetch(FetchDescriptor<Stamp>(predicate: #Predicate { $0.runId == runID })).first
    }

    func reward(forRun runID: String) -> EarnedReward? {
        try? context.fetch(FetchDescriptor<EarnedReward>(predicate: #Predicate { $0.runId == runID })).first
    }

    // MARK: Stamps & badges

    func hasStamp(for placeID: String) -> Bool {
        let descriptor = FetchDescriptor<Stamp>(predicate: #Predicate { $0.id == placeID })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func saveStamp(_ stamp: Stamp) {
        context.insert(stamp)
        try? context.save()
        cloud?.upload(stamp)
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
        for kind in fresh {
            let badge = EarnedBadge(kind: kind)
            context.insert(badge)
            cloud?.upload(badge)
        }
        if !fresh.isEmpty { try? context.save() }
        return fresh
    }

    // MARK: Accounts

    /// Called when a user signs in. A different account than last time → wipe the local cache first,
    /// so nobody sees someone else's history. Then two-way merge with Firestore.
    func attach(uid: String) async {
        let previous = UserDefaults.standard.string(forKey: ownerKey)
        if let previous, previous != uid { wipeLocal() }
        UserDefaults.standard.set(uid, forKey: ownerKey)
        let cloud = CloudHistorySync(uid: uid)
        self.cloud = cloud

        guard let remote = await cloud.fetchAll() else { return }   // offline: try again next launch

        // Pull: anything only in the cloud (e.g. this is a new phone).
        let localRuns = Set(runs().map(\.id))
        for run in remote.runs where !localRuns.contains(run.id) { context.insert(run) }
        let localPlaces = Set(savedPlaces().map(\.id))
        for place in remote.places where !localPlaces.contains(place.id) { context.insert(place) }
        let localStamps = Set(fetch(Stamp.self).map(\.id))
        for stamp in remote.stamps where !localStamps.contains(stamp.id) { context.insert(stamp) }
        let localBadges = earnedBadgeIDs
        for badge in remote.badges where !localBadges.contains(badge.id) { context.insert(badge) }
        let localRewards = Set(fetch(EarnedReward.self).map(\.id))
        for reward in remote.rewards where !localRewards.contains(reward.id) { context.insert(reward) }
        try? context.save()

        // Push: anything only on this phone (e.g. runs from before accounts existed).
        let remoteRuns = Set(remote.runs.map(\.id))
        for run in runs() where !remoteRuns.contains(run.id) { cloud.upload(run) }
        let remotePlaces = Set(remote.places.map(\.id))
        for place in savedPlaces() where !remotePlaces.contains(place.id) { cloud.upload(place) }
        let remoteStamps = Set(remote.stamps.map(\.id))
        for stamp in fetch(Stamp.self) where !remoteStamps.contains(stamp.id) { cloud.upload(stamp) }
        let remoteBadges = Set(remote.badges.map(\.id))
        for badge in fetch(EarnedBadge.self) where !remoteBadges.contains(badge.id) { cloud.upload(badge) }
        let remoteRewards = Set(remote.rewards.map(\.id))
        for reward in fetch(EarnedReward.self) where !remoteRewards.contains(reward.id) { cloud.upload(reward) }
        refresh()
    }

    /// Signed out: stop mirroring (the local cache stays until a different account signs in).
    func detach() { cloud = nil }

    private func wipeLocal() {
        try? context.delete(model: RunRecord.self)
        try? context.delete(model: SavedPlace.self)
        try? context.delete(model: EarnedReward.self)
        try? context.delete(model: Stamp.self)
        try? context.delete(model: EarnedBadge.self)
        try? context.save()
        refresh()
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: Derived sets

    func refresh() {
        let visited = (try? context.fetch(FetchDescriptor<RunRecord>(predicate: #Predicate { $0.checkedIn }))) ?? []
        visitedIDs = Set(visited.compactMap(\.destinationId))
        let saved = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        savedIDs = Set(saved.map(\.id))
    }
}
