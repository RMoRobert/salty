//
//  SyncCredentialStore.swift
//  Salty
//
//  The credential storage SaltySyncService depends on, behind a protocol so it can be substituted.
//

import Foundation

/// Where the sync service reads and writes the secrets it needs.
///
/// One secret is kept: the long-lived per-device sync token the server issues at enrolment. (There used
/// to be a second, a short-lived JWT minted from it, until the server dropped its JWT tier and the token
/// became what every request carries.) The password is only ever *read*, and only by the one-time
/// migration that spends a pre-enrolment build's saved password to enrol this device before deleting it
/// -- `setPassword` exists so that deletion has a way to happen, not so a password can be stored.
///
/// The app has exactly one implementation, `KeychainHelper`. The indirection exists for the tests: without
/// it, every test that builds a `SaltySyncService` -- even ones that only exercise stubbed HTTP error
/// paths and never authenticate -- reaches into the machine's real keychain, which makes results depend on
/// the developer's keychain state and, on macOS, can put an authorization dialog in front of a test run.
protocol SyncCredentialStore: Sendable {
    /// Legacy only. Non-empty just on installs upgrading from a build that saved the password.
    func password() -> String
    /// In practice only ever called with `""`, to erase a migrated legacy password.
    func setPassword(_ password: String)
    func deviceToken() -> String?
    func setDeviceToken(_ token: String?)
    /// The id this device registers and enrols under. Not a secret (the server lists it), but it is
    /// kept here so it stays on this device: see `SaltySyncService.deviceId`.
    func deviceId() -> String?
    @discardableResult
    func setDeviceId(_ id: String) -> Bool
}

extension KeychainHelper: SyncCredentialStore {
    func password() -> String { getPassword() }
    func setPassword(_ password: String) { savePassword(password) }
    func deviceToken() -> String? { getDeviceToken() }
    func setDeviceToken(_ token: String?) { saveDeviceToken(token) }
    func deviceId() -> String? { getDeviceId() }
    func setDeviceId(_ id: String) -> Bool { saveDeviceId(id) }
}
