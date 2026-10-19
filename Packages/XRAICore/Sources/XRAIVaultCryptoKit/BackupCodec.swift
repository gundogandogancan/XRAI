// Sealed backup export/import (decisions 3–4; hardening V32-02-01H §1, §5).
// Outer AES-256-GCM envelope under a key derived (HKDF-SHA256, context-separated) from the user's
// recovery key. All record metadata is inside the ciphertext. XRAI never sees the recovery key.
// `internal`: callers go through `SecureVault`, which authorizes and verifies first.
import CryptoKit
import Foundation
import XRAIVaultContracts

enum BackupCodec {
    static let kekInfo = Array("xrai.backup.kek.v2".utf8)      // wraps the per-record DEKs
    static let outerInfo = Array("xrai.backup.outer.v2".utf8)  // outer body AEAD key

    static func generateRecoveryKey() throws -> RecoveryKey {
        try RecoveryKey(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
    }

    static func randomSalt() -> [UInt8] {
        var rng = SystemRandomNumberGenerator()
        return (0..<SealedBackup.saltBytes).map { _ in UInt8.random(in: 0...255, using: &rng) }
    }

    static func deriveKeys(recoveryKey: RecoveryKey, salt: [UInt8]) -> (kek: [UInt8], outer: SymmetricKey) {
        let ikm = SymmetricKey(data: recoveryKey.bytes)
        let kek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: kekInfo, outputByteCount: 32)
        let outer = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: outerInfo, outputByteCount: 32)
        return (kek.withUnsafeBytes { Array($0) }, outer)
    }

    /// Caller (SecureVault) has already verified every envelope and authorized the export.
    static func export(verified envelopes: [RecordEnvelope], from device: any KeyProvider, recoveryKey: RecoveryKey, nowUnixSeconds: Int64) throws -> [UInt8] {
        let salt = randomSalt()
        let keys = deriveKeys(recoveryKey: recoveryKey, salt: salt)
        let backupProvider = try InMemoryKeyProvider(keyID: SealedBackup.backupKeyID, material: keys.kek)
        var entries: [RecordEnvelope] = []
        entries.reserveCapacity(envelopes.count)
        for env in envelopes {
            let dek = try device.unwrapDataKey(env.wrappedDEK)
            let w = try backupProvider.wrapDataKey(dek, boundTo: env.header.recordID)
            entries.append(env.replacingWrappedDEK(w))
        }
        let body = BackupBody(createdAtUnixSeconds: nowUnixSeconds, entries: entries).encode()
        let padded = BackupBody.pad(body)
        let nonce = AES.GCM.Nonce()
        let nonceBytes = nonce.withUnsafeBytes { Array($0) }
        let ad = SealedBackup.associatedData(formatVersion: SealedBackup.currentFormatVersion, salt: salt, nonce: nonceBytes)
        let box = try AES.GCM.seal(padded, using: keys.outer, nonce: nonce, authenticating: ad)
        return SealedBackup(salt: salt, nonce: nonceBytes, ciphertext: Array(box.ciphertext), tag: Array(box.tag)).encode()
    }

    /// Decode → outer AEAD open → unpad → body decode (limits, duplicates, tier floors) → re-wrap DEKs
    /// under the new device key. Returns envelopes still to be payload-verified by the caller.
    static func restore(bytes: [UInt8], recoveryKey: RecoveryKey, into device: any KeyProvider) throws -> (BackupBody, [RecordEnvelope]) {
        let sealed = try SealedBackup.decode(bytes)
        let keys = deriveKeys(recoveryKey: recoveryKey, salt: sealed.salt)
        let padded: [UInt8]
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed.nonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
            padded = Array(try AES.GCM.open(box, using: keys.outer, authenticating: sealed.associatedData))
        } catch {
            throw VaultError.backupIntegrityFailed
        }
        let body = try BackupBody.decode(try BackupBody.unpad(padded))
        let backupProvider = try InMemoryKeyProvider(keyID: SealedBackup.backupKeyID, material: keys.kek)
        var out: [RecordEnvelope] = []
        out.reserveCapacity(body.entries.count)
        for env in body.entries {
            let dek = try backupProvider.unwrapDataKey(env.wrappedDEK)
            let w = try device.wrapDataKey(dek, boundTo: env.header.recordID)
            out.append(env.replacingWrappedDEK(w))
        }
        return (body, out)
    }
}
