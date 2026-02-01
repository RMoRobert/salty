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

/// Helper class for storing and retrieving server login and other sensitive data in Keychain
class KeychainHelper {
    static let shared = KeychainHelper()
    private let logger = Logger(subsystem: "Salty", category: "Keychain")
    private let service = "com.inuvro.salty"
    
    private init() {}
    
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
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        } else if status != errSecItemNotFound {
            logger.error("Failed to retrieve keychain item for key: \(key), status: \(status)")
        }
        
        return nil
    }
    
    /// Delete an item from the Keychain
    /// - Parameter key: The key to delete
    /// - Returns: True if successful or item didn't exist
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Convenience Methods for Common Keys
    
    /// Keys used for Salty Sever sync authentication
    enum Key: String {
        case serverPassword = "salty.server.password"
        case jwtToken = "salty.server.jwtToken"
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
    
    /// Clear all authentication data
    func clearAuthData() {
        delete(forKey: Key.serverPassword.rawValue)
        delete(forKey: Key.jwtToken.rawValue)
        logger.info("Cleared all authentication data from keychain")
    }
}
