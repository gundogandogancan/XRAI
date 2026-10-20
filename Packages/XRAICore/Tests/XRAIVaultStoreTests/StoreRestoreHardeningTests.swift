// P03-04bH — restore identity, authorization & deletion integrity gate (rows NT-BH-01…08).
// F-P04B-01 bloom resurrection, F-P04B-02 unauthorized envelope write, F-P04B-03 verified provenance,
// plus the six additional checks. Synthetic data only.
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

@Suite("P03-04bH — a deleted identity never returns; no write bypasses the privacy boundary; only verified provenance is trusted", .serialized)
struct StoreRestoreHardeningTests {
    /// Attack: delete → compact (digest) → restore the old backup → acknowledge → activate.
    @Test("NT-BH-01 (F-P04B-01): after compaction the old id is possiblyDeleted — activation and release are refused forever under that id; only an explicit re-import under a NEW id works, and the old id becomes exactly deleted")
    func bloomResurrectionAttack() async throws {
        let f = StoreFixture(limits: StoreLimits(ledgerCompactionThreshold: 4, ledgerRecentKept: 2, ledgerDigestCapacity: 1_000)); defer { f.cleanup() }
        let s = try await f.open()
        var ids: [RecordID] = []
        var text: [RecordID: String] = [:]
        for i in 0..<6 { let id = try await f.put(s, "r\(i)"); ids.append(id); text[id] = "r\(i)" }
        let (bytes, rk) = try await f.exportV3(s)
        try await f.delete(s, Set(ids))
        let compacted = ids.filter { s.deletionLookup($0) == .possiblyDeleted }
        #expect(compacted.count == 4 && ids.filter { s.deletionLookup($0) == .deleted }.count == 2)
        let rep = try await f.admit(s, try f.restore(s, bytes, rk))
        #expect(Set(rep.staged) == Set(compacted) && rep.skippedDeleted.count == 2)
        for id in compacted { #expect(rep.risks[id] == [.possiblyDeleted] && s.state(of: id) == .quarantined) }
        let victim = compacted[0]
        // the attack: acknowledge the risk and activate → refused with the dedicated error
        await expectVaultError(.possiblyDeletedForever) { try await f.activate(s, [victim], [.possiblyDeleted]) }
        await expectVaultError(.possiblyDeletedForever) { try await f.activate(s, Set(compacted), [.possiblyDeleted]) }
        await expectVaultError(.possiblyDeletedForever) { try await f.get(s, victim) }   // reads apply the identity policy too (P03-04bH2)
        #expect(s.state(of: victim) == .quarantined)
        try await s.close()
        let s2 = try await f.open()   // nothing changes across relaunch
        await expectVaultError(.possiblyDeletedForever) { try await f.activate(s2, [victim], [.possiblyDeleted]) }
        // explicit re-import: new id, fresh DEK, old id exactly deleted, plaintext preserved
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s2.reimportUnderNewID(victim, authorization: try s2.issuer.issue(scope: .reimport(recordID: compacted[1]))) }
        let newID = try await s2.reimportUnderNewID(victim, authorization: try s2.issuer.issue(scope: .reimport(recordID: victim)))
        #expect(newID != victim && s2.state(of: newID) == .active && s2.entry(of: newID)?.provenance == .reimportedAfterDeletion)
        #expect(try await f.get(s2, newID) == text[victim])
        #expect(s2.state(of: victim) == nil && !f.fileExists(victim) && s2.deletionLookup(victim) == .deleted && !f.quarantine.isQuarantined(victim))
        await expectVaultError(.recordMissing) { try await s2.reimportUnderNewID(victim, authorization: try s2.issuer.issue(scope: .reimport(recordID: victim))) }
        // the same backup again: the old id is now exactly deleted (skipped), the reimported record is unaffected
        let rep2 = try await f.admit(s2, try f.restore(s2, bytes, rk))
        #expect(rep2.skippedDeleted.contains(victim) && !rep2.skippedExisting.contains(victim) && !rep2.staged.contains(victim))
        #expect(Set(rep2.skippedExisting) == Set(compacted.dropFirst()), "the other staged ids are still staged")
        #expect(try await f.get(s2, newID) == text[victim])
        try await s2.close()
        let s3 = try await f.open()
        #expect(s3.deletionLookup(victim) == .deleted && s3.state(of: newID) == .active)
        try await s3.close()
    }

