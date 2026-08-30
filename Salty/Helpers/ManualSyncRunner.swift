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
//  One outcome is neither: a sync that stopped because this device isn't enrolled with the server.
//  That is a question, not a failure, so it raises `needsEnrolment` instead of `errorMessage` and
//  MainView answers it with the one-time username/password sheet.
//

import Foundation
import Observation

@MainActor
@Observable
final class ManualSyncRunner {
    static let shared = ManualSyncRunner()

    /// Non-nil when the last user-initiated sync failed. The alert observing this clears it on dismiss.
    var errorMessage: String?

    /// True when a sync stopped because this device holds no usable sync token -- a first sync, or one
    /// after the token was revoked. Drives the enrolment sheet MainView presents.
    ///
    /// Only ever set from a user-initiated sync: the user just asked for this, so a prompt is an answer
    /// rather than an interruption. Auto-sync deliberately never raises it (see `AutoSyncCoordinator`).
    var needsEnrolment = false

    func sync() async {
        do {
            try await SaltySyncService.shared.syncNow()
        } catch SyncError.throttled, SyncError.serverNotConfigured {
            // Throttled: already up to date moments ago. Not configured: the pull gesture exists even
            // when sync is off (the footer doesn't), so it has to end silently rather than scold.
        } catch SyncError.enrolmentRequired, SyncError.credentialsNotConfigured {
            // Answerable, so ask instead of reporting. `credentialsNotConfigured` lands here too: it now
            // means the same thing -- no token and no saved password to enrol with.
            needsEnrolment = true
        } catch let error where SyncError.isCancellation(error) {
            // The user stopped it from Settings; their choice, not a failure.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Connects this device with the password from the prompt, then runs the sync it was blocking.
    ///
    /// A failure here reports through `errorMessage` like any other sync failure, rather than through a
    /// prompt-specific channel: from the user's side "couldn't reach the server" means the same thing
    /// whether it happened while connecting or while syncing.
    func connectAndSync(password: String) async {
        let syncService = SaltySyncService.shared
        do {
            try await syncService.enroll(username: syncService.serverUsername, password: password)
        } catch {
            errorMessage = friendlySyncMessage(error)
            return
        }
        await sync()
    }
}
