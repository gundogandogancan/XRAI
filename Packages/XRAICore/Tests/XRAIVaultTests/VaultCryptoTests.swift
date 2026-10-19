import CryptoKit
import Foundation
import Testing
import XRAIVaultContracts
@testable import XRAIVaultCryptoKit

// Adversarial tests for the CryptoKit adapter through the authorized `SecureVault` facade.
// Every input here is synthetic; no real user data. `@testable` is used only to forge backups.

private let t0: Int64 = 1_760_000_000
private func desc(_ dc: DataClass = .birthDate, retention: RetentionClass = .untilUserDeletes) throws -> RecordDescriptor {
    try RecordDescriptor(dataClass: dc, retention: retention, createdAtUnixSeconds: t0)
}
private func vault(_ key: String = "device", authority: any ConsentAuthority = NoConsentAuthority()) -> SecureVault {
    SecureVault(keyProvider: InMemoryKeyProvider(keyID: key), consentAuthority: authority)
}
private func seal(_ v: SecureVault, _ text: String, _ dc: DataClass = .birthDate, retention: RetentionClass = .untilUserDeletes) throws -> RecordEnvelope {
    try v.seal(plaintext: Array(text.utf8), descriptor: try desc(dc, retention: retention), purpose: "", nowUnixSeconds: t0)
}

@Suite("AES-256-GCM envelope: round trip and structure")
struct SealRoundTripTests {
    @Test("seal/open round-trips for every consent-free class and ciphertext hides the plaintext")
    func roundTrip() throws {
        let v = vault()
        for dc in DataClass.allCases where !dc.requiresPurposeConsentToStore {
            let plain = Array("synthetic-\(dc.rawValue)-1998-06-30".utf8)
            let env = try v.seal(plaintext: plain, descriptor: try desc(dc), purpose: "", nowUnixSeconds: t0)
            #expect(env.header.dataClass == dc && env.header.privacyTier == dc.minimumTier)
            #expect(env.header.algorithm == .aes256gcm && env.header.formatVersion == 1)
            #expect(env.nonce.count == 12 && env.tag.count == 16 && env.ciphertext.count == plain.count)
            #expect(env.ciphertext != plain && !bytesContain(env.ciphertext, Array("1998".utf8)))
            #expect(try v.open(env) == plain)
        }
        let env = try v.seal(plaintext: [], descriptor: try desc(), purpose: "", nowUnixSeconds: t0)
        #expect(env.ciphertext.isEmpty && env.tag.count == 16)
        #expect(try v.open(env) == [])
    }

    @Test("nonce strategy: fresh random nonce per seal; same plaintext never repeats nonce or ciphertext")
    func nonces() throws {
        let v = vault()
        var nonces = Set<[UInt8]>(), cts = Set<[UInt8]>(), wrapNonces = Set<[UInt8]>()
        for _ in 0..<500 {
            let env = try seal(v, "same-plaintext")
            nonces.insert(env.nonce); cts.insert(env.ciphertext); wrapNonces.insert(env.wrappedDEK.nonce)
        }
        #expect(nonces.count == 500 && cts.count == 500 && wrapNonces.count == 500)
    }

    @Test("envelope description is redacted and the type stores no plaintext field")
    func redaction() throws {
        let env = try seal(vault(), "secret-goal-line", .goalRoadmap)
        let s = "\(env)"
        #expect(s.contains("payload: <encrypted>") && s.contains("id: <redacted>") && !s.contains("secret") && !s.contains(env.header.recordID.hex) && !s.contains("device"))
        #expect(Mirror(reflecting: env).children.compactMap { $0.label } == ["header", "wrappedDEK", "nonce", "ciphertext", "tag"])
    }
}

