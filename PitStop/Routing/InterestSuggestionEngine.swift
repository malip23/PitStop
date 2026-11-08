import MapKit
import Observation

/// Finds quick stops along the route that match the runner's interests.
///
/// **At run start (`prepare`):** gather candidates once: partner businesses, the nearby-places cache,
/// and MapKit searches for the runner's top interests around 3 points along the route. Keep places
/// within `corridor` (150 m) of the route, and record where along the route each one is passed.
/// Partners with a live promotion are skipped, because the timed offer popup handles those.
///
/// **On every fix (`eligible`):** return places that are ahead of the runner (approaching, not passed),
/// within a small detour (< 0.3 mi), not suggested before this run, and only once the 3-minute
/// cooldown has passed.
///
/// **Demo Mode:** if no interest matches lie on the simulated route, any nearby spot within 300 m
/// qualifies, so the demo always shows at least one suggestion.
@Observable
final class InterestSuggestionEngine {
    struct Candidate {
        let destination: PlannedDestination
        let interest: Interest?
        let alongRoute: Double
        let lateral: Double

        /// There-and-back from the route, with the usual 1.25 street factor.
        var detour: Double { max(50, lateral * 2 * 1.25) }
    }

    private(set) var candidates: [Candidate] = []
    private(set) var isPreparing = false

    let corridor: Double = 150
    let maxDetour: Double = 0.3 * Units.metersPerMile
    let cooldown: TimeInterval = 180
    let lookAhead: ClosedRange<Double> = 60...500

    @ObservationIgnored private var pool: [(PlannedDestination, Interest?)] = []
    @ObservationIgnored private var suggestedIDs: Set<String> = []
    @ObservationIgnored private var lastSuggestionAt: Date?
    @ObservationIgnored private var demoRelaxed = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        candidates = []
        pool = []
        suggestedIDs = []
        lastSuggestionAt = nil
        isPreparing = false
    }

    /// Gathers candidates for a new run.
    func prepare(route: RouteOption, interests: Set<Interest>, partners: [Business],
                 hasLivePromotion: @escaping (Business.ID) -> Bool, nearbyPlaces: [RealPlace],
                 excludeID: String?, demoMode: Bool) {
        reset()
        demoRelaxed = demoMode
        isPreparing = true
        task = Task {
            var pool: [String: (PlannedDestination, Interest?)] = [:]
            func interest(for category: BusinessCategory) -> Interest? {
                interests.sorted { $0.rawValue < $1.rawValue }.first { $0.categories.contains(category) }
            }

            for business in partners where !hasLivePromotion(business.id) && business.id != excludeID {
                pool[business.id] = (PlannedDestination(business: business), interest(for: business.category))
            }
            for place in nearbyPlaces where place.id != excludeID {
                pool[place.id] = pool[place.id] ?? (PlannedDestination(place: place), interest(for: place.category))
            }
            for (place, matched) in await search(interests: interests, along: route) where place.id != excludeID {
                pool[place.id] = (PlannedDestination(place: place), matched)
            }
            guard !Task.isCancelled else { return }
            self.pool = Array(pool.values)
            project(onto: route)
            isPreparing = false
        }
    }

    /// Re-measures the cached pool against a new route (after a reroute). No new searches.
    func routeChanged(_ route: RouteOption) {
        guard !pool.isEmpty else { return }
        project(onto: route)
    }

    /// Candidates the runner is approaching, best (closest ahead) first. Empty during the cooldown.
    func eligible(progress: Double, timeScale: Double) -> [Candidate] {
        if let last = lastSuggestionAt, Date.now.timeIntervalSince(last) < cooldown / max(timeScale, 1) { return [] }
        let detourLimit = demoRelaxed ? 0.5 * Units.metersPerMile : maxDetour
        let ahead = demoRelaxed ? 40...700 : lookAhead
        return candidates
            .filter { !suggestedIDs.contains($0.destination.id) && $0.detour <= detourLimit
                && ahead.contains($0.alongRoute - progress) }
            .sorted { $0.alongRoute < $1.alongRoute }
    }

    /// Marks a suggestion as made (starts the cooldown; never repeats this place this run).
    func markSuggested(_ id: String) {
        suggestedIDs.insert(id)
        lastSuggestionAt = .now
    }

    // MARK: Private

    private func project(onto route: RouteOption) {
        let coords = route.coordinates
        guard coords.count > 1 else { return }
        var cumulative: [Double] = [0]
        for (a, b) in zip(coords, coords.dropFirst()) { cumulative.append(cumulative.last! + a.distance(to: b)) }

        func measure(_ corridor: Double, requireInterest: Bool) -> [Candidate] {
            pool.compactMap { destination, interest in
                if requireInterest && interest == nil { return nil }
                var best: (lateral: Double, along: Double)?
                for i in 0..<(coords.count - 1) {
                    let (d, t) = NavigationEngine.distance(from: destination.coordinate, toSegment: coords[i], coords[i + 1])
                    if d <= corridor, best == nil || d < best!.lateral {
                        best = (d, cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t)
                    }
                }
                guard let best else { return nil }
                return Candidate(destination: destination, interest: interest, alongRoute: best.along, lateral: best.lateral)
            }
        }

        var result = measure(corridor, requireInterest: true)
        if result.isEmpty && demoRelaxed {
            // Demo guarantee: any nearby spot along the simulated route.
            result = measure(300, requireInterest: false)
        }
        candidates = result.sorted { $0.alongRoute < $1.alongRoute }
    }

    /// MapKit searches for the top 3 interests around 3 points along the route (≤ 9 searches).
    private func search(interests: Set<Interest>, along route: RouteOption) async -> [(RealPlace, Interest)] {
        let coords = route.coordinates
        guard coords.count > 1 else { return [] }
        let centers = [0.2, 0.5, 0.8].map { coords[min(Int(Double(coords.count - 1) * $0), coords.count - 1)] }
        let top = interests.filter { !$0.categories.isEmpty || $0 == .parks }.sorted { $0.rawValue < $1.rawValue }.prefix(3)

        var tasks: [Task<[(RealPlace, Interest)], Never>] = []
        for interest in top {
            for center in centers {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = Self.query(for: interest)
                request.resultTypes = .pointOfInterest
                request.region = MKCoordinateRegion(center: center, latitudinalMeters: 1200, longitudinalMeters: 1200)
                let search = MKLocalSearch(request: request)
                tasks.append(Task {
                    guard let response = try? await search.start() else { return [] }
                    return response.mapItems.prefix(8).compactMap { item in
                        RealPlace(mapItem: item, category: interest.categories.first).map { ($0, interest) }
                    }
                })
            }
        }
        var all: [(RealPlace, Interest)] = []
        for task in tasks { all += await task.value }
        return all
    }

    private static func query(for interest: Interest) -> String {
        switch interest {
        case .coffee: "coffee"
        case .bakeries: "bakery"
        case .smoothies: "smoothie"
        case .bookstores: "bookstore"
        case .gyms: "gym"
        case .vintage: "vintage clothing"
        case .food: "restaurant"
        case .parks: "park"
        default: interest.displayName
        }
    }
}
