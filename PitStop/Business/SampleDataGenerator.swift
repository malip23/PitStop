import FirebaseFirestore
import Foundation

/// "Generate sample week" for DEMO businesses only, so the impact chart has something to show.
///
/// Writes 7 days of Off-Peak windows (expired quests with realistic offer stats) and check-ins,
/// mostly inside those windows. Every visit is marked `isSample: true`, and the chart labels it
/// "Includes sample data". Real businesses never get this button.
enum SampleDataGenerator {
    static func generateWeek(for business: Business, runnerUid: String) async throws {
        let db = Firestore.firestore()
        let batch = db.batch()
        let calendar = Calendar.current
        var rng = SystemRandomNumberGenerator()

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: .now)) else { continue }
            // Two typical lulls: mid-morning and mid-afternoon.
            for (startHour, endHour) in [(10, 11), (14, 16)] {
                guard let start = calendar.date(bySettingHour: startHour, minute: Int.random(in: 0...20, using: &rng), second: 0, of: day),
                      let end = calendar.date(bySettingHour: endHour, minute: Int.random(in: 0...30, using: &rng), second: 0, of: day),
                      end < .now else { continue }
                let shown = Int.random(in: 4...12, using: &rng)
                let accepted = Int.random(in: 1...max(1, shown / 2), using: &rng)
                var quest = Quest(businessId: business.id, reward: business.reward)
                quest.status = .expired
                quest.createdAt = start
                quest.endedAt = end
                quest.offerStats = OfferStats(shown: shown, accepted: accepted, dismissed: shown - accepted - 1,
                                              expired: 1, lastOutcome: .expired, lastOutcomeAt: end)
                try batch.setData(from: quest, forDocument: db.collection("quests").document(quest.id))

                // Most accepted offers turn into a verified visit inside the window.
                for _ in 0..<accepted {
                    let t = start.addingTimeInterval(Double.random(in: 0...end.timeIntervalSince(start), using: &rng))
                    let verified = Int.random(in: 0..<10, using: &rng) > 0
                    let visit = Visit(businessId: business.id, runnerUid: runnerUid, questId: quest.id, verified: verified,
                                      verificationReasons: verified ? [] : ["Almost no steps while moving"],
                                      timestamp: t, isSample: true)
                    try batch.setData(from: visit, forDocument: db.collection("visits").document(visit.id))
                }
            }
            // A couple of ordinary (non-quest) check-ins at busier times.
            for hour in [8, 12, 18] where Bool.random(using: &rng) {
                guard let t = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &rng), second: 0, of: day),
                      t < .now else { continue }
                let visit = Visit(businessId: business.id, runnerUid: runnerUid, questId: nil, verified: true,
                                  verificationReasons: [], timestamp: t, isSample: true)
                try batch.setData(from: visit, forDocument: db.collection("visits").document(visit.id))
            }
        }
        try await batch.commit()
    }
}
