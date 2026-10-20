import CryptoKit
import Foundation
import Testing
import XRAIVaultContracts
@testable import XRAIVaultCryptoKit
import XRAIVaultTesting

// Adversarial tests for the CryptoKit adapter through the authorized `SecureVault` facade.
// Every input here is synthetic; no real user data. `@testable` is used only to forge backups.

@Suite("AES-256-GCM envelope: round trip and structure")
struct SealRoundTripTests {
    @Test("seal/open round-trips for every class (consent granted where required) and ciphertext hides the plaintext")
    func roundTrip() throws {
        let h = Harness()
        for dc in DataClass.allCases {
            let purpose = dc.requiresPurposeConsentToStore ? "lens" : ""
            if dc.requiresPurposeConsentToStore { h.grant(dc, purpose: purpose) }
            let plain = Array("synthetic-\(dc.rawValue)-1998-06-30".utf8)
            let env = try h.seal(String(decoding: plain, as: UTF8.self), dc, purpose: purpose)
            #expect(env.header.dataClass == dc && env.header.privacyTier == dc.minimumTier && env.header.formatVersion == 2 && env.header.consentPurpose == purpose)
            #expect(env.nonce.count == 12 && env.tag.count == 16 && env.ciphertext.count == plain.count)
            #expect(env.ciphertext != plain && !bytesContain(env.ciphertext, Array("1998".utf8)))
            #expect(try h.open(env) == plain)
        }
        let empty = try h.seal("")
        #expect(empty.ciphertext.isEmpty && empty.tag.count == 16)
        #expect(try h.open(empty) == [])
    }

    @Test("nonce strategy: fresh random nonce per seal; same plaintext never repeats nonce or ciphertext")
    func nonces() throws {
        let h = Harness()
        var nonces = Set<[UInt8]>(), cts = Set<[UInt8]>(), wrapNonces = Set<[UInt8]>()
        for _ in 0..<500 {
            let env = try h.seal("same-plaintext")
            nonces.insert(env.nonce); cts.insert(env.ciphertext); wrapNonces.insert(env.wrappedDEK.nonce)
        }
        #expect(nonces.count == 500 && cts.count == 500 && wrapNonces.count == 500)
    }

    @Test("envelope description is redacted and the type stores no plaintext field")
    func redaction() throws {
        let env = try Harness().seal("secret-goal-line", .goalRoadmap)
        let s = "\(env)"
        #expect(s.contains("payload: <encrypted>") && s.contains("id: <redacted>") && !s.contains("secret") && !s.contains(env.header.recordID.hex) && !s.contains("device"))
        #expect(Mirror(reflecting: env).children.compactMap { $0.label } == ["header", "wrappedDEK", "nonce", "ciphertext", "tag"])
    }
}

