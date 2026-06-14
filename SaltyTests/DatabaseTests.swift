//
//  DatabaseTests.swift
//  SaltyTests
//
//  Exercises the real migrations + schema + foreign keys against a fresh, isolated
//  temporary database (the `.test` dependency context makes `appDatabase()` open a
//  throwaway temp-file DatabasePool, so these tests never touch real user data).
//
//  NOTE: These tests drive the database with GRDB raw SQL rather than the StructuredQueries
//  `.insert {}` / `.where {}` builders. Those macro-generated generics crash at runtime when
//  instantiated from the test bundle (missing protocol-witness symbols across the test-host
//  boundary). Raw SQL verifies the schema/migrations/foreign-keys layer reliably; the Codable
//  shape of the JSON columns is covered separately in `RecipeModelTests`.
//

import Testing
import Foundation
import GRDB
import SQLiteData
@testable import Salty

@Suite(.serialized)
struct DatabaseTests {

    /// Builds a fresh, migrated, isolated database for a single test.
    private func makeTestDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
        } operation: {
            try appDatabase()
        }
    }

    // MARK: - Migrations

    @Test func migrationsSeedDefaultCategoriesAndCourses() async throws {
        let db = try makeTestDatabase()

        let categoryCount = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM category") ?? 0 }
        let courseCount = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course") ?? 0 }
        let shoppingListCount = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM shoppingList") ?? 0 }

        #expect(categoryCount >= 5)
        #expect(courseCount >= 10)
        #expect(shoppingListCount == 1)
    }

    @Test func migrationsCreateExpectedColumns() async throws {
        let db = try makeTestDatabase()

        // 0003 + 0004 add columns that older databases lacked; verify they exist on a fresh DB.
        let recipeHasVariations = try await db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM pragma_table_info('recipe') WHERE name = 'variations'") ?? 0
        }
        let categoryHasLastModified = try await db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM pragma_table_info('category') WHERE name = 'lastModifiedDate'") ?? 0
        }

        #expect(recipeHasVariations == 1)
        #expect(categoryHasLastModified == 1)
    }

    @Test func foreignKeysAreEnabled() async throws {
        let db = try makeTestDatabase()
        let fkEnabled = try await db.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") ?? 0 }
        #expect(fkEnabled == 1)
    }

    // MARK: - Recipe persistence / JSON columns (via raw SQL)

    @Test func recipeJSONColumnsAreStoredAndDecodable() async throws {
        let db = try makeTestDatabase()

        let directionsJSON = #"[{"id":"d1","isHeading":false,"text":"Mix well"}]"#
        let ingredientsJSON = #"[{"id":"i1","isHeading":false,"isMain":true,"text":"1 cup flour"},{"id":"i2","isHeading":false,"isMain":false,"text":"1/2 cup water"}]"#
        let nutritionJSON = #"{"id":"nut1","calories":250,"protein":8}"#

        try await db.write { db in
            try db.execute(
                sql: """
                INSERT INTO recipe (id, name, isFavorite, directions, ingredients, nutrition)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: ["recipe-1", "Round Trip", true, directionsJSON, ingredientsJSON, nutritionJSON]
            )
        }

        let row = try await db.read { db -> (String, String, String, String)? in
            guard let r = try Row.fetchOne(db, sql: "SELECT name, directions, ingredients, nutrition FROM recipe WHERE id = ?", arguments: ["recipe-1"]) else {
                return nil
            }
            return (r["name"], r["directions"], r["ingredients"], r["nutrition"])
        }

        #expect(row != nil)
        #expect(row?.0 == "Round Trip")

        // The stored JSON must decode back into the app's Codable models.
        let decoder = JSONDecoder()
        let directions = try decoder.decode([Direction].self, from: Data((row?.1 ?? "").utf8))
        let ingredients = try decoder.decode([Ingredient].self, from: Data((row?.2 ?? "").utf8))
        let nutrition = try decoder.decode(NutritionInformation.self, from: Data((row?.3 ?? "").utf8))

        #expect(directions.first?.text == "Mix well")
        #expect(ingredients.count == 2)
        #expect(ingredients.first?.isMain == true)
        #expect(nutrition.calories == 250)
        #expect(nutrition.protein == 8)
    }

    @Test func recipeUpdatePersists() async throws {
        let db = try makeTestDatabase()

        try await db.write { db in
            try db.execute(sql: "INSERT INTO recipe (id, name, isFavorite) VALUES (?, ?, ?)", arguments: ["recipe-2", "Original", false])
        }
        try await db.write { db in
            try db.execute(sql: "UPDATE recipe SET name = ?, isFavorite = ? WHERE id = ?", arguments: ["Updated", true, "recipe-2"])
        }

        let row = try await db.read { db in
            try Row.fetchOne(db, sql: "SELECT name, isFavorite FROM recipe WHERE id = ?", arguments: ["recipe-2"])
        }
        #expect(row?["name"] == "Updated")
        #expect(row?["isFavorite"] == true)
    }

    // MARK: - Foreign keys

    @Test func deletingRecipeCascadesToJunctionRows() async throws {
        let db = try makeTestDatabase()

        try await db.write { db in
            try db.execute(sql: "INSERT INTO recipe (id, name) VALUES (?, ?)", arguments: ["recipe-3", "Has Category"])
            try db.execute(sql: "INSERT INTO category (id, name) VALUES (?, ?)", arguments: ["cat-1", "Test Category"])
            try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES (?, ?, ?)", arguments: ["rc-1", "recipe-3", "cat-1"])
        }

        let beforeCount = try await db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM recipeCategory WHERE recipeId = 'recipe-3'") ?? -1
        }
        #expect(beforeCount == 1)

        try await db.write { db in
            try db.execute(sql: "DELETE FROM recipe WHERE id = ?", arguments: ["recipe-3"])
        }

        // onDelete: .cascade should remove the junction row...
        let afterCount = try await db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM recipeCategory WHERE recipeId = 'recipe-3'") ?? -1
        }
        #expect(afterCount == 0)

        // ...but leave the category itself intact.
        let categoryStillExists = try await db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM category WHERE id = 'cat-1'") ?? 0
        }
        #expect(categoryStillExists == 1)
    }

    @Test func eachTestDatabaseIsIsolated() async throws {
        let db1 = try makeTestDatabase()
        let db2 = try makeTestDatabase()

        try await db1.write { db in
            try db.execute(sql: "INSERT INTO recipe (id, name) VALUES (?, ?)", arguments: ["only-in-db1", "X"])
        }

        let inDb2 = try await db2.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM recipe WHERE id = 'only-in-db1'") ?? -1
        }
        #expect(inDb2 == 0)
    }
}
