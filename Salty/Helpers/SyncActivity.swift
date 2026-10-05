//
//  SyncActivity.swift
//  Salty
//
//  Whether a sync is running, readable from any thread.
//

import Synchronization

/// Mirrors `SaltySyncService.isSyncing` behind a lock, for callers that can't wait for the main actor:
/// the database observer that tells sync's own writes apart from the user's runs on GRDB's writer
/// queue and must decide at commit time.
final class SyncActivity: Sendable {
    private let state = Mutex(false)

    var isSyncing: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
