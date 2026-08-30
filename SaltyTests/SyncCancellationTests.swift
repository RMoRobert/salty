//
//  SyncCancellationTests.swift
//  SaltyTests
//
//  Covers the pieces that keep a user-initiated cancel out of the error paths: a cancel must not surface
//  as a red "Couldn't reach the server" in Settings, and must not count toward the auto-sync failure
//  banner. Also covers the persistence of the last successful sync time across launches.
//

import Testing
import Foundation
@testable import Salty

struct SyncCancellationClassificationTests {

    @Test func recognizesSwiftTaskCancellation() {
        #expect(SyncError.isCancellation(CancellationError()))
    }

    /// The form the cancel actually arrives in most of the time: URLSession aborting its in-flight request.
    @Test func recognizesCancelledURLRequest() {
        #expect(SyncError.isCancellation(URLError(.cancelled)))
    }

    @Test func recognizesOwnNormalizedCase() {
        #expect(SyncError.isCancellation(SyncError.cancelled))
    }

    @Test func doesNotMistakeRealFailuresForCancellation() {
        #expect(!SyncError.isCancellation(URLError(.notConnectedToInternet)))
        #expect(!SyncError.isCancellation(URLError(.timedOut)))
        #expect(!SyncError.isCancellation(SyncError.serverNotConfigured))
        #expect(!SyncError.isCancellation(SyncError.uploadFailed("boom")))
    }

    /// `URLError.cancelled` would otherwise fall through to the generic "Couldn't reach the server"
    /// wording, blaming the network for something the user chose to do.
    @Test func cancellationMessageDoesNotBlameTheNetwork() {
        let message = friendlySyncMessage(URLError(.cancelled))
        #expect(message.localizedStandardContains("cancelled"))
        #expect(!message.localizedStandardContains("reach the server"))
        #expect(friendlySyncMessage(SyncError.cancelled) == message)
    }

    @Test func genuineConnectivityFailuresKeepTheirWording() {
        #expect(friendlySyncMessage(URLError(.notConnectedToInternet))
                    .localizedStandardContains("No internet connection"))
    }
}

@MainActor
@Suite(.serialized)
struct SyncCancelStateTests {

    /// Nothing to cancel: the button state must not latch on, or the UI would show "Cancelling..." forever.
    @Test func cancellingWhenIdleIsANoOp() {
        let service = SaltySyncService(session: .shared, credentials: InMemorySyncCredentialStore())
        #expect(!service.isCancellable)
        service.cancelSync()
        #expect(!service.isCancelling)
    }

    /// The last successful sync time survives a relaunch (a fresh instance reads it back).
    @Test func lastSyncDateRoundTripsThroughUserDefaults() {
        let key = "lastSuccessfulSyncDate"
        let saved = UserDefaults.standard.object(forKey: key) as? Date
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let service = SaltySyncService(session: .shared, credentials: InMemorySyncCredentialStore())
        let stamp = Date(timeIntervalSince1970: 1_773_671_400)
        service.lastSyncDate = stamp

        let relaunched = SaltySyncService(session: .shared, credentials: InMemorySyncCredentialStore())
        #expect(relaunched.lastSyncDate == stamp)
    }
}
