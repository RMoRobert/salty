//
//  SaltySharedMigrationTests.swift
//  SaltyTests
//
//  Pins the cross-platform `saltyMigration` ledger: a shared change runs exactly once per DB, and is
//  skipped if the OTHER app (SaltyKMP) already recorded it. Mirror of SaltyKMP's DatabaseMigrationTest.
//  Assertions are by DB side-effect (a re-run of `ADD COLUMN` would throw "duplicate column"), so a
//  passing run-twice proves run-once without any captured mutable state.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

struct SaltySharedMigrationTests {

    private func columnExists(_ writer: any DatabaseWriter, table: String, column: String) throws -> Bool {
        try writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?",
                arguments: [table, column]
            ) ?? 0 > 0
        }
    }

    @Test func appliesOnceRecordsThenSkipsOnNextOpen() throws {
        let dbQueue = try DatabaseQueue() // in-memory
        try dbQueue.write { try $0.execute(sql: #"CREATE TABLE "x" ("id" TEXT)"#) }
        let migrations = [
            SaltySharedMigration(id: "test:add-prep-notes") { db in
                try db.execute(sql: #"ALTER TABLE "x" ADD COLUMN "prepNotes" TEXT"#)
            }
        ]

        try runSaltySharedMigrations(dbQueue, migrations)
        #expect(try columnExists(dbQueue, table: "x", column: "prepNotes"))
        let recorded = try dbQueue.read { db in
            try Int.fetchOne(db, sql: #"SELECT 1 FROM "saltyMigration" WHERE "identifier" = ?"#,
                             arguments: ["test:add-prep-notes"]) != nil
        }
        #expect(recorded)

        // Second open must NOT re-run — a repeated ADD COLUMN would throw "duplicate column name".
        try runSaltySharedMigrations(dbQueue, migrations)
    }

    @Test func skipsMigrationAlreadyRecordedByTheKmpApp() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.execute(sql: #"CREATE TABLE "x" ("id" TEXT)"#)
            // Simulate SaltyKMP having applied + recorded the shared migration first.
            try db.execute(sql: """
                CREATE TABLE "saltyMigration" (
                    "identifier" TEXT NOT NULL PRIMARY KEY, "platform" TEXT, "appliedDate" TEXT NOT NULL
                )
                """)
            try db.execute(sql: #"INSERT INTO "saltyMigration" VALUES ('shared:1', 'kmp', '2026-01-01T00:00:00.000Z')"#)
        }
        let migrations = [
            SaltySharedMigration(id: "shared:1") { db in
                try db.execute(sql: #"ALTER TABLE "x" ADD COLUMN "shouldNotAppear" TEXT"#)
            }
        ]

        try runSaltySharedMigrations(dbQueue, migrations)

        // KMP already recorded it → this app must skip, so the column is never added.
        #expect(try !columnExists(dbQueue, table: "x", column: "shouldNotAppear"))
    }

    @Test func createsLedgerTableEvenWithNoMigrations() throws {
        let dbQueue = try DatabaseQueue()
        try runSaltySharedMigrations(dbQueue, [])
        let exists = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='saltyMigration'") != nil
        }
        #expect(exists)
    }

    /// The real SHARED-V0003 entry: on a DB predating it, both sync-bookkeeping columns are added at
    /// the END of `shoppingList` (positional `SELECT *` compat with KMP), and the ledger makes the
    /// re-run a no-op — a repeated ADD COLUMN would throw "duplicate column name". Runs the full
    /// production array so the ordering/interplay of the shipped entries is what's exercised.
    @Test func sharedV0003AddsSyncBookkeepingColumnsOnceToAPreexistingDb() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            // Minimal pre-V0003 shapes: just enough of `recipe` for the image-date entry's ALTER, and
            // the `shoppingList` shape SHARED-V0002 leaves behind.
            try db.execute(sql: #"CREATE TABLE "recipe" ("id" TEXT)"#)
            try db.execute(sql: """
                CREATE TABLE "shoppingList" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "name" TEXT,
                    "isFreeform" BOOLEAN,
                    "contentsForFreeform" TEXT,
                    "contentsForList" TEXT,
                    "lastModifiedDate" DATETIME
                )
                """)
        }

        try runSaltySharedMigrations(dbQueue)
        #expect(try columnExists(dbQueue, table: "shoppingList", column: "syncedRevision"))
        #expect(try columnExists(dbQueue, table: "shoppingList", column: "syncedSnapshot"))
        // Appended LAST, in migration order — the cross-platform positional contract.
        let columns = try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('shoppingList') ORDER BY cid")
        }
        #expect(columns.suffix(2) == ["syncedRevision", "syncedSnapshot"])

        // Second open must NOT re-run.
        try runSaltySharedMigrations(dbQueue)
    }

    /// A KMP-created DB already has the columns (fresh Schema.sq CREATE) but no ledger row for this
    /// app to skip on — the per-column guard is what keeps the ALTER from throwing.
    @Test func sharedV0003IsANoOpWhenTheColumnsAlreadyExist() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.execute(sql: #"CREATE TABLE "recipe" ("id" TEXT, "lastModifiedImageDate" DATETIME)"#)
            try db.execute(sql: """
                CREATE TABLE "shoppingList" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "name" TEXT,
                    "isFreeform" BOOLEAN,
                    "contentsForFreeform" TEXT,
                    "contentsForList" TEXT,
                    "lastModifiedDate" DATETIME,
                    "syncedRevision" INTEGER,
                    "syncedSnapshot" TEXT
                )
                """)
        }

        try runSaltySharedMigrations(dbQueue)

        let recorded = try dbQueue.read { db in
            try Int.fetchOne(db, sql: #"SELECT 1 FROM "saltyMigration" WHERE "identifier" = 'SHARED-V0003'"#) != nil
        }
        #expect(recorded)
    }
}
