//
//  LibraryClassifierEditorTests.swift
//  SaltyTests
//
//  Covers the create / rename / delete half of the category, course, and tag editors -- logic that
//  used to live in three view models and so couldn't be tested at all.
//
//  Like DatabaseTests, these drive the database with GRDB raw SQL rather than the StructuredQueries
//  builders, which crash at runtime when instantiated from the test bundle.
//

import Testing
import Foundation
import GRDB
import SQLiteData
@testable import Salty
import SaltyCore

/// Builds a fresh, migrated, isolated database for a single test.
private func makeTestDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
    } operation: {
        try appDatabase()
    }
}

@Suite(.serialized)
struct LibraryClassifierEditorTests {

    // MARK: - Creating

    @Test func createStoresTheTrimmedName() async throws {
        let db = try makeTestDatabase()

        let id = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .tag, name: "  Weeknight  ", in: db)
        }

        let name = try await db.read {
            try String.fetchOne($0, sql: #"SELECT "name" FROM "tag" WHERE "id" = ?"#, arguments: [id])
        }
        #expect(name == "Weeknight")
    }

    @Test func createStampsLastModifiedSoTheRowSyncs() async throws {
        let db = try makeTestDatabase()

        let id = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .category, name: "Freezer", in: db)
        }

        let stamped = try await db.read {
            try String.fetchOne($0, sql: #"SELECT "lastModifiedDate" FROM "category" WHERE "id" = ?"#, arguments: [id])
        }
        #expect(stamped != nil)
    }

    // MARK: - Name conflicts

    @Test func existingRowMatchesIgnoringCaseAndSurroundingSpace() async throws {
        let db = try makeTestDatabase()
        let id = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .tag, name: "Comfort Food", in: db)
        }

        let conflict = try await db.read { db in
            try LibraryClassifierEditor.existingRow(classifier: .tag, name: "  comfort food ", in: db)
        }

        #expect(conflict?.id == id)
        // The stored spelling is what the merge prompt offers, not what was typed.
        #expect(conflict?.name == "Comfort Food")
    }

    /// Matching collapses internal whitespace the same way LibraryDuplicateFinder does, so the editor
    /// refuses exactly the pairs Consolidate Duplicates would later offer to merge.
    @Test func existingRowMatchesAcrossInternalWhitespaceRuns() async throws {
        let db = try makeTestDatabase()
        try await db.write { db in
            _ = try LibraryClassifierEditor.create(classifier: .category, name: "Slow  Cooker", in: db)
        }

        let conflict = try await db.read { db in
            try LibraryClassifierEditor.existingRow(classifier: .category, name: "Slow Cooker", in: db)
        }
        #expect(conflict != nil)
    }

    @Test func existingRowIgnoresTheRowBeingRenamed() async throws {
        let db = try makeTestDatabase()
        let id = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .tag, name: "desserts", in: db)
        }

        // Re-capitalizing a row isn't a conflict with itself.
        let conflict = try await db.read { db in
            try LibraryClassifierEditor.existingRow(classifier: .tag, name: "Desserts", excludingId: id, in: db)
        }
        #expect(conflict == nil)
    }

    @Test func existingRowIgnoresBlankNames() async throws {
        let db = try makeTestDatabase()

        let conflict = try await db.read { db in
            try LibraryClassifierEditor.existingRow(classifier: .tag, name: "   ", in: db)
        }
        #expect(conflict == nil)
    }

    // MARK: - Renaming

    @Test func renameStoresTheTrimmedNameAndMovesTheTimestamp() async throws {
        let db = try makeTestDatabase()
        let id = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .tag, name: "Deserts", in: db)
        }
        let before = try await db.read {
            try String.fetchOne($0, sql: #"SELECT "lastModifiedDate" FROM "tag" WHERE "id" = ?"#, arguments: [id])
        }

        try await Task.sleep(for: .milliseconds(20))
        try await db.write { db in
            try LibraryClassifierEditor.rename(classifier: .tag, id: id, to: " Desserts ", in: db)
        }

        let (name, after) = try await db.read { db -> (String?, String?) in
            let row = try Row.fetchOne(
                db,
                sql: #"SELECT "name", "lastModifiedDate" FROM "tag" WHERE "id" = ?"#,
                arguments: [id]
            )
            return (row?["name"], row?["lastModifiedDate"])
        }
        #expect(name == "Desserts")
        #expect(after != before)
    }

    /// A rename touches only the classifier row: membership syncs as the recipe's id arrays, which a
    /// rename doesn't change, so bumping every recipe using it would be pointless sync traffic.
    @Test func renameLeavesRecipesAlone() async throws {
        let db = try makeTestDatabase()
        let tagId = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .tag, name: "Grill", in: db)
        }
        try await db.write { db in
            try db.execute(sql: #"INSERT INTO "recipe" ("id", "name") VALUES (?, ?)"#, arguments: ["r-1", "Burgers"])
            try db.execute(
                sql: #"INSERT INTO "recipeTag" ("id", "recipeId", "tagId") VALUES (?, ?, ?)"#,
                arguments: ["rt-1", "r-1", tagId]
            )
        }
        let before = try await recipeTimestamp("r-1", in: db)

        try await Task.sleep(for: .milliseconds(20))
        try await db.write { db in
            try LibraryClassifierEditor.rename(classifier: .tag, id: tagId, to: "Grilling", in: db)
        }

        #expect(try await recipeTimestamp("r-1", in: db) == before)
    }

    // MARK: - Deleting

    @Test func deletingACategoryDropsItsJunctionRowsAndTouchesTheRecipes() async throws {
        let db = try makeTestDatabase()
        let categoryId = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .category, name: "Zzz Test Category", in: db)
        }
        try await db.write { db in
            try db.execute(sql: #"INSERT INTO "recipe" ("id", "name") VALUES (?, ?)"#, arguments: ["r-1", "Cake"])
            try db.execute(
                sql: #"INSERT INTO "recipeCategory" ("id", "recipeId", "categoryId") VALUES (?, ?, ?)"#,
                arguments: ["rc-1", "r-1", categoryId]
            )
        }
        let before = try await recipeTimestamp("r-1", in: db)

        try await Task.sleep(for: .milliseconds(20))
        let touched = try await db.write { db in
            try LibraryClassifierEditor.delete(classifier: .category, ids: [categoryId], in: db)
        }

        #expect(touched == ["r-1"])
        let junctionCount = try await db.read {
            try Int.fetchOne($0, sql: #"SELECT COUNT(*) FROM "recipeCategory" WHERE "categoryId" = ?"#, arguments: [categoryId]) ?? -1
        }
        #expect(junctionCount == 0)
        // The recipe survives, with a moved timestamp so the lost classification syncs.
        let recipeCount = try await db.read {
            try Int.fetchOne($0, sql: #"SELECT COUNT(*) FROM "recipe" WHERE "id" = 'r-1'"#) ?? 0
        }
        #expect(recipeCount == 1)
        #expect(try await recipeTimestamp("r-1", in: db) != before)
    }

    @Test func deletingATagDropsItsJunctionRows() async throws {
        let db = try makeTestDatabase()
        let tagId = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .tag, name: "Zzz Test Tag", in: db)
        }
        try await db.write { db in
            try db.execute(sql: #"INSERT INTO "recipe" ("id", "name") VALUES (?, ?)"#, arguments: ["r-1", "Chili"])
            try db.execute(
                sql: #"INSERT INTO "recipeTag" ("id", "recipeId", "tagId") VALUES (?, ?, ?)"#,
                arguments: ["rt-1", "r-1", tagId]
            )
        }

        let touched = try await db.write { db in
            try LibraryClassifierEditor.delete(classifier: .tag, ids: [tagId], in: db)
        }

        #expect(touched == ["r-1"])
        let junctionCount = try await db.read {
            try Int.fetchOne($0, sql: #"SELECT COUNT(*) FROM "recipeTag" WHERE "tagId" = ?"#, arguments: [tagId]) ?? -1
        }
        #expect(junctionCount == 0)
    }

    /// recipe.courseId is ON DELETE SET NULL, so the delete itself clears the recipes -- but they still
    /// need their timestamps moved, which is the part the FK can't do.
    @Test func deletingACourseClearsCourseIdAndTouchesTheRecipes() async throws {
        let db = try makeTestDatabase()
        let courseId = try await db.write { db in
            try LibraryClassifierEditor.create(classifier: .course, name: "Zzz Test Course", in: db)
        }
        try await db.write { db in
            try db.execute(
                sql: #"INSERT INTO "recipe" ("id", "name", "courseId") VALUES (?, ?, ?)"#,
                arguments: ["r-1", "Soup", courseId]
            )
        }
        let before = try await recipeTimestamp("r-1", in: db)

        try await Task.sleep(for: .milliseconds(20))
        let touched = try await db.write { db in
            try LibraryClassifierEditor.delete(classifier: .course, ids: [courseId], in: db)
        }

        #expect(touched == ["r-1"])
        let courseIdAfter = try await db.read {
            try String.fetchOne($0, sql: #"SELECT "courseId" FROM "recipe" WHERE "id" = 'r-1'"#)
        }
        #expect(courseIdAfter == nil)
        #expect(try await recipeTimestamp("r-1", in: db) != before)
    }

    @Test func deletingSeveralRowsAtOnceReportsEveryAffectedRecipe() async throws {
        let db = try makeTestDatabase()
        let (first, second) = try await db.write { db in
            (
                try LibraryClassifierEditor.create(classifier: .tag, name: "Zzz One", in: db),
                try LibraryClassifierEditor.create(classifier: .tag, name: "Zzz Two", in: db)
            )
        }
        try await db.write { db in
            try db.execute(sql: #"INSERT INTO "recipe" ("id", "name") VALUES (?, ?)"#, arguments: ["r-1", "Stew"])
            try db.execute(sql: #"INSERT INTO "recipe" ("id", "name") VALUES (?, ?)"#, arguments: ["r-2", "Pie"])
            try db.execute(
                sql: #"INSERT INTO "recipeTag" ("id", "recipeId", "tagId") VALUES (?, ?, ?)"#,
                arguments: ["rt-1", "r-1", first]
            )
            try db.execute(
                sql: #"INSERT INTO "recipeTag" ("id", "recipeId", "tagId") VALUES (?, ?, ?)"#,
                arguments: ["rt-2", "r-2", second]
            )
        }

        let touched = try await db.write { db in
            try LibraryClassifierEditor.delete(classifier: .tag, ids: [first, second], in: db)
        }

        #expect(touched == ["r-1", "r-2"])
        let remaining = try await db.read {
            try Int.fetchOne($0, sql: #"SELECT COUNT(*) FROM "tag" WHERE "id" IN (?, ?)"#, arguments: [first, second]) ?? -1
        }
        #expect(remaining == 0)
    }

    // MARK: - Helpers

    private func recipeTimestamp(_ id: String, in db: any DatabaseWriter) async throws -> String? {
        try await db.read {
            try String.fetchOne($0, sql: #"SELECT "lastModifiedDate" FROM "recipe" WHERE "id" = ?"#, arguments: [id])
        }
    }
}