@Suite("Mandatory policy enforcement at the vault entry point")
struct EnforcementTests {
    @Test("consent-gated classes cannot be sealed without an active grant in the authority; grant unlocks; revocation re-locks")
    func consentGate() throws {
        let a = InMemoryConsentAuthority()
        let v = vault(authority: a)
        for dc in DataClass.allCases where dc.requiresPurposeConsentToStore {
            #expect(throws: VaultError.notAuthorized(.consentRequired)) {
                try v.seal(plaintext: [1], descriptor: try desc(dc), purpose: "lens", nowUnixSeconds: t0)
            }
        }
        a.register(ConsentReceipt(id: "r1", scopes: [ConsentScope(dataClass: .parentsNames, purpose: "lens", destination: .deviceVault)], grantedAtUnixSeconds: t0))
        _ = try v.seal(plaintext: [1], descriptor: try desc(.parentsNames), purpose: "lens", nowUnixSeconds: t0 + 1)
        #expect(throws: VaultError.notAuthorized(.consentRequired)) {
            try v.seal(plaintext: [1], descriptor: try desc(.parentsNames), purpose: "other", nowUnixSeconds: t0 + 1)
        }
        a.revoke(id: "r1", atUnixSeconds: t0 + 5)
        #expect(throws: VaultError.notAuthorized(.consentRequired)) {
            try v.seal(plaintext: [1], descriptor: try desc(.parentsNames), purpose: "lens", nowUnixSeconds: t0 + 5)
        }
    }

    @Test("a forged receipt presented by the caller has no effect: only the authority is consulted")
    func forgedReceiptIsIgnored() throws {
        // The API offers no parameter for a receipt; the only route is the authority, which is empty.
        let v = vault(authority: InMemoryConsentAuthority())
        #expect(throws: VaultError.notAuthorized(.consentRequired)) {
            try v.seal(plaintext: [1], descriptor: try desc(.journal), purpose: "p", nowUnixSeconds: t0)
        }
    }

    @Test("raw sealer and backup codec are not public API (compile-time boundary, checked by reflection on the facade)")
    func facadeOnly() {
        let labels = Mirror(reflecting: vault()).children.compactMap { $0.label }
        #expect(labels == ["keyProvider", "consentAuthority", "sealer"])
    }
}

