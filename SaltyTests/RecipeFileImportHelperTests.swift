//
//  RecipeFileImportHelperTests.swift
//  SaltyTests
//
//  The app's importer for recipe files. Library rows are read back with raw SQL (see the note in
//  RecipeWriterTests). No photos here: attaching one writes into the app's real image folder.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

struct RecipeFileImportHelperTests {

    private func library() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        try runSaltySharedMigrations(queue)
        return queue
    }

    private func file(_ contents: String, extension fileExtension: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(fileExtension)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func importsASaltyRecipeFileStampedAsANewChange() async throws {
        let queue = try library()
        let url = try file(#"""
            [{"name": "Aioli", "lastModifiedDate": "2020-01-01T00:00:00Z", "tags": ["Sauce"]},
             {"name": "Brioche", "lastModifiedDate": "2020-01-01T00:00:00Z"}]
            """#, extension: "saltyRecipe")
        defer { try? FileManager.default.removeItem(at: url) }

        let ids = try await RecipeFileImportHelper.importIntoDatabase(queue, fileUrl: url)

        #expect(ids.count == 2)
        let names = try await queue.read { db in
            try String.fetchAll(db, sql: #"SELECT "name" FROM "recipe" ORDER BY "name""#)
        }
        #expect(names == ["Aioli", "Brioche"])
        // Stamped now, not 2020: an old stamp on a row the server has never seen can read to sync as
        // "deleted on the server".
        let modified = try await queue.read { db in
            try Date.fetchOne(db, sql: #"SELECT "lastModifiedDate" FROM "recipe" WHERE "id" = ?"#, arguments: [ids[0]])
        }
        let stamp = try #require(modified)
        #expect(stamp.timeIntervalSinceNow > -60)
        let tags = try await queue.read { db in
            try String.fetchAll(db, sql: #"SELECT t."name" FROM "recipeTag" rt JOIN "tag" t ON t."id" = rt."tagId" WHERE rt."recipeId" = ?"#,
                                arguments: [ids[0]])
        }
        #expect(tags == ["Sauce"])
    }

    @Test func importsACroutonFile() async throws {
        let queue = try library()
        let url = try file(#"{"name": "Meat Pies", "serves": 16, "tags": ["Dinner"]}"#, extension: "crumb")
        defer { try? FileManager.default.removeItem(at: url) }

        let ids = try await RecipeFileImportHelper.importIntoDatabase(queue, fileUrl: url)

        let id = try #require(ids.first)
        let servings = try await queue.read { db in
            try Int.fetchOne(db, sql: #"SELECT "servings" FROM "recipe" WHERE "id" = ?"#, arguments: [id])
        }
        #expect(servings == 16)
    }

    @Test func aFileThatIsNotItsFormatThrowsAndImportsNothing() async throws {
        let queue = try library()
        let url = try file("not a recipe", extension: "crumb")
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: ImportError.self) {
            try await RecipeFileImportHelper.importIntoDatabase(queue, fileUrl: url)
        }
        #expect(try await queue.read { db in try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "recipe""#) } == 0)
    }

    @Test func anExtensionSaltyDoesNotImportThrows() async throws {
        let queue = try library()
        let url = try file("{}", extension: "mgourmet4")
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: ImportError.self) {
            try await RecipeFileImportHelper.importIntoDatabase(queue, fileUrl: url)
        }
    }

    @Test func peeksNamesInAnyFormatItImports() throws {
        let crumb = try file(#"{"name": "Meat Pies"}"#, extension: "crumb")
        let text = try file(#"{"name": "Meat Pies"}"#, extension: "txt")
        defer {
            try? FileManager.default.removeItem(at: crumb)
            try? FileManager.default.removeItem(at: text)
        }

        #expect(RecipeFileImportHelper.peekRecipeNames(crumb) == ["Meat Pies"])
        #expect(RecipeFileImportHelper.peekRecipeNames(text).isEmpty)
    }
}
