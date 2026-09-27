//
//  ClassifierTombstoneWriter.swift
//  SaltyCore
//
//  `RecipeTombstoneWriter`, extended to categories, courses and tags: records that one was deleted
//  HERE, so the next sync deletes it on the server as a recorded fact instead of inferring it.
//
//  Same rule as recipes (SYNC-008/SYNC-021): an absence alone never deletes anything on the server —
//  it can't tell "deleted here" from "never had it" (a restored backup, another app's file, a peer's
//  slow clock). A tombstoned row is deleted there; any other server-only row is downloaded.
//
//  Same shape as `deletedRecipe`, one table per classifier (`deletedCategory`, `deletedCourse`,
//  `deletedTag`), created on demand.
//
//  Write tombstones only for a deletion made HERE on purpose — the editor, a merge. Never for a
//  deletion sync itself applies, and never for the force re-sync's wipe: those follow the server, and
//  a tombstone would echo them back to it.
//

import Foundation
import GRDB

public enum ClassifierTombstoneWriter {

    /// Records `ids` as deleted on this device, inside the caller's transaction — the SAME
    /// `database.write` as the delete, for the reasons `RecipeTombstoneWriter.recordDeletions` gives.
    public static func recordDeletions(
        _ kind: LibraryClassifier, _ ids: some Sequence<String>, in db: Database
    ) throws {
        let wanted = ids.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !wanted.isEmpty else { return }

        try db.execute(sql: #"""
            CREATE TABLE IF NOT EXISTS "\#(tableName(kind))" (
                "id" TEXT NOT NULL PRIMARY KEY,
                "deletedDate" TEXT NOT NULL
            )
            """#)

        let deletedDate = SyncWireDate.string(from: Date())
        for id in wanted {
            try db.execute(
                sql: #"INSERT OR REPLACE INTO "\#(tableName(kind))" ("id", "deletedDate") VALUES (?, ?)"#,
                arguments: [id, deletedDate]
            )
        }
    }

    /// Ids of this kind awaiting a delete on the server.
    public static func pending(_ kind: LibraryClassifier, in db: Database) throws -> Set<String> {
        guard try tableExists(kind, in: db) else { return [] }
        return Set(try String.fetchAll(db, sql: #"SELECT "id" FROM "\#(tableName(kind))""#))
    }

    /// Forgets tombstones that have been dealt with: deleted on the server, dropped because the server's
    /// copy changed after the delete, or stale (the row is back here, or already gone there).
    public static func clear(
        _ kind: LibraryClassifier, _ ids: some Sequence<String>, in db: Database
    ) throws {
        guard try tableExists(kind, in: db) else { return }
        for id in ids {
            try db.execute(sql: #"DELETE FROM "\#(tableName(kind))" WHERE "id" = ?"#, arguments: [id])
        }
    }

    /// Forgets every pending classifier deletion — for the force re-syncs, after which one side is an
    /// exact copy of the other and there is nothing left to tell the server.
    public static func clearAll(in db: Database) throws {
        for kind in LibraryClassifier.allCases where try tableExists(kind, in: db) {
            try db.execute(sql: #"DELETE FROM "\#(tableName(kind))""#)
        }
    }

    // MARK: - Private

    /// A fixed literal per kind, since it is interpolated into SQL.
    private static func tableName(_ kind: LibraryClassifier) -> String {
        switch kind {
        case .category: return "deletedCategory"
        case .course: return "deletedCourse"
        case .tag: return "deletedTag"
        }
    }

    private static func tableExists(_ kind: LibraryClassifier, in db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            arguments: [tableName(kind)]
        ) ?? 0 > 0
    }
}