    @Test("NT-BH-01b (F-P04B-01): re-import needs the record's purpose and an ACTIVE grant; a revoked purpose refuses; a record other records derive from refuses (no dependency migration)")
    func reimportAuthorization() async throws {
        let f = StoreFixture(limits: StoreLimits(ledgerCompactionThreshold: 2, ledgerRecentKept: 1, ledgerDigestCapacity: 1_000)); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "j", id: "g-j")
        let j = try await f.put(s, "entry", .journal, purpose: "j"); f.base.advance(1)
        let d = try await f.put(s, "derived", .derivedResult, derivedFrom: [j]); f.base.advance(1)
        _ = try await f.put(s, "filler")
        let (bytes, rk) = try await f.exportV3(s)
        try await f.delete(s, [j, d])
        _ = try await f.put(s, "x"); try await f.delete(s, [s.recordIDs.last!])
        #expect(s.deletionLookup(j) == .possiblyDeleted)
        let rep = try await f.admit(s, try f.restore(s, bytes, rk))
        #expect(rep.staged.contains(j))
        if rep.staged.contains(d) {
            // d derives from j → j cannot be re-imported while d references it (no dependency migration)
            await expectVaultError(.notEligible(reason: "records derive from this id")) { try await s.reimportUnderNewID(j, authorization: try s.issuer.issue(scope: .reimport(recordID: j), purpose: "j")) }
            try await f.delete(s, [d])
        }
        f.authority.revoke(id: "g-j", atUnixSeconds: (try? f.base.now()) ?? storeT0)
        // wrong purpose on the token
        await expectVaultError(.authorizationInvalid(.purposeMismatch)) { try await s.reimportUnderNewID(j, authorization: try s.issuer.issue(scope: .reimport(recordID: j), purpose: "other")) }
        // purpose right but consent gone
        await expectVaultError(.notAuthorized(.consentRequired)) { try await s.reimportUnderNewID(j, authorization: try s.issuer.issue(scope: .reimport(recordID: j), purpose: "j")) }
        f.grant(.journal, purpose: "j")
        let newID = try await s.reimportUnderNewID(j, authorization: try s.issuer.issue(scope: .reimport(recordID: j), purpose: "j"))
        #expect(try await f.get(s, newID, purpose: "j") == "entry" && s.deletionLookup(j) == .deleted)
        try await s.close()
    }

    @Test("NT-BH-02 (F-P04B-02): every personal write path enforces purpose, consent, tier, key binding and AEAD — wrong-purpose token, revoked consent, tampered or foreign-key envelopes never enter the store")
    func writePaths() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "j", id: "g-j")
        // put (seal): purpose mismatch and revoked consent
        await expectVaultError(.authorizationInvalid(.purposeMismatch)) { try await s.put(plaintext: [1], descriptor: try f.descriptor(.journal, purpose: "j"), authorization: try s.issuer.issue(scope: .write(.journal), purpose: "other")) }
        let j = try await f.put(s, "ok", .journal, purpose: "j")
        f.authority.revoke(id: "g-j", atUnixSeconds: (try? f.base.now()) ?? storeT0)
        await expectVaultError(.notAuthorized(.consentRequired)) { try await s.put(plaintext: [1], descriptor: try f.descriptor(.journal, purpose: "j"), authorization: try s.issuer.issue(scope: .write(.journal), purpose: "j")) }
        await expectVaultError(.notAuthorized(.consentRequired)) { try await s.putAttachment(from: InMemoryAttachmentSource([1]), descriptor: try f.descriptor(.journal, purpose: "j"), authorization: try s.issuer.issue(scope: .write(.journal), purpose: "j")) }
        #expect(s.recordIDs == [j] && f.names("records").count == 1 && f.names("attachments").isEmpty)
        // a ready-made envelope (tampered, or wrapped by another device's key) has no write path: caller-built results are unverified
        let other = StoreFixture(); defer { other.cleanup() }
        let so = try await other.open()
        let foreignKeyEnv = try so.vault.seal(plaintext: [7], descriptor: try other.descriptor(), authorization: try so.issuer.issue(scope: .write(.birthDate)))
        try await so.close()
        await expectVaultError(.restoreUnverified) { try await s.admitRestored(RestoreResult(active: [foreignKeyEnv], quarantined: []), authorization: try s.issuer.issue(scope: .admitRestored)) }
        var tampered = try s.vault.seal(plaintext: [8], descriptor: try f.descriptor(), authorization: try s.issuer.issue(scope: .write(.birthDate)))
        var ct = tampered.ciphertext; ct[0] ^= 1
        tampered = RecordEnvelope(header: tampered.header, wrappedDEK: tampered.wrappedDEK, nonce: tampered.nonce, ciphertext: ct, tag: tampered.tag)
        await expectVaultError(.restoreUnverified) { try await s.admitRestored(RestoreResult(active: [tampered], quarantined: []), authorization: try s.issuer.issue(scope: .admitRestored)) }
        #expect(s.recordIDs == [j] && f.names("records").count == 1 && f.names("journal").isEmpty)
        // the verified path re-wraps under the current key and re-verifies every payload: a backup from the other vault restores as foreign, nothing else
        try await s.close()
    }

    @Test("NT-BH-03 (F-P04B-03): forged instance ids, ledger hashes, trust flags, generations and caller-built results are refused; a verified result altered after the restore is refused; legacy v2 stays verified with its risk; history merges only from verified inputs")
    func forgedProvenance() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let x = try await f.put(s, "x")
        let (bytes, rk) = try await f.exportV3(s)
        let real = try f.restore(s, bytes, rk)
        #expect(s.vault.isVerified(real))
        let env = try s.vault.seal(plaintext: [1], descriptor: try f.descriptor(), authorization: try s.issuer.issue(scope: .write(.birthDate)))
        var ledger = DeletionLedger(); ledger.append(DeletionLedger.Entry(recordID: x, deletedAtUnixSeconds: storeT0, manifestGeneration: 1))
        let lb = ledger.encode()
        let forged = [
            BackupProvenance(formatVersion: 3, bodySchemaVersion: 2, createdAtUnixSeconds: storeT0, vaultInstanceID: s.vaultInstanceID, backupGeneration: 99, sourceManifestGeneration: 1, sourceManifestHash: s.manifestHash, deletionLedgerBytes: lb, deletionLedgerHash: VaultDigest.sha256(lb), deletionHistoryTrusted: true),
            BackupProvenance(formatVersion: 3, bodySchemaVersion: 2, createdAtUnixSeconds: storeT0, vaultInstanceID: [UInt8](repeating: 1, count: 16), backupGeneration: 1, sourceManifestGeneration: 1, sourceManifestHash: Manifest.zeroHash, deletionLedgerBytes: nil, deletionLedgerHash: nil, deletionHistoryTrusted: true),
            BackupProvenance(formatVersion: 2, bodySchemaVersion: 0, createdAtUnixSeconds: storeT0, vaultInstanceID: nil, backupGeneration: nil, sourceManifestGeneration: nil, sourceManifestHash: nil, deletionLedgerBytes: nil, deletionLedgerHash: nil),
            real.provenance,
        ]
        let before = s.deletionCount
        for p in forged {
            await expectVaultError(.restoreUnverified) { try await s.admitRestored(RestoreResult(active: [env], quarantined: [], provenance: p), authorization: try s.issuer.issue(scope: .admitRestored)) }
        }
        // a forged seal and an altered verified result
        await expectVaultError(.restoreUnverified) { try await s.admitRestored(RestoreResult(active: [env], quarantined: [], provenance: real.provenance, verificationSeal: [UInt8](repeating: 0xAB, count: 32)), authorization: try s.issuer.issue(scope: .admitRestored)) }
        await expectVaultError(.restoreUnverified) { try await s.admitRestored(RestoreResult(active: real.active + [env], quarantined: [], provenance: real.provenance, verificationSeal: real.verificationSeal), authorization: try s.issuer.issue(scope: .admitRestored)) }
        await expectVaultError(.restoreUnverified) { try await s.admitRestored(RestoreResult(active: real.active, quarantined: [], provenance: forged[0], verificationSeal: real.verificationSeal), authorization: try s.issuer.issue(scope: .admitRestored)) }
        #expect(s.deletionCount == before && s.deletionLookup(x) == .notDeleted && s.recordIDs == [x], "no history merged, nothing staged")
        // a result sealed by ANOTHER facade instance is not verified here either
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let viaOther = try g.restore(sg, bytes, rk)
        #expect(sg.vault.isVerified(viaOther) && !s.vault.isVerified(viaOther))
        await expectVaultError(.restoreUnverified) { try await s.admitRestored(viaOther, authorization: try s.issuer.issue(scope: .admitRestored)) }
        try await sg.close()
        // the genuine verified result still works, and a verified legacy v2 result keeps its explicit risk
        let rep = try await f.admit(s, real)
        #expect(rep.skippedExisting == [x])
        let rk2 = try SecureVault.generateRecoveryKey()
        let v2 = try s.vault.exportBackup([env], recoveryKey: rk2, authorization: try s.issuer.issue(scope: .exportBackup))
        let legacy = try f.restore(s, v2, rk2)
        #expect(s.vault.isVerified(legacy) && legacy.provenance.isLegacy)
        let rep2 = try await f.admit(s, legacy)
        #expect(rep2.risks[env.header.recordID] == [.legacyFormat] && !rep2.historyMerged)
        try await s.close()
    }

    @Test("NT-BH-04: a derived-data cycle or a self-reference smuggled through a restored batch is refused at activation / admission")
    func derivedCycle() async throws {
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let idA = RecordID(), idB = RecordID()
        let dA = try RecordDescriptor(recordID: idA, dataClass: .derivedResult, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0, derivedFrom: [idB])
        let dB = try RecordDescriptor(recordID: idB, dataClass: .derivedResult, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0, derivedFrom: [idA])
        let envA = try sg.vault.seal(plaintext: [1], descriptor: dA, authorization: try sg.issuer.issue(scope: .write(.derivedResult)))
        let envB = try sg.vault.seal(plaintext: [2], descriptor: dB, authorization: try sg.issuer.issue(scope: .write(.derivedResult)))
        let rk = try SecureVault.generateRecoveryKey()
        let v2 = try sg.vault.exportBackup([envA, envB], recoveryKey: rk, authorization: try sg.issuer.issue(scope: .exportBackup))
        try await sg.close()
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let rep = try await f.admit(s, try f.restore(s, v2, rk))
        #expect(Set(rep.staged) == [idA, idB])
        await expectVaultError(.unknownDependency) { try await f.activate(s, [idA, idB], [.legacyFormat]) }
        await expectVaultError(.recordNotActive(state: "sourceInactive")) { try await f.activate(s, [idA], [.legacyFormat]) }
        #expect(s.state(of: idA) == .quarantined && s.state(of: idB) == .quarantined)
        // self reference: refused already at descriptor/header construction (the admission guard is defense in depth)
        let idC = RecordID()
        #expect(throws: VaultError.unknownDependency) { _ = try RecordDescriptor(recordID: idC, dataClass: .derivedResult, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0, derivedFrom: [idC]) }
        #expect(s.state(of: idC) == nil && f.names("journal").isEmpty)
        try await s.close()
    }

    @Test("NT-BH-05: risk acknowledgment is EXACT — a superset is refused, the exact set activates; activation re-checks consent at the trusted time")
    func exactAcknowledgment() async throws {
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        g.grant(.journal, purpose: "j")
        let j = try await sg.put(plaintext: Array("e".utf8), descriptor: try g.descriptor(.journal, purpose: "j"), authorization: try sg.issuer.issue(scope: .write(.journal), purpose: "j"))
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try await sg.exportBackup(recoveryKey: rk, authorization: try sg.issuer.issue(scope: .exportBackup))
        try await sg.close()
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "local")   // non-empty → foreign
        let rep = try await f.admit(s, try f.restore(s, bytes, rk))
        #expect(rep.risks[j] == [.foreignInstance, .consentInactiveAtRestore])
        await expectVaultError(.notEligible(reason: "restore risks must be acknowledged exactly: need 1,32 got 1,2,32")) { try await f.activate(s, [j], [.foreignInstance, .consentInactiveAtRestore, .legacyFormat]) }
        await expectVaultError(.notAuthorized(.consentRequired)) { try await f.activate(s, [j], [.foreignInstance, .consentInactiveAtRestore]) }
        f.grant(.journal, purpose: "j")
        try await f.activate(s, [j], [.foreignInstance, .consentInactiveAtRestore])
        #expect(try await f.get(s, j, purpose: "j") == "e")
        try await s.close()
    }

    @Test("NT-BH-06: an attachment file replaced under its path while a read is in progress does not change what the read delivers (both passes use one descriptor); the next read sees the replacement and fails closed")
    func attachmentReplacedBetweenPasses() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let bytes = pattern(2_200_000)
        let id = try await f.putAttachment(s, bytes)
        let url = f.attachmentURL(id)
        let (orig, pad) = try frames(of: url)
        var t = orig; t[2][10] ^= 0x01
        let tamperedURL = f.rootURL.appendingPathComponent("tampered.att")
        try writeFrames(t, to: tamperedURL, padding: pad)
        let box = ChunkBox()
        try await s.readAttachment(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [id]))) { i, c in
            if i == 0 { _ = try? FileManager.default.replaceItemAt(url, withItemAt: tamperedURL) }   // substitution mid-read
            box.add(i, c)
        }
        #expect(box.joined == bytes, "pass 2 kept reading the inode it verified")
        await expectVaultError(.recordNotActive(state: "corrupt")) { try await f.readAttachment(s, id) }
        try await s.close()
    }

    @Test("NT-BH-07: a backup made while attachments exist says so inside the sealed body; the importer marks every record with attachmentsMissing; a backup without attachments carries 0")
    func incompleteBackupFlag() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let p = try await f.put(s, "p"); f.base.advance(1)
        _ = try await f.putAttachment(s, pattern(10), derivedFrom: [p])
        let (bytes, rk) = try await f.exportV3(s)
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let r = try g.restore(sg, bytes, rk)
        #expect(r.provenance.excludedAttachmentCount == 1)
        let rep = try await g.admit(sg, r)
        #expect(rep.risks[p] == [.attachmentsMissing])
        await expectVaultError(.notEligible(reason: "restore risks must be acknowledged exactly: need 128 got ")) { try await g.activate(sg, [p]) }
        try await g.activate(sg, [p], [.attachmentsMissing])
        try await sg.close()
        let h = StoreFixture(); defer { h.cleanup() }
        let sh = try await h.open()
        _ = try await h.put(sh, "q")
        let (b2, rk2) = try await h.exportV3(sh)
        #expect(try h.restore(sh, b2, rk2).provenance.excludedAttachmentCount == 0)
        try await sh.close(); try await s.close()
    }

    @Test("NT-BH-08: a crash at every syscall of activation leaves each record either active (released) or still quarantined with its risks and registry entry; never half")
    func activationCrashEverywhere() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let ids = [try await a.put(sa, "1"), try await a.put(sa, "2")]
        let (bytes, rk) = try await a.exportV3(sa)
        try await sa.close()
        var step = 1
        var outcomes = Set<String>()
        while true {
            let b = StoreFixture(); defer { b.cleanup() }
            let sb = try await b.open()
            _ = try await b.admit(sb, try b.restore(sb, bytes, rk))
            b.fs.arm(at: step)
            var crashed = false
            do { try await b.activate(sb, Set(ids)) } catch is SimulatedCrash { crashed = true } catch { Issue.record("step \(step): \(error)"); b.fs.disarm(); try await sb.close(); throw error }
            b.fs.disarm(); try await sb.close()
            let rb = try await b.open()
            #expect(rb.mode == .readWrite)
            let states = ids.map { rb.state(of: $0) }
            if states.allSatisfy({ $0 == .active }) {
                for id in ids { #expect(!b.quarantine.isQuarantined(id) && rb.entry(of: id)?.restoreRisks == 0); _ = try await b.get(rb, id) }
                outcomes.insert("active")
            } else {
                #expect(states.allSatisfy { $0 == .quarantined }, Comment(rawValue: "step \(step): \(states)"))
                for id in ids { #expect(b.quarantine.isQuarantined(id)); await expectVaultError(.recordNotActive(state: "quarantined")) { try await b.get(rb, id) } }
                outcomes.insert("quarantined")
            }
            try await rb.close()
            if !crashed { break }
            step += 1
            if step > 100 { Issue.record("never completed"); break }
        }
        #expect(outcomes == ["active", "quarantined"], Comment(rawValue: "\(outcomes)"))
    }
}
