import Foundation
import Observation

/// Owns all quests and saves them to `Documents/quests.json`.
///
/// Lifecycle: business goes slow → `open` (active) → runner `accept`s → `complete` on check-in.
/// The business stops being slow → `expire`.
@Observable
final class QuestStore {
    private(set) var quests: [Quest] = []
    /// Quests this runner dismissed. Local only; never synced.
    private(set) var dismissedIDs: Set<Quest.ID> = []

    private let fileName = "quests.json"

    init() {
        quests = LocalFileStore.load([Quest].self, from: fileName) ?? []
    }

    var openQuests: [Quest] { quests.filter(\.isOpen) }
    var acceptedQuest: Quest? { quests.first { $0.status == .accepted } }

    func openQuest(for businessID: String) -> Quest? {
        quests.first { $0.businessId == businessID && $0.isOpen }
    }

    /// Completed visits per business in the last 30 days. Feeds the "fair discovery" boost.
    func recentVisits(to businessID: String) -> Int {
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 3600)
        return quests.filter { $0.businessId == businessID && $0.status == .completed && ($0.completedAt ?? .distantPast) > cutoff }.count
    }

    /// Creates an active quest for a business that just went slow (one open quest per business).
    @discardableResult
    func open(for business: Business) -> Quest {
        if let existing = openQuest(for: business.id) { return existing }
        let quest = Quest(businessId: business.id, reward: business.reward)
        quests.append(quest)
        save()
        return quest
    }

    /// Business is no longer slow: close any open quest for it.
    func expire(for businessID: String) {
        mutate(where: { $0.businessId == businessID && $0.isOpen }) { $0.status = .expired }
    }

    /// Business deleted: drop its quests entirely.
    func removeAll(for businessID: String) {
        quests.removeAll { $0.businessId == businessID }
        save()
    }

    /// Keeps an open quest's reward in step with the business's edited reward text.
    func updateReward(_ reward: String, for businessID: String) {
        mutate(where: { $0.businessId == businessID && $0.isOpen }) { $0.reward = reward }
    }

    func accept(_ id: Quest.ID) {
        // Only one accepted quest at a time: release any other back to active.
        mutate(where: { $0.status == .accepted && $0.id != id }) { $0.status = .active; $0.etaSeconds = nil }
        mutate(where: { $0.id == id && $0.status == .active }) { $0.status = .accepted }
    }

    func cancelAccepted() {
        mutate(where: { $0.status == .accepted }) { $0.status = .active; $0.etaSeconds = nil }
    }

    func complete(_ id: Quest.ID) {
        mutate(where: { $0.id == id }) { $0.status = .completed; $0.completedAt = .now }
    }

    func dismiss(_ id: Quest.ID) {
        dismissedIDs.insert(id)
    }

    private func mutate(where predicate: (Quest) -> Bool, _ change: (inout Quest) -> Void) {
        var changed = false
        for index in quests.indices where predicate(quests[index]) {
            change(&quests[index])
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        LocalFileStore.save(quests, to: fileName)
    }
}
