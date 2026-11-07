import MapKit
import Observation

/// Finds destinations that fit a run goal.
///
/// The algorithm, step by step:
///
/// 1. **Ring.** A destination should be a straight-line distance of 70–100% of the goal away
///    (one-way) or 40–50% (out-and-back, because you come back). The ring sits in the middle of that band.
/// 2. **Ring searches.** One MapKit search returns only a limited number of places, so we run
///    `ringPoints` searches centered on points spaced evenly around the ring, then merge and
///    de-duplicate the results. Nearby cached places and partner businesses are added too.
/// 3. **Pre-filter.** Drop anything clearly outside the band, by straight-line distance.
///    Keep the `routeCheckLimit` closest to the ring's middle, since real routing is the expensive step.
/// 4. **Real routes.** Ask MapKit for the actual walking (or cycling) route distance to each one,
///    a few at a time to stay under MapKit's throttle, with results cached.
/// 5. **Filter by the goal.** Total = one leg (one-way) or two legs (out-and-back). Keep places within
///    ±15% of the goal. Partners with a live quest that are *closer* than the goal are kept too, flagged
///    `needsLongerRoute`, since the RouteGenerator adds waypoints to make up the distance.
/// 6. **Sort.** Partners with live quests first, then everything else, each group by fit.
///
/// Fallback: if MapKit routing fails (offline, throttled), straight-line × 1.25 is used and
/// flagged `isEstimate`.
@Observable
final class DestinationFinder {
    enum Phase: Equatable {
        case idle
        case searching(String)
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var matches: [DestinationMatch] = []

    let tolerance = 0.15
    let ringPoints = 6
    let routeCheckLimit = 14
    let partnerCheckLimit = 6
    let concurrentRoutes = 3
    /// Straight line → street distance, used only for estimates and pre-filtering.
    let streetFactor = 1.25

    private let poiFilter = MKPointOfInterestFilter(including: [.cafe, .bakery, .restaurant, .fitnessCenter, .store, .foodMarket])
    @ObservationIgnored private var routeCache: [String: Double] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        phase = .idle
        matches = []
    }

    func match(id: String) -> DestinationMatch? {
        matches.first { $0.id == id }
    }

    /// Starts a new search, cancelling any previous one. Progress is published through `phase`.
    func find(plan: RunPlan, target: Double, from start: CLLocation,
              partners: [Business], openQuest: @escaping (Business.ID) -> Quest?,
              nearbyPlaces: [RealPlace]) {
        task?.cancel()
        matches = []
        phase = .searching("Starting search…")
        task = Task {
            await run(plan: plan, target: target, start: start, partners: partners,
                      openQuest: openQuest, nearbyPlaces: nearbyPlaces)
        }
    }

    // MARK: Pipeline

