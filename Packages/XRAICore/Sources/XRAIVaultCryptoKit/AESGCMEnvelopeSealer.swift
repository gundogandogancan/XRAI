// XRAIVaultCryptoKit — the ONLY module in XRAICore allowed to import CryptoKit.
// Adapter for the XRAIVaultContracts ports using Apple CryptoKit AES-256-GCM (decision 5).
// No home-made primitives. No persistence. No networking.
//
// Hardening V32-02-01H/H2: the raw sealer and key wrapper are `internal`. The only public way to
// seal, open, export or restore is `SecureVault`, which enforces authorization, consent, clock and
// tier floors first. The development `InMemoryKeyProvider` lives in the separate `XRAIVaultTesting`
// target so production code cannot link it by accident.
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

    /// Verifies the payload first (G4): a tampered envelope is never re-wrapped as if valid.
    func rewrap(_ envelope: RecordEnvelope) throws -> RecordEnvelope {
        _ = try open(envelope)
        let dek = try keyProvider.unwrapDataKey(envelope.wrappedDEK)
        let w = try keyProvider.wrapDataKey(dek, boundTo: envelope.header.recordID)
        return envelope.replacingWrappedDEK(w)
    }
}

/// Internal AES-256-GCM DEK wrapper over a raw KEK. Used for the backup key derived from the
/// recovery key. It is NOT a `KeyProvider` and is not exposed.
struct GCMKeyWrapper {
    let keyID: String
    let version: UInt32
    private let kek: SymmetricKey

    init(keyID: String, version: UInt32, material: [UInt8]) throws {
        guard material.count == CryptoConstants.keyBytes else {
            throw VaultError.invalidLength(field: "kek", expected: CryptoConstants.keyBytes, actual: material.count)
        }
        self.keyID = keyID
        self.version = version
        self.kek = SymmetricKey(data: material)
    }

    func wrap(_ dek: [UInt8], boundTo recordID: RecordID) throws -> WrappedKey {
        let nonce = AES.GCM.Nonce()
        let ad = WrappedKey.associatedData(keyID: keyID, keyVersion: version, recordID: recordID)
        let box = try AES.GCM.seal(dek, using: kek, nonce: nonce, authenticating: ad)
        return WrappedKey(keyID: keyID, keyVersion: version, boundRecordID: recordID,
                          nonce: nonce.withUnsafeBytes { Array($0) }, ciphertext: Array(box.ciphertext), tag: Array(box.tag))
    }

    func unwrap(_ wrapped: WrappedKey) throws -> [UInt8] {
        guard wrapped.keyID == keyID, wrapped.keyVersion == version else { throw VaultError.keyUnavailable(version: wrapped.keyVersion) }
        let ad = WrappedKey.associatedData(keyID: wrapped.keyID, keyVersion: wrapped.keyVersion, recordID: wrapped.boundRecordID)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: wrapped.nonce), ciphertext: wrapped.ciphertext, tag: wrapped.tag)
            return Array(try AES.GCM.open(box, using: kek, authenticating: ad))
        } catch {
            throw VaultError.authenticationFailed
        }
    }
}
