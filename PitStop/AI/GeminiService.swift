import Foundation
import Observation

/// Gemini over REST: `POST {base}/models/{model}:generateContent`.
///
/// Request pipeline, in order:
/// 1. **Cache:** identical request (same body + task) within its TTL? Return the cached answer.
/// 2. **De-duplicate:** the same request already in flight? Await that one instead of sending twice.
/// 3. **Throttle:** wait for this task's slot and count it against the daily cap (`AIRateLimiter`).
/// 4. **Send** through the Cloudflare Worker (recommended) or directly with the key (demo).
/// 5. **429:** wait the server's `retryDelay` (max 8 s) once and retry, then try the fallback model,
///    then give up with `.rateLimited`. Callers show "AI unavailable" and use their non-AI fallback.
/// 6. **Compatibility retries:** if the model rejects `thinkingConfig`, or JSON-schema output combined
///    with tools, retry without it (the agent runner then asks for JSON in a separate final call).
@Observable
final class GeminiService: AIService {
    /// Last failure, for the small "AI unavailable" notes in the UI. Cleared on the next success.
    private(set) var lastError: AIError?
    private(set) var lastSuccessAt: Date?
    /// Which model answered last (shown on AI cards).
    private(set) var lastModelUsed: String?
    /// Set when the model refused tools + responseSchema in one request.
    @ObservationIgnored private(set) var toolsWithSchemaUnsupported = false

    @ObservationIgnored private let cache = AIResponseCache()
    @ObservationIgnored let limiter = AIRateLimiter()
    @ObservationIgnored private var inFlight: [String: Task<AIResponse, Error>] = [:]
    @ObservationIgnored private var thinkingUnsupported: Set<String> = []
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AIConfig.requestTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    var connection: AIConfig.Connection { AIConfig.connection }

    var isAvailable: Bool {
        guard connection != .unavailable else { return false }
        if case .rateLimited = lastError, let since = lastErrorAt, Date.now.timeIntervalSince(since) < 60 { return false }
        return true
    }
    @ObservationIgnored private var lastErrorAt: Date?

    func clearCache() { cache.clear() }

    // MARK: AIService