@Suite("AES-256-GCM envelope: adversarial")
struct SealAdversarialTests {
    @Test("wrong key provider cannot open")
    func wrongKey() throws {
        let a = vault("device"), b = vault("device"), c = vault("other")
        let env = try seal(a, "x")
        #expect(throws: VaultError.authenticationFailed) { try b.open(env) }
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try c.open(env) }
    }

    @Test("tampered ciphertext, tag, nonce or wrapped key fails authentication")
    func tamperBytes() throws {
        let v = vault()
        let env = try seal(v, "hello vault")
        let h = env.header, w = env.wrappedDEK
        let tampered: [RecordEnvelope] = [
            RecordEnvelope(header: h, wrappedDEK: w, nonce: env.nonce, ciphertext: flipByte(env.ciphertext, at: 0), tag: env.tag),
            RecordEnvelope(header: h, wrappedDEK: w, nonce: env.nonce, ciphertext: env.ciphertext, tag: flipByte(env.tag, at: 15)),
            RecordEnvelope(header: h, wrappedDEK: w, nonce: flipByte(env.nonce, at: 3), ciphertext: env.ciphertext, tag: env.tag),
            RecordEnvelope(header: h, wrappedDEK: WrappedKey(keyID: w.keyID, keyVersion: w.keyVersion, boundRecordID: w.boundRecordID, nonce: w.nonce, ciphertext: flipByte(w.ciphertext, at: 1), tag: w.tag), nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag),
            RecordEnvelope(header: h, wrappedDEK: WrappedKey(keyID: w.keyID, keyVersion: w.keyVersion, boundRecordID: w.boundRecordID, nonce: w.nonce, ciphertext: w.ciphertext, tag: flipByte(w.tag, at: 0)), nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag),
        ]
        for t in tampered { #expect(throws: VaultError.authenticationFailed) { try v.open(t) } }
        #expect(try v.open(env) == Array("hello vault".utf8))
    }

    @Test("tampered authenticated metadata fails; a tier DOWNGRADE fails closed before any crypto")
    func tamperHeader() throws {
        let v = vault()
        let env = try seal(v, "dob", .birthDate)
        let h = env.header
        func hdr(dc: DataClass = h.dataClass, tier: PrivacyTier = h.privacyTier, ret: RetentionClass = h.retention, t: Int64 = h.createdAtUnixSeconds, id: RecordID = h.recordID) -> EnvelopeHeader {
            EnvelopeHeader(formatVersion: h.formatVersion, algorithm: h.algorithm, recordID: id, dataClass: dc, privacyTier: tier, retention: ret, createdAtUnixSeconds: t)
        }
        for th in [hdr(dc: .goalRoadmap), hdr(tier: .deviceHighSensitivity), hdr(ret: .sessionOnly), hdr(t: h.createdAtUnixSeconds + 1), hdr(id: RecordID())] {
            #expect(throws: VaultError.authenticationFailed) { try v.open(RecordEnvelope(header: th, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag)) }
        }
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .birthDate, required: .deviceSensitive, got: .publicContent)) {
            try v.open(RecordEnvelope(header: hdr(tier: .publicContent), wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag))
        }
    }

    @Test("a DEK wrapped for one record cannot be swapped into another record")
    func dekSwap() throws {
        let v = vault()
        let a = try seal(v, "a"), b = try seal(v, "b")
        let forged = WrappedKey(keyID: b.wrappedDEK.keyID, keyVersion: b.wrappedDEK.keyVersion, boundRecordID: a.header.recordID, nonce: b.wrappedDEK.nonce, ciphertext: b.wrappedDEK.ciphertext, tag: b.wrappedDEK.tag)
        #expect(throws: VaultError.authenticationFailed) { try v.open(a.replacingWrappedDEK(forged)) }
    }

    @Test("unsupported format version and malformed lengths are rejected with typed errors")
    func versions() throws {
        let v = vault()
        let env = try seal(v, "v")
        let h = env.header
        let future = EnvelopeHeader(formatVersion: 99, algorithm: h.algorithm, recordID: h.recordID, dataClass: h.dataClass, privacyTier: h.privacyTier, retention: h.retention, createdAtUnixSeconds: h.createdAtUnixSeconds)
        #expect(throws: VaultError.unsupportedFormat(99)) { try v.open(RecordEnvelope(header: future, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: env.tag)) }
        #expect(throws: VaultError.invalidLength(field: "nonce", expected: 12, actual: 11)) { try v.open(RecordEnvelope(header: h, wrappedDEK: env.wrappedDEK, nonce: Array(env.nonce.dropLast()), ciphertext: env.ciphertext, tag: env.tag)) }
        #expect(throws: VaultError.invalidLength(field: "tag", expected: 16, actual: 15)) { try v.open(RecordEnvelope(header: h, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: env.ciphertext, tag: Array(env.tag.dropLast()))) }
    }
}

@Suite("Key lifecycle")
struct KeyRotationTests {
    @Test("rotation re-wraps the DEK, payload bytes unchanged; forgotten old version makes un-rewrapped envelopes unreadable")
    func rotate() throws {
        let provider = InMemoryKeyProvider(keyID: "device")
        let v = SecureVault(keyProvider: provider, consentAuthority: NoConsentAuthority())
        let plain = Array("rotate me".utf8)
        let v1 = try v.seal(plaintext: plain, descriptor: try desc(), purpose: "", nowUnixSeconds: t0)
        #expect(v1.wrappedDEK.keyVersion == 1)
        #expect(try provider.rotate().version == 2 && provider.currentKey.version == 2)
        #expect(try v.open(v1) == plain)
        let v2 = try v.rewrap(v1)
        #expect(v2.wrappedDEK.keyVersion == 2 && v2.ciphertext == v1.ciphertext && v2.nonce == v1.nonce && v2.tag == v1.tag && v2.header == v1.header && v2.wrappedDEK != v1.wrappedDEK)
        #expect(try v.open(v2) == plain)
        try provider.forget(version: 1)
        #expect(provider.availableVersions == [2])
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try v.open(v1) }
        #expect(try v.open(v2) == plain)
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try provider.forget(version: 2) }
    }
}

