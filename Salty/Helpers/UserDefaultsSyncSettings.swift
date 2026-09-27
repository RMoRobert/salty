//
//  UserDefaultsSyncSettings.swift
//  Salty
//
//  The sync settings ServerSyncEngine reads, kept in UserDefaults.
//

import Foundation
import SaltyCore

/// The server address and account name, in `UserDefaults` under the keys Settings binds to.
///
/// Read live on every call, so a change in Settings reaches the very next request.
struct UserDefaultsSyncSettings: SyncSettingsStore {
    func serverURL() -> String {
        UserDefaults.standard.string(forKey: "serverUrl") ?? ""
    }

    func username() -> String {
        UserDefaults.standard.string(forKey: "serverUsername") ?? ""
    }

    func setUsername(_ username: String) {
        UserDefaults.standard.set(username, forKey: "serverUsername")
    }
}
