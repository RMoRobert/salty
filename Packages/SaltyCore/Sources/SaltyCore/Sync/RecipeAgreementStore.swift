//
//  RecipeAgreementStore.swift
//  SaltyCore
//
//  Reads and writes `recipe.syncedModifiedDate` (SHARED-V0005): the value of `lastModifiedDate` a row
//  carried the last time this library and the server agreed about it. NULL means they never have.
//
//  What it buys: sync no longer has to GUESS whether a recipe that exists here and not on the server is
//  a creation or a deletion. That guess was made by comparing the row's timestamp to the sync
//  watermark, and it is wrong in two real cases — when this device's clock and the server's disagree,
//  and for any row whose `lastModifiedDate` is genuinely old but has never been anywhere. A recipe
//  imported from a file exported two years ago is the second case, and the old rule deleted it.
//
//  Deliberately NOT a property on `Recipe`. It belongs to the sync pass the way `syncedRevision` belongs
//  to the shopping-list pass: a body save must never write it, and putting it on the struct would mean
//  every `Recipe.update` carried whatever value happened to be in memory. Raw SQL, like
//  `LibraryClassifierResolver` and `RecipeTombstoneWriter`, so it can also be driven from tests.
//
//  Mirror: `SyncLocalStore.MarkRecipesSyncedAsync` in Salty.NET, and the same column in SaltyKMP.
//

import Foundation
import GRDB

public enum RecipeAgreementStore {

    /// True when this library has run SHARED-V0005. A library another client hasn't migrated yet reads
    /// as false, and everything falls back to the old timestamp rule — which is exactly what happened
    /// before the column existed.
    public static func isAvailable(in db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM pragma_table_info('recipe') WHERE name = 'syncedModifiedDate'"
        ) ?? 0 > 0
    }

    /// The agreement stamp for every recipe that has one, keyed by id. Rows with no stamp are simply
    /// absent, which is what the reconciler reads as "never agreed".
    public static func stamps(in db: Database) throws -> [String: Date] {
        guard try isAvailable(in: db) else { return [:] }

        var stamps: [String: Date] = [:]
        let rows = try Row.fetchAll(
            db,
            sql: #"SELECT "id", "syncedModifiedDate" FROM "recipe" WHERE "syncedModifiedDate" IS NOT NULL"#
        )
        for row in rows {
            let id: String = row["id"]
            if let date: Date = row["syncedModifiedDate"] {
                stamps[id] = date
            }
        }
        return stamps
    }

    /// Records that these recipes now match the server, at whatever `lastModifiedDate` they carry.
    ///
    /// One statement for uploads, downloads and rows that were already identical, because all three mean
    /// the same thing afterwards. Call it only for recipes that actually made it: stamping one that
    /// never reached the server would tell the next sync the server has a copy it does not, and that row
    /// would be deleted locally instead of retried.
    public static func markAgreed(_ ids: [String], in db: Database) throws {
        guard !ids.isEmpty, try isAvailable(in: db) else { return }

        for id in ids {
            try db.execute(
                sql: #"UPDATE "recipe" SET "syncedModifiedDate" = "lastModifiedDate" WHERE "id" = ?"#,
                arguments: [id]
            )
        }
    }

    /// Marks the whole library as agreed. For the force pull, where every row came from the server
    /// moments ago and the two sides match by construction; saying so stops the next ordinary sync from
    /// reading the restored library as never-agreed and uploading all of it back.
    public static func markAllAgreed(in db: Database) throws {
        guard try isAvailable(in: db) else { return }

        try db.execute(sql: #"UPDATE "recipe" SET "syncedModifiedDate" = "lastModifiedDate""#)
    }
}
