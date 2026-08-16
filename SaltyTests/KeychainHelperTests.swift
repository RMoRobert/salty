//
//  KeychainHelperTests.swift
//  SaltyTests
//
//  Guards the entitlement KeychainHelper's data-protection keychain queries depend on.
//

import Testing
import Foundation
@testable import Salty

/// The one test that deliberately uses the real keychain -- everything else injects
/// `InMemorySyncCredentialStore` instead.
///
/// It exists because `KeychainHelper` pins every query to the data-protection keychain, which on macOS
/// only answers a binary carrying an `application-identifier` entitlement. That entitlement arrives
/// indirectly: `Salty.entitlements` declares a `keychain-access-groups` group, which forces signing to
/// use a provisioning profile, which supplies the app identifier. Drop the group from the entitlements
/// and every save silently fails with `errSecMissingEntitlement` while the app quietly falls back to
/// prompting against the login keychain -- a regression nothing else here would notice. Uses its own
/// throwaway key, so it never disturbs real sync credentials.
@Suite(.serialized)
struct KeychainHelperTests {

    @Test func dataProtectionKeychainRoundTripsAValue() {
        let key = "salty.test.roundTrip"
        defer { KeychainHelper.shared.delete(forKey: key) }

        #expect(KeychainHelper.shared.save("hello", forKey: key))
        #expect(KeychainHelper.shared.getString(forKey: key) == "hello")
    }

    @Test func deletedValuesReadBackAsNil() {
        let key = "salty.test.delete"
        KeychainHelper.shared.save("hello", forKey: key)

        #expect(KeychainHelper.shared.delete(forKey: key))
        #expect(KeychainHelper.shared.getString(forKey: key) == nil)
        #expect(!KeychainHelper.shared.exists(forKey: key))
    }

    /// Saving twice must update rather than fail on a duplicate item.
    @Test func savingTwiceReplacesTheValue() {
        let key = "salty.test.replace"
        defer { KeychainHelper.shared.delete(forKey: key) }

        KeychainHelper.shared.save("first", forKey: key)
        #expect(KeychainHelper.shared.save("second", forKey: key))
        #expect(KeychainHelper.shared.getString(forKey: key) == "second")
    }
}
