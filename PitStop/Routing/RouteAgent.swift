import MapKit

/// The AI route agent: Gemini picks the nicest path, but only among REAL routes.
///
/// ## Why it's grounded
/// The model can't draw lines on a map. It only gets three tools, all backed by MapKit:
/// - `get_user_preferences()`: goal, shape, activity, pace, interests, destination
/// - `search_places_near(latitude, longitude, category)`: real parks, landmarks, museums, waterfronts
///   to use as scenic waypoints
/// - `get_walking_routes(candidates)`: routes up to 3 waypoint lists through MapKit (the same
///   RouteGenerator code) and returns each one's real distance, time, turns, and fit, with an id
///
/// The model must answer by choosing a candidate id from `get_walking_routes`. It cannot invent paths
/// or distances.
///
/// ## Validation (in Swift, after the AI answers)
/// The chosen route must (1) exist, (2) actually end at the destination, and (3) be within 10% of the
/// goal, or at least no worse than the RouteGenerator's best plus 5%. If any check fails, or the API
/// fails, the caller keeps the RouteGenerator's route.
///
/// Privacy: the start is sent rounded to ~100 m. Only public place data, goals, and interests are sent.
@MainActor
final class RouteAgent {
    struct Suggestion {
        let option: RouteOption
        let title: String
        let reason: String
        let highlights: [String]
        let model: String?
    }

    struct Context {
        let request: RouteGenerator.Request
        let plan: RunPlan
        let interests: [Interest]
        let secondsPerMeter: Double
        /// The RouteGenerator's best option (validation baseline + "direct" info for the model).
        let baseline: RouteOption?
    }

    private struct Answer: Decodable {
        let chosen_candidate_id: String
        let title: String
        let reason: String
        let highlights: [String]
    }

    private let ai: any AIService
    private let generator: RouteGenerator

    init(ai: any AIService, generator: RouteGenerator) {
        self.ai = ai
        self.generator = generator
    }

