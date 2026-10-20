// P03-04 H5: the vault anchor lives in the Keychain, a persistence domain separate from the file
// system, so an attacker who replaces the whole vault directory with an older snapshot is detected.
// Holds (instance id, manifest generation, manifest hash) only — no personal data, no key material.
import Foundation
import Security
import XRAIVaultContracts

public final class KeychainAnchorStore: VaultAnchorStore, @unchecked Sendable {
    public let configuration: KeychainConfiguration
    public let account: String
    private let store: KeychainStore
    private let lock = NSLock()

    /// Same keychain-mode rules as `KeychainKeyProvider`: production = data-protection keychain or
    /// fail closed; the legacy macOS keychain only with the explicit test flag.
    public init(keyID: String, configuration: KeychainConfiguration) throws {
        guard !keyID.isEmpty, keyID.count <= 64, !keyID.contains("/") else { throw VaultError.limitExceeded("keyID") }
        self.configuration = configuration
        self.account = keyID + "/anchor"
        var mode: KeychainStore.Mode = .dataProtection
        if configuration.useDataProtectionKeychain {
            let probe = KeychainStore(service: configuration.service, accessibility: configuration.accessibility, mode: .dataProtection).probe()
            if probe != errSecSuccess {
                #if os(macOS)
                if configuration.allowLegacyMacOSKeychainForTesting { mode = .legacyMacOS } else { throw KeychainStatusMapping.map(probe) }
                #else
                throw KeychainStatusMapping.map(probe)
                #endif
            }
        } else {
            #if os(macOS)
            guard configuration.allowLegacyMacOSKeychainForTesting else { throw VaultError.keychainUnavailable(status: errSecParam) }
            mode = .legacyMacOS
            #else
            throw VaultError.keychainUnavailable(status: errSecParam)
            #endif
        }
        self.store = KeychainStore(service: configuration.service, accessibility: configuration.accessibility, mode: mode)
    }

    public func readAnchor() throws -> VaultAnchor? {
        lock.lock(); defer { lock.unlock() }
        guard let d = try store.read(account: account) else { return nil }
        return try VaultAnchor.decode(Array(d))
    }

    /// Add on first write, update afterwards (the same pointer mechanism as `<keyID>/current`).
    public func writeAnchor(_ anchor: VaultAnchor) throws {
        lock.lock(); defer { lock.unlock() }
        let data = Data(anchor.encode())
        if try store.read(account: account) == nil {
            do { try store.add(account: account, data: data) } catch VaultError.keychainConflict { try store.update(account: account, data: data) }
        } else {
            try store.update(account: account, data: data)
        }
    }

    public func clearAnchor() throws {
        lock.lock(); defer { lock.unlock() }
        try store.delete(account: account)
    }
}

/// `KeychainKeyProvider` already implements two-phase forgetting; expose it through the store port.
extension KeychainKeyProvider: RetirableKeyProvider {}