@Suite("Sealed backup: confidentiality, authorization and robustness")
struct BackupTests {
    private func records(_ v: SecureVault) throws -> ([RecordEnvelope], [[UInt8]]) {
        let plains = [Array("dob:1998-06-30".utf8), Array("goal: learn".utf8), Array("derived: lp9".utf8)]
        let classes: [DataClass] = [.birthDate, .goalRoadmap, .derivedResult]
        var envs: [RecordEnvelope] = []
        for (p, c) in zip(plains, classes) { envs.append(try v.seal(plaintext: p, descriptor: try desc(c), purpose: "", nowUnixSeconds: t0)) }
        return (envs, plains)
    }

    @Test("export → bytes → restore on a NEW device; plaintext recovered; old keys useless; payload ciphertext unchanged")
    func migration() throws {
        let old = vault("device-old")
        let (envs, plains) = try records(old)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try old.exportBackup(envs, recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0 + 5)
        let new = vault("device-new")
        let restored = try new.restoreBackup(bytes: bytes, recoveryKey: rk, userInitiated: true)
        #expect(restored.count == 3)
        for ((r, e), p) in zip(zip(restored, envs), plains) {
            #expect(r.header == e.header && r.ciphertext == e.ciphertext && r.nonce == e.nonce && r.tag == e.tag)
            #expect(r.wrappedDEK.keyID == "device-new" && r.wrappedDEK.keyVersion == 1)
            #expect(try new.open(r) == p)
        }
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try old.open(restored[0]) }
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try new.open(envs[0]) }
    }

    @Test("metadata leak: backup bytes expose only magic, version, salt, nonce — no record ids, classes, tiers, timestamps, counts, plaintext or recovery key")
    func metadataConfidentiality() throws {
        let v = vault()
        let (envs, plains) = try records(v)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try v.exportBackup(envs, recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0 + 5)
        let sealed = try SealedBackup.decode(bytes)
        #expect(sealed.formatVersion == 2 && sealed.salt.count == 16 && sealed.nonce.count == 12 && sealed.tag.count == 16)
        let clear = SealedBackup.magic.count + 2 + 4 + 16 + 4 + 12 + 4 + 4 + 16
        #expect(bytes.count == clear + sealed.ciphertext.count, "nothing but the technical header is outside the ciphertext")
        #expect(sealed.ciphertext.count % BackupLimits.paddingBlockBytes == 0, "block padded")
        for env in envs {
            #expect(!bytesContain(bytes, Array(env.header.recordID.hex.utf8)))
            #expect(!bytesContain(bytes, Array(env.header.dataClass.rawValue.utf8)))
            #expect(!bytesContain(bytes, Array(env.header.privacyTier.rawValue.utf8)))
            #expect(!bytesContain(bytes, env.ciphertext), "even inner ciphertext is re-encrypted")
        }
        var tEnc = CanonicalEncoder(); tEnc.appendI64(t0)
        #expect(!bytesContain(bytes, tEnc.bytes))
        #expect(!bytesContain(bytes, Array("XRAI-ENV".utf8)) && !bytesContain(bytes, Array("AES-256-GCM".utf8)) && !bytesContain(bytes, Array("device".utf8)))
        for p in plains { #expect(!bytesContain(bytes, p)) }
        #expect(!bytesContain(bytes, rk.bytes))
    }

    @Test("unauthorized export: not user-initiated, session-only record, duplicate id, tampered envelope, foreign envelope")
    func unauthorizedExport() throws {
        let v = vault()
        let (envs, _) = try records(v)
        let rk = try SecureVault.generateRecoveryKey()
        #expect(throws: VaultError.notAuthorized(.userInitiationRequired)) { try v.exportBackup(envs, recoveryKey: rk, userInitiated: false, nowUnixSeconds: t0) }
        let session = try seal(v, "transient", .derivedResult, retention: .sessionOnly)
        #expect(throws: VaultError.notAuthorized(.sessionOnlyNeverPersisted)) { try v.exportBackup(envs + [session], recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0) }
        #expect(throws: VaultError.duplicateRecordID) { try v.exportBackup(envs + [envs[0]], recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0) }
        let tampered = RecordEnvelope(header: envs[1].header, wrappedDEK: envs[1].wrappedDEK, nonce: envs[1].nonce, ciphertext: flipByte(envs[1].ciphertext, at: 0), tag: envs[1].tag)
        #expect(throws: VaultError.envelopeIntegrityFailed) { try v.exportBackup([envs[0], tampered], recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0) }
        let foreign = try seal(vault("other-device"), "not mine")
        #expect(throws: VaultError.envelopeIntegrityFailed) { try v.exportBackup([foreign], recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0) }
        let mixed = envs[0].replacingWrappedDEK(envs[1].wrappedDEK)
        #expect(throws: VaultError.envelopeIntegrityFailed) { try v.exportBackup([mixed], recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0) }
    }

    @Test("wrong recovery key, corrupted bytes, truncation, trailing bytes, old format version, oversize → rejected; restore requires user initiation")
    func corruptedOrWrongKey() throws {
        let v = vault()
        let (envs, _) = try records(v)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try v.exportBackup(envs, recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0)
        let new = vault("n")
        #expect(throws: VaultError.notAuthorized(.userInitiationRequired)) { try new.restoreBackup(bytes: bytes, recoveryKey: rk, userInitiated: false) }
        #expect(throws: VaultError.backupIntegrityFailed) { try new.restoreBackup(bytes: bytes, recoveryKey: try SecureVault.generateRecoveryKey(), userInitiated: true) }
        for pos in [0, 7, 12, 40, bytes.count / 2, bytes.count - 20, bytes.count - 1] {
            do {
                _ = try new.restoreBackup(bytes: flipByte(bytes, at: pos), recoveryKey: rk, userInitiated: true)
                Issue.record("flip at \(pos) accepted")
            } catch let e as VaultError {
                switch e {
                case .backupIntegrityFailed, .backupCorrupted, .unsupportedFormat, .invalidLength, .limitExceeded: break
                default: Issue.record("unexpected \(e) at \(pos)")
                }
            }
        }
        #expect(throws: VaultError.self) { try new.restoreBackup(bytes: Array(bytes.dropLast(5)), recoveryKey: rk, userInitiated: true) }
        #expect(throws: VaultError.backupCorrupted(reason: "trailing bytes")) { try new.restoreBackup(bytes: bytes + [0], recoveryKey: rk, userInitiated: true) }
        #expect(throws: VaultError.backupCorrupted(reason: "bad magic")) { try new.restoreBackup(bytes: Array("NOPE".utf8) + bytes, recoveryKey: rk, userInitiated: true) }
        // old (v1) format: version field at bytes[6...7]
        var v1 = bytes; v1[6] = 0; v1[7] = 1
        #expect(throws: VaultError.unsupportedFormat(1)) { try new.restoreBackup(bytes: v1, recoveryKey: rk, userInitiated: true) }
        #expect(throws: VaultError.limitExceeded("backup size")) { try SealedBackup.decode([UInt8](repeating: 0, count: BackupLimits.maxBackupBytes + 1)) }
    }

    @Test("forged body: tier downgrade, duplicate ids, oversize entry count and bad padding inside a correctly-encrypted backup are rejected (fail closed)")
    func forgedBody() throws {
        let v = vault("src")
        let (envs, _) = try records(v)
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try v.exportBackup(envs, recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0)
        let sealed = try SealedBackup.decode(bytes)
        let keys = BackupCodec.deriveKeys(recoveryKey: rk, salt: sealed.salt)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed.nonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
        let body = try BackupBody.decode(try BackupBody.unpad(Array(try AES.GCM.open(box, using: keys.outer, authenticating: sealed.associatedData))))
        #expect(body.entries.count == 3 && body.createdAtUnixSeconds == t0)

        func reseal(_ padded: [UInt8]) throws -> [UInt8] {
            let nonce = AES.GCM.Nonce()
            let nb = nonce.withUnsafeBytes { Array($0) }
            let ad = SealedBackup.associatedData(formatVersion: 2, salt: sealed.salt, nonce: nb)
            let b = try AES.GCM.seal(padded, using: keys.outer, nonce: nonce, authenticating: ad)
            return SealedBackup(salt: sealed.salt, nonce: nb, ciphertext: Array(b.ciphertext), tag: Array(b.tag)).encode()
        }
        let new = vault("dst")

        // 1. tier downgrade on an entry (header rewritten; AEAD of the record will also fail, but the floor fails first)
        let e0 = body.entries[0]
        let down = EnvelopeHeader(formatVersion: 1, algorithm: .aes256gcm, recordID: e0.header.recordID, dataClass: e0.header.dataClass, privacyTier: .publicContent, retention: e0.header.retention, createdAtUnixSeconds: e0.header.createdAtUnixSeconds)
        let downgraded = BackupBody(createdAtUnixSeconds: t0, entries: [RecordEnvelope(header: down, wrappedDEK: e0.wrappedDEK, nonce: e0.nonce, ciphertext: e0.ciphertext, tag: e0.tag)] + Array(body.entries.dropFirst()))
        #expect(throws: VaultError.privacyTierBelowMinimum(dataClass: .birthDate, required: .deviceSensitive, got: .publicContent)) {
            try new.restoreBackup(bytes: try reseal(BackupBody.pad(downgraded.encode())), recoveryKey: rk, userInitiated: true)
        }
        // 2. duplicate record ids
        let dup = BackupBody(createdAtUnixSeconds: t0, entries: body.entries + [body.entries[0]])
        #expect(throws: VaultError.duplicateRecordID) { try new.restoreBackup(bytes: try reseal(BackupBody.pad(dup.encode())), recoveryKey: rk, userInitiated: true) }
        // 3. entry count above the limit (count field forged; no actual entries follow)
        var enc = CanonicalEncoder(); enc.appendI64(t0); enc.appendU32(UInt32(BackupLimits.maxEntries + 1))
        #expect(throws: VaultError.limitExceeded("entry count")) { try new.restoreBackup(bytes: try reseal(BackupBody.pad(enc.bytes)), recoveryKey: rk, userInitiated: true) }
        // 4. session-only record smuggled into a backup
        let sess = EnvelopeHeader(formatVersion: 1, algorithm: .aes256gcm, recordID: e0.header.recordID, dataClass: e0.header.dataClass, privacyTier: e0.header.privacyTier, retention: .sessionOnly, createdAtUnixSeconds: e0.header.createdAtUnixSeconds)
        let smuggled = BackupBody(createdAtUnixSeconds: t0, entries: [RecordEnvelope(header: sess, wrappedDEK: e0.wrappedDEK, nonce: e0.nonce, ciphertext: e0.ciphertext, tag: e0.tag)])
        #expect(throws: VaultError.notAuthorized(.sessionOnlyNeverPersisted)) { try new.restoreBackup(bytes: try reseal(BackupBody.pad(smuggled.encode())), recoveryKey: rk, userInitiated: true) }
        // 5. tampered inner payload under a valid outer envelope → payload verification fails closed
        let inner = BackupBody(createdAtUnixSeconds: t0, entries: [RecordEnvelope(header: e0.header, wrappedDEK: e0.wrappedDEK, nonce: e0.nonce, ciphertext: flipByte(e0.ciphertext, at: 0), tag: e0.tag)])
        #expect(throws: VaultError.backupIntegrityFailed) { try new.restoreBackup(bytes: try reseal(BackupBody.pad(inner.encode())), recoveryKey: rk, userInitiated: true) }
        // 6. bad padding bytes
        var padded = BackupBody.pad(body.encode()); padded[padded.count - 1] = 0xFF
        #expect(throws: VaultError.backupCorrupted(reason: "padding bytes")) { try new.restoreBackup(bytes: try reseal(padded), recoveryKey: rk, userInitiated: true) }
        // sanity: the untouched body still restores
        #expect(try new.restoreBackup(bytes: try reseal(BackupBody.pad(body.encode())), recoveryKey: rk, userInitiated: true).count == 3)
    }

    @Test("two exports differ in salt, nonce and ciphertext; recovery keys are high entropy; HKDF contexts are separated")
    func salts() throws {
        let v = vault()
        let (envs, _) = try records(v)
        let rk = try SecureVault.generateRecoveryKey()
        let b1 = try SealedBackup.decode(try v.exportBackup(envs, recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0))
        let b2 = try SealedBackup.decode(try v.exportBackup(envs, recoveryKey: rk, userInitiated: true, nowUnixSeconds: t0))
        #expect(b1.salt != b2.salt && b1.nonce != b2.nonce && b1.ciphertext != b2.ciphertext)
        var keys = Set<[UInt8]>()
        for _ in 0..<50 { keys.insert(try SecureVault.generateRecoveryKey().bytes) }
        #expect(keys.count == 50)
        let k = BackupCodec.deriveKeys(recoveryKey: rk, salt: b1.salt)
        #expect(k.kek != k.outer.withUnsafeBytes { Array($0) })
    }
}

