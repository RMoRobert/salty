//
//  RecipeTombstoneWriter.swift
//  SaltyCore
//
//  Records that a recipe was deleted HERE, so the next sync can say so rather than infer it.
//
//  Why this app writes a table it doesn't read: the `deletedRecipe` table is shared bookkeeping, and
//  the other two clients (Salty.NET, SaltyKMP) consume it. Without a tombstone, a deletion is visible
//  to a peer only as an absence, and an absence is ambiguous — "deleted here" and "never downloaded"
//  look identical. The peer then falls back to comparing the server's timestamp against its own sync
//  watermark, and when the recipe happened to be edited on a third device since that watermark, the
//  guess comes out as "new on the server" and the recipe you deleted is downloaded again.
//
//  That path is live whenever a library folder is shared: delete a recipe in Salty, sync from the .NET
//  client before Salty itself has synced, and it comes back. Writing the tombstone costs one row and
//  closes it.
//
//  Note this is the OTHER half of SHARED-V0005. `syncedModifiedDate` settles "this row is here and not
//  on the server" — is it new, or deleted there? A tombstone settles the mirror question, "this row is
//  on the server and not here" — did I delete it, or have I never seen it? A column cannot answer that
//  one: the row is gone, so there is nothing left to carry a column. The two mechanisms are
//  complementary and neither replaces the other.
//
//  Raw SQL against a GRDB `Database` (like `LibraryClassifierResolver`) so it can be called from inside
//  whatever transaction is already deleting the rows, and driven from the test bundle.
//

import Foundation
import GRDB

public enum RecipeTombstoneWriter {

    /// Records `ids` as deleted on this device, inside the caller's transaction.
    ///
    /// Call it in the SAME `database.write` as the delete: a tombstone without the deletion would ask
    /// the server to remove a recipe that is still here, and a deletion without the tombstone is the
    /// ambiguity this exists to remove.
    ///
    /// The table is created if absent because a Salty-created library has never had one — only the .NET
    /// and KMP clients declare it up front — and the shape matches theirs exactly, including the
    /// ISO-8601 `deletedDate` that SaltyKMP writes.
    ///
    /// Tombstones are transient: every client clears them as soon as it has pushed the deletions to the
    /// server, so the table drains on the next successful sync rather than growing.
    public static func recordDeletions(_ ids: [String], in db: Database) throws {
        let wanted = ids.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !wanted.isEmpty else { return }

        try db.execute(sql: #"""
            CREATE TABLE IF NOT EXISTS "deletedRecipe" (
                "id" TEXT NOT NULL PRIMARY KEY,
                "deletedDate" TEXT NOT NULL
            )
            """#)

        let deletedDate = SyncWireDate.string(from: Date())
        for id in wanted {
            try db.execute(
                sql: #"INSERT OR REPLACE INTO "deletedRecipe" ("id", "deletedDate") VALUES (?, ?)"#,
                arguments: [id, deletedDate]
            )
        }
    }

    /// Convenience for the single-recipe delete paths.
    public static func recordDeletion(_ id: String, in db: Database) throws {
        try recordDeletions([id], in: db)
    }

    /// Ids awaiting a push to the server. The sync pass reads these, deletes them there, then calls
    /// `clear(_:in:)`.
    public static func pending(in db: Database) throws -> [String] {
        let exists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'deletedRecipe'"
        ) ?? 0 > 0
        guard exists else { return [] }

        return try String.fetchAll(db, sql: #"SELECT "id" FROM "deletedRecipe""#)
    }

    /// Forgets tombstones that have been dealt with — pushed to the server, or dropped because the
    /// server's copy turned out to be newer than the deletion.
    public static func clear(_ ids: [String], in db: Database) throws {
        guard !ids.isEmpty else { return }

        let exists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'deletedRecipe'"
        ) ?? 0 > 0
        guard exists else { return }

        for id in ids {
            try db.execute(sql: #"DELETE FROM "deletedRecipe" WHERE "id" = ?"#, arguments: [id])
        }
    }
}
