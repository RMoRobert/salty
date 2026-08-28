//
//  RecipeSyncReconciler.swift
//  Salty
//
//  Pure, I/O-free recipe sync diff. Given the local recipes and the server's full manifest
//  (id + lastModifiedDate for EVERY server recipe), it decides what to upload, download, and delete
//  on each side. Kept free of networking/DB so it can be unit-tested exhaustively. This is the
//  data-loss-critical logic, so it must be correct (see RecipeSyncReconcilerTests).
//
//  IMPORTANT: `server` must be the COMPLETE manifest, not a `modifiedSince` delta. Deletions are
//  detected by absence; running this against a partial list would treat unchanged recipes as deleted.
//

import Foundation

public enum RecipeSyncReconciler {

    /// An (id, lastModifiedDate) pair from either side. A missing server timestamp should be mapped
    /// to `Date.distantPast` by the caller (so it sorts as "older than anything").
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let lastModified: Date

        /// The `lastModifiedDate` this row carried when the two sides last agreed about it, or nil if
        /// they never have (`recipe.syncedModifiedDate`, added in SHARED-V0005). Only meaningful on
        /// LOCAL entries, and only when `plan(tracksAgreement:)` is true.
        public let syncedModified: Date?

        public init(id: String, lastModified: Date, syncedModified: Date? = nil) {
            self.id = id
            self.lastModified = lastModified
            self.syncedModified = syncedModified
        }
    }

    /// The reconciled set of actions, expressed as recipe ids.
    public struct Plan: Equatable, Sendable {
        public var toUpload: [String] = []         // local is new or newer → push to server
        public var toDownload: [String] = []       // server is new or newer → pull to local
        public var toDeleteLocally: [String] = []  // existed before lastSync, now gone on server → delete here
        public var toDeleteOnServer: [String] = [] // existed before lastSync, now gone locally → delete there

        public init() {}
    }

    /// Mirrors the original `syncRecipesWithDeletions` rules exactly:
    /// - On both sides: newer timestamp wins (upload if local newer, download if server newer).
    /// - Only local: first sync / newer-than-lastSync → upload; otherwise it was deleted on the server.
    /// - Only server: first sync / newer-than-lastSync → download; otherwise it was deleted locally.
    /// - No lastSyncDate (and not first sync): conservatively treat the orphan as new (never delete).
    ///
    /// `tracksAgreement` replaces the third rule with a recorded fact rather than a guess about clocks.
    /// Pass it when the local entries carry `syncedModified` (i.e. the library has SHARED-V0005's
    /// `recipe.syncedModifiedDate`). A row that exists here and not on the server is then classified by
    /// whether the two sides ever agreed about it:
    ///
    /// - nil stamp → never been to the server → it is NEW HERE → upload.
    /// - stamp set, row unchanged since → the server had exactly this row and deleted it → delete here.
    /// - stamp set, row CHANGED since → a real delete-vs-edit conflict, resolved the way Salty resolves
    ///   it everywhere: the edit wins → upload.
    ///
    /// Callers must give `lastModified` and `syncedModified` the SAME rounding (`roundedToWireMillis`),
    /// or an unchanged row compares as edited and the delete branch never fires.
    ///
    /// No clock is consulted, which matters because the timestamp rule is wrong in two real cases: when
    /// this device's clock and the server's disagree, and for any row whose `lastModifiedDate` is
    /// genuinely old but has never been anywhere — a recipe imported from a file exported two years ago
    /// reads as "existed before the last sync, gone on the server" and is destroyed.
    ///
    /// Mirror: `SyncReconciler.CreatePlan(tracksAgreement:)` in Salty.NET and `SyncReconciler` in SaltyKMP.
    public static func plan(
        local: [Entry],
        server: [Entry],
        isFirstSync: Bool,
        lastSyncDate: Date?,
        tracksAgreement: Bool = false
    ) -> Plan {
        var plan = Plan()
        let serverById = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let localIds = Set(local.map { $0.id })

        for l in local {
            if let s = serverById[l.id] {
                if l.lastModified > s.lastModified {
                    plan.toUpload.append(l.id)
                } else if s.lastModified > l.lastModified {
                    plan.toDownload.append(l.id)
                }
                // equal timestamps → already in sync, nothing to do
            } else if isFirstSync {
                plan.toUpload.append(l.id)
            } else if tracksAgreement {
                // Still clock-free: both values were written by THIS device (the stamp is a copy of
                // lastModifiedDate taken at agreement time). Callers must give both the same rounding.
                //
                //   nil stamp            → never been to the server → new here → upload.
                //   row changed since    → edited here after the server last had it, and the server has
                //                          since deleted it. Delete-vs-edit is a genuine conflict, and
                //                          everywhere else in Salty an edit beats a delete (the
                //                          tombstone push drops a tombstone whose server copy was
                //                          edited) → upload, resurrecting it WITH the edit.
                //   row unchanged since  → the server had exactly this row and deleted it → delete here.
                //
                // `!=` rather than `>` on purpose: any difference means "changed since agreement", so a
                // clock that ran backwards errs toward upload — the non-destructive direction.
                if l.syncedModified == nil || l.lastModified != l.syncedModified {
                    plan.toUpload.append(l.id)
                } else {
                    plan.toDeleteLocally.append(l.id)
                }
            } else if let lastSync = lastSyncDate {
                if l.lastModified > lastSync {
                    plan.toUpload.append(l.id)        // created after last sync → new local
                } else {
                    plan.toDeleteLocally.append(l.id) // existed before last sync, gone on server
                }
            } else {
                plan.toUpload.append(l.id)
            }
        }

        for s in server where !localIds.contains(s.id) {
            if isFirstSync {
                plan.toDownload.append(s.id)
            } else if let lastSync = lastSyncDate {
                if s.lastModified > lastSync {
                    plan.toDownload.append(s.id)         // created after last sync → new on server
                } else {
                    plan.toDeleteOnServer.append(s.id)   // existed before last sync, gone locally
                }
            } else {
                plan.toDownload.append(s.id)
            }
        }

        return plan
    }
}
