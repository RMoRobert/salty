//
//  ClassifierAgreementStore.swift
//  SaltyCore
//
//  SHARED-V0006: `RecipeAgreementStore`'s bookkeeping, extended to `category`, `course` and `tag`.
//
//  Recipes stopped guessing in V0005; the library tables kept guessing until now. A classifier that
//  exists here and not on the server was classified by comparing its timestamp to the sync watermark,
//  and that comparison is wrong whenever this device's clock and the server's disagree, or whenever a
//  row was created while the previous sync was still running — after its entries were read, before the
//  server stamped the watermark. The row then read as "existed before the last sync, gone on the
//  server" and was DELETED, cascading its junction rows, so recipes silently lost their filing.
//
//  Deliberately NOT a property on `Course`/`Category`/`Tag`, for the reason spelled out in
//  `RecipeAgreementStore`: a rename must never write it, and putting it on the struct would mean every
//  update carried whatever value happened to be in memory.
//
//  Mirror: `SyncLocalStore.MarkOrganizersSyncedAsync` in Salty.NET, `LocalStore.markCoursesAgreed` and
//  siblings in SaltyKMP.
//

import Foundation
import GRDB

public enum ClassifierAgreementStore {

    /// The three tables this covers. Interpolated into SQL below, so it is a fixed list of literals —
    /// never a caller-supplied name.
    public enum Table: String, CaseIterable, Sendable {
        case category
        case course
        case tag
    }

    /// True when this library has run SHARED-V0006. A library another client has not migrated yet reads
    /// as false, and that table falls back to the watermark rule — exactly what happened before.
    public static func isAvailable(_ table: Table, in db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = 'syncedModifiedDate'",
            arguments: [table.rawValue]
        ) ?? 0 > 0
    }

    /// Agreement stamps for one table, keyed by id. Rows with no stamp are absent, which the caller
    /// reads as "never agreed".
    public static func stamps(_ table: Table, in db: Database) throws -> [String: Date] {
        guard try isAvailable(table, in: db) else { return [:] }

        var stamps: [String: Date] = [:]
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT "id", "syncedModifiedDate" FROM "\(table.rawValue)" \
                WHERE "syncedModifiedDate" IS NOT NULL
                """
        )
        for row in rows {
            let id: String = row["id"]
            if let date: Date = row["syncedModifiedDate"] {
                stamps[id] = date
            }
        }
        return stamps
    }

    /// Records that these rows now match the server, at whatever `lastModifiedDate` they carry.
    ///
    /// The rules of `RecipeAgreementStore.markAgreed` apply unchanged — most importantly, call it only
    /// for rows that actually made it. Stamping one that never reached the server would tell the next
    /// sync the server has a copy it does not, and that row would be deleted here instead of retried.
    public static func markAgreed(_ table: Table, _ ids: [String], in db: Database) throws {
        guard !ids.isEmpty, try isAvailable(table, in: db) else { return }

        for id in ids {
            try db.execute(
                sql: """
                    UPDATE "\(table.rawValue)" SET "syncedModifiedDate" = "lastModifiedDate" WHERE "id" = ?
                    """,
                arguments: [id]
            )
        }
    }

    /// Marks every classifier row agreed, for the force paths where both sides mirror by construction.
    /// See `RecipeAgreementStore.markAllAgreed`.
    public static func markAllAgreed(in db: Database) throws {
        for table in Table.allCases where try isAvailable(table, in: db) {
            try db.execute(
                sql: #"UPDATE "\#(table.rawValue)" SET "syncedModifiedDate" = "lastModifiedDate""#
            )
        }
    }
}
