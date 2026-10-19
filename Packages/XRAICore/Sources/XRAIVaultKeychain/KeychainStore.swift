// XRAIVaultKeychain — production KeyProvider on Apple Keychain, optionally Secure Enclave-wrapped.
// Imports Security (only module in XRAICore allowed to), CryptoKit, Foundation, the contracts and
// the CryptoKit adapter (for the package-internal GCM wrapper). No persistence of user data here:
// only key-encryption-key material and small key metadata ever touch the Keychain.
import Foundation
import Security
import XRAIVaultContracts

/// Accessibility classes offered for the KEK items. All are `ThisDeviceOnly` (never migrate to a
/// new device via backup/restore; never iCloud-synchronized).
public enum KeychainAccessibility: String, Hashable, Sendable, CaseIterable {
    /// Readable only while the device is unlocked. Default: the vault is a foreground feature.
    case whenUnlockedThisDeviceOnly = "WHEN_UNLOCKED_THIS_DEVICE_ONLY"
    /// Readable after the first unlock since boot (background work). Weaker; opt-in only.
    case afterFirstUnlockThisDeviceOnly = "AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY"
    /// Strongest: requires a device passcode; the OS DELETES the item if the passcode is removed.
    /// Consequence: removing the passcode destroys the KEK and therefore every record (fail closed).
    case whenPasscodeSetThisDeviceOnly = "WHEN_PASSCODE_SET_THIS_DEVICE_ONLY"

    var cfValue: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly: return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}

/// Secure Enclave policy. `required` fails closed when the SE is absent; `preferred` records the
/// truthful lower protection level and NEVER pretends; `disabled` is keychain-only.
public enum SecureEnclavePolicy: String, Hashable, Sendable {
    case required = "REQUIRED"
    case preferred = "PREFERRED"
    case disabled = "DISABLED"
}

public struct KeychainConfiguration: Hashable, Sendable {
    /// Keychain service name; one per app/environment. Tests use a unique, cleaned-up service.
    public let service: String
    public let accessibility: KeychainAccessibility
    public let secureEnclave: SecureEnclavePolicy
    /// Production: `true`. The data-protection keychain gives the ThisDeviceOnly semantics above.
    public let useDataProtectionKeychain: Bool
    /// TEST ONLY. On a macOS CLI test host the data-protection keychain needs an entitlement the
    /// unsigned `swift test` binary lacks (errSecMissingEntitlement). With this flag the provider
    /// falls back to the login keychain and REPORTS `keychainLegacyMacOSTestOnly`. Production
    /// configurations must leave it `false` so the failure stays closed.
    public let allowLegacyMacOSKeychainForTesting: Bool

    public init(service: String, accessibility: KeychainAccessibility = .whenUnlockedThisDeviceOnly, secureEnclave: SecureEnclavePolicy = .preferred, useDataProtectionKeychain: Bool = true, allowLegacyMacOSKeychainForTesting: Bool = false) {
        self.service = service
        self.accessibility = accessibility
        self.secureEnclave = secureEnclave
        self.useDataProtectionKeychain = useDataProtectionKeychain
        self.allowLegacyMacOSKeychainForTesting = allowLegacyMacOSKeychainForTesting
    }

    public static func production(service: String) -> KeychainConfiguration {
        KeychainConfiguration(service: service, accessibility: .whenUnlockedThisDeviceOnly, secureEnclave: .preferred, useDataProtectionKeychain: true, allowLegacyMacOSKeychainForTesting: false)
    }
}

/// OSStatus → typed, identifier-free `VaultError`. Pure function, unit-tested.
public enum KeychainStatusMapping {
    public static func map(_ status: OSStatus) -> VaultError {
        switch status {
        case errSecItemNotFound: return .keyUnavailable(version: 0)
        case errSecDuplicateItem: return .keychainConflict
        case errSecInteractionNotAllowed: return .keychainUnavailable(status: status)   // device locked
        case errSecAuthFailed: return .keychainUnavailable(status: status)              // access denied
        case errSecMissingEntitlement: return .keychainUnavailable(status: status)      // -34018
        case errSecUserCanceled: return .keychainUnavailable(status: status)
        case errSecNotAvailable: return .keychainUnavailable(status: status)
        case errSecDecode: return .keychainCorrupted(reason: "decode")
        default: return .keychainUnavailable(status: status)
        }
    }
}

/// Thin, synchronous generic-password store. Internal: the provider is the only client.
struct KeychainStore {
    enum Mode: Hashable { case dataProtection, legacyMacOS }

    let service: String
    let accessibility: KeychainAccessibility
    let mode: Mode

    private func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if mode == .dataProtection {
            q[kSecUseDataProtectionKeychain as String] = true
        }
        return q
    }

    /// Adds a new item. Never overwrites: a duplicate is a conflict (fail closed).
    func add(account: String, data: Data) throws {
        var q = baseQuery(account: account)
        q[kSecValueData as String] = data
        q[kSecAttrSynchronizable as String] = false
        if mode == .dataProtection {
            q[kSecAttrAccessible as String] = accessibility.cfValue
        }
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStatusMapping.map(status) }
    }

    func read(account: String) throws -> Data? {
        var q = baseQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStatusMapping.map(status) }
        guard let d = out as? Data else { throw VaultError.keychainCorrupted(reason: "item type") }
        return d
    }

    /// Updates an existing item's data (used only for the small `current` pointer).
    func update(account: String, data: Data) throws {
        let q = baseQuery(account: account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecSuccess else { throw KeychainStatusMapping.map(status) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainStatusMapping.map(status) }
    }

    /// Deletes every item of this service (test cleanup / explicit user wipe).
    func deleteAll() throws {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if mode == .dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        // The legacy macOS keychain deletes only the first match unless asked for all.
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainStatusMapping.map(status) }
    }

    /// Probes whether this mode is usable: writes and deletes a probe item.
    func probe() -> OSStatus {
        let account = "probe." + UUID().uuidString
        var q = baseQuery(account: account)
        q[kSecValueData as String] = Data([1])
        q[kSecAttrSynchronizable as String] = false
        if mode == .dataProtection { q[kSecAttrAccessible as String] = accessibility.cfValue }
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecSuccess { _ = SecItemDelete(baseQuery(account: account) as CFDictionary) }
        return status
    }
}