    func generate(_ request: AIRequest) async throws -> AIResponse {
        guard connection != .unavailable else { throw fail(.notConfigured) }

        // 1–2. Cache and in-flight de-duplication, keyed on the model-independent body.
        let keyBody = (try? JSONEncoder.sorted.encode(body(for: request, model: "", includeThinking: false))) ?? Data()
        let key = AIResponseCache.key(for: keyBody, task: request.task)
        if request.cacheTTL > 0, let cached = cache.get(key) { return cached }
        if let running = inFlight[key] { return try await running.value }

        let task = Task { try await self.send(request) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        do {
            let response = try await task.value
            if request.cacheTTL > 0 { cache.set(key, response: response, ttl: request.cacheTTL) }
            lastError = nil
            lastSuccessAt = .now
            lastModelUsed = response.modelUsed
            return response
        } catch let error as AIError {
            throw fail(error)
        } catch {
            throw fail((error as? URLError)?.code == .notConnectedToInternet ? .offline : .invalidResponse)
        }
    }

    // MARK: Sending with retries and model fallback

    private func send(_ request: AIRequest) async throws -> AIResponse {
        var lastFailure: AIError = .invalidResponse
        for model in request.task.models {
            var backedOff = false
            var attempt = request
            if toolsWithSchemaUnsupported, !attempt.tools.isEmpty { attempt.responseSchema = nil }
            while true {
                try await limiter.acquire(request.task)
                do {
                    return try await post(attempt, model: model)
                } catch AIError.rateLimited(let retryAfter) {
                    lastFailure = .rateLimited(retryAfter: retryAfter)
                    let wait = min(retryAfter ?? 3, AIConfig.maxBackoff)
                    if !backedOff, (retryAfter ?? 0) <= AIConfig.maxBackoff {
                        backedOff = true
                        try await Task.sleep(for: .seconds(wait))
                        continue                     // retry same model once
                    }
                    limiter.coolDown(request.task, for: retryAfter ?? 30)
                    break                            // try the fallback model
                } catch AIError.http(let status, let message) where status == 400 {
                    // Compatibility fallbacks, then a real error.
                    if message.localizedCaseInsensitiveContains("thinking"), !thinkingUnsupported.contains(model) {
                        thinkingUnsupported.insert(model)
                        continue
                    }
                    if attempt.responseSchema != nil, !attempt.tools.isEmpty {
                        toolsWithSchemaUnsupported = true
                        attempt.responseSchema = nil
                        continue
                    }
                    throw AIError.http(status: status, message: message)
                } catch AIError.http(let status, let message) where status == 404 || status >= 500 {
                    lastFailure = .http(status: status, message: message)
                    break                            // model missing or server trouble → fallback model
                }
            }
        }
        throw lastFailure
    }

    private func post(_ request: AIRequest, model: String) async throws -> AIResponse {
        let url: URL
        var urlRequest: URLRequest
        switch connection {
        case .proxy(let host, let token):
            url = URL(string: "https://\(host)/v1beta/models/\(model):generateContent")!
            urlRequest = URLRequest(url: url)
            if let token { urlRequest.setValue(token, forHTTPHeaderField: "x-pitstop-token") }
        case .direct(let apiKey):
            url = AIConfig.directBaseURL.appending(path: "models/\(model):generateContent")
            urlRequest = URLRequest(url: url)
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .unavailable:
            throw AIError.notConfigured
        }
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            body(for: request, model: model, includeThinking: !thinkingUnsupported.contains(model)))

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null

        guard status == 200 else {
            let message = json["error"]?["message"]?.stringValue ?? HTTPURLResponse.localizedString(forStatusCode: status)
            if status == 429 { throw AIError.rateLimited(retryAfter: Self.retryDelay(from: json, response: response)) }
            throw AIError.http(status: status, message: message)
        }

        if let reason = json["promptFeedback"]?["blockReason"]?.stringValue { throw AIError.blocked(reason) }
        guard let content = json["candidates"]?.arrayValue?.first?["content"],
              let parts = content["parts"]?.arrayValue, !parts.isEmpty else {
            let finish = json["candidates"]?.arrayValue?.first?["finishReason"]?.stringValue
            throw finish.map { AIError.blocked($0) } ?? AIError.invalidResponse
        }
        return AIResponse(message: AIMessage(role: "model", parts: parts), modelUsed: model, fromCache: false)
    }

    // MARK: Request body

    private func body(for request: AIRequest, model: String, includeThinking: Bool) -> JSONValue {
        var body: [String: JSONValue] = [
            "contents": .array(request.messages.map { ["role": .string($0.role), "parts": .array($0.parts)] }),
        ]
        if let system = request.system {
            body["systemInstruction"] = ["parts": [["text": .string(system)]]]
        }
        if !request.tools.isEmpty {
            body["tools"] = [[
                "functionDeclarations": .array(request.tools.map {
                    ["name": .string($0.name), "description": .string($0.description), "parameters": $0.parameters]
                }),
            ]]
        }
        var config: [String: JSONValue] = [
            "temperature": .number(request.temperature),
            "maxOutputTokens": .number(Double(request.maxOutputTokens)),
        ]
        if let schema = request.responseSchema {
            config["responseMimeType"] = "application/json"
            config["responseSchema"] = schema
        }
        if includeThinking {
            config["thinkingConfig"] = ["thinkingLevel": .string(request.task.thinkingLevel)]
        }
        body["generationConfig"] = .object(config)
        return .object(body)
    }

    /// Reads `retryDelay` ("17s") from google.rpc.RetryInfo, or the Retry-After header.
    private static func retryDelay(from json: JSONValue, response: URLResponse) -> TimeInterval? {
        for detail in json["error"]?["details"]?.arrayValue ?? [] {
            if let delay = detail["retryDelay"]?.stringValue, let seconds = Double(delay.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) {
                return seconds
            }
        }
        if let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(header) {
            return seconds
        }
        return nil
    }

    private func fail(_ error: AIError) -> AIError {
        lastError = error
        lastErrorAt = .now
        return error
    }
}

extension JSONEncoder {
    /// Stable key order, so equal requests hash equally for the cache.
    static let sorted: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
