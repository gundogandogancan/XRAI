// Portable backup export/import (decisions 3 and 4). End-to-end encrypted under a key derived from
// the user's recovery key. Payload ciphertext is never decrypted during export or import; only DEKs
// are re-wrapped. XRAI never sees or stores the recovery key.
import CryptoKit
import Foundation
import XRAIVaultContracts

public enum BackupCodec {
    static let kekInfo = Array("xrai.backup.kek.v1".utf8)
    static let macInfo = Array("xrai.backup.mac.v1".utf8)
    public static let saltBytes = 16

    public static func generateRecoveryKey() throws -> RecoveryKey {
        try RecoveryKey(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
    }

    static func deriveKeys(recoveryKey: RecoveryKey, salt: [UInt8]) -> (kek: [UInt8], mac: SymmetricKey) {
        let ikm = SymmetricKey(data: recoveryKey.bytes)
        let kek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: kekInfo, outputByteCount: 32)
        let mac = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: macInfo, outputByteCount: 32)
        return (kek.withUnsafeBytes { Array($0) }, mac)
    }

    /// Export: unwrap each DEK with the device provider, re-wrap under the backup KEK, MAC the result.
    public static func export(
        _ envelopes: [RecordEnvelope],
        from device: any KeyProvider,
        recoveryKey: RecoveryKey,
        nowUnixSeconds: Int64
    ) throws -> PortableBackup {
        var salt = [UInt8](repeating: 0, count: saltBytes)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<saltBytes { salt[i] = UInt8.random(in: 0...255, using: &rng) }
        let keys = deriveKeys(recoveryKey: recoveryKey, salt: salt)
        let backupProvider = try InMemoryKeyProvider(keyID: PortableBackup.backupKeyID, material: keys.kek)
        var entries: [RecordEnvelope] = []
        entries.reserveCapacity(envelopes.count)
        for env in envelopes {
            let dek = try device.unwrapDataKey(env.wrappedDEK)
            let w = try backupProvider.wrapDataKey(dek, boundTo: env.header.recordID)
            entries.append(env.replacingWrappedDEK(w))
        }
        let authenticated = PortableBackup.authenticatedBytes(formatVersion: PortableBackup.currentFormatVersion, salt: salt, createdAtUnixSeconds: nowUnixSeconds, entries: entries)
        let tag = Array(HMAC<SHA256>.authenticationCode(for: authenticated, using: keys.mac))
        return PortableBackup(salt: salt, createdAtUnixSeconds: nowUnixSeconds, entries: entries, integrityTag: tag)
    }

    /// Import on a (new) device: verify MAC, unwrap under the backup KEK, re-wrap under the new device key.
    public static func restore(
        _ backup: PortableBackup,
        recoveryKey: RecoveryKey,
        into device: any KeyProvider
    ) throws -> [RecordEnvelope] {
        guard backup.formatVersion == PortableBackup.currentFormatVersion else { throw VaultError.unsupportedFormat(backup.formatVersion) }
        let keys = deriveKeys(recoveryKey: recoveryKey, salt: backup.salt)
        let expected = Array(HMAC<SHA256>.authenticationCode(for: backup.authenticatedBytes, using: keys.mac))
        guard ConstantTime.equal(expected, backup.integrityTag) else { throw VaultError.backupIntegrityFailed }
        let backupProvider = try InMemoryKeyProvider(keyID: PortableBackup.backupKeyID, material: keys.kek)
        var out: [RecordEnvelope] = []
        out.reserveCapacity(backup.entries.count)
        for env in backup.entries {
            let dek = try backupProvider.unwrapDataKey(env.wrappedDEK)
            let w = try device.wrapDataKey(dek, boundTo: env.header.recordID)
            out.append(env.replacingWrappedDEK(w))
        }
        return out
    }

    public static func restore(bytes: [UInt8], recoveryKey: RecoveryKey, into device: any KeyProvider) throws -> [RecordEnvelope] {
        try restore(try PortableBackup.decode(bytes), recoveryKey: recoveryKey, into: device)
    }
}
