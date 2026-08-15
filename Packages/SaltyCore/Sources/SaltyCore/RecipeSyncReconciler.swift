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

        public init(id: String, lastModified: Date) {
            self.id = id
            self.lastModified = lastModified
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
    public static func plan(local: [Entry], server: [Entry], isFirstSync: Bool, lastSyncDate: Date?) -> Plan {
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
