import FirebaseFirestore
import Foundation

/// Mirrors the local SwiftData history to the user's private Firestore subcollections:
///
///     users/{uid}/runs/{runId}          RunRecord (verification + effort score; never health data)
///     users/{uid}/rewards/{rewardId}    kind: "stamp" | "badge" | "partner"
///     users/{uid}/savedPlaces/{placeId} Future Places
///
/// SwiftData stays the source the UI reads (fast, works offline); every local write is also sent
/// here. On sign-in, `merge` pulls what's only in the cloud (e.g. a new phone) and pushes what's only
/// local (e.g. runs from before accounts existed).
@MainActor
final class CloudHistorySync {
    let uid: String
    private var user: DocumentReference { Firestore.firestore().collection("users").document(uid) }

    init(uid: String) { self.uid = uid }

    // MARK: Uploads (fire-and-forget; Firestore queues them while offline)

    func upload(_ run: RunRecord) { user.collection("runs").document(run.id).setData(run.firestoreData) }
    func deleteRun(id: String) { user.collection("runs").document(id).delete() }
    func upload(_ place: SavedPlace) { user.collection("savedPlaces").document(place.id).setData(place.firestoreData) }
    func deleteSavedPlace(id: String) { user.collection("savedPlaces").document(id).delete() }
    func upload(_ stamp: Stamp) { user.collection("rewards").document("stamp-\(stamp.id)").setData(stamp.firestoreData) }
    func upload(_ badge: EarnedBadge) { user.collection("rewards").document("badge-\(badge.id)").setData(badge.firestoreData) }
    func upload(_ reward: EarnedReward) { user.collection("rewards").document(reward.id).setData(reward.firestoreData) }

    // MARK: Two-way merge on sign-in

    struct Remote {
        var runs: [RunRecord] = []
        var places: [SavedPlace] = []
        var stamps: [Stamp] = []
        var badges: [EarnedBadge] = []
        var rewards: [EarnedReward] = []
    }

    func fetchAll() async -> Remote? {
        do {
            async let runs = user.collection("runs").getDocuments()
            async let places = user.collection("savedPlaces").getDocuments()
            async let rewards = user.collection("rewards").getDocuments()
            var remote = Remote()
            remote.runs = try await runs.documents.compactMap { RunRecord(firestore: $0.data()) }
            remote.places = try await places.documents.compactMap { SavedPlace(firestore: $0.data()) }
            for doc in try await rewards.documents {
                let data = doc.data()
                switch data["kind"] as? String {
                case "stamp": if let s = Stamp(firestore: data) { remote.stamps.append(s) }
                case "badge": if let b = EarnedBadge(firestore: data) { remote.badges.append(b) }
                case "partner": if let r = EarnedReward(firestore: data) { remote.rewards.append(r) }
                default: break
                }
            }
            return remote
        } catch {
            print("CloudHistorySync: fetch failed: \(error)")
            return nil
        }
    }
}

// MARK: - Firestore encoding (plain dictionaries; dates as Timestamps)

private func firestoreDate(_ value: Any?) -> Date? { (value as? Timestamp)?.dateValue() ?? value as? Date }

extension RunRecord {
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id, "date": Timestamp(date: date), "activity": activityRaw, "goalType": goalTypeRaw,
            "goalValue": goalValue, "routeShape": routeShapeRaw, "isPartner": isPartner, "checkedIn": checkedIn,
            "distanceMeters": distanceMeters, "durationSeconds": durationSeconds,
            "route": route.map { ["lat": $0.latitude, "lng": $0.longitude] },
            "verification": ["passed": verification.passed, "reasons": verification.reasons, "notes": verification.notes],
        ]
        data["destinationId"] = destinationId
        data["destinationName"] = destinationName
        data["destinationCategory"] = destinationCategoryRaw
        data["destinationLatitude"] = destinationLatitude
        data["destinationLongitude"] = destinationLongitude
        data["questId"] = questId
        data["averagePaceSecondsPerMeter"] = averagePaceSecondsPerMeter
        data["effortScore"] = effortScore
        return data
    }

    convenience init?(firestore d: [String: Any]) {
        guard let id = d["id"] as? String, let date = firestoreDate(d["date"]) else { return nil }
        let v = d["verification"] as? [String: Any] ?? [:]
        self.init(id: id, date: date, plan: nil, destination: nil,
                  checkedIn: d["checkedIn"] as? Bool ?? false, questId: d["questId"] as? String,
                  distanceMeters: d["distanceMeters"] as? Double ?? 0, durationSeconds: d["durationSeconds"] as? Double ?? 0,
                  averagePace: d["averagePaceSecondsPerMeter"] as? Double,
                  route: (d["route"] as? [[String: Double]] ?? []).compactMap { p in
                      guard let lat = p["lat"], let lng = p["lng"] else { return nil }
                      return GeoPoint(latitude: lat, longitude: lng)
                  },
                  verification: VerificationResult(passed: v["passed"] as? Bool ?? false,
                                                   reasons: v["reasons"] as? [String] ?? [],
                                                   notes: v["notes"] as? [String] ?? []),
                  effortScore: d["effortScore"] as? Double)
        activityRaw = d["activity"] as? String ?? activityRaw
        goalTypeRaw = d["goalType"] as? String ?? goalTypeRaw
        goalValue = d["goalValue"] as? Double ?? goalValue
        routeShapeRaw = d["routeShape"] as? String ?? routeShapeRaw
        destinationId = d["destinationId"] as? String
        destinationName = d["destinationName"] as? String
        destinationCategoryRaw = d["destinationCategory"] as? String
        destinationLatitude = d["destinationLatitude"] as? Double
        destinationLongitude = d["destinationLongitude"] as? Double
        isPartner = d["isPartner"] as? Bool ?? false
    }
}

