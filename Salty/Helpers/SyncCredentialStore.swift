//
//  SyncCredentialStore.swift
//  Salty
//
//  The credential storage SaltySyncService depends on, behind a protocol so it can be substituted.
//

import Foundation

/// Where the sync service reads and writes the two secrets it needs: the server password the user typed,
/// and the JWT the server hands back in exchange for it.
///
/// The app has exactly one implementation, `KeychainHelper`. The indirection exists for the tests: without
/// it, every test that builds a `SaltySyncService` -- even ones that only exercise stubbed HTTP error
/// paths and never authenticate -- reaches into the machine's real keychain, which makes results depend on
/// the developer's keychain state and, on macOS, can put an authorization dialog in front of a test run.
protocol SyncCredentialStore: Sendable {
    func password() -> String
    func setPassword(_ password: String)
    func jwtToken() -> String?
    func setJwtToken(_ token: String?)
}

extension KeychainHelper: SyncCredentialStore {
    func password() -> String { getPassword() }
    func setPassword(_ password: String) { savePassword(password) }
    func jwtToken() -> String? { getJwtToken() }
    func setJwtToken(_ token: String?) { saveJwtToken(token) }
}
