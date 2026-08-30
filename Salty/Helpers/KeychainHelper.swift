//
//  KeychainHelper.swift
//  Salty
//
//  Created by Robert on 1/25/26
//
//  Secure storage for sensitive data like passwords and tokens, used with Salty Server preferences
//

import Foundation
import Security
import OSLog

/// Helper class for storing and retrieving server login and other sensitive data in Keychain.
/// Stateless (only immutable `let` properties), so it's safely `Sendable` and usable from any actor.
final class KeychainHelper: Sendable {
    static let shared = KeychainHelper()
    private let logger = Logger(subsystem: "Salty", category: "Keychain")
    private let service = "com.inuvro.salty"
    
    private init() {}

    // MARK: - Query construction

    /// The attributes shared by every query, identifying one item and pinning it to the data-protection
    /// keychain.
    ///
    /// `kSecUseDataProtectionKeychain` matters only on macOS, and it matters a lot: without it the
    /// Security framework falls back to the legacy file-based login keychain, where each item carries an
    /// ACL bound to the exact code signature of the binary that created it. Every rebuild produces a new
    /// signature -- as does the unit-test host, which runs inside `Salty.app` but is a different binary --
    /// so macOS puts up an "allow access?" prompt on essentially every run, and "Always Allow" only holds
    /// until the next build. The data-protection keychain instead scopes items to the app's keychain
    /// access group, derived from the `application-identifier` entitlement, so access is decided by the
    /// signature's team and bundle ID rather than by a per-binary ACL: no prompts, ever, and the same
    /// semantics iOS has always had. Items written by earlier (legacy) builds are moved across once by
    /// `migrateLegacyMacKeychainIfNeeded()`.
    ///
    /// - Note: One consequence of access groups is that Debug and Release no longer share credentials,
    ///   since they ship under different bundle IDs (`com.inuvro.salty-dev` vs `com.inuvro.salty`).
    ///   That separation is deliberate; sharing them again would need a Keychain Sharing capability.
    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    // MARK: - Public API

