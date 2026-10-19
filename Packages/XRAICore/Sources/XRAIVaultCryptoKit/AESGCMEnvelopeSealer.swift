// XRAIVaultCryptoKit — the ONLY module in XRAICore allowed to import CryptoKit.
// Adapter for the XRAIVaultContracts ports using Apple CryptoKit AES-256-GCM (decision 5).
// No home-made primitives. No persistence. No networking.
//
// Hardening V32-02-01H §2: the raw sealer is `internal`. The only public way to seal, open, export
// or restore is `SecureVault`, which enforces policy, consent authority and tier floors first.
import CryptoKit
import Foundation
import XRAIVaultContracts

public enum CryptoConstants {
    public static let gcmNonceBytes = 12
    public static let gcmTagBytes = 16
    public static let keyBytes = 32
}

/// AES-256-GCM envelope sealer: random 256-bit DEK per record, 96-bit random nonce per seal,
/// header canonical bytes as associated data, DEK wrapped by the `KeyProvider`.
struct AESGCMEnvelopeSealer: EnvelopeSealer {
    let keyProvider: any KeyProvider

    init(keyProvider: any KeyProvider) { self.keyProvider = keyProvider }

    func seal(plaintext: [UInt8], descriptor: RecordDescriptor) throws -> RecordEnvelope {
        let header = EnvelopeHeader(algorithm: .aes256gcm, descriptor: descriptor)
        try header.validate()
        let dek = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce() // fresh system-random 96-bit nonce per seal
        let box = try AES.GCM.seal(plaintext, using: dek, nonce: nonce, authenticating: header.canonicalBytes())
        let dekBytes = dek.withUnsafeBytes { Array($0) }
        let wrapped = try keyProvider.wrapDataKey(dekBytes, boundTo: descriptor.recordID)
        return RecordEnvelope(
            header: header,
            wrappedDEK: wrapped,
            nonce: nonce.withUnsafeBytes { Array($0) },
            ciphertext: Array(box.ciphertext),
            tag: Array(box.tag)
        )
    }

    func open(_ envelope: RecordEnvelope) throws -> [UInt8] {
        let h = envelope.header
        try h.validate()
        guard envelope.nonce.count == CryptoConstants.gcmNonceBytes else {
            throw VaultError.invalidLength(field: "nonce", expected: CryptoConstants.gcmNonceBytes, actual: envelope.nonce.count)
        }
        guard envelope.tag.count == CryptoConstants.gcmTagBytes else {
            throw VaultError.invalidLength(field: "tag", expected: CryptoConstants.gcmTagBytes, actual: envelope.tag.count)
        }
        guard envelope.wrappedDEK.boundRecordID == h.recordID else { throw VaultError.authenticationFailed }
        let dekBytes = try keyProvider.unwrapDataKey(envelope.wrappedDEK)
        guard dekBytes.count == CryptoConstants.keyBytes else {
            throw VaultError.invalidLength(field: "dek", expected: CryptoConstants.keyBytes, actual: dekBytes.count)
        }
        let dek = SymmetricKey(data: dekBytes)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: envelope.nonce), ciphertext: envelope.ciphertext, tag: envelope.tag)
            let plain = try AES.GCM.open(box, using: dek, authenticating: h.canonicalBytes())
            return Array(plain)
        } catch {
            throw VaultError.authenticationFailed
        }
    }

    func rewrap(_ envelope: RecordEnvelope) throws -> RecordEnvelope {
        try envelope.header.validate()
        let dek = try keyProvider.unwrapDataKey(envelope.wrappedDEK)
        let w = try keyProvider.wrapDataKey(dek, boundTo: envelope.header.recordID)
        return envelope.replacingWrappedDEK(w)
    }
}

/// Wraps/unwraps DEKs with an in-memory AES-256-GCM key-encryption key.
///
/// This is the TEST DOUBLE and development provider. It is NOT the production provider: the
/// production `KeychainKeyProvider` (Keychain-stored KEK, Secure Enclave wrapping where the device
/// supports it, `ThisDeviceOnly` accessibility) is a P02-02 task that needs a physical iPhone to verify.
public final class InMemoryKeyProvider: KeyProvider, @unchecked Sendable {
    public let keyID: String
    private let lock = NSLock()
    private var keks: [UInt32: SymmetricKey] = [:]
    private var current: UInt32

    public init(keyID: String) {
        self.keyID = keyID
        self.current = 1
        self.keks[1] = SymmetricKey(size: .bits256)
    }

    /// Deterministic variant for backup keys derived from a recovery key.
    init(keyID: String, material: [UInt8]) throws {
        guard material.count == CryptoConstants.keyBytes else {
            throw VaultError.invalidLength(field: "kek", expected: CryptoConstants.keyBytes, actual: material.count)
        }
        self.keyID = keyID
        self.current = 1
        self.keks[1] = SymmetricKey(data: material)
    }

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
    }
}
