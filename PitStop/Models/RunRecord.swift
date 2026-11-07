import Foundation
import SwiftData

/// One completed run, saved locally with SwiftData.
///
/// Fields are flat (strings, numbers, Codable structs) so each record maps directly onto the
/// Firestore document `users/{uid}/runs/{id}`. Health data is deliberately absent: only the
/// anti-cheat verdict and (later) an effort score are kept.
@Model
final class RunRecord {
    @Attribute(.unique) var id: String
    var date: Date
    var activityRaw: String
    var goalTypeRaw: String
    /// Miles for distance goals, minutes for time goals.
    var goalValue: Double
    var routeShapeRaw: String

    var destinationId: String?
    var destinationName: String?
    var destinationCategoryRaw: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var isPartner: Bool
    /// Reached the destination and stayed 10 s (check-in).
    var checkedIn: Bool
    var questId: String?

    var distanceMeters: Double
    var durationSeconds: Double
    var averagePaceSecondsPerMeter: Double?
    var route: [GeoPoint]
    var verification: VerificationResult
    /// Effort relative to the user's own baseline (filled in once HealthKit is wired in).
    var effortScore: Double?

    init(id: String = UUID().uuidString, date: Date, plan: RunPlan?, destination: PlannedDestination?,
         checkedIn: Bool, questId: String?, distanceMeters: Double, durationSeconds: Double,
         averagePace: Double?, route: [GeoPoint], verification: VerificationResult, effortScore: Double? = nil) {
        self.id = id
        self.date = date
        let plan = plan ?? RunPlan()
        activityRaw = plan.activity.rawValue
        goalTypeRaw = plan.goalType.rawValue
        goalValue = plan.goalType == .distance ? plan.goalMiles : plan.goalMinutes
        routeShapeRaw = plan.shape.rawValue
        destinationId = destination?.id
        destinationName = destination?.name
        destinationCategoryRaw = destination?.category.rawValue
        destinationLatitude = destination?.latitude
        destinationLongitude = destination?.longitude
        isPartner = destination?.isPartner ?? false
        self.checkedIn = checkedIn
        self.questId = questId
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        averagePaceSecondsPerMeter = averagePace
        self.route = route
        self.verification = verification
        self.effortScore = effortScore
    }

    var activity: Activity { Activity(rawValue: activityRaw) ?? .run }
    var goalType: RunPlan.GoalType { RunPlan.GoalType(rawValue: goalTypeRaw) ?? .distance }
    var routeShape: RunPlan.RouteShape { RunPlan.RouteShape(rawValue: routeShapeRaw) ?? .oneWay }
    var destinationCategory: BusinessCategory { destinationCategoryRaw.flatMap(BusinessCategory.init(rawValue:)) ?? .other }
    var destinationPoint: GeoPoint? {
        guard let destinationLatitude, let destinationLongitude else { return nil }
        return GeoPoint(latitude: destinationLatitude, longitude: destinationLongitude)
    }
    var goalText: String {
        goalType == .distance ? String(format: "%.1f mi goal", goalValue) : "\(Int(goalValue)) min goal"
    }
}
