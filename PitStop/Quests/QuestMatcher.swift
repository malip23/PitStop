import CoreLocation

/// Decides which open quests to offer a runner, and in what order.
///
/// **Eligibility:** only partner businesses with an *active* quest, reachable within `maxDetour`
/// extra meters.
///
/// **Extra distance:** if the runner has a planned destination D, going via business B costs
/// `|A→B| + |B→D| − |A→D|`. With no plan, it's just `|A→B|`. Straight-line distances are scaled by
/// `streetFactor`, because real streets are never straight.
///
/// **Score (0–1):**
///   - 50% closeness: `1 − extra / maxDetour`
///   - 25% urgency: how long the business has been slow (max after 60 min)
///   - 25% fair discovery: businesses with fewer recent visits get a boost, so the same popular
///     café doesn't win every time
enum QuestMatcher {
    static let maxDetour: CLLocationDistance = 1.5 * Units.metersPerMile
    static let streetFactor = 1.25

    static let weightDistance = 0.5
    static let weightSlow = 0.25
    static let weightDiscovery = 0.25

    static func offers(
        quests: [Quest],
        businesses: [Business],
        runner: CLLocation,
        plannedDestination: CLLocation? = nil,
        recentVisits: (String) -> Int,
        now: Date = .now
    ) -> [QuestOffer] {
        quests.compactMap { quest -> QuestOffer? in
            guard quest.status == .active,
                  let business = businesses.first(where: { $0.id == quest.businessId }),
                  business.isSlow else { return nil }

            let extra = extraDistance(from: runner, via: business.location, to: plannedDestination)
            guard extra <= maxDetour else { return nil }

            let distanceScore = 1 - extra / maxDetour
            let minutesSlow = now.timeIntervalSince(business.slowSince ?? now) / 60
            let slowScore = min(max(minutesSlow / 60, 0), 1)
            let discoveryScore = 1 / (1 + Double(recentVisits(business.id)) / 5)

            let score = weightDistance * distanceScore + weightSlow * slowScore + weightDiscovery * discoveryScore
            return QuestOffer(quest: quest, business: business, extraDistance: extra,
                              distanceScore: distanceScore, slowScore: slowScore,
                              discoveryScore: discoveryScore, score: score)
        }
        .sorted { $0.score > $1.score }
    }

    static func extraDistance(from start: CLLocation, via stop: CLLocation, to destination: CLLocation?) -> Double {
        let toStop = start.distance(from: stop)
        guard let destination else { return toStop * streetFactor }
        let detour = toStop + stop.distance(from: destination) - start.distance(from: destination)
        return max(0, detour) * streetFactor
    }
}
