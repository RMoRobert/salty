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
import SaltyCore

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

    /// A cancel mid-sync stops it as a cancel, not a failure, and the display ends on "Sync cancelled".
    ///
    /// The engine owns the progress display, so it must be told "Cancelling..." before the cancel, or that
    /// label could overtake the engine's own "Sync cancelled".
    @Test func cancellingARunningSyncStopsItQuietly() async throws {
        let keys = ["serverUrl", "serverUse", "serverUsername"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        UserDefaults.standard.set("https://stub.local", forKey: "serverUrl")
        UserDefaults.standard.set(true, forKey: "serverUse")
        UserDefaults.standard.set("tester", forKey: "serverUsername")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingDeviceRegistrationURLProtocol.self]
        let service = SaltySyncService(
            session: URLSession(configuration: config),
            credentials: InMemorySyncCredentialStore(deviceToken: "salty_test", deviceId: "TEST-DEVICE-CANCEL")
        )

        let sync = Task { try await service.syncNow(force: true) }

        // Wait for the sync to be parked on the request that never answers.
        let deadline = ContinuousClock.now + .seconds(10)
        while service.syncProgress.currentStep != "Registering device...", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(service.syncProgress.currentStep == "Registering device...")
        #expect(service.isCancellable)

        service.cancelSync()
        #expect(service.isCancelling)

        do {
            try await sync.value
            Issue.record("the sync finished instead of being cancelled")
        } catch SyncError.cancelled {
            // Expected: normalised from URLSession's cancelled request.
        } catch {
            Issue.record("expected SyncError.cancelled, got \(error)")
        }

        #expect(service.syncProgress.currentStep == "Sync cancelled")
        #expect(service.lastSyncError == nil, "a cancel is not a failure to report")
        #expect(!service.isSyncing)
        #expect(!service.isCancelling)
        #expect(!service.isCancellable)
    }
}

/// Answers the token check, then holds device registration open until the request is cancelled -- a sync
/// parked on the network, which is where a real cancel usually lands.
private final class HangingDeviceRegistrationURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard request.url?.path == "/api/auth/token/verify", let url = request.url else { return }
        if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                          headerFields: ["Content-Type": "application/json"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(#"{"username":"tester"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
