import MapKit
import Observation

/// City-guide narration along the active route.
///
/// **Prepare (once, when navigation starts):**
/// 1. Gather interesting places: MapKit landmarks (parks, museums, libraries, universities, stadiums,
///    theaters, and landmarks on iOS 18+) around 3 points of the route, plus businesses that match the
///    runner's interests and partner businesses.
/// 2. Keep those within `corridor` (75 m) of the route, note which side they're on, thin them so
///    they're at least 120 m apart along the route, and cap at 12.
/// 3. Pre-fetch ALL intros in ONE batched Flash-Lite request, so there's no delay later and only
///    one API call. The model may only use the data we send (name, category, address, side, our
///    notes) and must not invent facts. Missing or invalid lines fall back to templates.
///
/// **Update (every fix):** when a place is about 60 m ahead, it's not on cooldown (one per 2 minutes),
/// and it hasn't been narrated this run, hand back its narration.
@Observable
final class NarrationEngine {
    struct Point {
        let id: String
        let name: String
        let kindName: String
        let symbol: String
        let address: String?
        let note: String?
        let destination: PlannedDestination?
        let coordinate: CLLocationCoordinate2D
        var alongRoute: Double = 0
        var side: String = "ahead"
    }

    private(set) var points: [Point] = []
    private(set) var lines: [String: (text: String, usedAI: Bool)] = [:]
    private(set) var isPreparing = false

    let corridor: Double = 75
    let cooldown: TimeInterval = 120
    let triggerAhead: ClosedRange<Double> = 0...60
    let minSpacing: Double = 120
    let maxPoints = 12

    @ObservationIgnored private var narratedIDs: Set<String> = []
    @ObservationIgnored private var lastNarrationAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var demoRelaxed = false

    func reset() {
        task?.cancel()
        points = []
        lines = [:]
        narratedIDs = []
        lastNarrationAt = nil
        isPreparing = false
    }

    func prepare(route: RouteOption, interests: Set<Interest>, partners: [Business], nearbyPlaces: [RealPlace],
                 ai: any AIService, demoMode: Bool) {
        reset()
        demoRelaxed = demoMode
        isPreparing = true
        task = Task {
            var pool = await landmarks(along: route)
            for business in partners {
                pool.append(Point(id: business.id, name: business.name, kindName: business.category.displayName,
                                  symbol: business.category.symbol, address: business.address,
                                  note: "a PitStop partner business", destination: PlannedDestination(business: business),
                                  coordinate: business.coordinate))
            }
            for place in nearbyPlaces {
                let match = interests.first { $0.categories.contains(place.category) }
                guard match != nil || demoMode else { continue }
                pool.append(Point(id: place.id, name: place.name, kindName: place.category.displayName,
                                  symbol: place.category.symbol, address: place.address,
                                  note: match.map { "matches the runner's interest in \($0.displayName.lowercased())" },
                                  destination: PlannedDestination(place: place), coordinate: place.coordinate))
            }
            guard !Task.isCancelled else { return }

            var selected = select(pool, route: route, corridor: demoMode ? 150 : corridor)
            if selected.isEmpty && demoMode { selected = select(pool, route: route, corridor: 300) }
            points = selected
            isPreparing = false
            await prefetch(ai: ai)
        }
    }

    /// Re-measures the same points against a new route (after a reroute).
    func routeChanged(_ route: RouteOption) {
        points = select(points, route: route, corridor: demoRelaxed ? 300 : corridor * 2)
    }

    /// The next narration to show, if one is due.
    func due(progress: Double, timeScale: Double) -> Narration? {
        // Places already behind the runner are never narrated late.
        for point in points where point.alongRoute < progress - 10 { narratedIDs.insert(point.id) }
        if let last = lastNarrationAt, Date.now.timeIntervalSince(last) < cooldown / max(timeScale, 1) { return nil }
        let window = demoRelaxed ? 0...90 : triggerAhead
        guard let point = points.first(where: { !narratedIDs.contains($0.id) && window.contains($0.alongRoute - progress) })
        else { return nil }
        narratedIDs.insert(point.id)
        lastNarrationAt = .now
        let line = lines[point.id] ?? (Self.template(point), false)
        return Narration(id: point.id, name: point.name, kindName: point.kindName, symbol: point.symbol,
                         text: line.text, destination: point.destination, alongRoute: point.alongRoute, usedAI: line.usedAI)
    }

    // MARK: Gathering

    private func landmarks(along route: RouteOption) async -> [Point] {
        let coords = route.coordinates
        guard coords.count > 1 else { return [] }
        var categories: [MKPointOfInterestCategory] = [.park, .museum, .library, .university, .stadium, .theater]
        if #available(iOS 18.0, *) { categories += [.landmark, .nationalMonument] }
        let filter = MKPointOfInterestFilter(including: categories)
        let centers = [0.2, 0.5, 0.8].map { coords[min(Int(Double(coords.count - 1) * $0), coords.count - 1)] }

        let tasks = centers.map { center in
            let request = MKLocalPointsOfInterestRequest(center: center, radius: 900)
            request.pointOfInterestFilter = filter
            let search = MKLocalSearch(request: request)
            return Task { () -> [Point] in
                guard let response = try? await search.start() else { return [] }
                return response.mapItems.compactMap { item in
                    guard let name = item.name, let place = RealPlace(mapItem: item) else { return nil }
                    let (kind, symbol) = Self.describe(item.pointOfInterestCategory)
                    return Point(id: place.id, name: name, kindName: kind, symbol: symbol, address: place.address,
                                 note: nil, destination: nil, coordinate: place.coordinate)
                }
            }
        }
        var all: [Point] = []
        for task in tasks { all += await task.value }
        return all
    }

