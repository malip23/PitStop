import CryptoKit
import Foundation

/// Caches AI answers by a hash of the request, in memory and on disk (Caches/ai/), with a TTL.
/// Identical questions inside the TTL never hit the network, which is the main defense against free-tier limits.
@MainActor
final class AIResponseCache {
    private struct Entry: Codable {
        let expires: Date
        let model: String
        let role: String
        let parts: [JSONValue]
    }

    private var memory: [String: Entry] = [:]
    private let folder: URL = {
        let url = URL.cachesDirectory.appending(path: "ai", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func key(for body: Data, task: AIConfig.Task) -> String {
        let digest = SHA256.hash(data: body + Data(task.rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func get(_ key: String) -> AIResponse? {
        let entry = memory[key] ?? load(key)
        guard let entry, entry.expires > .now else { return nil }
        memory[key] = entry
        return AIResponse(message: AIMessage(role: entry.role, parts: entry.parts), modelUsed: entry.model, fromCache: true)
    }

    func set(_ key: String, response: AIResponse, ttl: TimeInterval) {
        let entry = Entry(expires: .now.addingTimeInterval(ttl), model: response.modelUsed,
                          role: response.message.role, parts: response.message.parts)
        memory[key] = entry
        try? JSONEncoder().encode(entry).write(to: folder.appending(path: "\(key).json"), options: .atomic)
    }

    func clear() {
        memory = [:]
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func load(_ key: String) -> Entry? {
        guard let data = try? Data(contentsOf: folder.appending(path: "\(key).json")) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }
}
