import CoreLocation
import Foundation

/// Fetches crosswalks and traffic signals from the free OpenStreetMap Overpass API.
///
/// One query per route bounding box, cached on disk (Caches/overpass/) so the same area is never
/// fetched twice. If the main server fails or is busy, a public mirror is tried. Only a bounding box is
/// sent: no user data.
enum OverpassService {
    struct Node: Codable, Hashable {
        let id: Int64
        let lat: Double
        let lon: Double
        let tags: [String: String]?

        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        var isTrafficSignal: Bool { tags?["highway"] == "traffic_signals" || tags?["crossing"] == "traffic_signals" }
    }

    private struct Response: Decodable { let elements: [Node] }

    enum Failure: Error { case unavailable }

    private static let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
    ]

    /// Crossing and traffic-signal nodes inside the box (degrees).
    static func crossings(south: Double, west: Double, north: Double, east: Double) async throws -> [Node] {
        let key = String(format: "%.3f_%.3f_%.3f_%.3f", south, west, north, east)
        if let cached = loadCache(key) { return cached }

        let bbox = String(format: "%.6f,%.6f,%.6f,%.6f", south, west, north, east)
        let query = """
        [out:json][timeout:15];
        (node["highway"="crossing"](\(bbox));node["highway"="traffic_signals"](\(bbox)););
        out body;
        """
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "data", value: query)]
        let body = Data((form.percentEncodedQuery ?? "").utf8)

        for endpoint in endpoints {
            var request = URLRequest(url: endpoint, timeoutInterval: 12)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("PitStop-iOS/1.0 (hackathon demo)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(Response.self, from: data) else { continue }
            saveCache(key, decoded.elements)
            return decoded.elements
        }
        throw Failure.unavailable
    }

    // MARK: Cache

    private static func cacheURL(_ key: String) -> URL {
        let folder = URL.cachesDirectory.appending(path: "overpass", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(key).json")
    }

    private static func loadCache(_ key: String) -> [Node]? {
        guard let data = try? Data(contentsOf: cacheURL(key)) else { return nil }
        return try? JSONDecoder().decode([Node].self, from: data)
    }

    private static func saveCache(_ key: String, _ nodes: [Node]) {
        try? JSONEncoder().encode(nodes).write(to: cacheURL(key), options: .atomic)
    }
}
