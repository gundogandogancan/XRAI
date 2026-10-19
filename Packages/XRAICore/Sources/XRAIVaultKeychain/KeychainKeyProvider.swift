// Production KeyProvider on Apple Keychain, optionally Secure Enclave-wrapped (P02-02 GATE 1–2,
// hardened in P03-00 §3–§4).
//
// Keychain layout (generic-password items, service = configuration.service, non-synchronizable):
//   "<keyID>/meta"        → canonical { protection mode, accessibility }
//   "<keyID>/current"     → u32 current version (the ONLY pointer; always re-read before rotation)
//   "<keyID>/kek/v<N>"    → 32 raw KEK bytes (keychain-only) OR Secure Enclave blob (SE-wrapped)
//   "<keyID>/retired/v<N>"→ marker: version N may unwrap but never wrap; prerequisite for forget
// Invariants: items are never overwritten (SecItemAdd only; duplicates are conflicts); `current`
// moves only after the new version item is durably written; an interrupted rotation leaves an
// unreferenced newer item that the next rotation ADOPTS if it is readable (completing the rotation)
// and refuses if it is not (explicit repair required); any unreadable, malformed or mode-mismatched
// item fails closed. Key material never goes to UserDefaults, files, logs or Git.
//
// Key cache (P03-00 §3): unwrapped KEK bytes are kept in process memory for at most
// `KeyCachePolicy.ttlSeconds` (default 30 s) and are dropped by `purgeCache()`, which the app layer
// calls on lock / background / protected-data-unavailable events. The Secure Enclave protects the
// KEK AT REST (the keychain item alone is useless); it does NOT protect bytes already in process
// memory. Swift gives no zeroization guarantee; the cache only bounds the exposure window.
import CryptoKit
import Foundation
import Security
import XRAIVaultContracts
import XRAIVaultCryptoKit

/// How long an unwrapped KEK may be reused from memory. Shorter is safer; every miss costs a keychain
/// read (and an ECDH + HKDF when SE-wrapped).
public struct KeyCachePolicy: Hashable, Sendable {
    public let ttlSeconds: Int64
    public init(ttlSeconds: Int64 = 30) { self.ttlSeconds = max(0, ttlSeconds) }
    public static let disabled = KeyCachePolicy(ttlSeconds: 0)
}

/// Explicit, typed acknowledgement for the irreversible wipe. A value type cannot stop a determined
/// caller; it stops an accidental one and makes the intent reviewable.
public struct WipeConfirmation: Hashable, Sendable {
    public let keyID: String
    public let acknowledgesIrreversibleLoss: Bool
    public init(keyID: String, acknowledgesIrreversibleLoss: Bool) { self.keyID = keyID; self.acknowledgesIrreversibleLoss = acknowledgesIrreversibleLoss }
}

public final class KeychainKeyProvider: KeyProvider, @unchecked Sendable {
    public let keyID: String
    public let configuration: KeychainConfiguration
    public let protection: KeyProtection
    public let cachePolicy: KeyCachePolicy

    private let store: KeychainStore
    private let clock: any VaultClock
    private let lock = NSLock()
    private var cache: [UInt32: (kek: [UInt8], loadedAt: Int64)] = [:]
    private var currentVersion: UInt32
    private let seActive: Bool

