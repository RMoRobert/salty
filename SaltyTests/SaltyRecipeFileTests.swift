//
//  SaltyRecipeFileTests.swift
//  SaltyTests
//
//  `SaltyRecipeFile` (reading and writing `.saltyRecipe` files) and `SaltyRecipeImporter` (adding one
//  to a library). Reading follows Salty.NET's reader: files from every client and version must open.
//
//  Library rows are seeded and read back with raw SQL; see the note in RecipeWriterTests.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct SaltyRecipeFileTests {

    /// A recipe as Salty writes one (trimmed from a real export): whole-second dates with a `Z`.
    private static let saltyWritten = #"""
        {
            "wantToMake": false, "rating": 0, "difficulty": 0, "isFavorite": false, "version": "1.0",
            "directions": [{"isHeading": false, "text": "Beat butter and sugar."}],
            "ingredients": [{"text": "1 cup unsalted butter"}, {"text": "2 cups flour"}],
            "notes": [{"title": "Source", "id": "319A97FE-9067-4308-B497-56FE98ED0AC9", "content": "Chicago Tribune, 1993."}],
            "preparationTimes": [{"type": "Bake", "timeString": "6 min"}],
            "createdDate": "2025-08-07T02:21:54Z",
            "lastModifiedDate": "2025-10-17T21:33:29Z",
            "name": "Empires", "servings": 12, "id": "338FD4C2-8B7E-4751-94DC-E8993A7C7E61",
            "yield": "12 cookies", "course": "Dessert", "categories": ["Desserts"], "tags": ["holiday", " Holiday "],
            "source": "Chicago Tribune"
        }
        """#

    private func decode(_ text: String) throws -> [SaltyRecipeExport] {
        try SaltyRecipeFile.decode(Data(text.utf8))
    }

    private func library() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        try runSaltySharedMigrations(queue)
        return queue
    }

    // MARK: - Reading

    @Test func readsARecipeWrittenBySalty() throws {
        let recipe = try #require(try decode(Self.saltyWritten).first)
        #expect(recipe.name == "Empires")
        #expect(recipe.createdDate == Date(timeIntervalSince1970: 1_754_533_314))
        #expect(recipe.course == "Dessert")
        #expect(recipe.ingredients.count == 2)
    }

    /// Older SaltyKMP builds wrote milliseconds and no zone, which the Apple app's `.iso8601` decoder
    /// refuses. They meant UTC.
    @Test func readsTheKmpTimestampShapeThatTheStrictDecoderRejects() throws {
        let kmp = Self.saltyWritten.replacing(#""2025-08-07T02:21:54Z""#, with: #""2025-08-07T02:21:54.383""#)
        let recipe = try #require(try decode(kmp).first)
        let created = try #require(recipe.createdDate)
        #expect(abs(created.timeIntervalSince1970 - 1_754_533_314.383) < 0.001)
    }

    @Test func readsTheSyncWireShapeToo() throws {
        let wire = Self.saltyWritten.replacing(#""2025-08-07T02:21:54Z""#, with: #""2025-08-07T02:21:54.500Z""#)
        #expect(try #require(try decode(wire).first).createdDate != nil)
    }

    @Test func readsAFileHoldingManyRecipes() throws {
        let second = Self.saltyWritten.replacing(#""Empires""#, with: #""Shortbread""#)
        #expect(try decode("[\(Self.saltyWritten), \(second)]").map(\.name) == ["Empires", "Shortbread"])
    }

    @Test func oneUnreadableRecipeInAListDoesNotCostTheOthers() throws {
        #expect(try decode(#"[{"id": "no name"}, \#(Self.saltyWritten)]"#).map(\.name) == ["Empires"])
    }

    /// Only the name is required: a file that leaves out defaulted keys still reads, and a missing id
    /// gets a fresh one.
    @Test func aRecipeThatLeavesOutDefaultedKeysStillReads() throws {
        let recipe = try #require(try decode(#"{"name": "Bare", "rating": 9, "createdDate": "not a date"}"#).first)
        #expect(recipe.name == "Bare")
        #expect(recipe.version == "1.0")
        #expect(recipe.rating == .notSet, "an unreadable rating is unset, not fatal")
        #expect(recipe.createdDate == nil)
        #expect(recipe.notes.isEmpty && recipe.directions.isEmpty)
        #expect(!recipe.id.isEmpty)
    }

    @Test func anEmptyListIsNoRecipesRatherThanAnError() throws {
        #expect(try decode("[]").isEmpty)
    }

    @Test func aBlankFileAndAFileThatIsNotARecipeSaySo() {
        #expect(throws: SaltyRecipeFileError.empty) { try decode("  \n ") }
        #expect(throws: SaltyRecipeFileError.notARecipeFile) { try decode(#"{"hello": "world"}"#) }
        #expect(throws: SaltyRecipeFileError.notARecipeFile) { try decode("not json") }
        #expect(throws: SaltyRecipeFileError.notARecipeFile) { try decode(#"[{"hello": 1}]"#) }
    }

    // MARK: - Writing

    @Test func oneRecipeIsWrittenAsAnObjectAndSeveralAsAnArrayWithWholeSecondDates() throws {
        let recipe = try #require(try decode(Self.saltyWritten).first)

        let one = try #require(String(data: try SaltyRecipeFile.encode([recipe]), encoding: .utf8))
        let two = try #require(String(data: try SaltyRecipeFile.encode([recipe, recipe]), encoding: .utf8))

        #expect(one.hasPrefix("{"))
        #expect(two.hasPrefix("["))
        #expect(one.contains(#""2025-08-07T02:21:54Z""#), "the shape every Salty reader accepts")
        #expect(try decode(two).count == 2)
    }

    // MARK: - Importing

    @Test func anImportGetsFreshIdsAndMatchesClassifiersByName() throws {
        let queue = try library()
        try queue.write { db in
            try db.execute(sql: #"INSERT INTO "category" ("id", "name") VALUES ('cat-desserts', 'desserts')"#)
        }
        let export = try #require(try decode(Self.saltyWritten).first)
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        let stored = try queue.write { db in try SaltyRecipeImporter.insert(export, in: db, now: now) }

        #expect(stored.id != export.id, "importing never overwrites the original")
        #expect(stored.lastModifiedDate == now)
        #expect(stored.createdDate == export.createdDate)
        let categories = try queue.read { db in
            try String.fetchAll(db, sql: #"SELECT "categoryId" FROM "recipeCategory" WHERE "recipeId" = ?"#, arguments: [stored.id])
        }
        #expect(categories == ["cat-desserts"], "\"Desserts\" ticks the existing \"desserts\"")
        let tags = try queue.read { db in
            try String.fetchAll(db, sql: #"SELECT t."name" FROM "recipeTag" rt JOIN "tag" t ON t."id" = rt."tagId" WHERE rt."recipeId" = ?"#,
                                arguments: [stored.id])
        }
        #expect(tags == ["holiday"], "two spellings of one tag make one tag")
        let course = try queue.read { db in
            try String.fetchOne(db, sql: #"SELECT c."name" FROM "recipe" r JOIN "course" c ON c."id" = r."courseId" WHERE r."id" = ?"#,
                                arguments: [stored.id])
        }
        #expect(course?.caseInsensitiveCompare("Dessert") == .orderedSame)
    }

    @Test func importingTheSameFileTwiceMakesTwoRecipes() throws {
        let queue = try library()
        let export = try #require(try decode(Self.saltyWritten).first)

        let first = try queue.write { db in try SaltyRecipeImporter.insert(export, in: db) }
        let second = try queue.write { db in try SaltyRecipeImporter.insert(export, in: db) }

        #expect(first.id != second.id)
        #expect(try queue.read { db in try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "recipe" WHERE "name" = 'Empires'"#) } == 2)
    }
}
