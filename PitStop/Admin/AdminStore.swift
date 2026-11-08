import FirebaseFirestore
import Observation

/// Live admin data. Only works for admins (firestore.rules lets only `role == "admin"` read every user,
/// count all runs, and change roles).
@Observable
final class AdminStore {
    struct Stats: Equatable {
        var totalUsers = 0
        var activeQuests = 0
        var completedVisits = 0
        var totalRuns = 0
    }

    private(set) var users: [UserProfile] = []
    private(set) var quests: [Quest] = []
    private(set) var stats = Stats()
    private(set) var isLoadingStats = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    private var db: Firestore { Firestore.firestore() }

    func start() {
        guard listeners.isEmpty else { return }
        listeners.append(db.collection("users").addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error { self.errorMessage = error.localizedDescription; return }
            self.users = (snapshot?.documents ?? []).compactMap { try? $0.data(as: UserProfile.self) }
                .sorted { $0.lastActiveAt > $1.lastActiveAt }
            self.stats.totalUsers = self.users.count
        })
        listeners.append(db.collection("quests").order(by: "createdAt", descending: true).limit(to: 200)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.errorMessage = error.localizedDescription; return }
                self.quests = (snapshot?.documents ?? []).compactMap { try? $0.data(as: Quest.self) }
                self.stats.activeQuests = self.quests.filter(\.isOpen).count
            })
        Task { await refreshCounts() }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    /// Server-side counts (cheap aggregation queries; no documents downloaded).
    func refreshCounts() async {
        isLoadingStats = true
        defer { isLoadingStats = false }
        do {
            async let visits = db.collection("visits").whereField("verified", isEqualTo: true)
                .count.getAggregation(source: .server)
            async let runs = db.collectionGroup("runs").count.getAggregation(source: .server)
            stats.completedVisits = try await visits.count.intValue
            stats.totalRuns = try await runs.count.intValue
        } catch {
            errorMessage = "Counts unavailable: \(error.localizedDescription)"
        }
    }

    // MARK: Actions (admin-only by the rules)

    func setRole(_ role: UserRole, for uid: String) {
        db.collection("users").document(uid).updateData(["role": role.rawValue])
    }

    func deleteQuest(_ id: String) {
        db.collection("quests").document(id).delete()
    }

    /// Deletes a business with its quests and visits (quests first: the rules check the owner).
    func deleteBusiness(_ id: String) async {
        for quest in quests where quest.businessId == id { try? await db.collection("quests").document(quest.id).delete() }
        if let visits = try? await db.collection("visits").whereField("businessId", isEqualTo: id).getDocuments() {
            for doc in visits.documents { try? await doc.reference.delete() }
        }
        try? await db.collection("businesses").document(id).delete()
    }

    /// Removes every mock (demo) business and its quests and visits.
    func deleteAllMockData(_ businesses: [Business]) async {
        for business in businesses where business.isMock { await deleteBusiness(business.id) }
        await refreshCounts()
    }

    func user(_ uid: String?) -> UserProfile? {
        guard let uid else { return nil }
        return users.first { $0.id == uid }
    }
}