    /// Opens (or creates on first use) the key set for `keyID`. Fails closed when the configured
    /// keychain mode is unavailable or when Secure Enclave is required but absent.
    public init(keyID: String, configuration: KeychainConfiguration, clock: any VaultClock = SystemClock(), cachePolicy: KeyCachePolicy = KeyCachePolicy()) throws {
        guard !keyID.isEmpty, keyID.count <= 64, !keyID.contains("/") else { throw VaultError.limitExceeded("keyID") }
        self.keyID = keyID
        self.configuration = configuration
        self.clock = clock
        self.cachePolicy = cachePolicy

        // 1. Keychain mode. Production: data-protection keychain or fail.
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

        // 2. Protection level, truthfully.
        let seAvailable = SecureEnclaveWrapper.isAvailable
        let useSE: Bool
        switch configuration.secureEnclave {
        case .required: guard seAvailable else { throw VaultError.secureEnclaveUnavailable }; useSE = true
        case .preferred: useSE = seAvailable
        case .disabled: useSE = false
        }
        self.seActive = useSE
        if mode == .legacyMacOS { self.protection = .keychainLegacyMacOSTestOnly }
        else if useSE { self.protection = .secureEnclaveWrapped(accessibility: configuration.accessibility.rawValue) }
        else { self.protection = .keychainDeviceBound(accessibility: configuration.accessibility.rawValue) }

        // 3. Load or create. Meta must match (mode mismatch = fail closed).
        let metaAccount = keyID + "/meta"
        let expectedMeta = KeychainKeyProvider.metaBytes(se: useSE, accessibility: configuration.accessibility)
        if let meta = try store.read(account: metaAccount) {
            guard Array(meta) == expectedMeta else { throw VaultError.keychainCorrupted(reason: "mode mismatch") }
            self.currentVersion = try KeychainKeyProvider.readPointer(store: store, keyID: keyID)
            _ = try loadKEK(version: currentVersion)  // fail closed now, not later
        } else {
            self.currentVersion = 1
            try writeKEK(version: 1)
            do {
                try store.add(account: metaAccount, data: Data(expectedMeta))
                try store.add(account: keyID + "/current", data: Data(KeychainKeyProvider.encodeVersion(1)))
            } catch VaultError.keychainConflict {
                // Lost a creation race with another instance: adopt the keychain's state, overwrite nothing.
                self.currentVersion = try KeychainKeyProvider.readPointer(store: store, keyID: keyID)
                lock.lock(); cache = [:]; lock.unlock()
                _ = try loadKEK(version: currentVersion)
            }
        }
    }

    // MARK: KeyProvider

    public var currentKey: KeyIdentity {
        lock.lock(); defer { lock.unlock() }
        return KeyIdentity(keyID: keyID, version: currentVersion)
    }

    /// Re-reads the `current` pointer (another instance may have rotated). Returns the identity.
    @discardableResult
    public func refreshCurrentKey() throws -> KeyIdentity {
        let v = try KeychainKeyProvider.readPointer(store: store, keyID: keyID)
        lock.lock(); currentVersion = v; lock.unlock()
        return KeyIdentity(keyID: keyID, version: v)
    }

    public func wrapDataKey(_ dek: [UInt8], boundTo recordID: RecordID) throws -> WrappedKey {
        let version = try refreshCurrentKey().version   // never wrap under a stale version
        let kek = try loadKEK(version: version)
        return try GCMKeyWrapper(keyID: keyID, version: version, material: kek).wrap(dek, boundTo: recordID)
    }

    public func unwrapDataKey(_ wrapped: WrappedKey) throws -> [UInt8] {
        guard wrapped.keyID == keyID, wrapped.keyVersion >= 1 else { throw VaultError.keyUnavailable(version: wrapped.keyVersion) }
        var cur: UInt32 = { lock.lock(); defer { lock.unlock() }; return currentVersion }()
        if wrapped.keyVersion > cur { cur = try refreshCurrentKey().version }   // another instance rotated?
        // Versions above the pointer are orphans of an interrupted rotation and are never usable.
        guard wrapped.keyVersion <= cur else { throw VaultError.keyUnavailable(version: wrapped.keyVersion) }
        let kek = try loadKEK(version: wrapped.keyVersion)
        return try GCMKeyWrapper(keyID: keyID, version: wrapped.keyVersion, material: kek).unwrap(wrapped)
    }

    /// Rotation with pointer re-read (compare-and-set against the keychain, not memory):
    /// next = stored current + 1. If `next` already exists (interrupted rotation by any instance),
    /// it is ADOPTED when readable — the pointer is moved to it, completing that rotation — and
    /// refused with `keychainCorrupted` when unreadable (call `repairOrphan` explicitly).
    public func rotate() throws -> KeyIdentity {
        lock.lock(); defer { lock.unlock() }
        let stored = try KeychainKeyProvider.readPointer(store: store, keyID: keyID)
        let next = stored + 1
        do {
            try writeKEKLocked(version: next)
        } catch VaultError.keychainConflict {
            cache[next] = nil
            _ = try loadKEKLocked(version: next)   // readable orphan → adopt; unreadable → throws corrupted
        }
        try store.update(account: keyID + "/current", data: Data(KeychainKeyProvider.encodeVersion(next)))
        currentVersion = next
        return KeyIdentity(keyID: keyID, version: next)
    }

    /// Deletes an UNREFERENCED orphan item above the pointer that could not be adopted. Never deletes
    /// a version at or below the pointer.
    public func repairOrphan(version: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        let stored = try KeychainKeyProvider.readPointer(store: store, keyID: keyID)
        guard version > stored else { throw VaultError.keyUnavailable(version: version) }
        try store.delete(account: keyID + "/kek/v" + String(version))
        cache[version] = nil
    }