@Suite("AES-256-GCM envelope: adversarial")
struct SealAdversarialTests {
    @Test("wrong key provider cannot open")
    func wrongKey() throws {
        let a = Harness(keyID: "device"), b = Harness(keyID: "device"), c = Harness(keyID: "other")
        let env = try a.seal("x")
        #expect(throws: VaultError.authenticationFailed) { try b.open(env) }
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try c.open(env) }
    }

    @Test("tampered ciphertext, tag, nonce or wrapped key fails authentication")
    func tamperBytes() throws {
        let h = Harness()
        let env = try h.seal("hello vault")
        let hd = env.header, w = env.wrappedDEK
        let tampered: [RecordEnvelope] = [
            RecordEnvelope(header: hd, wrappedDEK: w, nonce: env.nonce, ciphertext: flipByte(env.ciphertext, at: 0), tag: env.tag),
            RecordEnvelope(header: hd, wrappedDEK: w, nonce: env.nonce, ciphertext: env.ciphertext, tag: flipByte(env.tag, at: 15)),
            RecordEnvelope(header: hd, wrappedDEK: w, nonce: flipByte(env.nonce, at: 3), ciphertext: env.ciphertext, tag: env.tag),
            RecordEnvelope(header: hd, wrappedDEK: WrappedKey(keyID: w.keyID, keyVersion: w.keyVersion, boundRecordID: w.boundRecordID, nonce: w.nonce, ciphertext: flipByte(w.ciphertext, at: 1), tag: w.tag), nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag),
            RecordEnvelope(header: hd, wrappedDEK: WrappedKey(keyID: w.keyID, keyVersion: w.keyVersion, boundRecordID: w.boundRecordID, nonce: w.nonce, ciphertext: w.ciphertext, tag: flipByte(w.tag, at: 0)), nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag),
        ]
        for t in tampered { #expect(throws: VaultError.authenticationFailed) { try h.open(t) } }
        #expect(try h.open(env) == Array("hello vault".utf8))
    }

    @Test("tampered authenticated metadata fails; tier downgrade fails closed before any crypto; purpose is authenticated")
    func tamperHeader() throws {
        let h = Harness()
        let env = try h.seal("dob", .birthDate)
        for th in [header(env.header, dc: .goalRoadmap), header(env.header, tier: .deviceHighSensitivity), header(env.header, ret: .sessionOnly), header(env.header, t: t0 + 1), header(env.header, id: RecordID()), header(env.header, purpose: "other")] {
            let forged = RecordEnvelope(header: th, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag)
            #expect(throws: VaultError.authenticationFailed) { try h.vault.open(forged, authorization: try h.token(.read(recordIDs: nil), purpose: th.consentPurpose)) }
        }
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .birthDate, required: .deviceSensitive, got: .publicContent)) {
            try h.open(RecordEnvelope(header: header(env.header, tier: .publicContent), wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag))
        }
    }

    @Test("a DEK wrapped for one record cannot be swapped into another record")
    func dekSwap() throws {
        let h = Harness()
        let a = try h.seal("a"), b = try h.seal("b")
        let forged = WrappedKey(keyID: b.wrappedDEK.keyID, keyVersion: b.wrappedDEK.keyVersion, boundRecordID: a.header.recordID, nonce: b.wrappedDEK.nonce, ciphertext: b.wrappedDEK.ciphertext, tag: b.wrappedDEK.tag)
        #expect(throws: VaultError.authenticationFailed) { try h.open(a.replacingWrappedDEK(forged)) }
    }

    @Test("unsupported format version (incl. retired v1) and malformed lengths are rejected with typed errors")
    func versions() throws {
        let h = Harness()
        let env = try h.seal("v")
        for v in [UInt16(1), 99] {
            #expect(throws: VaultError.unsupportedFormat(v)) { try h.open(RecordEnvelope(header: header(env.header, version: v), wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag)) }
        }
        #expect(throws: VaultError.invalidLength(field: "nonce", expected: 12, actual: 11)) { try h.open(RecordEnvelope(header: env.header, wrappedDEK: env.wrappedDEK, nonce: Array(env.nonce.dropLast()), ciphertext: env.ciphertext, tag: env.tag)) }
        #expect(throws: VaultError.invalidLength(field: "tag", expected: 16, actual: 15)) { try h.open(RecordEnvelope(header: env.header, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: Array(env.tag.dropLast()))) }
    }
}

@Suite("Key lifecycle")
struct KeyRotationTests {
    @Test("rotation re-wraps the DEK (maintenance token), payload bytes unchanged; forgotten old version makes un-rewrapped envelopes unreadable")
    func rotate() throws {
        let h = Harness()
        let plain = Array("rotate me".utf8)
        let v1 = try h.seal("rotate me")
        #expect(v1.wrappedDEK.keyVersion == 1)
        #expect(try h.keys.rotate().version == 2 && h.vault.currentKeyIdentity.version == 2)
        #expect(try h.open(v1) == plain)
        let v2 = try h.vault.rewrap(v1, maintenance: try h.token(.maintenance(.rewrap)))
        #expect(v2.wrappedDEK.keyVersion == 2 && v2.ciphertext == v1.ciphertext && v2.nonce == v1.nonce && v2.tag == v1.tag && v2.header == v1.header && v2.wrappedDEK != v1.wrappedDEK)
        #expect(try h.open(v2) == plain)
        try h.keys.forget(version: 1)
        #expect(h.keys.availableVersions == [2])
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try h.open(v1) }
        #expect(try h.open(v2) == plain)
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try h.keys.forget(version: 2) }
    }
}