@Suite("Module boundary: CryptoKit only in the adapter")
struct ImportBoundaryTests {
    private static func sources() -> URL {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent(); u.deleteLastPathComponent(); u.deleteLastPathComponent()
        return u.appendingPathComponent("Sources", isDirectory: true)
    }
    private static func files(in dir: String) throws -> [(String, String)] {
        let root = sources().appendingPathComponent(dir, isDirectory: true)
        var out: [(String, String)] = []
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return out }
        for case let u as URL in e where u.pathExtension == "swift" { out.append((u.lastPathComponent, try String(contentsOf: u, encoding: .utf8))) }
        return out
    }
    private static func imports(_ text: String) -> Set<String> {
        Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("import ") }.map { String($0.dropFirst(7)) })
    }

    @Test("contracts import nothing; adapter imports only CryptoKit/Foundation/contracts; no IO, logging or Keychain tokens in vault modules")
    func boundary() throws {
        let contracts = try Self.files(in: "XRAIVaultContracts")
        #expect(contracts.count >= 4)
        for (f, t) in contracts { #expect(Self.imports(t).isEmpty, Comment(rawValue: f)) }
        let adapter = try Self.files(in: "XRAIVaultCryptoKit")
        #expect(adapter.count >= 3)
        for (f, t) in adapter { #expect(Self.imports(t).isSubset(of: ["CryptoKit", "Foundation", "XRAIVaultContracts"]), Comment(rawValue: f)) }
        for module in ["XRAIIdentityTime", "XRAINumerology", "XRAIVaultContracts"] {
            for (f, t) in try Self.files(in: module) { #expect(Self.imports(t).isDisjoint(with: ["CryptoKit", "Security", "Foundation"]), Comment(rawValue: "\(module)/\(f)")) }
        }
        for module in ["XRAIVaultContracts", "XRAIVaultCryptoKit"] {
            for (f, t) in try Self.files(in: module) {
                let code = t.split(separator: "\n", omittingEmptySubsequences: false).map { l -> Substring in if let r = l.range(of: "//") { return l[l.startIndex..<r.lowerBound] }; return l }.joined(separator: "\n")
                for token in ["URLSession", "FileManager", "UserDefaults", "print(", "NSLog", "os_log", "Logger(", "write(to", "Data(contentsOf", "String(contentsOf", "NWConnection", "Keychain", "SecItem"] {
                    #expect(!code.contains(token), "\(module)/\(f) contains \(token)")
                }
            }
        }
        // The raw sealer and codec must not be public.
        for (f, t) in adapter where f == "AESGCMEnvelopeSealer.swift" || f == "BackupCodec.swift" {
            #expect(!t.contains("public struct AESGCMEnvelopeSealer") && !t.contains("public enum BackupCodec"), Comment(rawValue: f))
        }
    }
}
