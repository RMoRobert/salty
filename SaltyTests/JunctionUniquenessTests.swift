//
//  JunctionUniquenessTests.swift
//  SaltyTests
//
//  Forward-compatibility for the `UNIQUE (recipeId, categoryId)` index the junction tables do not have
//  yet (ID-006 in salty-contract/SPEC.md).
//
//  Adding that index is only safe if every junction insert tolerates a conflict on the pair. Salty
//  cannot express that in SQL: a conflict target must name an index that already exists, so the pair
//  cannot be targeted before the index lands, and StructuredQueries deprecated `insert(or: .ignore)`
//  after 0.24.0. `insertIfAbsent` checks first instead, which needs no library support.
//
//  These tests create the index up front and drive the real helper, so "adding it later is safe" is
//  checked rather than asserted -- and the contrast test pins the reason the helper exists at all.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct JunctionUniquenessTests {

    /// A migrated in-memory library carrying the pair index this schema does not ship yet, plus one
    /// recipe and one category to file it under.
    private func library() throws -> (queue: DatabaseQueue, recipeId: String, categoryId: String) {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        try queue.write { db in
            try db.execute(sql: #"""
                CREATE UNIQUE INDEX "recipeCategory_pair" ON "recipeCategory" ("recipeId", "categoryId")
                """#)
        }

        let recipeId = SaltyId.new()
        let categoryId = SaltyId.new()
        try queue.write { db in
            try db.execute(sql: #"INSERT INTO "recipe" ("id", "name") VALUES (?, ?)"#,
                           arguments: [recipeId, "Bread"])
            try db.execute(sql: #"INSERT INTO "category" ("id", "name") VALUES (?, ?)"#,
                           arguments: [categoryId, "Baking"])
        }
        return (queue, recipeId, categoryId)
    }

    private func linkCount(_ queue: DatabaseQueue, _ recipeId: String) throws -> Int {
        try queue.read { db in
            try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "recipeCategory" WHERE "recipeId" = ?"#,
                             arguments: [recipeId]) ?? 0
        }
    }

    @Test("filing a recipe under the same category twice is a no-op, not a constraint violation")
    func insertIfAbsentToleratesADuplicatePair() throws {
        let (queue, recipeId, categoryId) = try library()

        let (first, second) = try queue.write { db in
            (
                try RecipeCategory.insertIfAbsent(
                    RecipeCategory(id: SaltyId.new(), recipeId: recipeId, categoryId: categoryId),
                    in: db
                ),
                try RecipeCategory.insertIfAbsent(
                    RecipeCategory(id: SaltyId.new(), recipeId: recipeId, categoryId: categoryId),
                    in: db
                )
            )
        }

        #expect(first, "the first filing inserts and says so")
        #expect(!second, "the duplicate is skipped and reported as such")
        #expect(try linkCount(queue, recipeId) == 1)
    }

    /// The contrast, and the reason `insertIfAbsent` exists: an unguarded insert violates the pair
    /// index once it is present. Each row carries a fresh id, so the primary key never collides — it is
    /// the PAIR that is violated, and nothing in a plain INSERT absorbs it.
    ///
    /// Asserted through raw SQL so the expectation observes SQLite's own error. Going through
    /// `RecipeCategory.insert {}` here does not surface a catchable `DatabaseError`: it reports the
    /// failure through the query library's issue-reporting path, which terminates the test process
    /// rather than throwing. Worth knowing on its own — a constraint violation on that path will not be
    /// caught by a `do`/`catch` around it.
    @Test("an unguarded insert would throw once the pair index exists")
    func anUnguardedInsertIsWhatTheIndexWouldHaveBroken() throws {
        let (queue, recipeId, categoryId) = try library()

        try queue.write { db in
            try RecipeCategory.insertIfAbsent(
                RecipeCategory(id: SaltyId.new(), recipeId: recipeId, categoryId: categoryId),
                in: db
            )
        }

        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(
                    sql: #"INSERT INTO "recipeCategory" ("id", "recipeId", "categoryId") VALUES (?, ?, ?)"#,
                    arguments: [SaltyId.new(), recipeId, categoryId]
                )
            }
        }

        #expect(try linkCount(queue, recipeId) == 1)
    }
}
