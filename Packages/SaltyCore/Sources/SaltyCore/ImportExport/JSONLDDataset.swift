//
//  JSONLDDataset.swift
//  SaltyCore
//
//  Purpose: All JSON-LD blocks on a page read as one dataset (JSON-LD 1.1 §7): node references resolve
//  across blocks, and schema.org properties are found under compacted or expanded names.
//  Rules: salty-contract SPEC.md §8.1 (WEB-002 to WEB-007).
//

import Foundation

struct JSONLDDataset {

    /// Each block's document, in page order.
    let blocks: [JSONLDValue]

    /// Every node that carries an `@id` and something besides it, by that id. The first definition wins.
    private let nodesByID: [String: JSONLDValue]

    init(blocks: [JSONLDValue]) {
        self.blocks = blocks
        var index: [String: JSONLDValue] = [:]
        for block in blocks {
            Self.indexNodes(in: block, into: &index)
        }
        nodesByID = index
    }

    // MARK: - Properties

    /// The property's values, as a flat list: an array is its elements, node references (WEB-006) are
    /// the nodes they name, value objects are their values, `@list` and `@set` are their arrays (WEB-007).
    /// A reference to nothing, and JSON null, are no value at all.
    func values(_ node: JSONLDValue, _ property: String) -> [JSONLDValue] {
        guard let raw = rawValue(node, property) else { return [] }
        return expand(raw)
    }

    /// Whether the node declares `property` at all, whatever its value.
    func has(_ node: JSONLDValue, _ property: String) -> Bool {
        rawValue(node, property) != nil
    }

    /// Whether `@type` names `type`, in any of the forms WEB-004 accepts.
    func hasType(_ node: JSONLDValue, _ type: String) -> Bool {
        guard let declared = node.fields?["@type"] else { return false }
        let names: [JSONLDValue]
        if case .array(let items) = declared { names = items } else { names = [declared] }
        return names.contains { name in
            guard case .string(let text) = name else { return false }
            return Self.localName(text) == type
        }
    }

    // MARK: - Finding recipes

    /// The page's recipes in document order, deduplicated by `@id` (WEB-002, WEB-005). Only top-level
    /// nodes, `@graph` members and `mainEntity` count: a recipe nested in a review or `isBasedOn` is a stub.
    func recipes() -> [JSONLDValue] {
        var found: [JSONLDValue] = []
        var seenIDs: Set<String> = []

        func add(_ node: JSONLDValue) {
            guard hasType(node, "Recipe") else { return }
            if case .string(let id)? = node.fields?["@id"] {
                guard seenIDs.insert(id).inserted else { return }
            }
            found.append(node)
        }

        func visit(_ value: JSONLDValue) {
            switch value {
            case .array(let items):
                items.forEach(visit)
            case .object(let fields):
                add(value)
                values(value, "mainEntity").forEach(add)
                if let graph = fields["@graph"] {
                    visit(graph)
                }
            default:
                break
            }
        }

        blocks.forEach(visit)
        return found
    }

    // MARK: - Private

    /// The property's raw value under the first of its WEB-004 names the node uses.
    private func rawValue(_ node: JSONLDValue, _ property: String) -> JSONLDValue? {
        guard let fields = node.fields else { return nil }
        for key in Self.names(for: property) {
            if let value = fields[key] {
                return value
            }
        }
        return nil
    }

    private func expand(_ value: JSONLDValue) -> [JSONLDValue] {
        switch resolve(value) {
        case .array(let items):
            return items.flatMap(expand)
        case .null:
            return []
        case let resolved:
            return [resolved]
        }
    }

    /// A node reference as its node, a value object as its value, `@list`/`@set` as its array.
    private func resolve(_ value: JSONLDValue) -> JSONLDValue {
        guard case .object(let fields) = value else { return value }
        if fields.count == 1, case .string(let id)? = fields["@id"] {
            return nodesByID[id] ?? .null
        }
        if let inner = fields["@value"] {
            return inner
        }
        if let list = fields["@list"] ?? fields["@set"] {
            return list
        }
        return value
    }

    /// Recursion is bounded by `JSONLDValue.maxDepth`, which every block was read under.
    private static func indexNodes(in value: JSONLDValue, into index: inout [String: JSONLDValue]) {
        switch value {
        case .array(let items):
            for item in items {
                indexNodes(in: item, into: &index)
            }
        case .object(let fields):
            if fields.count > 1, case .string(let id)? = fields["@id"], index[id] == nil {
                index[id] = value
            }
            for item in fields.values {
                indexNodes(in: item, into: &index)
            }
        default:
            break
        }
    }

    private static let schemaPrefixes = ["schema:", "http://schema.org/", "https://schema.org/"]

    /// The names a schema.org property may appear under in a compacted or expanded document.
    private static func names(for property: String) -> [String] {
        [property] + schemaPrefixes.map { $0 + property }
    }

    private static func localName(_ term: String) -> String {
        for prefix in schemaPrefixes where term.hasPrefix(prefix) {
            return String(term.dropFirst(prefix.count))
        }
        return term
    }
}