    private func run(plan: RunPlan, target: Double, start: CLLocation, partners: [Business],
                     openQuest: (Business.ID) -> Quest?, nearbyPlaces: [RealPlace]) async {
        // 1. Ring: the straight-line band where destinations should be.
        let band = plan.destinationRange(target: target)
        let ringRadius = (band.lowerBound + band.upperBound) / 2
        phase = .searching("Searching around \(Format.shortDistance(ringRadius)) away…")

        // 2. Ring searches, merged and de-duplicated.
        var places: [String: RealPlace] = [:]
        for place in nearbyPlaces { places[place.id] = place }
        for place in await ringSearch(center: start.coordinate, radius: ringRadius, bandWidth: band.upperBound - band.lowerBound) {
            places[place.id] = place
        }
        guard !Task.isCancelled else { return }

        // 3. Pre-filter by straight-line distance, keeping those nearest the ring's middle.
        let loose = (band.lowerBound * 0.8)...(band.upperBound * 1.1)
        let placeCandidates = places.values
            .filter { loose.contains(start.distance(from: $0.location)) }
            .sorted { abs(start.distance(from: $0.location) - ringRadius) < abs(start.distance(from: $1.location) - ringRadius) }
            .prefix(routeCheckLimit)
            .map { PlannedDestination(place: $0) }

        // Partners: any within the band's outer edge (closer is fine, since routes can be extended).
        let partnerCandidates = partners
            .filter { start.distance(from: $0.location) <= band.upperBound * 1.1 }
            .sorted { start.distance(from: $0.location) > start.distance(from: $1.location) }
            .prefix(partnerCheckLimit)
            .map { PlannedDestination(business: $0) }

        let candidates = Array(partnerCandidates) + Array(placeCandidates)
        guard !candidates.isEmpty else {
            phase = .failed("No places found at that distance. Try a different goal.")
            return
        }

        // 4. Real route distances, a few at a time.
        let legs = await routeDistances(from: start, to: candidates, transport: plan.activity.transportType)
        guard !Task.isCancelled else { return }

        // 5. Keep the ones that fit the goal.
        let legsPerRun: Double = plan.shape == .outAndBack ? 2 : 1
        var results: [DestinationMatch] = []
        for destination in candidates {
            let (leg, isEstimate) = legs[destination.id] ?? (start.distance(from: destination.location) * streetFactor, true)
            let total = leg * legsPerRun
            let offBy = (total - target) / target   // negative = shorter than the goal
            let quest = destination.isPartner ? openQuest(destination.id).flatMap { $0.status == .active ? $0 : nil } : nil

            let fits = abs(offBy) <= tolerance
            let extendable = quest != nil && offBy < -tolerance
            guard fits || extendable else { continue }

            results.append(DestinationMatch(
                destination: destination, legDistance: leg, totalDistance: total,
                fit: max(0, 1 - abs(offBy)), reward: quest?.reward, questID: quest?.id,
                isEstimate: isEstimate, needsLongerRoute: extendable))
        }

        // 6. Quests first, then by fit.
        matches = results.sorted {
            if $0.hasQuest != $1.hasQuest { return $0.hasQuest }
            return $0.fit > $1.fit
        }
        phase = matches.isEmpty ? .failed("Nothing within ±15% of your goal nearby. Try a different distance or shape.") : .done
    }

    /// Runs one POI search per point around the ring, all in parallel.
    private func ringSearch(center: CLLocationCoordinate2D, radius: Double, bandWidth: Double) async -> [RealPlace] {
        // Each search must reach halfway to its neighbors so the ring has no gaps.
        let spacing = 2 * .pi * radius / Double(ringPoints)
        let searchRadius = min(max(spacing / 2, bandWidth / 2, 400), 3000)

        let tasks = (0..<ringPoints).map { index in
            let bearing = Double(index) * 360 / Double(ringPoints)
            let point = center.offset(bearingDegrees: bearing, meters: radius)
            let request = MKLocalPointsOfInterestRequest(center: point, radius: searchRadius)
            request.pointOfInterestFilter = poiFilter
            let search = MKLocalSearch(request: request)
            return Task { () -> [RealPlace] in
                guard let response = try? await search.start() else { return [] }
                return response.mapItems.compactMap { RealPlace(mapItem: $0) }
            }
        }
        var all: [RealPlace] = []
        for task in tasks { all += await task.value }
        return all
    }

    /// Route distance (meters) to each destination. Values are (distance, isEstimate); a missing entry
    /// means "use the estimate".
    private func routeDistances(from start: CLLocation, to destinations: [PlannedDestination],
                                transport: MKDirectionsTransportType) async -> [String: (Double, Bool)] {
        var result: [String: (Double, Bool)] = [:]
        var done = 0
        for batch in destinations.chunked(into: concurrentRoutes) {
            guard !Task.isCancelled else { break }
            let tasks = batch.map { destination in
                Task { () -> (String, Double?) in
                    (destination.id, await self.routeDistance(from: start.coordinate, to: destination, transport: transport))
                }
            }
            for task in tasks {
                let (id, distance) = await task.value
                if let distance { result[id] = (distance, false) }
                done += 1
            }
            phase = .searching("Checking real routes (\(done) of \(destinations.count))…")
        }
        return result
    }

    private func routeDistance(from start: CLLocationCoordinate2D, to destination: PlannedDestination,
                               transport: MKDirectionsTransportType) async -> Double? {
        // Cache key: start rounded to ~100 m, so small GPS drift reuses results.
        let key = String(format: "%.3f,%.3f|%@|%lu", start.latitude, start.longitude, destination.id, transport.rawValue)
        if let cached = routeCache[key] { return cached }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = transport
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }
        routeCache[key] = route.distance
        return route.distance
    }
}

extension Array {
    /// Splits into consecutive groups of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
