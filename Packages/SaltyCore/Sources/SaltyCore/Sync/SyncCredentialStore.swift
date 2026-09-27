//
//  SyncCredentialStore.swift
//  SaltyCore
//
//  The credential storage ServerSyncEngine depends on, behind a protocol so each platform supplies its own.
//

import Foundation

/// Where the sync engine reads and writes the secrets it needs.
///
/// One secret is kept: the long-lived per-device sync token the server issues at enrolment. (There used
/// to be a second, a short-lived JWT minted from it, until the server dropped its JWT tier and the token
/// became what every request carries.) The password is only ever *read*, and only by the one-time
/// migration that spends a pre-enrolment build's saved password to enrol this device before deleting it
/// -- `setPassword` exists so that deletion has a way to happen, not so a password can be stored.
///
/// A protocol because secure storage is per-platform: the Apple app uses the Keychain (`KeychainHelper`).
/// Tests use an in-memory store so they never depend on, or prompt for, the developer's real keychain.
public protocol SyncCredentialStore: Sendable {
    /// Legacy only. Non-empty just on installs upgrading from a build that saved the password.
    func password() -> String
    /// In practice only ever called with `""`, to erase a migrated legacy password.
    func setPassword(_ password: String)
    func deviceToken() -> String?
    func setDeviceToken(_ token: String?)
    /// The id this device registers and enrols under. Not a secret (the server lists it), but it is
    /// kept here so it stays on this device: see `ServerSyncEngine.deviceId`.
    func deviceId() -> String?
    @discardableResult
    func setDeviceId(_ id: String) -> Bool
}
