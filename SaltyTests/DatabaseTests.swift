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
            // No list is seeded any more — the app starts empty and offers to create one.
            #expect(shoppingListCount == 0)
        }

        @Test func shoppingListTableHasLastModifiedDateOnAFreshDatabase() async throws {
            // The column comes solely from the shared migration ledger (migration 0001 deliberately
            // doesn't declare it), so this asserts the ledger runs as part of opening a database.
            let db = try makeTestDatabase()
            let hasColumn = try await db.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM pragma_table_info('shoppingList') WHERE name = 'lastModifiedDate'") ?? 0
            }
            #expect(hasColumn == 1)
        }

        /// Rows written by SaltyKMP or raw SQL can leave every `shoppingList` column NULL. Three of
        /// them are non-optional on the Swift model (decode failure), and a NULL `lastModifiedDate`
        /// would make sync delete the list rather than upload it. Assertions use raw SQL rather than
        /// the ORM — see the note below on `ShoppingList` generics in this test target.
        @Test func coalescingRepairsNullShoppingListColumns() async throws {
            let db = try makeTestDatabase()
            try await db.write {
                try $0.execute(sql: #"INSERT INTO "shoppingList" ("id") VALUES ('bare')"#)
            }

            coalesceNullShoppingListColumns(db)

            let row = try await db.read { database -> (String?, Int?, String?, String?) in
                try Row.fetchOne(database, sql: #"SELECT "name", "isFreeform", "contentsForList", "lastModifiedDate" FROM "shoppingList" WHERE "id" = 'bare'"#)
                    .map { ($0["name"], $0["isFreeform"], $0["contentsForList"], $0["lastModifiedDate"]) } ?? (nil, nil, nil, nil)
            }
            #expect(row.0 == "")
            #expect(row.1 == 0)      // no freeform text → checklist
            #expect(row.2 == "[]")
            #expect(row.3 != nil)    // must not stay NULL, or sync would delete this list
        }

        @Test func coalescingInfersFreeformFromExistingText() async throws {
            // A row carrying freeform text but a NULL flag must open as freeform — defaulting to a
            // checklist would hide content the user actually wrote.
            let db = try makeTestDatabase()
            try await db.write {
                try $0.execute(sql: #"INSERT INTO "shoppingList" ("id", "contentsForFreeform") VALUES ('ff', '# My List')"#)
            }

            coalesceNullShoppingListColumns(db)

            let isFreeform = try await db.read {
                try Int.fetchOne($0, sql: #"SELECT "isFreeform" FROM "shoppingList" WHERE "id" = 'ff'"#)
            }
            #expect(isFreeform == 1)
        }

        @Test func coalescingLeavesGoodRowsAloneAndIsIdempotent() async throws {
            let db = try makeTestDatabase()
            try await db.write {
                try $0.execute(sql: #"""
                    INSERT INTO "shoppingList" ("id", "name", "isFreeform", "contentsForList", "lastModifiedDate")
                    VALUES ('ok', 'Groceries', 0, '[]', '2026-01-01 00:00:00.000')
                    """#)
            }

            coalesceNullShoppingListColumns(db)
            coalesceNullShoppingListColumns(db)   // re-running must be a no-op

            let row = try await db.read { database -> (String?, String?) in
                try Row.fetchOne(database, sql: #"SELECT "name", "lastModifiedDate" FROM "shoppingList" WHERE "id" = 'ok'"#)
                    .map { ($0["name"], $0["lastModifiedDate"]) } ?? (nil, nil)
            }
            #expect(row.0 == "Groceries")
            #expect(row.1 == "2026-01-01 00:00:00.000")   // untouched
        }

        // NOTE: there is deliberately no `ShoppingList.insert` round-trip test here. Calling it from
        // this test target hard-crashes the test host — SIGSEGV inside the Swift runtime instantiating
        // the witness table for `Insert<ShoppingList, ()>` — which takes the whole bundle down and
        // reports every other test as failed. It is NOT an app bug: creating a list through the real
        // UI (which runs the identical `ShoppingList.insert`) was verified working on the simulator.
        // It appears to be a runtime/metadata issue specific to the `@testable` host. If you re-add
        // such a test and the suite starts dying wholesale, this is why.

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

        /// Regression for the 0003 idempotency guard. Simulates the KMP-seeded case (the `variations`
        /// column already exists but 0003 isn't recorded as applied): re-running the migrator must NOT
        /// fail with "duplicate column name: variations".
        @Test func migration0003IsIdempotentWhenVariationsColumnExists() throws {
            let queue = try DatabaseQueue()
            try saltyMigrator().migrate(queue)

            // Un-record 0003 while leaving its column in place.
            try queue.write { db in
                try db.execute(
                    sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                    arguments: ["0003: Add 'variations' column to 'recipe' table"]
                )
            }

            #expect(throws: Never.self) {
                try saltyMigrator().migrate(queue)
            }
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

            // `Row` isn't Sendable, so this resolves to the synchronous `read` (no `await`).
            let row = try db.read { db in
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

        @Test func deletingCourseSetsRecipeCourseIdToNull() async throws {
            // recipe.courseId is a `references("course", onDelete: .setNull)` FK, so deleting a course must
            // clear courseId on its recipes (not delete them). LibraryCoursesEditViewModel relies on this;
            // it additionally bumps lastModifiedDate so the change syncs, which is app logic, not tested here.
            let db = try makeTestDatabase()

            try await db.write { db in
                try db.execute(sql: "INSERT INTO course (id, name) VALUES (?, ?)", arguments: ["co-1", "Dessert"])
                try db.execute(sql: "INSERT INTO recipe (id, name, courseId) VALUES (?, ?, ?)", arguments: ["r-1", "Cake", "co-1"])
            }

            let before = try await db.read {
                try String.fetchOne($0, sql: "SELECT courseId FROM recipe WHERE id = 'r-1'")
            }
            #expect(before == "co-1")

            try await db.write { db in
                try db.execute(sql: "DELETE FROM course WHERE id = ?", arguments: ["co-1"])
            }

            // The recipe survives...
            let recipeStillExists = try await db.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM recipe WHERE id = 'r-1'") ?? 0
            }
            #expect(recipeStillExists == 1)

            // ...with its course reference set to NULL.
            let courseIdAfter = try await db.read {
                try String.fetchOne($0, sql: "SELECT courseId FROM recipe WHERE id = 'r-1'")
            }
            #expect(courseIdAfter == nil)
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

    // MARK: - Search execution (runs the builder's generated SQL against a seeded DB)

    @Suite struct Search {

        /// Executes a built query fragment via GRDB raw SQL and returns the matched recipe ids in order.
        private func runIDs(_ fragment: QueryFragment, _ db: any DatabaseWriter) async throws -> [String] {
            let (sqlText, bindings) = fragment.prepare { _ in "?" }
            let args: [(any DatabaseValueConvertible)?] = bindings.map { binding in
                switch binding {
                case .text(let s): return s
                case .bool(let b): return b
                case .int(let i): return i
                case .uint(let u): return Int64(bitPattern: u)
                case .double(let d): return d
                case .date(let d): return d
                case .blob(let bytes): return Data(bytes)
                case .uuid(let u): return u.uuidString
                case .null, .invalid: return nil
                }
            }
            // Build the (Sendable) StatementArguments before the closure so the non-Sendable `args`
            // array isn't captured into the @Sendable read closure.
            let arguments = StatementArguments(args)
            return try await db.read { db -> [String] in
                try Row.fetchAll(db, sql: sqlText, arguments: arguments).map { row in row["id"] }
            }
        }

        @Test func comboSearchMatchesByTagNameEvenWhenRecipeNameDoesNot() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r1', 'Mystery Dish')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r2', 'Plain Toast')")
                try db.execute(sql: "INSERT INTO tag (id, name) VALUES ('t1', 'weeknight')")
                try db.execute(sql: "INSERT INTO recipeTag (id, recipeId, tagId) VALUES ('rt1', 'r1', 't1')")
            }
            // category + course + tag selected, searching "weeknight". The OLD code silently fell
            // back to name-only for this combo and would have returned []; the new builder finds r1.
            let frag = RecipeListQueryBuilder.fragment(
                scope: .all,
                searchPattern: "%weeknight%",
                options: [.category, .course, .tags],
                includeFavorites: false,
                sortOrder: .byName,
                sortDirection: .ascending
            )
            let ids = try await runIDs(frag, db)
            #expect(ids == ["r1"])
        }

        @Test func categoryScopeReturnsOnlyRecipesInThatCategory() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r1', 'In Cat')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r2', 'Not In Cat')")
                try db.execute(sql: "INSERT INTO category (id, name) VALUES ('c1', 'Breads')")
                try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES ('rc1', 'r1', 'c1')")
            }
            let frag = RecipeListQueryBuilder.fragment(
                scope: .category("c1"), searchPattern: nil, options: [],
                includeFavorites: false, sortOrder: .byName, sortDirection: .ascending
            )
            let ids = try await runIDs(frag, db)
            #expect(ids == ["r1"])
        }

        @Test func courseNameSearchFindsRecipe() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO course (id, name) VALUES ('co1', 'Dessert')")
                try db.execute(sql: "INSERT INTO recipe (id, name, courseId) VALUES ('r1', 'Cake', 'co1')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r2', 'Salad')")
            }
            let frag = RecipeListQueryBuilder.fragment(
                scope: .all, searchPattern: "%dessert%", options: [.course],
                includeFavorites: false, sortOrder: .byName, sortDirection: .ascending
            )
            let ids = try await runIDs(frag, db)
            #expect(ids == ["r1"])
        }

        @Test func favoritesFilterRestrictsResults() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO recipe (id, name, isFavorite) VALUES ('r1', 'Fav', 1)")
                try db.execute(sql: "INSERT INTO recipe (id, name, isFavorite) VALUES ('r2', 'NotFav', 0)")
            }
            let frag = RecipeListQueryBuilder.fragment(
                scope: .all, searchPattern: nil, options: [],
                includeFavorites: true, sortOrder: .byName, sortDirection: .ascending
            )
            let ids = try await runIDs(frag, db)
            #expect(ids == ["r1"])
        }

        @Test func notesAndVariationsSearchTheirOwnColumns() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                // r1 has searchable text only in NOTES; r2 only in VARIATIONS.
                try db.execute(sql: "INSERT INTO recipe (id, name, notes) VALUES ('r1', 'A', ?)",
                               arguments: [#"[{"id":"n1","title":"t","content":"ZEBRANOTE"}]"#])
                try db.execute(sql: "INSERT INTO recipe (id, name, variations) VALUES ('r2', 'B', ?)",
                               arguments: [#"[{"id":"v1","variationName":"vn","text":"ZEBRAVAR"}]"#])
            }

            func search(_ opts: Set<RecipeListSearchOptions>, _ pattern: String) async throws -> [String] {
                try await runIDs(
                    RecipeListQueryBuilder.fragment(
                        scope: .all, searchPattern: pattern, options: opts,
                        includeFavorites: false, sortOrder: .byName, sortDirection: .ascending
                    ),
                    db
                )
            }

            // Notes-only finds the notes recipe, not the variations one.
            #expect(try await search([.notes], "%ZEBRANOTE%") == ["r1"])
            #expect(try await search([.notes], "%ZEBRAVAR%") == [])
            // Variations-only finds the variations recipe, not the notes one.
            #expect(try await search([.variations], "%ZEBRAVAR%") == ["r2"])
            #expect(try await search([.variations], "%ZEBRANOTE%") == [])
            // Both enabled finds either.
            #expect(try await search([.notes, .variations], "%ZEBRANOTE%") == ["r1"])
            #expect(try await search([.notes, .variations], "%ZEBRAVAR%") == ["r2"])

            // JSON keys / structure are NOT matched (the whole point of json_extract): searching
            // for "content"/"title"/"variationName"/"id" must find nothing.
            #expect(try await search([.notes], "%content%") == [])
            #expect(try await search([.notes], "%title%") == [])
            #expect(try await search([.variations], "%variationName%") == [])
            #expect(try await search([.notes, .variations], "%id%") == [])
        }

        @Test func notesSearchHandlesNullAndEmptyColumns() async throws {
            // json_valid guard: NULL / empty / non-array JSON must not error, just not match.
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO recipe (id, name, notes) VALUES ('r1', 'A', NULL)")
                try db.execute(sql: "INSERT INTO recipe (id, name, notes) VALUES ('r2', 'B', '')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r3', 'C')") // notes defaults to NULL
            }
            let ids = try await runIDs(
                RecipeListQueryBuilder.fragment(
                    scope: .all, searchPattern: "%anything%", options: [.notes],
                    includeFavorites: false, sortOrder: .byName, sortDirection: .ascending
                ),
                db
            )
            #expect(ids == [])
        }

        @Test func descendingNameSortOrdersResults() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r1', 'Apple')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r2', 'Banana')")
            }
            let frag = RecipeListQueryBuilder.fragment(
                scope: .all, searchPattern: nil, options: [],
                includeFavorites: false, sortOrder: .byName, sortDirection: .descending
            )
            let ids = try await runIDs(frag, db)
            #expect(ids == ["r2", "r1"])
        }
    }

    // MARK: - List projection (RecipeListItem)

    @Suite struct Projection {

        /// The SELECT projects the RecipeListItem columns positionally — its decoder reads columns by
        /// position, so this exact column order (and count) is the decode contract. A mismatch would
        /// silently load the wrong field into each property at runtime, which compilation can't catch.
        /// (We can't decode RecipeListItem itself here — StructuredQueries' generated witnesses crash
        /// from the test bundle — so we assert the generated SQL's column shape instead.)
        @Test func projectionSelectsListItemColumnsInPositionalOrder() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(
                    sql: "INSERT INTO recipe (id, name, source, sourceDetails, introduction, rating, isFavorite) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arguments: ["r1", "Soup", "Grandma", "p. 12", "Cozy and warm", 4, true]
                )
            }
            let (sqlText, _) = RecipeListQueryBuilder.fragment(
                scope: .all, searchPattern: nil, options: [],
                includeFavorites: false, sortOrder: .byName, sortDirection: .ascending
            ).prepare { _ in "?" }

            let row = try db.read { db in try Row.fetchOne(db, sql: sqlText) }
            #expect(row != nil)

            // Column order MUST match RecipeListItem's stored-property declaration order.
            let columnNames = row.map { $0.map { name, _ in name } } ?? []
            #expect(columnNames == [
                "id", "name", "source", "sourceDetails", "introduction",
                "createdDate", "lastModifiedDate", "rating", "isFavorite", "imageThumbnailData",
                "lastPrepared",
            ])

            // Spot-check that each named column carries its own value (not a neighbor's).
            #expect(row?["id"] == "r1")
            #expect(row?["name"] == "Soup")
            #expect(row?["source"] == "Grandma")
            #expect(row?["sourceDetails"] == "p. 12")
            #expect(row?["introduction"] == "Cozy and warm")
            #expect(row?["rating"] == 4)
            #expect(row?["isFavorite"] == true)
        }
    }

    // MARK: - NULL coalescing (cross-platform safety net)

    /// The shared DB can be written by SaltyKMP or raw SQL, which may leave columns the Swift model
    /// treats as non-optional set to NULL. `coalesceNullRecipeColumns` backfills those so the row still
    /// decodes. These insert deliberately-NULL rows (the GRDB schema permits them) and verify the pass.
    @Suite struct NullCoalescing {

        @Test func backfillsNullColumnsSoRowIsDecodable() async throws {
            let db = try makeTestDatabase()

            // A row as another writer might leave it: every non-optional column NULL.
            try await db.write { db in
                try db.execute(sql: """
                    INSERT INTO recipe (id, name, createdDate, lastModifiedDate, source, sourceDetails,
                        introduction, yield, difficulty, rating, isFavorite, wantToMake,
                        directions, ingredients, notes, variations, preparationTimes)
                    VALUES ('r-null', 'Name', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                        NULL, NULL, NULL, NULL, NULL)
                    """)
            }

            // Runs every launch from appDatabase(); call it directly here against the NULL row.
            coalesceNullRecipeColumns(db)
            // Idempotent: a second pass must be a harmless no-op.
            coalesceNullRecipeColumns(db)

            let row = try #require(try db.read { try Row.fetchOne($0, sql: "SELECT * FROM recipe WHERE id = 'r-null'") })

            // JSON columns are now valid empty-array JSON (decodable, not NULL).
            for column in ["directions", "ingredients", "notes", "variations", "preparationTimes"] {
                let json: String = row[column]
                #expect(json == "[]")
            }
            #expect(try JSONDecoder().decode([Direction].self, from: Data((row["directions"] as String).utf8)).isEmpty)

            // Text → "", bool/enum → 0, dates → a non-empty timestamp.
            for column in ["source", "sourceDetails", "introduction", "yield"] {
                #expect((row[column] as String) == "")
            }
            for column in ["isFavorite", "wantToMake", "difficulty", "rating"] {
                #expect((row[column] as Int) == 0)
            }
            for column in ["createdDate", "lastModifiedDate"] {
                #expect(!(row[column] as String).isEmpty)
            }
        }

        @Test func preservesExistingNonNullValues() async throws {
            let db = try makeTestDatabase()

            let directionsJSON = #"[{"id":"d1","isHeading":false,"text":"Mix"}]"#
            try await db.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO recipe (id, name, source, isFavorite, difficulty, directions)
                    VALUES ('r-keep', 'Keep', 'Grandma', 1, 3, ?)
                    """,
                    arguments: [directionsJSON]
                )
            }

            coalesceNullRecipeColumns(db)

            // The WHERE … IS NULL guard must leave populated columns untouched.
            let row = try #require(try db.read { try Row.fetchOne($0, sql: "SELECT * FROM recipe WHERE id = 'r-keep'") })
            #expect((row["source"] as String) == "Grandma")
            #expect((row["isFavorite"] as Int) == 1)
            #expect((row["difficulty"] as Int) == 3)
            #expect((row["directions"] as String) == directionsJSON)
        }
    }

    // MARK: - Consolidating duplicate categories / courses / tags

    /// `LibraryDuplicateMerger` re-points recipes before deleting the rows it merges away, so these
    /// run against a real schema with foreign keys on: the `recipe.courseId → course` FK is
    /// ON DELETE SET NULL, which would silently strip courses if the order were ever wrong.
    ///
    /// Note the seeded defaults from migration 0002 (5 categories, 11 courses) are present in every
    /// database here, hence the deliberately distinctive names below.
    @Suite struct DuplicateMerging {

        private func merge(_ db: any DatabaseWriter) async throws -> LibraryDuplicateMerger.Summary {
            try await db.write { database in
                let groups = try LibraryDuplicateMerger.duplicateGroups(in: database)
                return try LibraryDuplicateMerger.merge(groups, in: database)
            }
        }

        @Test func mergesCategoriesAndKeepsEveryRecipeClassified() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO category (id, name) VALUES ('cat-keep', 'Zzz Breads')")
                try db.execute(sql: "INSERT INTO category (id, name) VALUES ('cat-dupe', 'zzz breads')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r1', 'Sourdough')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r2', 'Focaccia')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r3', 'Rye')")
                // Two recipes in the survivor, one only in the duplicate — so the row with the most
                // recipes is the one that remains.
                try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES ('rc1', 'r1', 'cat-keep')")
                try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES ('rc3', 'r3', 'cat-keep')")
                try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES ('rc2', 'r2', 'cat-dupe')")
            }

            let summary = try await merge(db)

            #expect(summary.removedItems == 1)
            #expect(summary.touchedRecipes == 1)   // only r2 changed category

            let remaining = try await db.read {
                try String.fetchAll($0, sql: "SELECT id FROM category WHERE name LIKE 'zzz breads' COLLATE NOCASE")
            }
            #expect(remaining == ["cat-keep"])
            // Every recipe is still classified, now under the surviving row.
            let recipeIds = try await db.read {
                try String.fetchAll($0, sql: "SELECT recipeId FROM recipeCategory WHERE categoryId = 'cat-keep' ORDER BY recipeId")
            }
            #expect(recipeIds == ["r1", "r2", "r3"])
        }

        @Test func doesNotCreateDuplicateJunctionRowsForRecipesInBoth() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO tag (id, name) VALUES ('tag-keep', 'Zzz Vegan')")
                try db.execute(sql: "INSERT INTO tag (id, name) VALUES ('tag-dupe', 'zzz vegan')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r1', 'Dal')")
                // The same recipe carries BOTH tags — the case an unguarded UPDATE would double up.
                try db.execute(sql: "INSERT INTO recipeTag (id, recipeId, tagId) VALUES ('rt1', 'r1', 'tag-keep')")
                try db.execute(sql: "INSERT INTO recipeTag (id, recipeId, tagId) VALUES ('rt2', 'r1', 'tag-dupe')")
            }

            _ = try await merge(db)

            let links = try await db.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM recipeTag WHERE recipeId = 'r1'") ?? 0
            }
            #expect(links == 1)
            let tagCount = try await db.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM tag WHERE name LIKE 'zzz vegan' COLLATE NOCASE") ?? 0
            }
            #expect(tagCount == 1)
        }

        @Test func mergesCoursesWithoutClearingTheRecipesCourse() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO course (id, name) VALUES ('co-keep', 'Zzz Main')")
                try db.execute(sql: "INSERT INTO course (id, name) VALUES ('co-dupe', 'zzz  main')")
                try db.execute(sql: "INSERT INTO recipe (id, name, courseId) VALUES ('r1', 'Stew', 'co-keep')")
                try db.execute(sql: "INSERT INTO recipe (id, name, courseId) VALUES ('r2', 'Roast', 'co-keep')")
                try db.execute(sql: "INSERT INTO recipe (id, name, courseId) VALUES ('r3', 'Pie', 'co-dupe')")
            }

            _ = try await merge(db)

            // The FK is ON DELETE SET NULL: if the delete ran before the re-point, r3 would be NULL here.
            let courseIds = try await db.read {
                try String.fetchAll($0, sql: "SELECT IFNULL(courseId, '') FROM recipe ORDER BY id")
            }
            #expect(courseIds == ["co-keep", "co-keep", "co-keep"])
            let courseCount = try await db.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course WHERE name LIKE 'zzz%main' COLLATE NOCASE") ?? 0
            }
            #expect(courseCount == 1)
        }

        @Test func bumpsLastModifiedDateOnlyForRecipesThatChanged() async throws {
            // Junction rows ride along on the recipe payload when syncing, so a re-pointed recipe that
            // doesn't move its timestamp would never reach other devices.
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO category (id, name) VALUES ('cat-keep', 'Zzz Soups')")
                try db.execute(sql: "INSERT INTO category (id, name) VALUES ('cat-dupe', 'ZZZ SOUPS')")
                for id in ["r-moved", "r-stay", "r-unclassified"] {
                    try db.execute(
                        sql: "INSERT INTO recipe (id, name, lastModifiedDate) VALUES (?, ?, '2020-01-01 00:00:00.000')",
                        arguments: [id, id]
                    )
                }
                // Two recipes keep the survivor ahead on count; only r-moved has to be re-pointed.
                try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES ('rc1', 'r-stay', 'cat-keep')")
                try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES ('rc2', 'r-unclassified', 'cat-keep')")
                try db.execute(sql: "INSERT INTO recipeCategory (id, recipeId, categoryId) VALUES ('rc3', 'r-moved', 'cat-dupe')")
            }

            let summary = try await merge(db)
            #expect(summary.touchedRecipes == 1)

            func lastModified(_ id: String) async throws -> String? {
                try await db.read {
                    try String.fetchOne($0, sql: "SELECT lastModifiedDate FROM recipe WHERE id = ?", arguments: [id])
                }
            }
            #expect(try await lastModified("r-moved") != "2020-01-01 00:00:00.000")
            // Recipes already on the surviving row didn't change, so their timestamps must not move —
            // a blanket touch would push pointless re-uploads of every recipe in the category.
            #expect(try await lastModified("r-stay") == "2020-01-01 00:00:00.000")
            #expect(try await lastModified("r-unclassified") == "2020-01-01 00:00:00.000")
        }

        @Test func leavesDistinctNamesAlone() async throws {
            let db = try makeTestDatabase()
            let categoriesBefore = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM category") ?? 0 }
            let coursesBefore = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course") ?? 0 }

            let summary = try await merge(db)

            // A freshly-seeded library has no duplicates, so a merge run over it must be a no-op.
            #expect(summary.isEmpty)
            #expect(summary.removedItems == 0)
            let categoriesAfter = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM category") ?? 0 }
            let coursesAfter = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course") ?? 0 }
            #expect(categoriesAfter == categoriesBefore)
            #expect(coursesAfter == coursesBefore)
        }

        /// The rule the automatic post-sync pass uses. It must depend only on the id: recipe counts
        /// differ from device to device, so a count-based winner lets two devices disagree about
        /// which row to keep and re-create each other's "duplicate" forever.
        @Test func oldestIdRuleIgnoresRecipeCounts() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO tag (id, name) VALUES ('a-older', 'Zzz Vegan')")
                try db.execute(sql: "INSERT INTO tag (id, name) VALUES ('b-newer', 'zzz vegan')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r1', 'Dal')")
                // Every recipe is on the NEWER row, which the recipe-count rule would keep.
                try db.execute(sql: "INSERT INTO recipeTag (id, recipeId, tagId) VALUES ('rt1', 'r1', 'b-newer')")
            }

            let summary = try await db.write { database in
                try LibraryDuplicateMerger.consolidateDuplicates(in: database)
            }

            #expect(summary.removedItems == 1)
            let remaining = try await db.read {
                try String.fetchAll($0, sql: "SELECT id FROM tag WHERE name LIKE 'zzz vegan' COLLATE NOCASE")
            }
            #expect(remaining == ["a-older"])
            // …and the recipe followed the merge rather than losing its tag.
            let taggedWith = try await db.read {
                try String.fetchAll($0, sql: "SELECT tagId FROM recipeTag WHERE recipeId = 'r1'")
            }
            #expect(taggedWith == ["a-older"])
        }

        @Test func scanReportsRecipeCountsPerRow() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO tag (id, name) VALUES ('tag-a', 'Zzz Quick')")
                try db.execute(sql: "INSERT INTO tag (id, name) VALUES ('tag-b', 'zzz quick')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r1', 'A')")
                try db.execute(sql: "INSERT INTO recipe (id, name) VALUES ('r2', 'B')")
                try db.execute(sql: "INSERT INTO recipeTag (id, recipeId, tagId) VALUES ('rt1', 'r1', 'tag-b')")
                try db.execute(sql: "INSERT INTO recipeTag (id, recipeId, tagId) VALUES ('rt2', 'r2', 'tag-b')")
            }

            let groups = try await db.read { try LibraryDuplicateMerger.duplicateGroups(in: $0) }
            let quick = try #require(groups.first { $0.kind == .tag })

            // tag-b holds both recipes, so it wins despite being the newer row.
            #expect(quick.survivor.id == "tag-b")
            #expect(quick.survivor.recipeCount == 2)
            #expect(quick.duplicates.map(\.recipeCount) == [0])
        }
    }

    // MARK: - Resolving library items by name (the import path)

    /// `LibraryItemResolver` is what keeps an import from creating the duplicates the Consolidate
    /// command would then have to clean up: it matches names the way the editors do rather than
    /// with the exact, case-sensitive comparison the importers used to make inline.
    @Suite struct LibraryItemResolution {

        @Test func reusesAnExistingRowWhoseNameDiffersOnlyInCaseOrSpacing() async throws {
            let db = try makeTestDatabase()
            try await db.write { db in
                try db.execute(sql: "INSERT INTO category (id, name) VALUES ('cat-1', 'Zzz Slow Cooker')")
            }

            let resolved = try await db.write { database in
                try [
                    LibraryItemResolver.resolveId(kind: .category, name: "zzz slow cooker", in: database),
                    LibraryItemResolver.resolveId(kind: .category, name: "  Zzz Slow Cooker  ", in: database),
                    LibraryItemResolver.resolveId(kind: .category, name: "Zzz  Slow  Cooker", in: database),
                ]
            }

            #expect(resolved == ["cat-1", "cat-1", "cat-1"])
            let count = try await db.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM category WHERE name LIKE 'zzz%cooker' COLLATE NOCASE") ?? 0
            }
            #expect(count == 1)
        }

        @Test func createsOneRowForANewNameAndReusesItAfterwards() async throws {
            let db = try makeTestDatabase()

            let first = try await db.write { try LibraryItemResolver.resolveId(kind: .tag, name: " Weeknight ", in: $0) }
            let second = try await db.write { try LibraryItemResolver.resolveId(kind: .tag, name: "WEEKNIGHT", in: $0) }

            #expect(first != nil)
            #expect(first == second)
            // The row stores the trimmed name as given, capitalization intact.
            let name = try await db.read {
                try String.fetchOne($0, sql: "SELECT name FROM tag WHERE id = ?", arguments: [first])
            }
            #expect(name == "Weeknight")
        }

        @Test func blankNamesCreateNothing() async throws {
            let db = try makeTestDatabase()
            let before = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course") ?? 0 }

            let resolved = try await db.write { database in
                try [
                    LibraryItemResolver.resolveId(kind: .course, name: "", in: database),
                    LibraryItemResolver.resolveId(kind: .course, name: "   \n", in: database),
                ]
            }

            #expect(resolved == [nil, nil])
            let after = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course") ?? 0 }
            #expect(after == before)
        }

        /// An import must never produce a library the de-duplication command immediately wants to
        /// merge — the two use the same normalization, and this pins them together.
        @Test func resolvedNamesLeaveNothingForTheMergerToDo() async throws {
            let db = try makeTestDatabase()
            try await db.write { database in
                for name in ["Zzz Grill", "zzz grill", " ZZZ  GRILL "] {
                    _ = try LibraryItemResolver.resolveId(kind: .category, name: name, in: database)
                }
            }

            let groups = try await db.read { try LibraryDuplicateMerger.duplicateGroups(in: $0) }
            #expect(groups.isEmpty)
        }
    }
}
