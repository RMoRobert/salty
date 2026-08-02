// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

//
//  ManualSyncRunner.swift
//  Salty
//
//  Shared entry point for the lightweight user-initiated sync triggers: pull-to-refresh, the
//  "Last synced" footer rows, and the Sync Now menu command. (Settings' own Sync Now keeps its
//  richer flow -- it forces past the recently-synced guard and reports success explicitly.)
//
//  Quiet by design: benign outcomes -- already syncing, synced moments ago, sync not set up,
//  user cancelled -- end without comment, because the "Last synced" footer already tells that
//  story. Real failures set `errorMessage`, which drives a single alert bound in
//  RecipeNavigationSplitView no matter which trigger started the sync.
//

import Foundation
import Observation

@MainActor
@Observable
final class ManualSyncRunner {
    static let shared = ManualSyncRunner()

    /// Non-nil when the last user-initiated sync failed. The alert observing this clears it on dismiss.
    var errorMessage: String?

    func sync() async {
        do {
            try await SaltySyncService.shared.syncNow()
        } catch SyncError.throttled, SyncError.serverNotConfigured {
            // Throttled: already up to date moments ago. Not configured: the pull gesture exists even
            // when sync is off (the footer doesn't), so it has to end silently rather than scold.
        } catch let error where SyncError.isCancellation(error) {
            // The user stopped it from Settings; their choice, not a failure.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
