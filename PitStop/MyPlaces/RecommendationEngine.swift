import MapKit
import Observation

/// "Suggested for you": 3–5 places the runner might like next.
///
/// 1. **Gather candidates (app side):** partner businesses with a live promotion, partners that joined
///    recently ("new"), and real places matching the user's interests (cached nearby places plus one
///    MapKit search per top interest) within the goal distance.
/// 2. **Summarize the user:** visit counts per category, typical run distance, saved places, interests,
///    and the current goal. No names, no coordinates, no health data.
/// 3. **Ask Gemini to choose** 3–5 picks **by candidate id only**, each with a label and a short
///    personal reason. Any id not in the list is rejected.
/// 4. **Fallback:** if AI is unavailable, the same candidates are ranked by a simple score
///    (promotion > new > interest, then closeness to the usual distance) with template reasons.
///
/// Results are cached and refreshed at most every 3 hours, or right after a new visit.
@Observable
final class RecommendationEngine {
    struct Context {
        let here: CLLocation
        let partners: [Business]
        let liveQuestReward: (Business.ID) -> String?
        let nearbyPlaces: [RealPlace]
        let runs: [RunRecord]
        let saved: [SavedPlace]
        let interests: Set<Interest>
        let plan: RunPlan
        let target: Double
    }

    private(set) var items: [Recommendation] = []
    private(set) var isLoading = false
    private(set) var usedAI = false
    private(set) var aiError: AIError?
    private(set) var updatedAt: Date?

    let refreshInterval: TimeInterval = 3 * 3600
    @ObservationIgnored private var visitCountAtUpdate = -1
    @ObservationIgnored private var task: Task<Void, Never>?

    init() { loadCache() }

    func recommendation(id: String) -> Recommendation? { items.first { $0.id == id } }

    /// Refreshes only when stale, after a new visit, or when empty.
    func refreshIfNeeded(_ context: Context, ai: any AIService) {
        let visits = context.runs.filter(\.checkedIn).count
        let stale = updatedAt.map { Date.now.timeIntervalSince($0) > refreshInterval } ?? true
        guard !isLoading, items.isEmpty || stale || visits != visitCountAtUpdate else { return }
        refresh(context, ai: ai)
    }

    func refresh(_ context: Context, ai: any AIService) {
        task?.cancel()
        isLoading = true
        task = Task {
            let candidates = await gatherCandidates(context)
            guard !Task.isCancelled else { return }
            let outcome = await withAIFallback {
                try await self.askAI(candidates: candidates, context: context, ai: ai)
            } fallback: {
                Self.fallbackPicks(candidates, context: context)
            }
            items = outcome.value
            usedAI = outcome.usedAI
            aiError = outcome.error
            updatedAt = .now
            visitCountAtUpdate = context.runs.filter(\.checkedIn).count
            isLoading = false
            saveCache()
        }
    }

    // MARK: 1. Candidates

    struct Candidate {
        let id: String              // short id sent to the AI ("C7")
        let destination: PlannedDestination
        let labels: Set<Recommendation.Label>
        let distance: Double
        let reward: String?
        let interests: [Interest]
        let timesVisited: Int
    }

