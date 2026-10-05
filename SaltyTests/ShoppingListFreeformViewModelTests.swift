//
//  ShoppingListFreeformViewModelTests.swift
//  SaltyTests
//
//  The freeform editor's persistence, the text-blob twin of ShoppingListDetailViewModelTests: the
//  debounce, `flush()`, an outside write replacing the text and dropping the pending save, the
//  editor's own write coming back untouched (keystrokes typed since included), the refused stale
//  save, and the `storedText` rule that keeps a reload from being saved straight back as an edit.
//

import Testing
import Foundation
import GRDB
import SQLiteData
@testable import Salty
import SaltyCore

@MainActor
@Suite(.serialized)
struct ShoppingListFreeformViewModelTests {

    private func makeTestDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
        } operation: {
            try appDatabase()
        }
    }

    private func storedList(in database: any DatabaseWriter, text: String) async throws -> ShoppingList {
        let list = ShoppingList(id: SaltyId.new(), name: "Notes", isFreeform: true, contentsForFreeform: text)
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

    private func storedText(_ id: String, in database: any DatabaseWriter) async throws -> String? {
        try await storedRow(id, in: database)?.contentsForFreeform
    }

    private func withLoadedViewModel(
        text: String,
        debounce: Duration = .seconds(60),
        _ body: (ShoppingListFreeformViewModel, ShoppingList, any DatabaseWriter) async throws -> Void
    ) async throws {
        let database = try makeTestDatabase()
        let list = try await storedList(in: database, text: text)
        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let viewModel = ShoppingListFreeformViewModel(listId: list.id, debounce: debounce)
            await viewModel.load()
            try await body(viewModel, list, database)
        }
    }

    /// What the view does on every change to `text`.
    private func type(_ text: String, into viewModel: ShoppingListFreeformViewModel) {
        viewModel.text = text
        viewModel.scheduleSave()
    }

    // MARK: - Loading and saving

    @Test func loadReadsTheStoredText() async throws {
        try await withLoadedViewModel(text: "# Store\n* Milk") { viewModel, _, _ in
            #expect(viewModel.isLoaded)
            #expect(viewModel.text == "# Store\n* Milk")
        }
    }

    @Test func typingIsWrittenAfterTheDebounce() async throws {
        try await withLoadedViewModel(text: "* Milk", debounce: .milliseconds(1)) { viewModel, list, database in
            type("* Milk\n* Eggs", into: viewModel)
            await viewModel.settle()

            let stored = try #require(try await storedRow(list.id, in: database))
            #expect(stored.contentsForFreeform == "* Milk\n* Eggs")
            #expect(stored.lastModifiedDate != list.lastModifiedDate)
        }
    }

    @Test func flushWritesAPendingSaveAtOnce() async throws {
        try await withLoadedViewModel(text: "* Milk") { viewModel, list, database in
            type("* Milk\n* Eggs", into: viewModel)
            let beforeFlush = try await storedText(list.id, in: database)
            #expect(beforeFlush == "* Milk", "still in the debounce")

            viewModel.flush()
            await viewModel.settle()

            let afterFlush = try await storedText(list.id, in: database)
            #expect(afterFlush == "* Milk\n* Eggs")
        }
    }

    @Test func textTypedBackToWhatIsStoredSchedulesNoSave() async throws {
        try await withLoadedViewModel(text: "* Milk") { viewModel, list, database in
            type("* Milk\n", into: viewModel)
            type("* Milk", into: viewModel)
            viewModel.flush()
            await viewModel.settle()

            let stored = try #require(try await storedRow(list.id, in: database))
            #expect(stored.lastModifiedDate == list.lastModifiedDate, "nothing was written")
        }
    }

    // MARK: - Outside writes

    @Test func anOutsideWriteReplacesTheTextAndDropsThePendingSave() async throws {
        try await withLoadedViewModel(text: "* Milk") { viewModel, list, database in
            type("* Milk\n* Butter", into: viewModel)

            _ = try await database.write { db in
                try ShoppingListWriter.update(id: list.id, in: db) { $0.contentsForFreeform = "* Milk\n* Eggs" }
            }
            let outside = try await storedRow(list.id, in: database)
            viewModel.storedRowDidChange(to: outside)

            #expect(viewModel.text == "* Milk\n* Eggs")
            await viewModel.settle()
            let afterSettle = try await storedText(list.id, in: database)
            #expect(afterSettle == "* Milk\n* Eggs")

            // The reload is not an edit: the view's `onChange` would call this, and it must not
            // schedule a save that writes the reloaded text back as a new change.
            viewModel.scheduleSave()
            viewModel.flush()
            await viewModel.settle()
            let stored = try #require(try await storedRow(list.id, in: database))
            viewModel.storedRowDidChange(to: stored)
            #expect(stored.contentsForFreeform == "* Milk\n* Eggs")
        }
    }

    @Test func theEditorsOwnWriteComingBackLeavesLaterKeystrokesAlone() async throws {
        try await withLoadedViewModel(text: "* Milk") { viewModel, list, database in
            type("* Milk\n* Eggs", into: viewModel)
            viewModel.flush()
            await viewModel.settle()

            type("* Milk\n* Eggs\n* Fl", into: viewModel)
            let own = try await storedRow(list.id, in: database)
            viewModel.storedRowDidChange(to: own)

            #expect(viewModel.text == "* Milk\n* Eggs\n* Fl", "the half-typed line survived")
            viewModel.flush()
            await viewModel.settle()
            let stored = try await storedText(list.id, in: database)
            #expect(stored == "* Milk\n* Eggs\n* Fl")
        }
    }

    @Test func aSaveBuiltOnARowThatMovedOnIsRefused() async throws {
        try await withLoadedViewModel(text: "* Milk") { viewModel, list, database in
            type("* Milk\n* Butter", into: viewModel)

            _ = try await database.write { db in
                try ShoppingListWriter.update(id: list.id, in: db) { $0.contentsForFreeform = "* Milk\n* Eggs" }
            }

            viewModel.flush()
            await viewModel.settle()

            let stored = try await storedText(list.id, in: database)
            #expect(stored == "* Milk\n* Eggs", "the stale save did not land")
            let outside = try await storedRow(list.id, in: database)
            viewModel.storedRowDidChange(to: outside)
            #expect(viewModel.text == "* Milk\n* Eggs")
        }
    }

    @Test func aDeletedRowEmptiesTheEditor() async throws {
        try await withLoadedViewModel(text: "* Milk") { viewModel, list, database in
            try await deleteStoredRow(list.id, in: database)
            viewModel.storedRowDidChange(to: nil)
            #expect(viewModel.text.isEmpty)
        }
    }
}
