// XRAIVaultTesting — development and test doubles. NEVER link this target into the app.
// A test (`CompositionBoundaryTests`) asserts that no non-test target in Package.swift depends on it.
import CryptoKit
import Foundation
import XRAIVaultContracts

/// Wraps/unwraps DEKs with an in-memory AES-256-GCM key-encryption key. Development/test ONLY.
/// The production `KeychainKeyProvider` (P02-02) replaces it.
public final class InMemoryKeyProvider: RetirableKeyProvider, @unchecked Sendable {
    public let keyID: String
    private let lock = NSLock()
    private var keks: [UInt32: SymmetricKey] = [:]
    private var current: UInt32
    private var retired: Set<UInt32> = []

    public init(keyID: String) {
        self.keyID = keyID
        self.current = 1
        self.keks[1] = SymmetricKey(size: .bits256)
    }

    public var protection: KeyProtection { .inMemoryTestOnly }

    public var currentKey: KeyIdentity {
        lock.lock(); defer { lock.unlock() }
        return KeyIdentity(keyID: keyID, version: current)
    }

    public var availableVersions: [UInt32] {
        lock.lock(); defer { lock.unlock() }
        return keks.keys.sorted()
    }

    public func wrapDataKey(_ dek: [UInt8], boundTo recordID: RecordID) throws -> WrappedKey {
        let (version, kek): (UInt32, SymmetricKey) = {
            lock.lock(); defer { lock.unlock() }
            return (current, keks[current]!)
        }()
        let nonce = AES.GCM.Nonce()
        let ad = WrappedKey.associatedData(keyID: keyID, keyVersion: version, recordID: recordID)
        let box = try AES.GCM.seal(dek, using: kek, nonce: nonce, authenticating: ad)
        return WrappedKey(keyID: keyID, keyVersion: version, boundRecordID: recordID,
                          nonce: nonce.withUnsafeBytes { Array($0) }, ciphertext: Array(box.ciphertext), tag: Array(box.tag))
    }

    public func unwrapDataKey(_ wrapped: WrappedKey) throws -> [UInt8] {
        guard wrapped.keyID == keyID else { throw VaultError.keyUnavailable(version: wrapped.keyVersion) }
        let kek: SymmetricKey? = {
            lock.lock(); defer { lock.unlock() }
            return keks[wrapped.keyVersion]
        }()
        guard let kek else { throw VaultError.keyUnavailable(version: wrapped.keyVersion) }
        let ad = WrappedKey.associatedData(keyID: wrapped.keyID, keyVersion: wrapped.keyVersion, recordID: wrapped.boundRecordID)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: wrapped.nonce), ciphertext: wrapped.ciphertext, tag: wrapped.tag)
            return Array(try AES.GCM.open(box, using: kek, authenticating: ad))
        } catch {
            throw VaultError.authenticationFailed
        }
    }

    public func rotate() throws -> KeyIdentity {
        lock.lock(); defer { lock.unlock() }
        current += 1
        keks[current] = SymmetricKey(size: .bits256)
        return KeyIdentity(keyID: keyID, version: current)
    }

    public func forget(version: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        guard version != current else { throw VaultError.keyUnavailable(version: version) }
        keks[version] = nil
        retired.remove(version)
    }

    // P03-04: two-phase forgetting mirror of the production provider (retire never forgets by itself).
    public func retire(version: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        guard version < current else { throw VaultError.keyUnavailable(version: version) }
        retired.insert(version)
    }
    public func isRetired(version: UInt32) throws -> Bool { lock.lock(); defer { lock.unlock() }; return retired.contains(version) }
    /// Test hook: wraps under an OLD version (simulates a stale writer) — never exists in production providers.
    public func wrapDataKeyUnderVersion(_ dek: [UInt8], version: UInt32, boundTo recordID: RecordID) throws -> WrappedKey {
        let kek: SymmetricKey? = { lock.lock(); defer { lock.unlock() }; return keks[version] }()
        guard let kek else { throw VaultError.keyUnavailable(version: version) }
        let nonce = AES.GCM.Nonce()
        let ad = WrappedKey.associatedData(keyID: keyID, keyVersion: version, recordID: recordID)
        let box = try AES.GCM.seal(dek, using: kek, nonce: nonce, authenticating: ad)
        return WrappedKey(keyID: keyID, keyVersion: version, boundRecordID: recordID,
                          nonce: nonce.withUnsafeBytes { Array($0) }, ciphertext: Array(box.ciphertext), tag: Array(box.tag))
    }
    /// Test hook: drops a version WITHOUT retirement (simulates a Keychain item that vanished, T28).
    public func simulateKeyLoss(version: UInt32) { lock.lock(); keks[version] = nil; lock.unlock() }
}

