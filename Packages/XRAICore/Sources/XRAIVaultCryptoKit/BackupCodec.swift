// Sealed backup export/import (decisions 3–4; hardening V32-02-01H §1, §5; H2 G4).
// Outer AES-256-GCM envelope under a key derived (HKDF-SHA256, context-separated) from the user's
// recovery key. All record metadata is inside the ciphertext. XRAI never sees the recovery key.
// `internal`: callers go through `SecureVault`, which authorizes and verifies first.
import CryptoKit
import Foundation
import XRAIVaultContracts

enum BackupCodec {
    static let kekInfo = Array("xrai.backup.kek.v2".utf8)      // wraps the per-record DEKs (v2 bodies)
    static let outerInfo = Array("xrai.backup.outer.v2".utf8)  // outer body AEAD key (v2 bodies)
    static let kekInfoV3 = Array("xrai.backup.kek.v3".utf8)    // P03-04b: context-separated per format
    static let outerInfoV3 = Array("xrai.backup.outer.v3".utf8)

    static func generateRecoveryKey() throws -> RecoveryKey {
        try RecoveryKey(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
    }

    static func randomSalt() -> [UInt8] {
        var rng = SystemRandomNumberGenerator()
        return (0..<SealedBackup.saltBytes).map { _ in UInt8.random(in: 0...255, using: &rng) }
    }

    static func deriveKeys(recoveryKey: RecoveryKey, salt: [UInt8], formatVersion: UInt16 = SealedBackup.legacyFormatVersion) -> (kek: [UInt8], outer: SymmetricKey) {
        let ikm = SymmetricKey(data: recoveryKey.bytes)
        let v3 = formatVersion == SealedBackup.currentFormatVersion
        let kek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: v3 ? kekInfoV3 : kekInfo, outputByteCount: 32)
        let outer = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: v3 ? outerInfoV3 : outerInfo, outputByteCount: 32)
        return (kek.withUnsafeBytes { Array($0) }, outer)
    }

    /// Wraps every DEK under the backup KEK (shared by v2 and v3 export).
    private static func wrapEntries(_ envelopes: [RecordEnvelope], device: any KeyProvider, kek: [UInt8]) throws -> [RecordEnvelope] {
        let backupWrapper = try GCMKeyWrapper(keyID: SealedBackup.backupKeyID, version: 1, material: kek)
        var entries: [RecordEnvelope] = []
        entries.reserveCapacity(envelopes.count)
        var runningBytes = 0
        for env in envelopes {
            runningBytes += env.ciphertext.count + 256
            guard runningBytes <= BackupLimits.maxBackupBytes else { throw VaultError.limitExceeded("backup size") }
            let dek = try device.unwrapDataKey(env.wrappedDEK)
            let w = try backupWrapper.wrap(dek, boundTo: env.header.recordID)
            entries.append(env.replacingWrappedDEK(w))
        }
        return entries
    }

    private static func sealOuter(padded: [UInt8], salt: [UInt8], outer: SymmetricKey, formatVersion: UInt16) throws -> [UInt8] {
        guard padded.count + 64 <= BackupLimits.maxBackupBytes else { throw VaultError.limitExceeded("backup size") }
        let nonce = AES.GCM.Nonce()
        let nonceBytes = nonce.withUnsafeBytes { Array($0) }
        let ad = SealedBackup.associatedData(formatVersion: formatVersion, salt: salt, nonce: nonceBytes)
        let box = try AES.GCM.seal(padded, using: outer, nonce: nonce, authenticating: ad)
        return SealedBackup(formatVersion: formatVersion, salt: salt, nonce: nonceBytes, ciphertext: Array(box.ciphertext), tag: Array(box.tag)).encode()
    }

    /// P03-04b: v3 export. The facts come from the store; the ledger digest is verified here so a
    /// body whose embedded history does not match its own digest is never produced.
    static func exportV3(verified envelopes: [RecordEnvelope], from device: any KeyProvider, recoveryKey: RecoveryKey, nowUnixSeconds: Int64, facts: BackupExportFacts) throws -> [UInt8] {
        guard Array(SHA256.hash(data: facts.deletionLedgerBytes)) == facts.deletionLedgerHash else { throw VaultError.backupCorrupted(reason: "ledger digest") }
        let salt = randomSalt()
        let keys = deriveKeys(recoveryKey: recoveryKey, salt: salt, formatVersion: SealedBackup.currentFormatVersion)
        let entries = try wrapEntries(envelopes, device: device, kek: keys.kek)
        let padded = BackupBody.pad(BackupBodyV3(createdAtUnixSeconds: nowUnixSeconds, facts: facts, entries: entries).encode())
        return try sealOuter(padded: padded, salt: salt, outer: keys.outer, formatVersion: SealedBackup.currentFormatVersion)
    }

    /// Caller (SecureVault) has already verified every envelope and authorized the export.
    /// Size limit (G4): the padded body is measured BEFORE sealing; export is refused above
    /// `BackupLimits.maxBackupBytes`. Memory: the whole backup is built in memory (≈2× its size);
    /// streaming export is deferred until a persistence layer exists.
    /// LEGACY v2 export (store-less; kept so v2 compatibility can be tested). Production exports are v3.
    static func export(verified envelopes: [RecordEnvelope], from device: any KeyProvider, recoveryKey: RecoveryKey, nowUnixSeconds: Int64) throws -> [UInt8] {
        let salt = randomSalt()
        let keys = deriveKeys(recoveryKey: recoveryKey, salt: salt, formatVersion: SealedBackup.legacyFormatVersion)
        let entries = try wrapEntries(envelopes, device: device, kek: keys.kek)
        let padded = BackupBody.pad(BackupBody(createdAtUnixSeconds: nowUnixSeconds, entries: entries).encode())
        return try sealOuter(padded: padded, salt: salt, outer: keys.outer, formatVersion: SealedBackup.legacyFormatVersion)
    }

    /// Decode → outer AEAD open → unpad → body decode (limits, duplicates, tier floors) → re-wrap DEKs
    /// under the new device key. Returns envelopes still to be payload-verified by the caller.
    static func restore(bytes: [UInt8], recoveryKey: RecoveryKey, into device: any KeyProvider) throws -> (BackupProvenance, [RecordEnvelope]) {
        let sealed = try SealedBackup.decode(bytes)
        let keys = deriveKeys(recoveryKey: recoveryKey, salt: sealed.salt, formatVersion: sealed.formatVersion)
        let padded: [UInt8]
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed.nonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
            padded = Array(try AES.GCM.open(box, using: keys.outer, authenticating: sealed.associatedData))
        } catch {
            throw VaultError.backupIntegrityFailed
        }
        let plain = try BackupBody.unpad(padded)
        let entries: [RecordEnvelope]
        let provenance: BackupProvenance
        if sealed.formatVersion == SealedBackup.currentFormatVersion {
            let body = try BackupBodyV3.decode(plain)
            guard Array(SHA256.hash(data: body.facts.deletionLedgerBytes)) == body.facts.deletionLedgerHash else { throw VaultError.backupCorrupted(reason: "ledger digest") }
            entries = body.entries
            provenance = BackupProvenance(formatVersion: 3, bodySchemaVersion: body.schemaVersion, createdAtUnixSeconds: body.createdAtUnixSeconds, vaultInstanceID: body.facts.vaultInstanceID, backupGeneration: body.facts.backupGeneration, sourceManifestGeneration: body.facts.sourceManifestGeneration, sourceManifestHash: body.facts.sourceManifestHash, deletionLedgerBytes: body.facts.deletionLedgerBytes, deletionLedgerHash: body.facts.deletionLedgerHash, deletionHistoryTrusted: body.facts.deletionHistoryTrusted, excludedAttachmentCount: body.facts.excludedAttachmentCount)
        } else {
            let body = try BackupBody.decode(plain)
            entries = body.entries
            provenance = BackupProvenance(formatVersion: 2, bodySchemaVersion: 0, createdAtUnixSeconds: body.createdAtUnixSeconds, vaultInstanceID: nil, backupGeneration: nil, sourceManifestGeneration: nil, sourceManifestHash: nil, deletionLedgerBytes: nil, deletionLedgerHash: nil)
        }
        let backupWrapper = try GCMKeyWrapper(keyID: SealedBackup.backupKeyID, version: 1, material: keys.kek)
        var out: [RecordEnvelope] = []
        out.reserveCapacity(entries.count)
        for env in entries {
            let dek = try backupWrapper.unwrap(env.wrappedDEK)
            let w = try device.wrapDataKey(dek, boundTo: env.header.recordID)
            out.append(env.replacingWrappedDEK(w))
        }
        return (provenance, out)
    }
}
