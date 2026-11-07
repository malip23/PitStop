import Foundation
import Observation

/// Owns the partner businesses (currently all mock/demo businesses) and saves them to
/// `Documents/businesses.json` so they survive relaunches.
@Observable
final class BusinessStore {
    private(set) var businesses: [Business] = []

    private let fileName = "businesses.json"

    init() {
        businesses = LocalFileStore.load([Business].self, from: fileName) ?? []
    }

    func business(id: Business.ID) -> Business? {
        businesses.first { $0.id == id }
    }

    /// Insert or replace by id.
    func upsert(_ business: Business) {
        if let index = businesses.firstIndex(where: { $0.id == business.id }) {
            businesses[index] = business
        } else {
            businesses.append(business)
        }
        save()
    }

    func delete(id: Business.ID) {
        businesses.removeAll { $0.id == id }
        save()
    }

    /// Flip the "We're slow right now" switch. Records when slowness started (used in quest ranking).
    func setSlow(_ isSlow: Bool, id: Business.ID) {
        guard var business = business(id: id), business.isSlow != isSlow else { return }
        business.isSlow = isSlow
        business.slowSince = isSlow ? .now : nil
        upsert(business)
    }

    private func save() {
        LocalFileStore.save(businesses, to: fileName)
    }
}