/// In-memory anchor (test/dev). Production: `KeychainAnchorStore`.
public final class InMemoryAnchorStore: VaultAnchorStore, @unchecked Sendable {
    private let lock = NSLock()
    private var anchor: VaultAnchor?
    public init(_ initial: VaultAnchor? = nil) { anchor = initial }
    public func readAnchor() throws -> VaultAnchor? { lock.lock(); defer { lock.unlock() }; return anchor }
    public func writeAnchor(_ a: VaultAnchor) throws { lock.lock(); anchor = a; lock.unlock() }
    public func clearAnchor() throws { lock.lock(); anchor = nil; lock.unlock() }
    /// Test hook: overwrite with an arbitrary value (simulates a stale/foreign anchor).
    public func set(_ a: VaultAnchor?) { lock.lock(); anchor = a; lock.unlock() }
}

/// In-memory consent registry. Only receipts registered HERE grant anything.
public final class InMemoryConsentAuthority: ConsentAuthority, @unchecked Sendable {
    private let lock = NSLock()
    private var receipts: [String: ConsentReceipt] = [:]

    public init(_ receipts: [ConsentReceipt] = []) { for r in receipts { self.receipts[r.id] = r } }

    public func register(_ r: ConsentReceipt) { lock.lock(); receipts[r.id] = r; lock.unlock() }
    public func revoke(id: String, atUnixSeconds t: Int64) {
        lock.lock(); defer { lock.unlock() }
        if let r = receipts[id] { receipts[id] = r.revoked(atUnixSeconds: t) }
    }

    public func activeGrant(for dataClass: DataClass, purpose: String, destination: Destination, atUnixSeconds now: Int64) -> ConsentGrant? {
        lock.lock(); defer { lock.unlock() }
        for r in receipts.values where r.covers(dataClass, purpose: purpose, destination: destination, atUnixSeconds: now) {
            if let s = r.scopes.first(where: { $0.dataClass == dataClass && $0.purpose == purpose && $0.destination == destination }) {
                return ConsentGrant(receiptID: r.id, scope: s)
            }
        }
        return nil
    }
}

/// Manually advanced clock for deterministic tests.
public final class ManualClock: VaultClock, @unchecked Sendable {
    private let lock = NSLock()
    private var time: Int64
    public init(_ start: Int64) { self.time = start }
    public func now() throws -> Int64 { lock.lock(); defer { lock.unlock() }; return time }
    public func set(_ t: Int64) { lock.lock(); time = t; lock.unlock() }
    public func advance(_ seconds: Int64) { lock.lock(); time += seconds; lock.unlock() }
}

/// In-memory quarantine registry (test/dev). Production needs a persisted, integrity-protected one.
public final class InMemoryQuarantineRegistry: QuarantineAuthority, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String: DenialReason] = [:]
    public init() {}
    public func isQuarantined(_ recordID: RecordID) -> Bool { lock.lock(); defer { lock.unlock() }; return ids[recordID.hex] != nil }
    public func quarantine(_ recordID: RecordID, reason: DenialReason) { lock.lock(); ids[recordID.hex] = reason; lock.unlock() }
    public func release(_ recordID: RecordID) { lock.lock(); ids[recordID.hex] = nil; lock.unlock() }
    public var count: Int { lock.lock(); defer { lock.unlock() }; return ids.count }
}
