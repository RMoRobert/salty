//
//  ShoppingListDetailViewModelTests.swift
//  SaltyTests
//
//  The checklist editor's persistence: edits are written on a debounce, `flush()` writes at once, an
//  outside write to the row replaces the items and drops a save still pending, the editor's own
//  writes coming back through the observation are left alone, and a save built on a row that moved
//  on in between is refused rather than landed over the newer contents.
//
//  The row observation itself (`@FetchOne`) is SQLiteData's; what the view hands it is driven here
//  by calling `storedRowDidChange(to:)` with rows read back from the database, so nothing waits on
//  observation delivery. Serialized like the other database suites: the view model resolves its
//  database through swift-dependencies.
//

import Testing
import Foundation
import GRDB
import SQLiteData
@testable import Salty
import SaltyCore

@MainActor
@Suite(.serialized)
struct ShoppingListDetailViewModelTests {

    private func makeTestDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
        } operation: {
            try appDatabase()
        }
    }

    nonisolated private func item(_ text: String, completed: Bool = false) -> ShoppingListListContents {
        ShoppingListListContents(id: SaltyId.new(), isCompleted: completed, text: text)
    }

    /// A checklist stored with `items`, returned as inserted.
    private func storedList(
        in database: any DatabaseWriter, items: [ShoppingListListContents]
    ) async throws -> ShoppingList {
        let list = ShoppingList(id: SaltyId.new(), name: "Groceries", isFreeform: false, contentsForList: items)
        return try await database.write { db in try ShoppingListWriter.insert(list, in: db) }
    }

    /// The stored row, read with raw SQL: a StructuredQueries builder instantiated from the test
    /// bundle crashes at runtime (see the note at the top of RecipeWriterTests). The view model's own
    /// queries run inside the app module, where they resolve fine.
    private func storedRow(_ id: String, in database: any DatabaseWriter) async throws -> ShoppingList? {
        try await database.read { db in
            guard let row = try Row.fetchOne(db, sql: #"SELECT * FROM "shoppingList" WHERE "id" = ?"#, arguments: [id]) else {
                return nil
            }
            let json: String = row["contentsForList"] ?? "[]"
            return ShoppingList(
                id: row["id"], name: row["name"], isFreeform: row["isFreeform"],
                contentsForFreeform: row["contentsForFreeform"],
                contentsForList: try JSONDecoder().decode([ShoppingListListContents].self, from: Data(json.utf8)),
                lastModifiedDate: row["lastModifiedDate"],
                syncedRevision: row["syncedRevision"], syncedSnapshot: row["syncedSnapshot"]
            )
        }
    }

    private func deleteStoredRow(_ id: String, in database: any DatabaseWriter) async throws {
        try await database.write { db in
            try db.execute(sql: #"DELETE FROM "shoppingList" WHERE "id" = ?"#, arguments: [id])
        }
    }

    private func storedTexts(_ id: String, in database: any DatabaseWriter) async throws -> [String] {
        try await storedRow(id, in: database)?.contentsForList.map(\.text) ?? []
    }

    /// Hands the test body a loaded view model over `database`, with the whole body inside the
    /// dependency scope so the model's later writes resolve the same database.
    private func withLoadedViewModel(
        items: [ShoppingListListContents],
        debounce: Duration = .seconds(60),
        _ body: (ShoppingListDetailViewModel, ShoppingList, any DatabaseWriter) async throws -> Void
    ) async throws {
        let database = try makeTestDatabase()
        let list = try await storedList(in: database, items: items)
        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let viewModel = ShoppingListDetailViewModel(listId: list.id, debounce: debounce)
            await viewModel.load()
            try await body(viewModel, list, database)
        }
    }

    // MARK: - Loading and saving

    @Test func loadReadsTheStoredItems() async throws {
        try await withLoadedViewModel(items: [item("milk"), item("eggs", completed: true)]) { viewModel, _, _ in
            #expect(viewModel.isLoaded)
            #expect(viewModel.items.map(\.text) == ["milk", "eggs"])
            #expect(viewModel.completedCount == 1)
        }
    }

    @Test func editsAreWrittenAfterTheDebounce() async throws {
        try await withLoadedViewModel(items: [item("milk")], debounce: .milliseconds(1)) { viewModel, list, database in
            viewModel.addItem()
            let added = viewModel.items[1].id
            viewModel.updateText(id: added, text: "eggs")
            viewModel.toggleCompleted(id: list.contentsForList[0].id)

            await viewModel.settle()

            let stored = try #require(try await storedRow(list.id, in: database))
            #expect(stored.contentsForList.map(\.text) == ["milk", "eggs"])
            #expect(stored.contentsForList[0].isCompleted == true)
            #expect(stored.lastModifiedDate != list.lastModifiedDate, "the edit was stamped")
        }
    }

    @Test func flushWritesAPendingSaveAtOnce() async throws {
        try await withLoadedViewModel(items: [item("milk")]) { viewModel, list, database in
            viewModel.deleteItem(id: list.contentsForList[0].id)
            let beforeFlush = try await storedTexts(list.id, in: database)
            #expect(beforeFlush == ["milk"], "still in the debounce")

            viewModel.flush()
            await viewModel.settle()

            let afterFlush = try await storedTexts(list.id, in: database)
            #expect(afterFlush.isEmpty)
        }
    }

    @Test func flushWithNothingPendingWritesNothing() async throws {
        try await withLoadedViewModel(items: [item("milk")]) { viewModel, list, database in
            viewModel.flush()
            await viewModel.settle()
            let stored = try #require(try await storedRow(list.id, in: database))
            #expect(stored.lastModifiedDate == list.lastModifiedDate)
        }
    }

    // MARK: - Outside writes

    @Test func anOutsideWriteReplacesTheItemsAndDropsThePendingSave() async throws {
        try await withLoadedViewModel(items: [item("milk")]) { viewModel, list, database in
            // Typing in this editor, not yet written...
            viewModel.addItem()
            viewModel.updateText(id: viewModel.items[1].id, text: "butter")

            // ...when the "Add to Shopping List" sheet appends to the stored row.
            let eggs = item("eggs")
            _ = try await database.write { db in
                try ShoppingListWriter.update(id: list.id, in: db) { $0.contentsForList.append(eggs) }
            }
            let outside = try await storedRow(list.id, in: database)
            viewModel.storedRowDidChange(to: outside)

            #expect(viewModel.items.map(\.text) == ["milk", "eggs"])

            // The pending save was dropped, not flushed: the row keeps the outside contents.
            await viewModel.settle()
            let stored = try await storedTexts(list.id, in: database)
            #expect(stored == ["milk", "eggs"])
        }
    }

    @Test func aDeletedRowEmptiesTheChecklist() async throws {
        try await withLoadedViewModel(items: [item("milk")]) { viewModel, list, database in
            try await deleteStoredRow(list.id, in: database)
            viewModel.storedRowDidChange(to: nil)
            #expect(viewModel.items.isEmpty)
        }
    }

    @Test func theEditorsOwnWriteComingBackIsLeftAlone() async throws {
        try await withLoadedViewModel(items: [item("milk")]) { viewModel, list, database in
            viewModel.addItem()
            viewModel.updateText(id: viewModel.items[1].id, text: "eggs")
            viewModel.flush()
            await viewModel.settle()

            // Keystrokes since the write, still pending.
            viewModel.addItem()
            viewModel.updateText(id: viewModel.items[2].id, text: "flour")

            // The observation delivers the editor's own write.
            let own = try await storedRow(list.id, in: database)
            viewModel.storedRowDidChange(to: own)

            #expect(viewModel.items.map(\.text) == ["milk", "eggs", "flour"], "nothing was reloaded")
            viewModel.flush()
            await viewModel.settle()
            let stored = try await storedTexts(list.id, in: database)
            #expect(stored == ["milk", "eggs", "flour"],
                    "the pending save survived and its stamp expectation was current")
        }
    }

    @Test func aRepeatDeliveryOfTheSameRowIsIgnored() async throws {
        try await withLoadedViewModel(items: [item("milk")]) { viewModel, list, database in
            viewModel.addItem()
            viewModel.updateText(id: viewModel.items[1].id, text: "eggs")

            // The row as loaded, delivered again (SQLiteData's initial fetch, say).
            let same = try await storedRow(list.id, in: database)
            viewModel.storedRowDidChange(to: same)

            #expect(viewModel.items.map(\.text) == ["milk", "eggs"])
        }
    }

    /// The window the guard exists for: the outside write has committed but its observation hasn't
    /// been delivered yet when the debounce fires.
    @Test func aSaveBuiltOnARowThatMovedOnIsRefused() async throws {
        try await withLoadedViewModel(items: [item("milk")]) { viewModel, list, database in
            viewModel.addItem()
            viewModel.updateText(id: viewModel.items[1].id, text: "butter")

            let eggs = item("eggs")
            _ = try await database.write { db in
                try ShoppingListWriter.update(id: list.id, in: db) { $0.contentsForList.append(eggs) }
            }

            viewModel.flush()
            await viewModel.settle()

            let stored = try await storedTexts(list.id, in: database)
            #expect(stored == ["milk", "eggs"], "the stale save did not land")

            // The observation catches the editor up.
            let outside = try await storedRow(list.id, in: database)
            viewModel.storedRowDidChange(to: outside)
            #expect(viewModel.items.map(\.text) == ["milk", "eggs"])
        }
    }

    @Test func aLegacyUnstampedRowSavesOnFirstEdit() async throws {
        let database = try makeTestDatabase()
        let list = try await storedList(in: database, items: [item("milk")])
        try await database.write { db in
            try db.execute(sql: #"UPDATE "shoppingList" SET "lastModifiedDate" = NULL WHERE "id" = ?"#, arguments: [list.id])
        }
        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let viewModel = ShoppingListDetailViewModel(listId: list.id)
            await viewModel.load()
            viewModel.addItem()
            viewModel.updateText(id: viewModel.items[1].id, text: "eggs")
            viewModel.flush()
            await viewModel.settle()

            let stored = try #require(try await storedRow(list.id, in: database))
            #expect(stored.contentsForList.map(\.text) == ["milk", "eggs"])
            #expect(stored.lastModifiedDate != nil)
        }
    }

    // MARK: - Conversion

    @Test func convertingToFreeformWritesTheTextAndFlipsTheKind() async throws {
        try await withLoadedViewModel(items: [item("milk"), item("eggs", completed: true)]) { viewModel, list, database in
            viewModel.convertToFreeform()
            await viewModel.settle()

            let stored = try #require(try await storedRow(list.id, in: database))
            #expect(stored.isFreeform)
            #expect(stored.contentsForFreeform == ShoppingListFreeformConverter.text(from: list.contentsForList))
        }
    }
}
