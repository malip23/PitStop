import Foundation

/// Tiny JSON-file persistence in the app's Documents folder.
///
/// Used for mock businesses and quests. Each file holds a plain Codable array, which maps one-to-one
/// onto a cloud collection later.
enum LocalFileStore {
    static func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = URL.documentsDirectory.appending(path: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to fileName: String) {
        let url = URL.documentsDirectory.appending(path: fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            print("LocalFileStore: failed to save \(fileName): \(error)")
        }
    }
}