    func suggest(_ context: Context, onStep: @escaping (String) -> Void) async throws -> Suggestion {
        var computed: [String: RouteOption] = [:]   // candidate id → real MapKit route
        var counter = 0
        let r = context.request

        // MARK: Tools

        let preferences = AITool(
            name: "get_user_preferences",
            description: "The runner's goal, route shape, activity, pace, interests, start (rounded), and destination.",
            parameters: Schema.object([:])
        ) { _ in
            onStep("Reading your goal")
            var info: [String: JSONValue] = [
                "activity": .string(context.plan.activity.displayName),
                "goal_type": .string(context.plan.goalType.rawValue),
                "goal_distance_miles": .number((r.target / Units.metersPerMile * 100).rounded() / 100),
                "tolerance_percent": 10,
                "route_shape": .string(r.shape == .oneWay ? "one-way (finish at destination)" : "out-and-back loop (start → destination → start)"),
                "pace_minutes_per_mile": .number((context.secondsPerMeter * Units.metersPerMile / 60 * 10).rounded() / 10),
                "interests": .array(context.interests.map { .string($0.displayName) }),
                "start": ["latitude": .number(AIPrivacy.rounded(r.start.latitude)),
                          "longitude": .number(AIPrivacy.rounded(r.start.longitude))],
                "destination": ["name": .string(r.destinationName),
                                "latitude": .number(r.destination.latitude),
                                "longitude": .number(r.destination.longitude)],
            ]
            if let baseline = context.baseline {
                info["standard_route_miles"] = .number((baseline.distance / Units.metersPerMile * 100).rounded() / 100)
            }
            return .object(info)
        }

        let search = AITool(
            name: "search_places_near",
            description: "Find real nearby places to use as scenic waypoints. Returns up to 8 with name, category, and coordinates.",
            parameters: Schema.object([
                "latitude": Schema.number(), "longitude": Schema.number(),
                "category": Schema.string("Kind of place", enumValues: ["park", "landmark", "museum", "library", "waterfront", "university", "any"]),
            ], required: ["latitude", "longitude", "category"])
        ) { args in
            let category = args["category"]?.stringValue ?? "any"
            onStep("Looking for \(category == "any" ? "interesting spots" : category + "s")")
            guard let lat = args["latitude"]?.doubleValue, let lon = args["longitude"]?.doubleValue else {
                return ["error": "latitude and longitude are required"]
            }
            return await Self.searchPlaces(near: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                           category: category, start: r.start)
        }

        let routes = AITool(
            name: "get_walking_routes",
            description: """
            Route 1-3 candidate paths with real MapKit directions. Each candidate lists waypoints visited \
            between the start and the destination (0-3), and for out-and-back routes optional \
            return_waypoints visited on the way home. Returns real distance, minutes, turns, fit to the goal, \
            and the first step instructions, each with a candidate id.
            """,
            parameters: Schema.object([
                "candidates": Schema.array(Schema.object([
                    "label": Schema.string("Short name, e.g. 'Park loop'"),
                    "waypoints": Schema.array(Schema.object(["latitude": Schema.number(), "longitude": Schema.number()],
                                                            required: ["latitude", "longitude"])),
                    "return_waypoints": Schema.array(Schema.object(["latitude": Schema.number(), "longitude": Schema.number()],
                                                                   required: ["latitude", "longitude"])),
                ], required: ["label"]), description: "1 to 3 candidates"),
            ], required: ["candidates"])
        ) { [generator] args in
            let candidates = Array((args["candidates"]?.arrayValue ?? []).prefix(3))
            onStep("Checking \(candidates.count) real route\(candidates.count == 1 ? "" : "s")")
            var results: [JSONValue] = []
            for candidate in candidates {
                counter += 1
                let id = "C\(counter)"
                let label = candidate["label"]?.stringValue ?? "Route \(counter)"
                let outbound = Self.points(candidate["waypoints"]).prefix(3)
                let inbound = r.shape == .outAndBack ? Array(Self.points(candidate["return_waypoints"]).prefix(3)) : []
                var path = [r.start] + outbound + [r.destination]
                if r.shape == .outAndBack { path += inbound + [r.start] }

                guard let option = await generator.route(
                    through: path, transport: r.transport, title: label, kind: .ai,
                    waypoints: Array(outbound) + inbound, destinationLegIndex: outbound.count,
                    destinationName: r.destinationName) else {
                    results.append(["id": .string(id), "label": .string(label), "error": "No walkable route through these points"])
                    continue
                }
                computed[id] = option
                let offBy = (option.distance - r.target) / r.target * 100
                results.append([
                    "id": .string(id),
                    "label": .string(label),
                    "distance_miles": .number((option.distance / Units.metersPerMile * 100).rounded() / 100),
                    "minutes": .number((option.distance * context.secondsPerMeter / 60).rounded()),
                    "off_goal_percent": .number((offBy * 10).rounded() / 10),
                    "within_tolerance": .bool(abs(offBy) <= 10),
                    "turns": .number(Double(option.turnCount)),
                    "first_steps": .array(option.steps.prefix(8).map { .string($0.instruction) }),
                ])
            }
            return ["routes": .array(results)]
        }

        // MARK: Run the agent

        let system = """
        You are PitStop's route planner for runners and walkers. You choose among REAL routes returned by \
        tools; never invent paths, distances, or places.
        Plan: 1) call get_user_preferences (you may call search_places_near in the same turn, near the start, \
        the midpoint, or the destination, for parks, waterfront, or landmarks that fit the runner's interests); \
        2) call get_walking_routes with 1-3 candidates using those places as waypoints; 3) if none is within \
        10% of the goal, adjust waypoints (farther out if too short, closer if too long) and call it once more; \
        4) answer.
        Prefer parks, waterfronts, quieter residential streets, and interesting landmarks. Avoid unnecessary \
        turns and big roads. You have at most 5 steps.
        Final answer: JSON with chosen_candidate_id (an id from get_walking_routes), a short catchy title \
        (2-4 words, e.g. "Riverside Loop"), a 1-2 sentence reason mentioning distance fit, and 2-4 short \
        highlights naming places from the tool results.
        """
        let prompt = "Plan the best \(context.plan.activity.displayName.lowercased()) route to \(r.destinationName)."
        let schema = Schema.object([
            "chosen_candidate_id": Schema.string("Id from get_walking_routes, e.g. C2"),
            "title": Schema.string(),
            "reason": Schema.string(),
            "highlights": Schema.array(Schema.string()),
        ], required: ["chosen_candidate_id", "title", "reason", "highlights"])

        let answer = try await AgentRunner(service: ai).run(
            Answer.self, task: .planning, system: system, prompt: prompt,
            tools: [preferences, search, routes], schema: schema, temperature: 0.4,
            cacheTTL: 30 * 60, onStep: { _ in })

        // MARK: Validate with MapKit numbers (never trust the text)

        guard let option = computed[answer.chosen_candidate_id] else { throw AIError.badJSON("unknown candidate id") }
        if let arrival = option.destinationArrival, arrival.distance(to: r.destination) > 80 {
            throw AIError.badJSON("route doesn't reach the destination")
        }
        let error = abs(option.distance - r.target)
        let baselineError = context.baseline.map { abs($0.distance - r.target) } ?? .infinity
        guard error <= r.target * 0.10 || error <= baselineError + r.target * 0.05 else {
            throw AIError.badJSON("route is \(Int(error / r.target * 100))% off the goal")
        }

        return Suggestion(option: option, title: answer.title, reason: answer.reason,
                          highlights: Array(answer.highlights.prefix(4)), model: (ai as? GeminiService)?.lastModelUsed)
    }

    // MARK: Tool helpers

    private static func points(_ value: JSONValue?) -> [CLLocationCoordinate2D] {
        (value?.arrayValue ?? []).compactMap { point in
            guard let lat = point["latitude"]?.doubleValue, let lon = point["longitude"]?.doubleValue,
                  abs(lat) <= 90, abs(lon) <= 180 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private static func searchPlaces(near center: CLLocationCoordinate2D, category: String,
                                     start: CLLocationCoordinate2D) async -> JSONValue {
        var categories: [MKPointOfInterestCategory]
        switch category {
        case "park": categories = [.park, .nationalPark]
        case "museum": categories = [.museum]
        case "library": categories = [.library]
        case "waterfront": categories = [.beach, .marina]
        case "university": categories = [.university]
        case "landmark":
            categories = [.museum, .theater, .stadium]
            if #available(iOS 18.0, *) { categories += [.landmark, .nationalMonument] }
        default:
            categories = [.park, .museum, .library, .beach, .marina]
            if #available(iOS 18.0, *) { categories += [.landmark] }
        }
        let request = MKLocalPointsOfInterestRequest(center: center, radius: 1500)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return ["places": [], "note": "Search unavailable"]
        }
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let places: [JSONValue] = response.mapItems.prefix(8).compactMap { item in
            guard let name = item.name else { return nil }
            let c = item.placemark.coordinate
            return [
                "name": .string(name),
                "category": .string(item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? category),
                "latitude": .number((c.latitude * 10_000).rounded() / 10_000),
                "longitude": .number((c.longitude * 10_000).rounded() / 10_000),
                "distance_from_start_m": .number(startLocation.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)).rounded()),
            ]
        }
        return ["places": .array(places)]
    }
}
