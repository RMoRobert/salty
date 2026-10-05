//
//  AgreementStoreTests.swift
//  SaltyTests
//
//  `RecipeAgreementStore` and `ClassifierAgreementStore` directly: nothing is available before the
//  shared migrations add their columns (and every call is then a quiet no-op), a stamp copies the
//  row's `lastModifiedDate` at the database's millisecond resolution, and `markAllAgreed` covers
//  every row after a force pull.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct AgreementStoreTests {
    private let t1 = SyncTestClock.t1
    private let t2 = SyncTestClock.t2

    private func baseLibrary() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        return queue
    }

    // MARK: - Before the shared migrations

    @Test func nothingIsAvailableBeforeTheSharedMigrations() throws {
        let queue = try baseLibrary()
        try queue.write { db in
            // The base schema predates the shared migrations entirely (no prepared stamp either), so
            // the row is seeded by hand.
            try db.execute(
                sql: #"INSERT INTO "recipe" ("id", "name", "lastModifiedDate") VALUES ('r1', 'Loaf', ?)"#,
                arguments: [t1]
            )
            #expect(try !RecipeAgreementStore.isAvailable(in: db))
            #expect(try RecipeAgreementStore.stamps(in: db).isEmpty)
            // Both writes are no-ops rather than failures against a column that isn't there.
            try RecipeAgreementStore.markAgreed(["r1"], in: db)
            try RecipeAgreementStore.markAllAgreed(in: db)
            #expect(try RecipeAgreementStore.stamps(in: db).isEmpty)
            for table in ClassifierAgreementStore.Table.allCases {
                #expect(try !ClassifierAgreementStore.isAvailable(table, in: db))
                #expect(try ClassifierAgreementStore.stamps(table, in: db).isEmpty)
            }
            try ClassifierAgreementStore.markAllAgreed(in: db)
        }
    }

    // MARK: - Recipes

    @Test func markAgreedCopiesTheStampAtWireResolution() throws {
        let queue = try makeSyncTestLibrary()
        // A stamp with sub-millisecond precision: the column holds milliseconds, so the agreement
        // stamp must compare equal to the rounded value, never to the raw one.
        let fine = t1.addingTimeInterval(0.000_4)
        try queue.write { db in
            try RecipeWriter.save(Recipe(id: "r1", name: "Loaf", lastModifiedDate: fine), in: db, now: fine)
            try RecipeWriter.save(Recipe(id: "r2", name: "Rolls", lastModifiedDate: t2), in: db, now: t2)
            #expect(try RecipeAgreementStore.isAvailable(in: db))
            #expect(try RecipeAgreementStore.stamps(in: db).isEmpty, "nothing agreed yet")

            try RecipeAgreementStore.markAgreed(["r1"], in: db)

            let stamps = try RecipeAgreementStore.stamps(in: db)
            #expect(stamps.count == 1)
            #expect(stamps["r1"] == t1.roundedToWireMillis)
            #expect(stamps["r2"] == nil)
        }
    }

    @Test func markAgreedWithAnUnknownIdChangesNothing() throws {
        let queue = try makeSyncTestLibrary()
        try queue.write { db in
            try RecipeWriter.save(Recipe(id: "r1", name: "Loaf", lastModifiedDate: t1), in: db, now: t1)
            try RecipeAgreementStore.markAgreed(["ghost"], in: db)
            try RecipeAgreementStore.markAgreed([], in: db)
            #expect(try RecipeAgreementStore.stamps(in: db).isEmpty)
        }
    }

    @Test func markAllAgreedStampsEveryRecipe() throws {
        let queue = try makeSyncTestLibrary()
        try queue.write { db in
            try RecipeWriter.save(Recipe(id: "r1", name: "Loaf", lastModifiedDate: t1), in: db, now: t1)
            try RecipeWriter.save(Recipe(id: "r2", name: "Rolls", lastModifiedDate: t2), in: db, now: t2)

            try RecipeAgreementStore.markAllAgreed(in: db)

            #expect(try RecipeAgreementStore.stamps(in: db) == ["r1": t1, "r2": t2])
        }
    }

    // MARK: - Classifiers

    @Test func classifierStampsAreKeptPerTable() throws {
        let queue = try makeSyncTestLibrary()
        try seedClassifier("category", id: "c1", name: "Bread", modified: t1, in: queue)
        try seedClassifier("course", id: "k1", name: "Dinner", modified: t1, in: queue)
        try seedClassifier("tag", id: "g1", name: "quick", modified: t2, in: queue)
        try queue.write { db in
            for table in ClassifierAgreementStore.Table.allCases {
                #expect(try ClassifierAgreementStore.isAvailable(table, in: db))
            }

            try ClassifierAgreementStore.markAgreed(.category, ["c1"], in: db)

            #expect(try ClassifierAgreementStore.stamps(.category, in: db) == ["c1": t1])
            #expect(try ClassifierAgreementStore.stamps(.course, in: db).isEmpty, "the same id in another table is untouched")
            #expect(try ClassifierAgreementStore.stamps(.tag, in: db).isEmpty)
        }
    }

    @Test func markAllAgreedCoversEveryClassifierTable() throws {
        let queue = try makeSyncTestLibrary()
        try seedClassifier("category", id: "c1", name: "Bread", modified: t1, in: queue)
        try seedClassifier("course", id: "k1", name: "Dinner", modified: t1, in: queue)
        try seedClassifier("tag", id: "g1", name: "quick", modified: t2, in: queue)
        try queue.write { db in
            try ClassifierAgreementStore.markAllAgreed(in: db)
            #expect(try ClassifierAgreementStore.stamps(.category, in: db) == ["c1": t1])
            #expect(try ClassifierAgreementStore.stamps(.course, in: db) == ["k1": t1])
            #expect(try ClassifierAgreementStore.stamps(.tag, in: db) == ["g1": t2])
        }
    }
}
