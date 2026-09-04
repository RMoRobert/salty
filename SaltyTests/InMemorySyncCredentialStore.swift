//
//  InMemorySyncCredentialStore.swift
//  SaltyTests
//
//  A SyncCredentialStore that lives entirely in memory, so tests never touch the real keychain.
//

import Foundation
import Synchronization
@testable import Salty

/// Stands in for `KeychainHelper` in tests.
///
/// Two reasons this exists rather than letting tests hit the keychain: the real store makes results depend
/// on whatever credentials the developer happens to have saved, and on macOS a keychain read can raise an
/// authorization dialog mid-run (dismissing it logged `status: -128` under every sync test). Values here
/// start empty and vanish with the instance, so each test states the credentials it wants, if any.
///
/// `Mutex` rather than actor isolation because `SyncCredentialStore` is a synchronous, `Sendable` protocol.
final class InMemorySyncCredentialStore: SyncCredentialStore {
    private struct Storage {
        var password = ""
        var deviceToken: String?
        var deviceId: String?
    }

    private let storage: Mutex<Storage>

    init(password: String = "", deviceToken: String? = nil, deviceId: String? = nil) {
        storage = Mutex(Storage(password: password, deviceToken: deviceToken, deviceId: deviceId))
    }

    func deviceId() -> String? {
        storage.withLock { $0.deviceId }
    }

    func setDeviceId(_ id: String) -> Bool {
        storage.withLock { $0.deviceId = id }
        return true
    }

    func password() -> String {
        storage.withLock { $0.password }
    }

    func setPassword(_ password: String) {
        storage.withLock { $0.password = password }
    }

    func deviceToken() -> String? {
        storage.withLock { $0.deviceToken }
    }

    func setDeviceToken(_ token: String?) {
        storage.withLock { $0.deviceToken = token }
    }
}
