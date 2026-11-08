import FirebaseFirestore
import Foundation
import Observation

/// Off-Peak Quests, live from Firestore `quests/{id}` (last 30 days).
///
/// Lifecycle: business goes slow → `open` (active) → a runner `accept`s (status, runnerUid, live ETA)
/// → `complete` on check-in. The business stops being slow → `expire`.
///
/// Who writes what (enforced by firestore.rules):
/// - the business owner / admin: create, expire, reward text, delete
/// - runners: only status, runnerUid, etaSeconds, etaUpdatedAt, completedAt, offerStats
/// Offer stats use server-side increments, so two phones never overwrite each other's counts.
@Observable
final class QuestStore {
    private(set) var quests: [Quest] = []
    /// Quests this runner dismissed. Local only; never synced.
    private(set) var dismissedIDs: Set<Quest.ID> = []
    private(set) var lastError: String?

    /// Called after each remote update (AppState re-checks offers and "Offer ended").
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private(set) var uid: String?

    private var collection: CollectionReference { Firestore.firestore().collection("quests") }

    func start(uid: String) {
        stop()
        self.uid = uid
        let since = Date.now.addingTimeInterval(-30 * 24 * 3600)
        listener = collection.whereField("createdAt", isGreaterThan: since)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.lastError = error.localizedDescription; return }
                self.quests = (snapshot?.documents ?? []).compactMap { try? $0.data(as: Quest.self) }
                self.lastError = nil
                self.onChange?()
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        quests = []
        uid = nil
    }

    var openQuests: [Quest] { quests.filter(\.isOpen) }

    /// The quest THIS runner accepted.
    var acceptedQuest: Quest? { quests.first { $0.status == .accepted && $0.runnerUid == uid } }

    func openQuest(for businessID: String) -> Quest? {
        quests.first { $0.businessId == businessID && $0.isOpen }
    }

    /// Completed visits per business in the last 30 days. Feeds the "fair discovery" boost.
    func recentVisits(to businessID: String) -> Int {
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 3600)
        return quests.filter { $0.businessId == businessID && $0.status == .completed && ($0.completedAt ?? .distantPast) > cutoff }.count
    }

    // MARK: Business owner

    /// Creates an active quest for a business that just went slow (one open quest per business).
    func open(for business: Business) {
        guard openQuest(for: business.id) == nil else { return }
        let quest = Quest(businessId: business.id, reward: business.reward)
        try? collection.document(quest.id).setData(from: quest)
    }

    /// Business is no longer slow: close any open quest for it.
    func expire(for businessID: String) {
        for quest in quests where quest.businessId == businessID && quest.isOpen {
            collection.document(quest.id).updateData(["status": Quest.Status.expired.rawValue,
                                                      "endedAt": Timestamp(date: .now)])
        }
    }

    /// Business deleted: drop its quests.
    func removeAll(for businessID: String) {
        for quest in quests where quest.businessId == businessID {
            collection.document(quest.id).delete()
        }
    }

    /// Keeps an open quest's reward in step with the business's edited reward text.
    func updateReward(_ reward: String, for businessID: String) {
        for quest in quests where quest.businessId == businessID && quest.isOpen && quest.reward != reward {
            collection.document(quest.id).updateData(["reward": reward])
        }
    }

    // MARK: Runner (runner-side fields only)

    func accept(_ id: Quest.ID) {
        guard let uid else { return }
        // Only one accepted quest at a time: release my other one back to active.
        if let mine = acceptedQuest, mine.id != id { release(mine.id) }
        collection.document(id).updateData(["status": Quest.Status.accepted.rawValue, "runnerUid": uid])
    }

    func cancelAccepted() {
        if let mine = acceptedQuest { release(mine.id) }
    }

    func complete(_ id: Quest.ID) {
        collection.document(id).updateData(["status": Quest.Status.completed.rawValue,
                                            "completedAt": Timestamp(date: .now)])
    }

    /// Live arrival estimate for the business dashboard.
    func updateETA(_ seconds: Double, for id: Quest.ID) {
        collection.document(id).updateData(["etaSeconds": seconds.rounded(),
                                            "etaUpdatedAt": FieldValue.serverTimestamp()])
    }

    func dismiss(_ id: Quest.ID) {
        dismissedIDs.insert(id)
    }

    /// Records what happened to an offer popup, so the business dashboard can show it.
    func recordOffer(_ outcome: OfferStats.Outcome, for id: Quest.ID) {
        collection.document(id).updateData([
            "offerStats.\(outcome.rawValue)": FieldValue.increment(Int64(1)),
            "offerStats.lastOutcome": outcome.rawValue,
            "offerStats.lastOutcomeAt": Timestamp(date: .now),
        ])
    }

    private func release(_ id: Quest.ID) {
        collection.document(id).updateData(["status": Quest.Status.active.rawValue,
                                            "runnerUid": FieldValue.delete(),
                                            "etaSeconds": FieldValue.delete(),
                                            "etaUpdatedAt": FieldValue.delete()])
    }
}
