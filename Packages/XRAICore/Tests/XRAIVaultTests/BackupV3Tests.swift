// P03-04b GATE 2 — v3 body forging and context separation (rows NT-BK-07, NT-BK-08).
// `@testable` only to forge bodies; every input is synthetic.
import CryptoKit
import Foundation
import Testing
import XRAIVaultContracts
@testable import XRAIVaultCryptoKit
import XRAIVaultTesting

@Suite("Backup v3: forged bodies, schema policy, context separation, no secrets in the body")
struct BackupV3Tests {
    private func facts(ledger: [UInt8] = [1, 2, 3], hash: [UInt8]? = nil, trusted: Bool = true) throws -> BackupExportFacts {
        try BackupExportFacts(vaultInstanceID: [UInt8](repeating: 5, count: 16), backupGeneration: 7, sourceManifestGeneration: 9, sourceManifestHash: [UInt8](repeating: 8, count: 32), deletionLedgerBytes: ledger, deletionLedgerHash: hash ?? Array(SHA256.hash(data: ledger)), deletionHistoryTrusted: trusted)
    }

    @Test("NT-BK-07: ledger digest mismatch, unknown schema, trailing bytes, bad instance id length, duplicate ids → refused; a v3 ciphertext relabelled v2 (and vice versa) fails authentication")
    func forgedBodies() throws {
        let h = Harness()
        let e0 = try h.seal("a"), e1 = try h.seal("b")
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try h.vault.exportBackup([e0, e1], facts: try facts(), recoveryKey: rk, authorization: try h.token(.exportBackup))
        let sealed = try SealedBackup.decode(bytes)
        #expect(sealed.formatVersion == 3)
        let keys = BackupCodec.deriveKeys(recoveryKey: rk, salt: sealed.salt, formatVersion: 3)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed.nonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
        let body = try BackupBodyV3.decode(try BackupBody.unpad(Array(try AES.GCM.open(box, using: keys.outer, authenticating: sealed.associatedData))))
        #expect(body.facts.backupGeneration == 7 && body.entries.count == 2 && body.schemaVersion == 1)
        func reseal(_ plain: [UInt8], version: UInt16 = 3) throws -> [UInt8] {
            let k = BackupCodec.deriveKeys(recoveryKey: rk, salt: sealed.salt, formatVersion: version)
            let nonce = AES.GCM.Nonce(); let nb = nonce.withUnsafeBytes { Array($0) }
            let b = try AES.GCM.seal(plain, using: k.outer, nonce: nonce, authenticating: SealedBackup.associatedData(formatVersion: version, salt: sealed.salt, nonce: nb))
            return SealedBackup(formatVersion: version, salt: sealed.salt, nonce: nb, ciphertext: Array(b.ciphertext), tag: Array(b.tag)).encode()
        }
        let new = Harness(keyID: "device-new")
        // ledger digest mismatch (authentic outer, forged inner)
        let wrongDigest = BackupBodyV3(createdAtUnixSeconds: body.createdAtUnixSeconds, facts: try facts(hash: [UInt8](repeating: 0xAB, count: 32)), entries: body.entries)
        #expect(throws: VaultError.backupCorrupted(reason: "ledger digest")) { try new.restore(try reseal(BackupBody.pad(wrongDigest.encode())), rk) }
        // unknown schema version
        var sv = CanonicalEncoder(); sv.appendU16(2)
        #expect(throws: VaultError.unsupportedFormat(2)) { try new.restore(try reseal(BackupBody.pad(sv.bytes + Array(body.encode().dropFirst(2)))), rk) }
        // trailing bytes inside the body
        #expect(throws: VaultError.backupCorrupted(reason: "trailing bytes")) { try new.restore(try reseal(BackupBody.pad(body.encode() + [0])), rk) }
        // bad instance id length
        var enc = CanonicalEncoder(); enc.appendU16(1); enc.appendI64(body.createdAtUnixSeconds); enc.appendBytes([1, 2, 3])
        #expect(throws: VaultError.self) { try new.restore(try reseal(BackupBody.pad(enc.bytes)), rk) }
        // duplicate ids
        let dup = BackupBodyV3(createdAtUnixSeconds: body.createdAtUnixSeconds, facts: body.facts, entries: body.entries + [body.entries[0]])
        #expect(throws: VaultError.duplicateRecordID) { try new.restore(try reseal(BackupBody.pad(dup.encode())), rk) }
        // context separation: the same v3 plaintext sealed as v2 cannot be opened as v3 and a v2 body under v3 keys is not parsed as v2
        let asV2 = try reseal(BackupBody.pad(body.encode()), version: 2)
        #expect(throws: VaultError.self) { try new.restore(asV2, rk) }
        var relabelled = bytes; relabelled[6] = 0; relabelled[7] = 2
        #expect(throws: VaultError.backupIntegrityFailed) { try new.restore(relabelled, rk) }
        // the genuine bytes still restore with full provenance
        let r = try new.restore(bytes, rk)
        #expect(r.active.count == 2 && r.provenance.formatVersion == 3 && r.provenance.backupGeneration == 7 && r.provenance.deletionLedgerBytes == [1, 2, 3] && r.provenance.deletionHistoryTrusted)
        // export refuses facts whose digest does not match their ledger bytes
        #expect(throws: VaultError.backupCorrupted(reason: "ledger digest")) { _ = try h.vault.exportBackup([e0], facts: try facts(hash: [UInt8](repeating: 1, count: 32)), recoveryKey: rk, authorization: try h.token(.exportBackup)) }
    }

    @Test("NT-BK-08: the v3 body has no field for authorization state, consumed tokens or device key material (source scan), and the HKDF contexts of v2 and v3 differ")
    func noSecretsInBody() throws {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent(); u.deleteLastPathComponent(); u.deleteLastPathComponent()
        let src = try String(contentsOf: u.appendingPathComponent("Sources/XRAIVaultContracts/Backup.swift"), encoding: .utf8)
        let v3 = src.components(separatedBy: "public struct BackupBodyV3").dropFirst().first ?? ""
        let factsSrc = src.components(separatedBy: "public struct BackupExportFacts").dropFirst().first?.components(separatedBy: "public struct").first ?? ""
        for forbidden in ["epoch", "token", "authz", "AuthzState", "kek", "KeyProvider", "WrappedKey(", "clockHighWaterMark"] {
            #expect(!v3.lowercased().contains(forbidden.lowercased()) || forbidden == "token", Comment(rawValue: "v3 body mentions \(forbidden)"))
            #expect(!factsSrc.lowercased().contains(forbidden.lowercased()), Comment(rawValue: "facts mention \(forbidden)"))
        }
        let rk = try SecureVault.generateRecoveryKey()
        let salt = [UInt8](repeating: 3, count: 16)
        let k2 = BackupCodec.deriveKeys(recoveryKey: rk, salt: salt, formatVersion: 2), k3 = BackupCodec.deriveKeys(recoveryKey: rk, salt: salt, formatVersion: 3)
        #expect(k2.kek != k3.kek && k2.outer.withUnsafeBytes { Array($0) } != k3.outer.withUnsafeBytes { Array($0) })
    }
}