    /// Save a string value to the Keychain
    /// - Parameters:
    ///   - value: The string to store
    ///   - key: The key to store it under
    /// - Returns: True if successful
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to encode string for key: \(key)")
            return false
        }
        return save(data, forKey: key)
    }
    
    /// Save data to the Keychain
    /// - Parameters:
    ///   - data: The data to store
    ///   - key: The key to store it under
    /// - Returns: True if successful
    @discardableResult
    func save(_ data: Data, forKey key: String) -> Bool {
        // Delete any existing item first
        delete(forKey: key)
        
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            logger.debug("Saved keychain item for key: \(key)")
            return true
        } else {
            logger.error("Failed to save keychain item for key: \(key), status: \(status)")
            return false
        }
    }
    
    /// Retrieve a string value from the Keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored string, or nil if not found
    func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Retrieve data from the Keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored data, or nil if not found
    func getData(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            break
        case errSecUserCanceled, errSecInteractionNotAllowed:
            // The item exists but couldn't be read right now -- an authorization prompt was dismissed, or
            // the device is locked. Not a fault, and callers already treat nil as "no credentials yet".
            logger.debug("Keychain item unavailable for key: \(key), status: \(status)")
        default:
            logger.error("Failed to retrieve keychain item for key: \(key), status: \(status)")
        }

        return nil
    }
    
    /// Delete an item from the Keychain
    /// - Parameter key: The key to delete
    /// - Returns: True if successful or item didn't exist
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            logger.debug("Deleted keychain item for key: \(key)")
            return true
        } else {
            logger.error("Failed to delete keychain item for key: \(key), status: \(status)")
            return false
        }
    }
    
    /// Check if an item exists in the Keychain
    /// - Parameter key: The key to check
    /// - Returns: True if the item exists
    func exists(forKey key: String) -> Bool {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Convenience Methods for Common Keys
    
    /// Keys used for Salty Sever sync authentication
    enum Key: String, CaseIterable {
        /// Only ever read now, never written: pre-enrolment builds saved the password here, and
        /// `SaltySyncService` spends it once to enrol this device before deleting it. See
        /// `enrollUsingSavedPasswordIfPresent()`.
        case serverPassword = "salty.server.password"
        case jwtToken = "salty.server.jwtToken"
        /// The per-device sync token (`salty_…`) the server issues at enrolment. Long-lived and the
        /// only credential the app keeps: it can sync, and deliberately nothing else -- it cannot
        /// change a password or revoke another device.
        case deviceToken = "salty.server.deviceToken"
    }
    
    /// Save the server password
    @discardableResult
    func savePassword(_ password: String) -> Bool {
        if password.isEmpty {
            return delete(forKey: Key.serverPassword.rawValue)
        }
        return save(password, forKey: Key.serverPassword.rawValue)
    }
    
    /// Get the server password
    func getPassword() -> String {
        return getString(forKey: Key.serverPassword.rawValue) ?? ""
    }
    
    /// Save the JWT token
    @discardableResult
    func saveJwtToken(_ token: String?) -> Bool {
        if let token = token, !token.isEmpty {
            return save(token, forKey: Key.jwtToken.rawValue)
        } else {
            return delete(forKey: Key.jwtToken.rawValue)
        }
    }
    
    /// Get the JWT token
    func getJwtToken() -> String? {
        return getString(forKey: Key.jwtToken.rawValue)
    }

    /// Save the device sync token. Passing nil or "" deletes it, which is how a device is un-enrolled.
    @discardableResult
    func saveDeviceToken(_ token: String?) -> Bool {
        if let token, !token.isEmpty {
            return save(token, forKey: Key.deviceToken.rawValue)
        } else {
            return delete(forKey: Key.deviceToken.rawValue)
        }
    }

    /// Get the device sync token
    func getDeviceToken() -> String? {
        return getString(forKey: Key.deviceToken.rawValue)
    }

    /// Clear all authentication data
    func clearAuthData() {
        delete(forKey: Key.serverPassword.rawValue)
        delete(forKey: Key.jwtToken.rawValue)
        delete(forKey: Key.deviceToken.rawValue)
        logger.info("Cleared all authentication data from keychain")
    }

    // MARK: - Legacy macOS keychain migration

#if os(macOS)
    private static let legacyMigrationDefaultsKey = "keychainLegacyMacMigrationCompleted"

    /// Moves credentials written by pre-data-protection builds out of the login keychain, once.
    ///
    /// Builds before `baseQuery(forKey:)` pinned `kSecUseDataProtectionKeychain` stored these items in the
    /// file-based login keychain, where they're invisible to the queries above. Reading one costs a single
    /// authorization prompt (a missing item returns `errSecItemNotFound` with no prompt at all), after
    /// which nothing in the app ever touches the legacy keychain again -- so this is the last such prompt
    /// the user can see. The completion flag is set whether or not anything was found, and whether or not
    /// the user allowed the read: a dismissed prompt must not mean asking again on the next launch. Worst
    /// case the user re-enters the sync password in Settings, which writes it to the modern keychain.
    ///
    /// Safe to delete once no install can still be carrying legacy items.
    func migrateLegacyMacKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.legacyMigrationDefaultsKey) else { return }
        defaults.set(true, forKey: Self.legacyMigrationDefaultsKey)

        for key in Key.allCases {
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
                kSecUseDataProtectionKeychain as String: false,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else {
                if status != errSecItemNotFound {
                    logger.debug("Skipped legacy keychain migration for key: \(key.rawValue), status: \(status)")
                }
                continue
            }

            // Never overwrite a value the modern keychain already holds -- that one is authoritative.
            if getData(forKey: key.rawValue) == nil {
                save(data, forKey: key.rawValue)
            }

            var deleteQuery = legacyQuery
            deleteQuery.removeValue(forKey: kSecReturnData as String)
            deleteQuery.removeValue(forKey: kSecMatchLimit as String)
            SecItemDelete(deleteQuery as CFDictionary)
            logger.info("Migrated legacy keychain item to the data-protection keychain: \(key.rawValue)")
        }
    }
#endif
}
