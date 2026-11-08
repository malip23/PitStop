import FirebaseFirestore
import Foundation
import Observation

/// Partner businesses, live from Firestore `businesses/{id}`.
///
/// Every signed-in user listens to the collection (firestore.rules allows reads), so a business
/// created or flipped to "slow" on one phone appears on every other phone within a second. Writes go
/// straight to Firestore; with offline persistence they apply locally at once and sync when online.
@Observable
final class BusinessStore {
    private(set) var businesses: [Business] = []
    private(set) var lastError: String?

    /// Called after each remote update (AppState re-checks quest offers).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var uid: String?

    private var collection: CollectionReference { Firestore.firestore().collection("businesses") }

    func start(uid: String) {
        stop()
        self.uid = uid
        listener = collection.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error { self.lastError = error.localizedDescription; return }
            self.businesses = (snapshot?.documents ?? [])
                .compactMap { try? $0.data(as: Business.self) }
                .sorted { $0.createdAt < $1.createdAt }
            self.lastError = nil
            self.onChange?()
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        businesses = []
        uid = nil
    }

    func business(id: Business.ID) -> Business? {
        businesses.first { $0.id == id }
    }

    /// Insert or replace by id. New businesses are owned by the signed-in user.
    func upsert(_ business: Business) {
        var business = business
        if business.ownerUid == nil { business.ownerUid = uid }
        do {
            try collection.document(business.id).setData(from: business)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(id: Business.ID) {
        collection.document(id).delete()
    }

    /// Flip the "We're slow right now" switch. Records when slowness started (used in quest ranking).
    func setSlow(_ isSlow: Bool, id: Business.ID) {
        collection.document(id).updateData([
            "isSlow": isSlow,
            "slowSince": isSlow ? Timestamp(date: .now) : NSNull(),
        ])
    }

    /// One-time move of the old local `Documents/businesses.json` into Firestore (business/admin only).
    func migrateLocalFileIfNeeded() {
        let url = URL.documentsDirectory.appending(path: "businesses.json")
        guard uid != nil, let local = LocalFileStore.load([Business].self, from: "businesses.json"), !local.isEmpty else { return }
        for var business in local {
            business.ownerUid = uid
            try? collection.document(business.id).setData(from: business, merge: true)
        }
        try? FileManager.default.moveItem(at: url, to: URL.documentsDirectory.appending(path: "businesses.migrated.json"))
    }
}