    /// Two-phase forgetting, phase 1: mark a version retired. Retired versions still unwrap (so
    /// records can be re-wrapped) but are never used to wrap. Idempotent. Not allowed for `current`.
    public func retire(version: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        let stored = try KeychainKeyProvider.readPointer(store: store, keyID: keyID)
        currentVersion = stored
        guard version < stored else { throw VaultError.keyUnavailable(version: version) }
        do { try store.add(account: keyID + "/retired/v" + String(version), data: Data([1])) } catch VaultError.keychainConflict {}
    }

    public func isRetired(version: UInt32) throws -> Bool {
        try store.read(account: keyID + "/retired/v" + String(version)) != nil
    }

    /// Phase 2: delete the material. Allowed only for a RETIRED version, i.e. after the store layer
    /// has re-wrapped every record that referenced it. The current version cannot be forgotten.
    public func forget(version: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        let stored = try KeychainKeyProvider.readPointer(store: store, keyID: keyID)
        currentVersion = stored
        guard version != stored, version < stored else { throw VaultError.keyUnavailable(version: version) }
        guard try store.read(account: keyID + "/retired/v" + String(version)) != nil else { throw VaultError.keyVersionNotRetired(version: version) }
        try store.delete(account: keyID + "/kek/v" + String(version))
        try store.delete(account: keyID + "/retired/v" + String(version))
        cache[version] = nil
    }

    /// Explicit, user-initiated, irreversible wipe of this key set (all versions, markers, meta, pointer).
    /// Requires a confirmation naming this key id and acknowledging loss of every record.
    public func wipeAllKeys(confirmation: WipeConfirmation) throws {
        guard confirmation.keyID == keyID, confirmation.acknowledgesIrreversibleLoss else { throw VaultError.notAuthorized(.userInitiationRequired) }
        lock.lock(); defer { lock.unlock() }
        let stored = (try? KeychainKeyProvider.readPointer(store: store, keyID: keyID)) ?? currentVersion
        var v: UInt32 = 1
        while v <= stored + 2 {
            try store.delete(account: keyID + "/kek/v" + String(v))
            try store.delete(account: keyID + "/retired/v" + String(v))
            v += 1
        }
        try store.delete(account: keyID + "/current")
        try store.delete(account: keyID + "/meta")
        cache = [:]
    }

    // MARK: Cache (P03-00 §3)

    /// Drops every unwrapped KEK from memory. Call on device lock, app background,
    /// `protectedDataWillBecomeUnavailable`, and before handing control to untrusted code.
    public func purgeCache() { lock.lock(); cache = [:]; lock.unlock() }

    public var cachedVersions: [UInt32] { lock.lock(); defer { lock.unlock() }; return cache.keys.sorted() }

    // MARK: Internals

    private func writeKEK(version: UInt32) throws { lock.lock(); defer { lock.unlock() }; try writeKEKLocked(version: version) }

    private func writeKEKLocked(version: UInt32) throws {
        let kek = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
        let payload: [UInt8] = seActive ? try SecureEnclaveWrapper.wrap(kek: kek, accessibility: configuration.accessibility) : kek
        try store.add(account: keyID + "/kek/v" + String(version), data: Data(payload))
        cache[version] = (kek, (try? clock.now()) ?? 0)
    }

    private func loadKEK(version: UInt32) throws -> [UInt8] { lock.lock(); defer { lock.unlock() }; return try loadKEKLocked(version: version) }

    private func loadKEKLocked(version: UInt32) throws -> [UInt8] {
        let now = (try? clock.now()) ?? 0
        if let c = cache[version] {
            if cachePolicy.ttlSeconds > 0, now - c.loadedAt < cachePolicy.ttlSeconds { return c.kek }
            cache[version] = nil
        }
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
        if cachePolicy.ttlSeconds > 0 { cache[version] = (kek, now) }
        return kek
    }

    static func readPointer(store: KeychainStore, keyID: String) throws -> UInt32 {
        guard let cur = try store.read(account: keyID + "/current") else { throw VaultError.keychainCorrupted(reason: "missing current") }
        return try decodeVersion(Array(cur))
    }

    static func metaBytes(se: Bool, accessibility: KeychainAccessibility) -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-KEK-META"); e.appendU16(1)
        e.appendString(se ? "SE_WRAPPED" : "KEYCHAIN_ONLY"); e.appendString(accessibility.rawValue)
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
}
