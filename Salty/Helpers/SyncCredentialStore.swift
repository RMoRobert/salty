//
//  SyncCredentialStore.swift
//  Salty
//
//  The Keychain as sync's credential store. The protocol lives in SaltyCore.
//

import Foundation
import SaltyCore

extension KeychainHelper: SyncCredentialStore {
    func password() -> String { getPassword() }
    func setPassword(_ password: String) { savePassword(password) }
    func deviceToken() -> String? { getDeviceToken() }
    func setDeviceToken(_ token: String?) { saveDeviceToken(token) }
    func deviceId() -> String? { getDeviceId() }
    func setDeviceId(_ id: String) -> Bool { saveDeviceId(id) }
}
