//
//  ShoppingListWriterTests.swift
//  SaltyTests
//
//  Two load-bearing `ShoppingListWriter` behaviours: the stamp is what sync compares (a missed bump is
//  an edit that never leaves the device), and the mutation runs against the row as stored, so a
//  debounced save in one window can't write a stale copy over a newer edit from another.
//
//  Rows are seeded and read back with raw SQL (or through the writer itself), never with a
//  StructuredQueries builder: those crash when instantiated from the test bundle. See the note at
//  the top of RecipeWriterTests.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct ShoppingListWriterTests {

    private func library() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        // `shoppingList.lastModifiedDate` comes from shared migration SHARED-V0002, not the base schema.
        try runSaltySharedMigrations(queue)
        return queue
    }

    /// A list stored with a known stamp, forced by hand after the insert — NULL is what a list
    /// predating SHARED-V0002 looks like.
    private func storedList(
        in queue: DatabaseQueue, at stamp: Date?, isFreeform: Bool = false,
        items: [ShoppingListListContents] = []
    ) throws -> ShoppingList {
        var list = ShoppingList(
            id: SaltyId.new(), name: "Groceries", isFreeform: isFreeform,
            contentsForFreeform: isFreeform ? "" : nil, contentsForList: items
        )
        try queue.write { db in
            try ShoppingListWriter.insert(list, in: db)
            try db.execute(
                sql: #"UPDATE "shoppingList" SET "lastModifiedDate" = ? WHERE "id" = ?"#,
                arguments: [stamp, list.id]
            )
        }
        list.lastModifiedDate = stamp
        return list
    }

    /// The stored row for `id`, read with raw SQL. See the note at the top of the file.
    private func row(_ id: String, from queue: DatabaseQueue) throws -> Row {
        let found = try queue.read { db in
            try Row.fetchOne(db, sql: #"SELECT * FROM "shoppingList" WHERE "id" = ?"#, arguments: [id])
        }
        return try #require(found)
    }

    private func modified(_ id: String, in queue: DatabaseQueue) throws -> Date? {
        try row(id, from: queue)["lastModifiedDate"]
    }

    private let past = Date(timeIntervalSince1970: 1_000_000)
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func item(_ text: String) -> ShoppingListListContents {
        ShoppingListListContents(id: SaltyId.new(), text: text)
    }

    // MARK: - Stamping

    @Test("an edit stamps lastModifiedDate")
    func editStamps() throws {
        let queue = try library()
        let list = try storedList(in: queue, at: past)

        try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: now) { $0.name = "Hardware" }
        }

        #expect(try row(list.id, from: queue)["name"] == "Hardware")
        #expect(try modified(list.id, in: queue) == now)
    }

    /// A debounced editor fires on a timer, not only on a keystroke, so it re-saves identical
    /// contents routinely. Stamping those would hand sync a stream of no-op edits.
    @Test("a write that changes nothing leaves the stamp alone")
    func noOpWriteDoesNotStamp() throws {
        let queue = try library()
        let items = [item("milk"), item("bread")]
        let list = try storedList(in: queue, at: past, items: items)

        try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: now) { $0.contentsForList = items }
        }

        #expect(try modified(list.id, in: queue) == past)
    }

    @Test("a stamp set inside the closure doesn't defeat the did-anything-change test")
    func callerStampIsNotMistakenForAChange() throws {
        let queue = try library()
        let list = try storedList(in: queue, at: past)

        try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: now) {
                $0.lastModifiedDate = Date(timeIntervalSince1970: 5_000_000)
            }
        }

        #expect(try modified(list.id, in: queue) == past)
    }

    @Test("a list that has never been stamped gets one on its first real edit")
    func nullStampIsFilledIn() throws {
        let queue = try library()
        let list = try storedList(in: queue, at: nil)

        try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: now) { $0.name = "Renamed" }
        }

        #expect(try modified(list.id, in: queue) == now)
    }

    @Test("stamps only ever move forwards")
    func stampNeverGoesBackwards() throws {
        let queue = try library()
        let future = Date(timeIntervalSince1970: 9_000_000)
        let list = try storedList(in: queue, at: future)

        try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: now) { $0.name = "Renamed" }
        }

        #expect(try modified(list.id, in: queue) == future)
    }

    // MARK: - Reading the stored row

    /// `AddToShoppingListViewModel` appends to a list's contents. It has to append to what's stored,
    /// not to whatever it loaded when the sheet opened.
    @Test("the closure sees the stored contents, not a stale copy")
    func closureSeesStoredRow() throws {
        let queue = try library()
        let list = try storedList(in: queue, at: past, items: [item("milk")])

        // Another window adds an item after `list` was captured.
        try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: past) {
                $0.contentsForList.append(self.item("eggs"))
            }
        }

        try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: now) {
                $0.contentsForList.append(self.item("flour"))
            }
        }

        let contents = try queue.read { db -> [String] in
            let row = try Row.fetchOne(
                db, sql: #"SELECT "contentsForList" FROM "shoppingList" WHERE "id" = ?"#,
                arguments: [list.id]
            )
            let json: String = row?["contentsForList"] ?? "[]"
            let items = try JSONDecoder().decode([ShoppingListListContents].self, from: Data(json.utf8))
            return items.map(\.text)
        }
        #expect(contents == ["milk", "eggs", "flour"])
    }

    @Test("editing a list that no longer exists is dropped rather than recreating it")
    func missingListIsDropped() throws {
        let queue = try library()
        let list = try storedList(in: queue, at: past)
        try queue.write { db in
            try db.execute(sql: #"DELETE FROM "shoppingList" WHERE "id" = ?"#, arguments: [list.id])
        }

        let result = try queue.write { db in
            try ShoppingListWriter.update(id: list.id, in: db, now: now) { $0.name = "Ghost" }
        }

        let remaining = try queue.read { db in
            try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "shoppingList""#) ?? -1
        }
        #expect(result == nil)
        #expect(remaining == 0)
    }

    // MARK: - Insert

    @Test("a new list is stamped on insert so sync has something to compare")
    func insertStamps() throws {
        let queue = try library()
        let list = ShoppingList(id: SaltyId.new(), name: "New List", isFreeform: false)

        try queue.write { db in try ShoppingListWriter.insert(list, in: db, now: now) }

        #expect(try modified(list.id, in: queue) == now)
    }
}
