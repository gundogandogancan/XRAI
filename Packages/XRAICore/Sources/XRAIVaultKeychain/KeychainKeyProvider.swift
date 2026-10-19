// Production KeyProvider on Apple Keychain, optionally Secure Enclave-wrapped (P02-02 GATE 1–2).
//
// Keychain layout (generic-password items, service = configuration.service, non-synchronizable):
//   "<keyID>/meta"      → canonical { protection raw string, accessibility raw string }
//   "<keyID>/current"   → u32 current version
//   "<keyID>/kek/v<N>"  → 32 raw KEK bytes (keychain-only) OR Secure Enclave blob (SE-wrapped)
// Invariants: items are never overwritten (SecItemAdd only; duplicates are conflicts); `current`
// is updated only after the new version item is durably written (an interrupted rotation leaves an
// unreferenced newer item that is ignored and can be garbage-collected); any unreadable, malformed
// or mode-mismatched item fails closed. Key material never goes to UserDefaults, files, logs or Git.
import CryptoKit
import Foundation
import Security
import XRAIVaultContracts
import XRAIVaultCryptoKit

public final class KeychainKeyProvider: KeyProvider, @unchecked Sendable {
    public let keyID: String
    public let configuration: KeychainConfiguration
    public let protection: KeyProtection

    private let store: KeychainStore
    private let lock = NSLock()
    private var cache: [UInt32: [UInt8]] = [:]   // KEK bytes loaded this process (cleared on forget)
    private var currentVersion: UInt32

