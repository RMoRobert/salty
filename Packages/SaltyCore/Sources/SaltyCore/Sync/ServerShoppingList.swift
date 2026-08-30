//
//  ServerShoppingList.swift
//  SaltyCore
//
//  The shopping-list wire shape, including the revision fields that drive optimistic concurrency, and
//  the item-by-item lenient decode that keeps one malformed item from aborting an entire sync.
//

import Foundation
import OSLog

/// Wire shape for a shopping list. Mirrors SaltyKMP's `ServerShoppingList` and the server's
/// `shopping_list` table. Everything past `id` is optional so a client predating a field still
/// round-trips — there is no protocol version field to negotiate with.
public struct ServerShoppingList: Codable, Sendable {
    public var id: String
    public var name: String?
    public var isFreeform: Bool?
    public var contentsForList: [ShoppingListListContents]?
    public var contentsForFreeform: String?
    public var lastModifiedDate: Date?
    /// Server-owned optimistic-concurrency counter: present on every GET/save response, bumped on
    /// every accepted write. Nil only from clients or servers that predate revisions.
    public var revision: Int64?
    /// Client → server on upload: the `revision` this edit is based on. The server rejects the write
    /// with 409 (+ its current row) when this no longer matches — that mismatch IS conflict
    /// detection. Legacy clients omit it and get timestamp-guarded last-writer-wins instead.
    /// Encoding stays synthesized (`encodeIfPresent`), so nil keeps both fields off the wire.
    public var baseRevision: Int64?

    /// Written out rather than synthesised because the type is public, and callers outside SaltyCore
    /// (sync, and the tests that stand in for a peer) build sparse payloads directly -- an older peer's
    /// response is exactly a value with most fields absent. Declaring it in the body replaces the
    /// memberwise init with an identical, public one; `init(list:)` and the lenient decoder stay in
    /// their extensions.
    public init(
        id: String,
        name: String? = nil,
        isFreeform: Bool? = nil,
        contentsForList: [ShoppingListListContents]? = nil,
        contentsForFreeform: String? = nil,
        lastModifiedDate: Date? = nil,
        revision: Int64? = nil,
        baseRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.isFreeform = isFreeform
        self.contentsForList = contentsForList
        self.contentsForFreeform = contentsForFreeform
        self.lastModifiedDate = lastModifiedDate
        self.revision = revision
        self.baseRevision = baseRevision
    }
}

/// Decodes a value, yielding nil instead of throwing. Wrapping array *elements* in this is what makes
/// an array decode item-by-item: decoding the element type directly and catching would leave the
/// container's index unadvanced, so the loop couldn't make progress.
private struct FailableDecodable<T: Decodable>: Decodable {
    public let value: T?
    public init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}

public extension ServerShoppingList {
    private enum CodingKeys: String, CodingKey {
        case id, name, isFreeform, contentsForList, contentsForFreeform, lastModifiedDate
        case revision, baseRevision
    }

    /// Hand-written purely so `contentsForList` decodes item-by-item: one malformed item would
    /// otherwise throw out of `fetchListFromServer` and abort the ENTIRE sync — recipes included —
    /// on every attempt, with no way for the user to clear it.
    ///
    /// The leniency deliberately stops at the item level, in two directions:
    ///
    /// - The array of *lists* stays strict (this is per-list decoding). Silently dropping an
    ///   undecodable list would read as "the server no longer has it", and the reconciler infers
    ///   deletions from absence — so it would delete that list locally, or push a deletion for it.
    /// - A `contentsForList` that isn't an array at all still throws. Coercing it to empty would
    ///   quietly blank a list, and the next upload would make that permanent.
    ///
    /// Both of those are cases where failing loudly loses less than recovering quietly.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let listId = try container.decode(String.self, forKey: .id)
        id = listId
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isFreeform = try container.decodeIfPresent(Bool.self, forKey: .isFreeform)
        contentsForFreeform = try container.decodeIfPresent(String.self, forKey: .contentsForFreeform)
        lastModifiedDate = try container.decodeIfPresent(Date.self, forKey: .lastModifiedDate)
        revision = try container.decodeIfPresent(Int64.self, forKey: .revision)
        baseRevision = try container.decodeIfPresent(Int64.self, forKey: .baseRevision)

        if let wrapped = try container.decodeIfPresent([FailableDecodable<ShoppingListListContents>].self, forKey: .contentsForList) {
            let items = wrapped.compactMap(\.value)
            if items.count != wrapped.count {
                let skipped = wrapped.count - items.count
                Logger(subsystem: "Salty", category: "Sync").error(
                    "Shopping list \(listId): skipped \(skipped) unreadable item(s) from the server payload"
                )
            }
            contentsForList = items
        } else {
            contentsForList = nil
        }
    }
}

// Conversions stay in an extension for readability; the memberwise init is now written out in the
// type body (see the note there), so it no longer depends on this separation to survive.
public extension ServerShoppingList {
    public init(list: ShoppingList) {
        self.id = list.id
        self.name = list.name
        self.isFreeform = list.isFreeform
        self.contentsForList = list.contentsForList
        self.contentsForFreeform = list.contentsForFreeform
        self.lastModifiedDate = list.lastModifiedDate
    }

    /// The local row this payload represents. `lastModifiedDate` falls back to "now" rather than
    /// `distantPast`: a nil would compare as older than the sync watermark forever, so the list would
    /// be re-deleted on the next sync instead of kept (same hazard `coalesceNullShoppingListColumns`
    /// guards against locally).
    public var asShoppingList: ShoppingList {
        ShoppingList(
            id: id,
            name: name ?? "",
            isFreeform: isFreeform ?? false,
            contentsForFreeform: contentsForFreeform,
            contentsForList: contentsForList ?? [],
            lastModifiedDate: lastModifiedDate ?? Date()
        )
    }
}