    private func gatherCandidates(_ c: Context) async -> [Candidate] {
        let maxDistance = min(max(c.target, 1500), 8000) * 1.1
        let visits = Dictionary(grouping: c.runs.filter(\.checkedIn), by: { $0.destinationId ?? "" }).mapValues(\.count)
        var byID: [String: (PlannedDestination, Set<Recommendation.Label>, String?, [Interest])] = [:]

        func matchingInterests(_ category: BusinessCategory) -> [Interest] {
            c.interests.filter { $0.categories.contains(category) }.sorted { $0.rawValue < $1.rawValue }
        }

        // Partners: promotions and new businesses.
        for business in c.partners where business.location.distance(from: c.here) <= maxDistance {
            var labels: Set<Recommendation.Label> = []
            let reward = c.liveQuestReward(business.id)
            if reward != nil { labels.insert(.promotion) }
            if business.isNew { labels.insert(.new) }
            let interests = matchingInterests(business.category)
            if !interests.isEmpty { labels.insert(.interest) }
            if !labels.isEmpty { byID[business.id] = (PlannedDestination(business: business), labels, reward, interests) }
        }

        // Real places matching interests: cached nearby places + one search per top interest.
        var places = c.nearbyPlaces
        places += await searchInterests(Array(c.interests.sorted { $0.rawValue < $1.rawValue }.prefix(4)),
                                        around: c.here.coordinate, radius: maxDistance)
        for place in places where byID[place.id] == nil && place.location.distance(from: c.here) <= maxDistance {
            let interests = matchingInterests(place.category) + (searchedInterest[place.id].map { [$0] } ?? [])
            guard !interests.isEmpty else { continue }
            byID[place.id] = (PlannedDestination(place: place), [.interest], nil, Array(Set(interests)))
        }

        // Rank roughly so the best 25 go to the AI (keeps the prompt small).
        let usual = Self.usualDistance(c)
        let ranked = byID.map { id, value -> (Candidate, Double) in
            let distance = value.0.location.distance(from: c.here)
            let score = (value.1.contains(.promotion) ? 3 : 0) + (value.1.contains(.new) ? 2 : 0)
                + Double(value.3.count) - abs(distance - usual) / max(usual, 1)
                - Double(visits[id] ?? 0) * 0.5
            return (Candidate(id: "", destination: value.0, labels: value.1, distance: distance,
                              reward: value.2, interests: value.3, timesVisited: visits[id] ?? 0), score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(25)

        return ranked.enumerated().map { index, pair in
            let c = pair.0
            return Candidate(id: "C\(index + 1)", destination: c.destination, labels: c.labels, distance: c.distance,
                             reward: c.reward, interests: c.interests, timesVisited: c.timesVisited)
        }
    }

    @ObservationIgnored private var searchedInterest: [String: Interest] = [:]

    private func searchInterests(_ interests: [Interest], around center: CLLocationCoordinate2D, radius: Double) async -> [RealPlace] {
        let tasks = interests.map { interest in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = Self.query(for: interest)
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            let search = MKLocalSearch(request: request)
            return Task { () -> [(RealPlace, Interest)] in
                guard let response = try? await search.start() else { return [] }
                return response.mapItems.prefix(10).compactMap { item in
                    guard let place = RealPlace(mapItem: item, category: interest.categories.first) else { return nil }
                    return (place, interest)
                }
            }
        }
        var result: [RealPlace] = []
        for task in tasks {
            for (place, interest) in await task.value {
                searchedInterest[place.id] = interest
                result.append(place)
            }
        }
        return result
    }

    private static func query(for interest: Interest) -> String {
        switch interest {
        case .coffee: "coffee"
        case .bakeries: "bakery"
        case .parks: "park"
        case .bookstores: "bookstore"
        case .smoothies: "smoothie"
        case .gyms: "gym"
        case .vintage: "vintage clothing"
        case .museums: "museum"
        case .waterfront: "waterfront"
        case .streetArt: "mural"
        case .food: "restaurant"
        case .music: "live music"
        }
    }

    /// Median distance of past checked-in runs, else the current goal.
    private static func usualDistance(_ c: Context) -> Double {
        let distances = c.runs.filter(\.checkedIn).map(\.distanceMeters).sorted()
        guard !distances.isEmpty else { return c.plan.shape == .outAndBack ? c.target / 2 : c.target }
        return distances[distances.count / 2]
    }

    // MARK: 2–3. AI picks

    private struct AIAnswer: Decodable {
        struct Pick: Decodable { let candidate_id: String; let label: String; let reason: String }
        let picks: [Pick]
    }

    private func askAI(candidates: [Candidate], context c: Context, ai: any AIService) async throws -> [Recommendation] {
        guard candidates.count >= 1 else { return [] }
        guard ai.isAvailable else { throw AIError.notConfigured }

        // User summary: counts and categories only.
        let visited = c.runs.filter(\.checkedIn)
        let byCategory = Dictionary(grouping: visited, by: \.destinationCategory).mapValues(\.count)
        let summary: JSONValue = [
            "interests": .array(c.interests.map { .string($0.displayName) }),
            "visits_by_category": .object(Dictionary(uniqueKeysWithValues: byCategory.map { ($0.key.displayName, JSONValue.number(Double($0.value))) })),
            "unique_places_visited": .number(Double(Set(visited.compactMap(\.destinationId)).count)),
            "usual_run_miles": .number((Self.usualDistance(c) / Units.metersPerMile * 10).rounded() / 10),
            "saved_for_later_categories": .array(Array(Set(c.saved.map(\.category.displayName))).map { .string($0) }),
            "current_goal": .string("\(String(format: "%.1f", c.target / Units.metersPerMile)) mi \(c.plan.shape.displayName.lowercased()) \(c.plan.activity.displayName.lowercased())"),
        ]
        let list: [JSONValue] = candidates.map { cand in
            var item: [String: JSONValue] = [
                "id": .string(cand.id),
                "name": .string(cand.destination.name),
                "category": .string(cand.destination.category.displayName),
                "distance_miles": .number((cand.distance / Units.metersPerMile * 10).rounded() / 10),
                "allowed_labels": .array(cand.labels.map { .string($0.rawValue) }),
                "times_visited": .number(Double(cand.timesVisited)),
                "on_pitstop": .bool(cand.destination.isPartner),
            ]
            if let reward = cand.reward { item["promotion"] = .string(reward) }
            if !cand.interests.isEmpty { item["matches_interests"] = .array(cand.interests.map { .string($0.displayName) }) }
            return .object(item)
        }

        let system = """
        You recommend places for a runner to run to next. Choose ONLY from the candidate list, by id. \
        Pick 3 to 5. Include promotions and new businesses when they're reasonable, and favor places not \
        visited yet. For each pick give a label from that candidate's allowed_labels and ONE short, \
        personal reason (max 22 words) based only on the user summary and candidate data, e.g. \
        "You've been to three cafés; this new bakery is 2.4 miles away, right in your usual range." \
        Never invent facts (hours, ratings, menus, history).
        """
        let prompt = "User summary: \(Self.compact(summary))\nCandidates: \(Self.compact(.array(list)))"
        let schema = Schema.object([
            "picks": Schema.array(Schema.object([
                "candidate_id": Schema.string(),
                "label": Schema.string(nil, enumValues: Recommendation.Label.allCases.map(\.rawValue)),
                "reason": Schema.string(),
            ], required: ["candidate_id", "label", "reason"])),
        ], required: ["picks"])

        let answer = try await ai.generateJSON(AIAnswer.self, task: .planning, system: system, prompt: prompt,
                                               schema: schema, temperature: 0.7, maxOutputTokens: 1024,
                                               cacheTTL: refreshInterval)

        // Validate: only known ids, no duplicates, labels the candidate actually qualifies for.
        let byShortID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var seen = Set<String>()
        var picks: [Recommendation] = []
        for pick in answer.picks {
            guard let cand = byShortID[pick.candidate_id], seen.insert(cand.id).inserted else { continue }
            let label = Recommendation.Label(rawValue: pick.label).flatMap { cand.labels.contains($0) ? $0 : nil }
                ?? Self.primaryLabel(cand)
            picks.append(Recommendation(destination: cand.destination, label: label,
                                        reason: String(pick.reason.prefix(160)), distance: cand.distance,
                                        reward: label == .promotion ? cand.reward : nil))
            if picks.count == 5 { break }
        }
        guard picks.count >= min(3, candidates.count) else { throw AIError.badJSON("too few valid picks") }
        return picks
    }

    // MARK: 4. Fallback

    private static func fallbackPicks(_ candidates: [Candidate], context: Context) -> [Recommendation] {
        candidates.prefix(5).map { cand in
            let label = primaryLabel(cand)
            let miles = String(format: "%.1f mi away", cand.distance / Units.metersPerMile)
            let reason: String = switch label {
            case .promotion: "\(cand.reward ?? "A reward") right now · \(miles)"
            case .new: "Just joined PitStop · \(miles)"
            case .interest: "Matches your interest in \(cand.interests.first?.displayName.lowercased() ?? "places like this") · \(miles)"
            }
            return Recommendation(destination: cand.destination, label: label, reason: reason,
                                  distance: cand.distance, reward: label == .promotion ? cand.reward : nil)
        }
    }

    private static func primaryLabel(_ c: Candidate) -> Recommendation.Label {
        c.labels.contains(.promotion) ? .promotion : c.labels.contains(.new) ? .new : .interest
    }

    private static func compact(_ value: JSONValue) -> String {
        (try? String(data: JSONEncoder.sorted.encode(value), encoding: .utf8)) ?? "{}"
    }

    // MARK: Cache (Caches/recommendations.json)

    private struct CacheFile: Codable { let items: [Recommendation]; let updatedAt: Date; let visits: Int; let usedAI: Bool }
    private var cacheURL: URL { URL.cachesDirectory.appending(path: "recommendations.json") }

    private func saveCache() {
        guard let updatedAt else { return }
        try? JSONEncoder().encode(CacheFile(items: items, updatedAt: updatedAt, visits: visitCountAtUpdate, usedAI: usedAI))
            .write(to: cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else { return }
        items = file.items
        updatedAt = file.updatedAt
        visitCountAtUpdate = file.visits
        usedAI = file.usedAI
    }
}
