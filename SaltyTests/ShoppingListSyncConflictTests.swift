//
//  ShoppingListSyncConflictTests.swift
//  SaltyTests
//
//  The revision-based conflict path: a list edited here and on the server since the last agreement
//  is merged three-way against its snapshot and posted with the server's revision as its base; a
//  409 on that post carries the server's current row, which is merged again and posted once more;
//  a second 409 gives up for this round and leaves the local row dirty for the next.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

@Suite(.serialized)
struct ShoppingListSyncConflictTests {
    private typealias Stub = SyncEngineStubURLProtocol
    private let clock = SyncTestClock.self

    private func item(_ id: String, _ text: String) -> ShoppingListListContents {
        ShoppingListListContents(id: id, text: text)
    }

    /// A checklist stored with its last agreement at revision 1 (`[Milk]`, stamped t1) and a local
    /// edit since (`[Milk, Eggs]`, stamped t2), so it reads as dirty.
    private func seedDirtyList(in library: DatabaseQueue) throws {
        let agreed = ServerShoppingList(
            id: "L", name: "Groceries", isFreeform: false, contentsForList: [item("a", "Milk")],
            lastModifiedDate: clock.t1, revision: 1
        )
        let snapshot = try wireJSON(agreed)
        let local = ShoppingList(
            id: "L", name: "Groceries", isFreeform: false,
            contentsForList: [item("a", "Milk"), item("b", "Eggs")], lastModifiedDate: clock.t2
        )
        try library.write { db in
            try ShoppingListWriter.insert(local, in: db, now: clock.t2)
            try db.execute(
                sql: #"UPDATE "shoppingList" SET "syncedRevision" = 1, "syncedSnapshot" = ? WHERE "id" = 'L'"#,
                arguments: [snapshot]
            )
        }
    }

    private func serverList(revision: Int64, modified: Date, items: [ShoppingListListContents]) -> ServerShoppingList {
        ServerShoppingList(id: "L", name: "Groceries", isFreeform: false, contentsForList: items,
                           lastModifiedDate: modified, revision: revision)
    }

    private func routes(serverRow: ServerShoppingList, saveResponses: [Stub.Response]) throws -> [Stub.Route] {
        [
            .init("GET", "/api/shoppingLists", body: try wireJSON([serverRow])),
            .init("POST", "/api/shoppingLists", responses: saveResponses),
        ] + syncBaseRoutes(lastSync: SyncTestClock.t1)
    }

    @Test func aConflictIsMergedAndASecondConflictMergedAgain() async throws {
        let library = try makeSyncTestLibrary()
        try seedDirtyList(in: library)
        // The server moved to revision 2 (added Bread) since our agreement at 1...
        let atTwo = serverList(revision: 2, modified: clock.t3, items: [item("a", "Milk"), item("c", "Bread")])
        // ...and to revision 3 (added Cheese) by the time our merged post arrives, then accepts at 4.
        let atThree = serverList(revision: 3, modified: clock.t4,
                                 items: [item("a", "Milk"), item("c", "Bread"), item("d", "Cheese")])
        let accepted = serverList(revision: 4, modified: clock.t4,
                                  items: [item("a", "Milk"), item("b", "Eggs"), item("c", "Bread"), item("d", "Cheese")])
        Stub.reset(routes: try routes(serverRow: atTwo, saveResponses: [
            .init(status: 409, body: try wireJSON(atThree)),
            .init(status: 200, body: try wireJSON(accepted)),
        ]))

        let engine = makeSyncEngine(database: library)
        try await engine.sync()

        let posts = Stub.requests("POST", "/api/shoppingLists")
        #expect(posts.count == 2)
        let first = try wireDecode(ServerShoppingList.self, from: try #require(posts.first).body)
        #expect(first.baseRevision == 2)
        #expect(Set(first.contentsForList?.map(\.text) ?? []) == ["Milk", "Eggs", "Bread"], "three-way merge keeps both sides' additions")
        let second = try wireDecode(ServerShoppingList.self, from: try #require(posts.last).body)
        #expect(second.baseRevision == 3, "the retry is based on the row the 409 carried")
        #expect(Set(second.contentsForList?.map(\.text) ?? []) == ["Milk", "Eggs", "Bread", "Cheese"])

        let row = try #require(try shoppingListRow("L", in: library))
        #expect(row["syncedRevision"] == Int64(4))
        #expect(try shoppingListTexts(row) == ["Milk", "Eggs", "Bread", "Cheese"], "the accepted row lands locally, clean")
        #expect(syncWasCompleted())
    }

    @Test func aSecondConflictLeavesTheRowDirtyForNextTime() async throws {
        let library = try makeSyncTestLibrary()
        try seedDirtyList(in: library)
        let atTwo = serverList(revision: 2, modified: clock.t3, items: [item("a", "Milk"), item("c", "Bread")])
        let atThree = serverList(revision: 3, modified: clock.t4, items: [item("a", "Milk"), item("d", "Cheese")])
        let atFour = serverList(revision: 4, modified: clock.t4, items: [item("a", "Milk"), item("e", "Jam")])
        Stub.reset(routes: try routes(serverRow: atTwo, saveResponses: [
            .init(status: 409, body: try wireJSON(atThree)),
            .init(status: 409, body: try wireJSON(atFour)),
        ]))

        try await makeSyncEngine(database: library).sync()

        #expect(Stub.requests("POST", "/api/shoppingLists").count == 2, "one retry, then give up for this round")
        let row = try #require(try shoppingListRow("L", in: library))
        #expect(row["syncedRevision"] == Int64(1), "agreement unchanged")
        #expect(row["lastModifiedDate"] == clock.t2, "the local edit is untouched and still reads as dirty")
        #expect(try shoppingListTexts(row) == ["Milk", "Eggs"])
        #expect(syncWasCompleted(), "a shopping-list conflict never fails the sync")
    }
}