    /// Opens (or creates on first use) the key set for `keyID`. Fails closed when the configured
    /// keychain mode is unavailable or when Secure Enclave is required but absent.
    public init(keyID: String, configuration: KeychainConfiguration) throws {
        guard !keyID.isEmpty, keyID.count <= 64, !keyID.contains("/") else { throw VaultError.limitExceeded("keyID") }
        self.keyID = keyID
        self.configuration = configuration

        // 1. Select the keychain mode. Production: data-protection keychain or fail.
        var mode: KeychainStore.Mode = .dataProtection
        if configuration.useDataProtectionKeychain {
            let probe = KeychainStore(service: configuration.service, accessibility: configuration.accessibility, mode: .dataProtection).probe()
            if probe != errSecSuccess {
                #if os(macOS)
                if configuration.allowLegacyMacOSKeychainForTesting {
                    mode = .legacyMacOS
                } else {
                    throw KeychainStatusMapping.map(probe)
                }
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

        // 2. Decide protection level truthfully.
        let seAvailable = SecureEnclaveWrapper.isAvailable
        let useSE: Bool
        switch configuration.secureEnclave {
        case .required:
            guard seAvailable else { throw VaultError.secureEnclaveUnavailable }
            useSE = true
        case .preferred: useSE = seAvailable
        case .disabled: useSE = false
        }
        let protection: KeyProtection
        if mode == .legacyMacOS {
            protection = .keychainLegacyMacOSTestOnly
        } else if useSE {
            protection = .secureEnclaveWrapped(accessibility: configuration.accessibility.rawValue)
        } else {
            protection = .keychainDeviceBound(accessibility: configuration.accessibility.rawValue)
        }
        let seActive = useSE  // SE wrapping is applied even in legacy test mode when the Mac has an enclave
        self.protection = protection

        // 3. Load or create. Meta must match (mode mismatch = fail closed).
        let metaAccount = keyID + "/meta"
        let expectedMeta = KeychainKeyProvider.metaBytes(se: seActive, accessibility: configuration.accessibility)
        if let meta = try store.read(account: metaAccount) {
            guard Array(meta) == expectedMeta else { throw VaultError.keychainCorrupted(reason: "mode mismatch") }
            guard let cur = try store.read(account: keyID + "/current") else { throw VaultError.keychainCorrupted(reason: "missing current") }
            self.currentVersion = try KeychainKeyProvider.decodeVersion(Array(cur))
            self.seActive = seActive
            _ = try loadKEK(version: currentVersion)  // fail closed now, not later
        } else {
            self.seActive = seActive
            self.currentVersion = 1
            try writeKEK(version: 1)
            do {
                try store.add(account: metaAccount, data: Data(expectedMeta))
                try store.add(account: keyID + "/current", data: Data(KeychainKeyProvider.encodeVersion(1)))
            } catch VaultError.keychainConflict {
                // Lost a creation race: another instance initialised the same keyID concurrently.
                // Reload from the keychain instead of overwriting anything.
                guard let cur = try store.read(account: keyID + "/current") else { throw VaultError.keychainConflict }
                self.currentVersion = try KeychainKeyProvider.decodeVersion(Array(cur))
                lock.lock(); cache = [:]; lock.unlock()
                _ = try loadKEK(version: currentVersion)
            }
        }
    }

    private let seActive: Bool

    // MARK: KeyProvider

    public var currentKey: KeyIdentity {
        lock.lock(); defer { lock.unlock() }
        return KeyIdentity(keyID: keyID, version: currentVersion)
    }

    public func wrapDataKey(_ dek: [UInt8], boundTo recordID: RecordID) throws -> WrappedKey {
        let version: UInt32 = { lock.lock(); defer { lock.unlock() }; return currentVersion }()
        let kek = try loadKEK(version: version)
        return try GCMKeyWrapper(keyID: keyID, version: version, material: kek).wrap(dek, boundTo: recordID)
    }

    public func unwrapDataKey(_ wrapped: WrappedKey) throws -> [UInt8] {
        guard wrapped.keyID == keyID else { throw VaultError.keyUnavailable(version: wrapped.keyVersion) }
        let cur: UInt32 = { lock.lock(); defer { lock.unlock() }; return currentVersion }()
        // Only versions at or below `current` are usable; an orphan from an interrupted rotation is not.
        guard wrapped.keyVersion >= 1, wrapped.keyVersion <= cur else { throw VaultError.keyUnavailable(version: wrapped.keyVersion) }
        let kek = try loadKEK(version: wrapped.keyVersion)
        return try GCMKeyWrapper(keyID: keyID, version: wrapped.keyVersion, material: kek).unwrap(wrapped)
    }

    /// Rotation: write v(N+1) item first, then move `current`. If the process dies in between, the
    /// new item is an unreferenced orphan and `current` still points at N (interrupted rotation safe).
    public func rotate() throws -> KeyIdentity {
        lock.lock(); defer { lock.unlock() }
        let next = currentVersion + 1
        try writeKEK(version: next)
        try store.update(account: keyID + "/current", data: Data(KeychainKeyProvider.encodeVersion(next)))
        currentVersion = next
        return KeyIdentity(keyID: keyID, version: next)
    }

    /// Secure forgetting: deletes the item and the in-process copy. The current version cannot be forgotten.
    public func forget(version: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        guard version != currentVersion else { throw VaultError.keyUnavailable(version: version) }
        try store.delete(account: keyID + "/kek/v" + String(version))
        cache[version] = nil
    }

    /// Explicit user-initiated wipe of this key set (all versions, meta, pointer). Irreversible.
    public func wipeAllKeys() throws {
        lock.lock(); defer { lock.unlock() }
        var v: UInt32 = 1
        while v <= currentVersion + 2 { try store.delete(account: keyID + "/kek/v" + String(v)); v += 1 }
        try store.delete(account: keyID + "/current")
        try store.delete(account: keyID + "/meta")
        cache = [:]
    }

    // MARK: Internals

    private func writeKEK(version: UInt32) throws {
        let kek = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
        let payload: [UInt8] = seActive ? try SecureEnclaveWrapper.wrap(kek: kek, accessibility: configuration.accessibility) : kek
        try store.add(account: keyID + "/kek/v" + String(version), data: Data(payload))
        cache[version] = kek
    }

    private func loadKEK(version: UInt32) throws -> [UInt8] {
        if let c: [UInt8] = { lock.lock(); defer { lock.unlock() }; return cache[version] }() { return c }
        guard let data = try store.read(account: keyID + "/kek/v" + String(version)) else { throw VaultError.keyUnavailable(version: version) }
        let bytes = Array(data)
        let kek: [UInt8]
        if seActive {
            kek = try SecureEnclaveWrapper.unwrap(blob: bytes)
        } else {
            guard bytes.count == 32 else { throw VaultError.keychainCorrupted(reason: "kek length") }
            kek = bytes
        }
        guard kek.count == 32 else { throw VaultError.keychainCorrupted(reason: "kek length") }
        lock.lock(); cache[version] = kek; lock.unlock()
        return kek
    }

    static func metaBytes(se: Bool, accessibility: KeychainAccessibility) -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-KEK-META")
        e.appendU16(1)
        e.appendString(se ? "SE_WRAPPED" : "KEYCHAIN_ONLY")
        e.appendString(accessibility.rawValue)
        return e.bytes
    }

    static func encodeVersion(_ v: UInt32) -> [UInt8] { var e = CanonicalEncoder(); e.appendU32(v); return e.bytes }
    static func decodeVersion(_ b: [UInt8]) throws -> UInt32 {
        guard b.count == 4 else { throw VaultError.keychainCorrupted(reason: "current pointer") }
        var d = CanonicalDecoder(b)
        let v = try d.readU32()
        guard v >= 1 else { throw VaultError.keychainCorrupted(reason: "current pointer") }
        return v
    }

    // Test support (package-internal): raw access to the store for corruption/conflict scenarios.
    package func debugStore() -> (service: String, mode: String) { (store.service, store.mode == .dataProtection ? "dataProtection" : "legacyMacOS") }
    package func debugCorrupt(version: UInt32, with bytes: [UInt8]) throws {
        try store.delete(account: keyID + "/kek/v" + String(version))
        try store.add(account: keyID + "/kek/v" + String(version), data: Data(bytes))
        lock.lock(); cache[version] = nil; lock.unlock()
    }
    package func debugDeleteItem(version: UInt32) throws { try store.delete(account: keyID + "/kek/v" + String(version)); lock.lock(); cache[version] = nil; lock.unlock() }
    package func debugAddConflicting(version: UInt32) throws { try store.add(account: keyID + "/kek/v" + String(version), data: Data(repeating: 7, count: 32)) }
    package func debugWriteOrphan(version: UInt32) throws { lock.lock(); defer { lock.unlock() }; try writeKEK(version: version); cache[version] = nil }
    package func debugDropCache() { lock.lock(); cache = [:]; lock.unlock() }
    package static func debugDeleteService(_ service: String) throws {
        for mode in [KeychainStore.Mode.dataProtection, .legacyMacOS] {
            try? KeychainStore(service: service, accessibility: .whenUnlockedThisDeviceOnly, mode: mode).deleteAll()
        }
    }
}