    /// Keeps points near the route, records where (and on which side) they're passed, spaces them out.
    private func select(_ pool: [Point], route: RouteOption, corridor: Double) -> [Point] {
        let coords = route.coordinates
        guard coords.count > 1 else { return [] }
        var cumulative: [Double] = [0]
        for (a, b) in zip(coords, coords.dropFirst()) { cumulative.append(cumulative.last! + a.distance(to: b)) }

        var seen = Set<String>()
        var measured: [Point] = []
        for var point in pool where seen.insert(point.id).inserted {
            var best: (d: Double, along: Double, index: Int)?
            for i in 0..<(coords.count - 1) {
                let (d, t) = NavigationEngine.distance(from: point.coordinate, toSegment: coords[i], coords[i + 1])
                if d <= corridor, best == nil || d < best!.d {
                    best = (d, cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t, i)
                }
            }
            guard let best else { continue }
            point.alongRoute = best.along
            // Side: sign of the turn from the route direction to the place.
            let a = coords[best.index], b = coords[best.index + 1]
            // Angle from the direction of travel to the place: positive = clockwise = on the right.
            let turn = (a.bearing(to: point.coordinate) - a.bearing(to: b) + 540).truncatingRemainder(dividingBy: 360) - 180
            point.side = best.d < 15 ? "ahead" : (turn > 0 ? "right" : "left")
            measured.append(point)
        }

        var spaced: [Point] = []
        for point in measured.sorted(by: { $0.alongRoute < $1.alongRoute }) {
            if let last = spaced.last, point.alongRoute - last.alongRoute < minSpacing { continue }
            spaced.append(point)
            if spaced.count == maxPoints { break }
        }
        return spaced
    }

    // MARK: One batched AI request

    private struct Batch: Decodable {
        struct Line: Decodable { let id: String; let text: String }
        let lines: [Line]
    }

    private func prefetch(ai: any AIService) async {
        guard !points.isEmpty, ai.isAvailable else { return }
        let list: [JSONValue] = points.map { p in
            var item: [String: JSONValue] = ["id": .string(p.id), "name": .string(p.name),
                                             "category": .string(p.kindName), "side": .string(p.side)]
            if let address = p.address { item["address"] = .string(address) }
            if let note = p.note { item["our_note"] = .string(note) }
            return .object(item)
        }
        let system = """
        You are a friendly city guide speaking to a runner through their earbuds. For EACH place, write a \
        short intro of 1-2 sentences (max 28 words) like "On your right is the town library, a good \
        cooldown spot." Use ONLY the given name, category, address, side, and our_note. Do NOT invent \
        history, dates, architects, ratings, opening hours, or any other facts. If there's nothing \
        notable, keep it simple. Mention the side when it's left or right.
        """
        let schema = Schema.object([
            "lines": Schema.array(Schema.object(["id": Schema.string(), "text": Schema.string()], required: ["id", "text"])),
        ], required: ["lines"])
        let prompt = "Places along the route: \((try? String(data: JSONEncoder.sorted.encode(JSONValue.array(list)), encoding: .utf8)) ?? "[]")"

        guard let batch = try? await ai.generateJSON(Batch.self, task: .narration, system: system, prompt: prompt,
                                                     schema: schema, temperature: 0.6, maxOutputTokens: 1500,
                                                     cacheTTL: 6 * 3600) else { return }
        let known = Set(points.map(\.id))
        for line in batch.lines where known.contains(line.id) {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 220 else { continue }
            lines[line.id] = (text, true)
        }
    }

    // MARK: Templates (no AI)

    static func template(_ p: Point) -> String {
        let side = p.side == "ahead" ? "Just ahead" : "On your \(p.side)"
        let article = ["a", "e", "i", "o", "u"].contains(p.kindName.lowercased().prefix(1)) ? "an" : "a"
        if let note = p.note, note.contains("partner") {
            return "\(side) is \(p.name), \(article) \(p.kindName.lowercased()) on PitStop."
        }
        return "\(side) is \(p.name), \(article) \(p.kindName.lowercased())."
    }

    private static func describe(_ category: MKPointOfInterestCategory?) -> (String, String) {
        switch category {
        case .park?, .nationalPark?: return ("park", "tree.fill")
        case .museum?: return ("museum", "building.columns.fill")
        case .library?: return ("library", "books.vertical.fill")
        case .university?: return ("university", "graduationcap.fill")
        case .stadium?: return ("stadium", "sportscourt.fill")
        case .theater?: return ("theater", "theatermasks.fill")
        default: return ("landmark", "mappin.and.ellipse")
        }
    }
}