@Suite("Sealed backup: confidentiality, authorization and robustness")
struct BackupTests {
    private func records(_ h: Harness) throws -> ([RecordEnvelope], [[UInt8]]) {
        let plains = [Array("dob:1998-06-30".utf8), Array("goal: learn".utf8), Array("derived: lp9".utf8)]
        let classes: [DataClass] = [.birthDate, .goalRoadmap, .derivedResult]
        var envs: [RecordEnvelope] = []
        for (p, c) in zip(plains, classes) { envs.append(try h.seal(String(decoding: p, as: UTF8.self), c)) }
        return (envs, plains)
    }

    @Test("export → bytes → restore on a NEW device; plaintext recovered; old keys useless; payload ciphertext unchanged")
    func migration() throws {
        let old = Harness(keyID: "device-old")
        let (envs, plains) = try records(old)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try old.export(envs, rk)
        let new = Harness(keyID: "device-new")
        let result = try new.restore(bytes, rk)
        #expect(result.active.count == 3 && result.quarantined.isEmpty)
        for ((r, e), p) in zip(zip(result.active, envs), plains) {
            #expect(r.header == e.header && r.ciphertext == e.ciphertext && r.nonce == e.nonce && r.tag == e.tag)
            #expect(r.wrappedDEK.keyID == "device-new" && r.wrappedDEK.keyVersion == 1)
            #expect(try new.open(r) == p)
        }
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try old.open(result.active[0]) }
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try new.open(envs[0]) }
    }

    @Test("metadata leak: backup bytes expose only magic, version, salt, nonce — no record ids, classes, tiers, purposes, timestamps, counts, plaintext or recovery key")
    func metadataConfidentiality() throws {
        let h = Harness()
        let (envs, plains) = try records(h)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try h.export(envs, rk)
        let sealed = try SealedBackup.decode(bytes)
        let clear = SealedBackup.magic.count + 2 + 4 + 16 + 4 + 12 + 4 + 4 + 16
        #expect(bytes.count == clear + sealed.ciphertext.count && sealed.ciphertext.count % BackupLimits.paddingBlockBytes == 0)
        for env in envs {
            #expect(!bytesContain(bytes, Array(env.header.recordID.hex.utf8)) && !bytesContain(bytes, Array(env.header.dataClass.rawValue.utf8)))
            #expect(!bytesContain(bytes, Array(env.header.privacyTier.rawValue.utf8)) && !bytesContain(bytes, env.ciphertext))
        }
        var tEnc = CanonicalEncoder(); tEnc.appendI64(t0)
        #expect(!bytesContain(bytes, tEnc.bytes) && !bytesContain(bytes, Array("XRAI-ENV".utf8)) && !bytesContain(bytes, Array("device".utf8)))
        for p in plains { #expect(!bytesContain(bytes, p)) }
        #expect(!bytesContain(bytes, rk.bytes))
    }

    @Test("unauthorized export: wrong-scope token, session-only record, duplicate id, tampered envelope, foreign envelope, mixed DEK")
    func unauthorizedExport() throws {
        let h = Harness()
        let (envs, _) = try records(h)
        let rk = try SecureVault.generateRecoveryKey()
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.exportBackup(envs, recoveryKey: rk, authorization: try h.token(.read(recordIDs: nil))) }
        let session = try h.seal("transient", .derivedResult, retention: .sessionOnly)
        #expect(throws: VaultError.notAuthorized(.sessionOnlyNeverPersisted)) { try h.export(envs + [session], rk) }
        #expect(throws: VaultError.duplicateRecordID) { try h.export(envs + [envs[0]], rk) }
        let tampered = RecordEnvelope(header: envs[1].header, wrappedDEK: envs[1].wrappedDEK, nonce: envs[1].nonce, ciphertext: flipByte(envs[1].ciphertext, at: 0), tag: envs[1].tag)
        #expect(throws: VaultError.envelopeIntegrityFailed) { try h.export([envs[0], tampered], rk) }
        let foreign = try Harness(keyID: "other-device").seal("not mine")
        #expect(throws: VaultError.envelopeIntegrityFailed) { try h.export([foreign], rk) }
        #expect(throws: VaultError.envelopeIntegrityFailed) { try h.export([envs[0].replacingWrappedDEK(envs[1].wrappedDEK)], rk) }
    }

    @Test("wrong recovery key, corrupted bytes, truncation, trailing bytes, old format version, oversize → rejected; restore needs its own scope")
    func corruptedOrWrongKey() throws {
        let h = Harness()
        let (envs, _) = try records(h)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try h.export(envs, rk)
        let new = Harness(keyID: "n")
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try new.vault.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try new.token(.exportBackup)) }
        #expect(throws: VaultError.backupIntegrityFailed) { try new.restore(bytes, try SecureVault.generateRecoveryKey()) }
        for pos in [0, 7, 12, 40, bytes.count / 2, bytes.count - 20, bytes.count - 1] {
            do { _ = try new.restore(flipByte(bytes, at: pos), rk); Issue.record("flip at \(pos) accepted") }
            catch let e as VaultError {
                switch e { case .backupIntegrityFailed, .backupCorrupted, .unsupportedFormat, .invalidLength, .limitExceeded: break; default: Issue.record("unexpected \(e) at \(pos)") }
            }
        }
        #expect(throws: VaultError.self) { try new.restore(Array(bytes.dropLast(5)), rk) }
        #expect(throws: VaultError.backupCorrupted(reason: "trailing bytes")) { try new.restore(bytes + [0], rk) }
        #expect(throws: VaultError.backupCorrupted(reason: "bad magic")) { try new.restore(Array("NOPE".utf8) + bytes, rk) }
        var v1 = bytes; v1[6] = 0; v1[7] = 1
        #expect(throws: VaultError.unsupportedFormat(1)) { try new.restore(v1, rk) }
        #expect(throws: VaultError.limitExceeded("backup size")) { try SealedBackup.decode([UInt8](repeating: 0, count: BackupLimits.maxBackupBytes + 1)) }
    }

    @Test("forged body inside a correctly-encrypted backup: tier downgrade, duplicate ids, oversize count, session-only, tampered inner payload, bad padding → rejected")
    func forgedBody() throws {
        let h = Harness(keyID: "src")
        let (envs, _) = try records(h)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try h.export(envs, rk)
        let sealed = try SealedBackup.decode(bytes)
        let keys = BackupCodec.deriveKeys(recoveryKey: rk, salt: sealed.salt)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed.nonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
        let body = try BackupBody.decode(try BackupBody.unpad(Array(try AES.GCM.open(box, using: keys.outer, authenticating: sealed.associatedData))))
        #expect(body.entries.count == 3 && body.createdAtUnixSeconds == t0)
        func reseal(_ padded: [UInt8]) throws -> [UInt8] {
            let nonce = AES.GCM.Nonce(); let nb = nonce.withUnsafeBytes { Array($0) }
            let b = try AES.GCM.seal(padded, using: keys.outer, nonce: nonce, authenticating: SealedBackup.associatedData(formatVersion: 2, salt: sealed.salt, nonce: nb))
            return SealedBackup(formatVersion: 2, salt: sealed.salt, nonce: nb, ciphertext: Array(b.ciphertext), tag: Array(b.tag)).encode()   // forging a LEGACY v2 body (P03-04b: export is v3)
        }
        let new = Harness(keyID: "dst")
        let e0 = body.entries[0]
        let downgraded = BackupBody(createdAtUnixSeconds: t0, entries: [RecordEnvelope(header: header(e0.header, tier: .publicContent), wrappedDEK: e0.wrappedDEK, nonce: e0.nonce, ciphertext: e0.ciphertext, tag: e0.tag)] + Array(body.entries.dropFirst()))
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .birthDate, required: .deviceSensitive, got: .publicContent)) { try new.restore(try reseal(BackupBody.pad(downgraded.encode())), rk) }
        #expect(throws: VaultError.duplicateRecordID) { try new.restore(try reseal(BackupBody.pad(BackupBody(createdAtUnixSeconds: t0, entries: body.entries + [e0]).encode())), rk) }
        var enc = CanonicalEncoder(); enc.appendI64(t0); enc.appendU32(UInt32(BackupLimits.maxEntries + 1))
        #expect(throws: VaultError.limitExceeded("entry count")) { try new.restore(try reseal(BackupBody.pad(enc.bytes)), rk) }
        let smuggled = BackupBody(createdAtUnixSeconds: t0, entries: [RecordEnvelope(header: header(e0.header, ret: .sessionOnly), wrappedDEK: e0.wrappedDEK, nonce: e0.nonce, ciphertext: e0.ciphertext, tag: e0.tag)])
        #expect(throws: VaultError.notAuthorized(.sessionOnlyNeverPersisted)) { try new.restore(try reseal(BackupBody.pad(smuggled.encode())), rk) }
        let inner = BackupBody(createdAtUnixSeconds: t0, entries: [RecordEnvelope(header: e0.header, wrappedDEK: e0.wrappedDEK, nonce: e0.nonce, ciphertext: flipByte(e0.ciphertext, at: 0), tag: e0.tag)])
        #expect(throws: VaultError.backupIntegrityFailed) { try new.restore(try reseal(BackupBody.pad(inner.encode())), rk) }
        var padded = BackupBody.pad(body.encode()); padded[padded.count - 1] = 0xFF
        #expect(throws: VaultError.backupCorrupted(reason: "padding bytes")) { try new.restore(try reseal(padded), rk) }
        #expect(try new.restore(try reseal(BackupBody.pad(body.encode())), rk).active.count == 3)
    }

    @Test("two exports differ in salt, nonce and ciphertext; recovery keys are high entropy; HKDF contexts are separated; export size limit is enforced before sealing")
    func saltsAndLimits() throws {
        let h = Harness()
        let (envs, _) = try records(h)
        let rk = try SecureVault.generateRecoveryKey()
        let b1 = try SealedBackup.decode(try h.export(envs, rk)), b2 = try SealedBackup.decode(try h.export(envs, rk))
        #expect(b1.salt != b2.salt && b1.nonce != b2.nonce && b1.ciphertext != b2.ciphertext)
        var ks = Set<[UInt8]>()
        for _ in 0..<50 { ks.insert(try SecureVault.generateRecoveryKey().bytes) }
        #expect(ks.count == 50)
        let k = BackupCodec.deriveKeys(recoveryKey: rk, salt: b1.salt)
        #expect(k.kek != k.outer.withUnsafeBytes { Array($0) })
        // size limit on export: a record larger than the cap is refused before any sealing happens
        let huge = try h.vault.seal(plaintext: [UInt8](repeating: 1, count: BackupLimits.maxRecordCiphertextBytes + 1), descriptor: try h.descriptor(.evidenceFiles), authorization: try h.token(.write(.evidenceFiles)))
        #expect(throws: VaultError.limitExceeded("record ciphertext")) { try h.export([huge], rk) }
    }
}
