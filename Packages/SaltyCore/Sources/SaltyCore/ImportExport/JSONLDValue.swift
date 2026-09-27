//
//  JSONLDValue.swift
//  SaltyCore
//
//  Purpose: A JSON-LD document read off a web page, as plain values the schema.org importer can walk
//  without casting `Any`. Read as strict JSON with bounded nesting, because it is untrusted content.
//

import Foundation

/// One value from a JSON-LD document.
enum JSONLDValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONLDValue])
    case object([String: JSONLDValue])
    case null

    /// Deeper than this and the whole block is refused rather than walked (contract WEB-008). Real recipe
    /// markup is a handful of levels deep, and the walk that follows recurses as deep as the document.
    static let maxDepth = 64

    /// The document in `data`, or nil when it isn't strict JSON (contract WEB-003); the caller skips
    /// such blocks (WEB-L01). Foundation's parsers accept trailing commas, so those are refused first.
    static func parse(_ data: Data) -> JSONLDValue? {
        guard !hasTrailingComma(data) else { return nil }
        return try? JSONDecoder().decode(JSONLDValue.self, from: data)
    }

    /// A comma followed by nothing but whitespace before a `]` or `}`, outside a string.
    private static func hasTrailingComma(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var inString = false
        var escaped = false
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: ",") {
                var next = index + 1
                while next < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[next]) {
                    next += 1
                }
                if next < bytes.count, bytes[next] == UInt8(ascii: "]") || bytes[next] == UInt8(ascii: "}") {
                    return true
                }
            }
            index += 1
        }
        return false
    }

    init(from decoder: any Decoder) throws {
        guard decoder.codingPath.count <= Self.maxDepth else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "JSON-LD nested deeper than \(Self.maxDepth) levels"))
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let fields = try? container.decode([String: JSONLDValue].self) {
            self = .object(fields)
        } else if let items = try? container.decode([JSONLDValue].self) {
            self = .array(items)
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }

    /// The fields when this is an object.
    var fields: [String: JSONLDValue]? {
        guard case .object(let fields) = self else { return nil }
        return fields
    }

    /// The text of a string, or of a number in its shortest decimal form ("4", not "4.0"); nil for
    /// anything else. A bare number where text is expected is accepted (contract WEB-L03).
    var primitiveText: String? {
        switch self {
        case .string(let text):
            return text
        case .number(let number):
            return Self.decimalText(number)
        default:
            return nil
        }
    }

    /// `number` as a person would write it: no fractional part when it is whole.
    static func decimalText(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 {
            return String(Int64(number))
        }
        return String(number)
    }
}
