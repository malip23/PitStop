import MapKit
import Observation

/// Finds real nearby places with Apple's MapKit search (no API key needed).
///
/// How it works:
/// 1. One `MKLocalPointsOfInterestRequest` per runner-friendly category (café, bakery, restaurant,
///    fitness center, store), plus natural-language `MKLocalSearch` queries for juice and smoothie
///    shops, which have no POI category of their own.
/// 2. All searches run in parallel. Results are de-duplicated, trimmed to the closest few per
///    category so the map stays readable, and cached to disk.
/// 3. `refreshIfNeeded` only searches again after the user moves `refreshDistance` away from the
///    last search center, or the cache is older than `maxAge`.
@Observable
final class PlacesService {
    private(set) var places: [RealPlace] = []
    private(set) var isSearching = false
    private(set) var lastError: String?

    @ObservationIgnored private var searchCenter: CLLocation?
    @ObservationIgnored private var searchedAt: Date?

    let searchRadius: CLLocationDistance = 1500
    let refreshDistance: CLLocationDistance = 600
    let maxAge: TimeInterval = 30 * 60
    let perCategoryLimit = 8

    /// POI categories to search, and how each maps to our own category.
    private let poiCategories: [(MKPointOfInterestCategory, BusinessCategory)] = [
        (.cafe, .cafe), (.bakery, .bakery), (.restaurant, .restaurant),
        (.fitnessCenter, .fitness), (.store, .store),
    ]
    /// Free-text queries for shop types MapKit has no POI category for.
    private let textQueries: [(String, BusinessCategory)] = [
        ("juice bar", .juicery), ("smoothie", .smoothieBar),
    ]

    init() {
        loadCache()
    }

    /// Call on every location fix. Searches only if the user has moved far or the cache is stale.
    func refreshIfNeeded(around location: CLLocation) {
        guard !isSearching else { return }
        if let center = searchCenter, let date = searchedAt,
           location.distance(from: center) < refreshDistance,
           Date.now.timeIntervalSince(date) < maxAge {
            return
        }
        Task { await search(around: location) }
    }

    /// Ignore the cache and search now (Settings → Refresh nearby places).
    func forceRefresh(around location: CLLocation) {
        guard !isSearching else { return }
        Task { await search(around: location) }
    }

    func place(id: RealPlace.ID) -> RealPlace? {
        places.first { $0.id == id }
    }

    // MARK: Search

    private func search(around location: CLLocation) async {
        isSearching = true
        defer { isSearching = false }
        // Record the center up front so incoming GPS fixes don't trigger duplicate searches.
        searchCenter = location
        searchedAt = .now

        let center = location.coordinate
        var searches: [(MKLocalSearch, BusinessCategory)] = []

        for (poi, category) in poiCategories {
            let request = MKLocalPointsOfInterestRequest(center: center, radius: searchRadius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [poi])
            searches.append((MKLocalSearch(request: request), category))
        }
        for (query, category) in textQueries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: center,
                                                latitudinalMeters: searchRadius * 2,
                                                longitudinalMeters: searchRadius * 2)
            searches.append((MKLocalSearch(request: request), category))
        }

        // Start every search at once. Each Task converts its results to `RealPlace` right away,
        // so only Sendable values cross the task boundary. nil means that search failed.
        let tasks = searches.map { search, category in
            Task { () -> [RealPlace]? in
                guard let response = try? await search.start() else { return nil }
                return response.mapItems.compactMap { Self.makePlace(from: $0, category: category) }
            }
        }
        var batches: [[RealPlace]] = []
        for task in tasks {
            if let batch = await task.value { batches.append(batch) }
        }

        guard !batches.isEmpty else {
            // Offline or throttled: keep the old results and retry in about a minute.
            lastError = "Couldn't load nearby places."
            searchedAt = Date.now.addingTimeInterval(-maxAge + 60)
            return
        }

        lastError = nil
        places = Self.merge(batches, around: location, radius: searchRadius, limit: perCategoryLimit)
        saveCache(center: location)
    }

    /// De-duplicates by id, drops far results, and keeps the closest `limit` per category.
    private static func merge(_ batches: [[RealPlace]], around location: CLLocation,
                              radius: CLLocationDistance, limit: Int) -> [RealPlace] {
        var seen = Set<String>()
        var byCategory: [BusinessCategory: [RealPlace]] = [:]
        for place in batches.joined() where seen.insert(place.id).inserted {
            guard place.location.distance(from: location) <= radius * 1.2 else { continue }
            byCategory[place.category, default: []].append(place)
        }
        return byCategory.values.flatMap { group in
            group.sorted { $0.location.distance(from: location) < $1.location.distance(from: location) }
                .prefix(limit)
        }
    }

    private static func makePlace(from item: MKMapItem, category: BusinessCategory) -> RealPlace? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let placemark = item.placemark
        let coordinate = placemark.coordinate

        // Stable id: MapKit's own identifier when available, otherwise name + rounded coordinate.
        var id = "\(name)|\(String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude))"
        if #available(iOS 18.0, *), let identifier = item.identifier {
            id = identifier.rawValue
        }

        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, placemark.locality ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")

        return RealPlace(id: id, name: name, category: category,
                         address: address.isEmpty ? nil : address,
                         latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    // MARK: Disk cache (Caches/nearby-places.json)

    private struct CacheFile: Codable {
        let latitude: Double
        let longitude: Double
        let date: Date
        let places: [RealPlace]
    }

    private var cacheURL: URL {
        URL.cachesDirectory.appending(path: "nearby-places.json")
    }

    private func saveCache(center: CLLocation) {
        let file = CacheFile(latitude: center.coordinate.latitude, longitude: center.coordinate.longitude,
                             date: .now, places: places)
        try? JSONEncoder().encode(file).write(to: cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else { return }
        places = file.places
        searchCenter = CLLocation(latitude: file.latitude, longitude: file.longitude)
        searchedAt = file.date
    }
}
