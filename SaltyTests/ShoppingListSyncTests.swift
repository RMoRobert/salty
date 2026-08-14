//
//  ShoppingListSyncTests.swift
//  SaltyTests
//
//  The model<->wire conversion behind shopping list sync. The reconciliation itself is revision-based
//  (see salty_kmp/SHOPPING_LIST_REVISIONS_PLAN.md), with the data-loss-critical merge covered by
//  ShoppingListMergeTests — what's pinned here is the payload mapping, including the revision fields
//  the algorithm rides on.
//

import Testing
import Foundation
@testable import Salty

struct ShoppingListSyncTests {

    @Test func roundTripsEveryFieldIncludingItemFlags() {
        let local = ShoppingList(
            id: "sl1", name: "Groceries", isFreeform: false,
            contentsForFreeform: nil,
            contentsForList: [
                ShoppingListListContents(id: "h1", isHeading: true, text: "Produce"),
                ShoppingListListContents(id: "i1", isCompleted: true, isImportant: true, isHeading: false, text: "Apples"),
            ],
            lastModifiedDate: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let restored = ServerShoppingList(list: local).asShoppingList

        #expect(restored.id == "sl1")
        #expect(restored.name == "Groceries")
        #expect(restored.isFreeform == false)
        #expect(restored.lastModifiedDate == local.lastModifiedDate)
        #expect(restored.contentsForList.count == 2)
        // isHeading is the newest field on the item model and the one most likely to be dropped by a
        // stale peer — assert it survives explicitly.
        #expect(restored.contentsForList[0].isHeading == true)
        #expect(restored.contentsForList[0].text == "Produce")
        #expect(restored.contentsForList[1].isCompleted == true)
        #expect(restored.contentsForList[1].isImportant == true)
    }

    @Test func roundTripsAFreeformList() {
        let local = ShoppingList(
            id: "sl2", name: "Notes", isFreeform: true,
            contentsForFreeform: "# Store\n* Milk",
            lastModifiedDate: Date(timeIntervalSince1970: 1_780_000_001)
        )
        let restored = ServerShoppingList(list: local).asShoppingList
        #expect(restored.isFreeform == true)
        #expect(restored.contentsForFreeform == "# Store\n* Milk")
        #expect(restored.contentsForList.isEmpty)
    }

    /// A payload with no timestamp must NOT decode to `distantPast`. The reconciler compares against
    /// the sync watermark, and `distantPast` is always `<=` it — so the list would be deleted on the
    /// next sync instead of kept. Falling back to "now" biases to the non-destructive direction, the
    /// same reasoning as `coalesceNullShoppingListColumns`.
    @Test func missingTimestampDecodesToNowNotDistantPast() {
        let payload = ServerShoppingList(list: ShoppingList(id: "sl3", name: "X", isFreeform: false))
        var undated = payload
        undated.lastModifiedDate = nil

        let restored = undated.asShoppingList

        #expect(restored.lastModifiedDate != nil)
        #expect(restored.lastModifiedDate != Date.distantPast)
        #expect(abs(restored.lastModifiedDate!.timeIntervalSinceNow) < 5)
    }

    // MARK: - Malformed payloads
    //
    // Nothing validates what the server stores, so a client has to survive a bad payload. The rule is
    // narrow on purpose: recover at the ITEM level, fail loudly above it.

    private func decode(_ json: String) throws -> ServerShoppingList {
        let decoder = JSONDecoder()
        return try decoder.decode(ServerShoppingList.self, from: Data(json.utf8))
    }

    @Test func skipsUnreadableItemsAndKeepsTheRest() throws {
        // Middle item is missing the non-optional `text`. Without item-level leniency this would throw
        // out of the fetch and abort the whole sync — recipes included — on every attempt.
        let list = try decode("""
        {"id":"sl1","name":"G","isFreeform":false,"contentsForList":[
            {"id":"a","text":"Milk"},
            {"id":"b"},
            {"id":"c","text":"Eggs"}
        ]}
        """)
        #expect(list.contentsForList?.map(\.text) == ["Milk", "Eggs"])
    }

    @Test func skipsItemsOfTheWrongShapeEntirely() throws {
        let list = try decode("""
        {"id":"sl1","contentsForList":[{"id":"a","text":"Milk"}, "not an object", 42]}
        """)
        #expect(list.contentsForList?.map(\.text) == ["Milk"])
    }

    @Test func stillDecodesWhenEveryItemIsGood() throws {
        let list = try decode("""
        {"id":"sl1","contentsForList":[{"id":"a","text":"Milk","isHeading":true}]}
        """)
        #expect(list.contentsForList?.count == 1)
        #expect(list.contentsForList?.first?.isHeading == true)
    }

    /// Leniency must NOT extend to the list itself. Deletions are inferred from absence, so a list that
    /// quietly decoded to "no contents" — or worse, got dropped from the array — would read as a
    /// server-side deletion and be destroyed. Failing loudly loses less.
    @Test func aContentsForListThatIsNotAnArrayStillThrows() {
        #expect(throws: (any Error).self) {
            try decode(#"{"id":"sl1","contentsForList":"totally wrong"}"#)
        }
    }

    @Test func aMissingListIdStillThrows() {
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"no id here"}"#)
        }
    }

    /// The server marks every field past `id` optional so older peers round-trip; the decoded row must
    /// still satisfy the non-optional Swift model rather than producing nulls it can't represent.
    @Test func absentOptionalFieldsDecodeToUsableDefaults() {
        let sparse = ServerShoppingList(
            id: "sl4", name: nil, isFreeform: nil,
            contentsForList: nil, contentsForFreeform: nil, lastModifiedDate: nil
        )
        let restored = sparse.asShoppingList
        #expect(restored.name == "")
        #expect(restored.isFreeform == false)
        #expect(restored.contentsForList.isEmpty)
    }

    // MARK: - Revision fields (SHARED-V0003 / revision-based sync)

    @Test func decodesRevisionAndBaseRevisionWhenPresent() throws {
        let list = try decode(#"{"id":"sl1","name":"G","revision":7,"baseRevision":6}"#)
        #expect(list.revision == 7)
        #expect(list.baseRevision == 6)
    }

    /// An old server omits the fields entirely — the row must decode with nils (landing on the
    /// legacy-seeding path), never throw.
    @Test func payloadWithoutRevisionFieldsDecodesToNil() throws {
        let list = try decode(#"{"id":"sl1","name":"G"}"#)
        #expect(list.revision == nil)
        #expect(list.baseRevision == nil)
    }

    /// Nil revision fields must stay OFF the wire (synthesized `encodeIfPresent`): an explicit null
    /// is exactly the kind of unknown-shape value an older server could choke on.
    @Test func encodingOmitsNilRevisionFieldsButCarriesASetBaseRevision() throws {
        var payload = ServerShoppingList(list: ShoppingList(id: "sl5", name: "X", isFreeform: false))
        let bare = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        #expect(bare?.keys.contains("revision") == false)
        #expect(bare?.keys.contains("baseRevision") == false)

        payload.baseRevision = 3
        let based = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        #expect(based?["baseRevision"] as? Int == 3)
        #expect(based?.keys.contains("revision") == false)
    }
}
