import Foundation

/// Any JSON value, losslessly Codable.
///
/// Gemini's responses can carry fields we don't model (e.g. Gemini 3's thought signatures on
/// function-call parts), and those must be sent back unchanged in the next turn. Keeping the model's
/// turns as raw JSON guarantees nothing is dropped.
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    // MARK: Convenience

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    var doubleValue: Double? { if case .number(let v) = self { v } else { nil } }
    var arrayValue: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    var objectValue: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }

    /// Encodes any Encodable value into JSONValue (e.g. tool results).
    static func from<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }

    /// Decodes this JSON into a Swift type (e.g. tool arguments, structured results).
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// Builders for Gemini's schema format (OpenAPI subset with uppercase type names).
enum Schema {
    static func object(_ properties: [String: JSONValue], required: [String] = [], description: String? = nil) -> JSONValue {
        var dict: [String: JSONValue] = ["type": "OBJECT", "properties": .object(properties)]
        if !required.isEmpty { dict["required"] = .array(required.map { .string($0) }) }
        if let description { dict["description"] = .string(description) }
        return .object(dict)
    }
    static func array(_ items: JSONValue, description: String? = nil) -> JSONValue {
        var dict: [String: JSONValue] = ["type": "ARRAY", "items": items]
        if let description { dict["description"] = .string(description) }
        return .object(dict)
    }
    static func string(_ description: String? = nil, enumValues: [String]? = nil) -> JSONValue {
        var dict: [String: JSONValue] = ["type": "STRING"]
        if let description { dict["description"] = .string(description) }
        if let enumValues { dict["enum"] = .array(enumValues.map { .string($0) }) }
        return .object(dict)
    }
    static func number(_ description: String? = nil) -> JSONValue {
        description.map { ["type": "NUMBER", "description": .string($0)] } ?? ["type": "NUMBER"]
    }
    static func integer(_ description: String? = nil) -> JSONValue {
        description.map { ["type": "INTEGER", "description": .string($0)] } ?? ["type": "INTEGER"]
    }
    static func boolean(_ description: String? = nil) -> JSONValue {
        description.map { ["type": "BOOLEAN", "description": .string($0)] } ?? ["type": "BOOLEAN"]
    }
}
