//
//  SyncSettingsStore.swift
//  SaltyCore
//
//  The non-secret sync settings ServerSyncEngine reads, and the one it writes back.
//

import Foundation

/// The sync settings a platform keeps: which server, and as whom.
///
/// Read live on each request rather than captured once, so a change in Settings (or a test) applies to
/// the next call. Whether sync is switched on, and when it last succeeded, are the app's business.
public protocol SyncSettingsStore: Sendable {
    /// The server's base URL, without a trailing path. Empty when not configured.
    func serverURL() -> String
    /// The account this device syncs as. Empty until the user has entered one.
    func username() -> String
    /// Called with the server's own spelling of the account name after enrolment and after each token
    /// check, so a rename on the server reaches the settings screen.
    func setUsername(_ username: String)
}
