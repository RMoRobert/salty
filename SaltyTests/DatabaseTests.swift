//
//  DatabaseTests.swift
//  SaltyTests
//
//  Integration tests for the real migrations / schema / foreign-keys layer and the WAL-safe
//  backup path, run against fresh, isolated temporary databases (the `.test` dependency
//  context makes `appDatabase()` open a throwaway temp-file DatabasePool, so these tests
//  never touch real user data).
//
//  IMPORTANT — why everything lives under one `.serialized` suite:
//  Each test builds a database via `appDatabase()`, which resolves `@Dependency(\.context)`.
//  Resolving swift-dependencies values from multiple test suites *in parallel* races inside
//  the dependency / swift-testing machinery and crashes (over-release in `_currentTest()`).
//  `.serialized` on a parent suite serializes all of its nested suites too, so no two
//  `appDatabase()` calls ever run concurrently.
//
//  Tests drive the database with GRDB raw SQL (and the app-module backup manager) rather than
//  the StructuredQueries `.insert {}` / `.where {}` builders, which crash at runtime when
//  instantiated from the test bundle (missing protocol-witness symbols across the test-host
//  boundary).
//

import Testing
import Foundation
import GRDB
import SQLiteData
@testable import Salty

/// Builds a fresh, migrated, isolated database for a single test.
private func makeTestDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
    } operation: {
        try appDatabase()
    }
}

@Suite(.serialized)
struct DatabaseIntegrationTests {

    // MARK: - Schema & migrations

    @Suite struct SchemaAndMigrations {

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

        // MARK: Recipe persistence / JSON columns (via raw SQL)

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

        // MARK: Foreign keys

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

    // MARK: - WAL-safe backups

    @Suite struct Backups {

        @Test func snapshotIsConsistentAndOpenable() async throws {
            // Build the DB via the safe helper first; never call appDatabase() inside a
            // withDependencies *mutation* closure (re-entrant \.context resolution crashes).
            let database = try makeTestDatabase()

            // Seed several recipes (raw SQL — safe from the test bundle).
            try await database.write { db in
                for i in 1...25 {
                    try db.execute(sql: "INSERT INTO recipe (id, name) VALUES (?, ?)", arguments: ["r\(i)", "Recipe \(i)"])
                }
            }
            let sourceCount = try await database.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM recipe") ?? -1
            }

            let snapshotURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("snapshot-\(UUID().uuidString).sqlite")
            defer {
                try? FileManager.default.removeItem(at: snapshotURL)
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: snapshotURL.path + "-wal"))
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: snapshotURL.path + "-shm"))
            }

            // The backup manager resolves @Dependency(\.defaultDatabase); provide the test DB.
            try withDependencies {
                $0.defaultDatabase = database
            } operation: {
                let manager = DatabaseBackupManager()
                try manager.writeConsistentDatabaseSnapshot(to: snapshotURL)
            }

            // The snapshot must be a single self-contained file (no WAL sidecars).
            #expect(FileManager.default.fileExists(atPath: snapshotURL.path))
            #expect(!FileManager.default.fileExists(atPath: snapshotURL.path + "-wal"))

            // Opening the snapshot fresh must yield the same data, including seeded defaults.
            let restored = try DatabaseQueue(path: snapshotURL.path)
            let restoredCount = try await restored.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM recipe") ?? -2
            }
            let restoredCategories = try await restored.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM category") ?? -2
            }
            try restored.close()

            #expect(restoredCount == sourceCount)
            #expect(restoredCount == 25)
            #expect(restoredCategories >= 5) // migration-seeded defaults survive the snapshot
        }

        @Test func snapshotCapturesUncheckpointedWrites() async throws {
            // The whole point of the fix: data still sitting in the WAL must appear in the backup.
            let database = try makeTestDatabase()

            try await database.write { db in
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('wal-1', 'Written via WAL')")
            }

            let snapshotURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("snapshot-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: snapshotURL) }

            try withDependencies {
                $0.defaultDatabase = database
            } operation: {
                let manager = DatabaseBackupManager()
                try manager.writeConsistentDatabaseSnapshot(to: snapshotURL)
            }

            let restored = try DatabaseQueue(path: snapshotURL.path)
            let found = try await restored.read {
                try String.fetchOne($0, sql: "SELECT name FROM recipe WHERE id = 'wal-1'")
            }
            try restored.close()

            #expect(found == "Written via WAL")
        }
    }
}