extension SavedPlace {
    var firestoreData: [String: Any] {
        var data: [String: Any] = ["id": id, "name": name, "category": categoryRaw, "latitude": latitude,
                                   "longitude": longitude, "isPartner": isPartner,
                                   "savedAt": Timestamp(date: savedAt), "source": sourceRaw]
        data["address"] = address
        return data
    }

    convenience init?(firestore d: [String: Any]) {
        guard let id = d["id"] as? String, let name = d["name"] as? String,
              let lat = d["latitude"] as? Double, let lng = d["longitude"] as? Double else { return nil }
        let category = BusinessCategory(rawValue: d["category"] as? String ?? "") ?? .other
        let place = RealPlace(id: id, name: name, category: category, address: d["address"] as? String, latitude: lat, longitude: lng)
        self.init(destination: PlannedDestination(place: place),
                  source: SavedPlace.Source(rawValue: d["source"] as? String ?? "") ?? .map)
        isPartner = d["isPartner"] as? Bool ?? false
        savedAt = firestoreDate(d["savedAt"]) ?? .now
    }
}

extension Stamp {
    var firestoreData: [String: Any] {
        var data: [String: Any] = ["kind": "stamp", "placeId": id, "placeName": placeName, "category": categoryRaw,
                                   "latitude": latitude, "longitude": longitude, "isPartner": isPartner,
                                   "earnedAt": Timestamp(date: earnedAt)]
        data["runId"] = runId
        return data
    }

    convenience init?(firestore d: [String: Any]) {
        guard let id = d["placeId"] as? String, let name = d["placeName"] as? String,
              let lat = d["latitude"] as? Double, let lng = d["longitude"] as? Double else { return nil }
        let category = BusinessCategory(rawValue: d["category"] as? String ?? "") ?? .other
        let place = RealPlace(id: id, name: name, category: category, address: nil, latitude: lat, longitude: lng)
        self.init(place: PlannedDestination(place: place), runId: d["runId"] as? String)
        isPartner = d["isPartner"] as? Bool ?? false
        earnedAt = firestoreDate(d["earnedAt"]) ?? .now
    }
}

extension EarnedBadge {
    var firestoreData: [String: Any] { ["kind": "badge", "badge": id, "earnedAt": Timestamp(date: earnedAt)] }

    convenience init?(firestore d: [String: Any]) {
        guard let raw = d["badge"] as? String, let kind = BadgeKind(rawValue: raw) else { return nil }
        self.init(kind: kind)
        earnedAt = firestoreDate(d["earnedAt"]) ?? .now
    }
}

extension EarnedReward {
    var firestoreData: [String: Any] {
        var data: [String: Any] = ["kind": "partner", "id": id, "businessId": businessId, "businessName": businessName,
                                   "category": categoryRaw, "reward": reward, "earnedAt": Timestamp(date: earnedAt),
                                   "redeemed": redeemed]
        data["questId"] = questId
        data["runId"] = runId
        return data
    }

    convenience init?(firestore d: [String: Any]) {
        guard let id = d["id"] as? String, let businessId = d["businessId"] as? String,
              let name = d["businessName"] as? String, let reward = d["reward"] as? String else { return nil }
        let category = BusinessCategory(rawValue: d["category"] as? String ?? "") ?? .other
        let business = Business(id: businessId, name: name, category: category, latitude: 0, longitude: 0, reward: reward)
        self.init(business: PlannedDestination(business: business), reward: reward,
                  questId: d["questId"] as? String, runId: d["runId"] as? String)
        self.id = id
        earnedAt = firestoreDate(d["earnedAt"]) ?? .now
        redeemed = d["redeemed"] as? Bool ?? false
    }
}
