// P03-04b GATE 2/3 — backup body v3 and two-phase restore reconciliation (rows NT-BK-01…06, NT-RR-01…14).
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

extension StoreFixture {
    func exportV3(_ s: FileVaultStore) async throws -> ([UInt8], RecoveryKey) {
        let rk = try SecureVault.generateRecoveryKey()
        return (try await s.exportBackup(recoveryKey: rk, authorization: try s.issuer.issue(scope: .exportBackup)), rk)
    }
    func restore(_ s: FileVaultStore, _ bytes: [UInt8], _ rk: RecoveryKey) throws -> RestoreResult {
        try s.vault.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try s.issuer.issue(scope: .restoreBackup))
    }
    func admit(_ s: FileVaultStore, _ r: RestoreResult) async throws -> AdmissionReport {
        try await s.admitRestored(r, authorization: try s.issuer.issue(scope: .admitRestored))
    }
    func activate(_ s: FileVaultStore, _ ids: Set<RecordID>, _ risks: Set<RestoreRisk> = []) async throws {
        try await s.activateRestored(ids, acknowledging: risks, authorization: try s.issuer.issue(scope: .activateRestored(recordIDs: ids)))
    }
}

func contains(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, hay.count >= needle.count else { return false }
    for i in 0...(hay.count - needle.count) where hay[i] == needle[0] { if Array(hay[i..<i + needle.count]) == needle { return true } }
    return false
}

@Suite("GATE 2 — backup body v3 through the store", .serialized)
struct StoreBackupV3Tests {
    @Test("NT-BK-01: v3 round trip — provenance carries instance id, backup generation, manifest binding and the deletion history; a fresh vault adopts the history, stages everything, activates with sources first")
    func roundTrip() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let x = try await a.put(sa, "x"); a.base.advance(1)
        let y = try await a.put(sa, "y"); a.base.advance(1)
        let d = try await a.put(sa, "d", .derivedResult, derivedFrom: [x])
        try await a.delete(sa, [y])
        let (bytes, rk) = try await a.exportV3(sa)
        #expect(sa.lastExportedGeneration == 1)
        let b = StoreFixture(); defer { b.cleanup() }
        let sb = try await b.open()
        let r = try b.restore(sb, bytes, rk)
        let p = r.provenance
        #expect(p.formatVersion == 3 && p.bodySchemaVersion == 2 && p.vaultInstanceID == sa.vaultInstanceID && p.backupGeneration == 1 && p.excludedAttachmentCount == 0)
        #expect(p.sourceManifestGeneration == sa.manifestGeneration && p.sourceManifestHash == sa.manifestHash && p.deletionHistoryTrusted)
        let embedded = try DeletionLedger.decode(try #require(p.deletionLedgerBytes))
        #expect(embedded.lookup(y) == .deleted && embedded.lookup(x) == .notDeleted)
        #expect(Set(r.active.map(\.header.recordID)) == [x, d] && r.quarantined.isEmpty)
        let rep = try await b.admit(sb, r)
        #expect(Set(rep.staged) == [x, d] && rep.risks[x] == [] && rep.risks[d] == [] && rep.historyMerged && rep.skippedDeleted.isEmpty)
        #expect(sb.deletionLookup(y) == .deleted && sb.deletionCount == 1, "the backup's history is now this vault's history")
        #expect(sb.state(of: x) == .quarantined && sb.state(of: d) == .quarantined)
        await expectVaultError(.recordNotActive(state: "quarantined")) { try await b.get(sb, x) }
        await expectVaultError(.recordNotActive(state: "sourceInactive")) { try await b.activate(sb, [d]) }
        try await b.activate(sb, [x, d])
        let gx = try await b.get(sb, x), gd = try await b.get(sb, d)
        #expect(gx == "x" && gd == "d")
        try await sb.close()
        let sb2 = try await b.open()
        #expect(sb2.state(of: x) == .active && sb2.deletionLookup(y) == .deleted && sb2.deletionHistoryTrusted)
        try await sb2.close(); try await sa.close()
    }

    @Test("NT-BK-02: v3 bytes expose only magic, version, salt and nonce — no instance id, manifest hash, ledger magic, record ids, authz magic or epoch")
    func cleartextLeak() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let x = try await a.put(sa, "x"); let y = try await a.put(sa, "y"); try await a.delete(sa, [y])
        let (bytes, _) = try await a.exportV3(sa)
        let sealed = try SealedBackup.decode(bytes)
        #expect(sealed.formatVersion == 3 && bytes.count == SealedBackup.magic.count + 2 + 4 + 16 + 4 + 12 + 4 + 4 + 16 + sealed.ciphertext.count && sealed.ciphertext.count % 4096 == 0)
        for needle in [sa.vaultInstanceID, sa.manifestHash, Array("XRAI-LEDGER-1".utf8), Array("XRAI-AUTHZ-1".utf8), Array("XRAI-MANIFEST-2".utf8), Array(x.hex.utf8), Array(y.hex.utf8), Array("birth_date".utf8)] {
            #expect(!contains(bytes, needle))
        }
        try await sa.close()
    }

    @Test("NT-BK-03: wrong recovery key, flipped bytes across the file, truncation, trailing bytes, version 1/4 → typed refusal; nothing is staged")
    func tamperAndWrongKey() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        _ = try await a.put(sa, "x")
        let (bytes, rk) = try await a.exportV3(sa)
        let b = StoreFixture(); defer { b.cleanup() }
        let sb = try await b.open()
        await expectVaultError(.backupIntegrityFailed) { try b.restore(sb, bytes, try SecureVault.generateRecoveryKey()) }
        var pos = 0
        while pos < bytes.count {
            var t = bytes; t[pos] ^= 0x01
            do { _ = try b.restore(sb, t, rk); Issue.record("flip at \(pos) accepted") }
            catch let e as VaultError {
                switch e { case .backupIntegrityFailed, .backupCorrupted, .unsupportedFormat, .invalidLength, .limitExceeded: break; default: Issue.record("unexpected \(e) at \(pos)") }
            }
            pos += max(1, bytes.count / 97)
        }
        #expect(throws: VaultError.self) { try b.restore(sb, Array(bytes.dropLast(7)), rk) }
        #expect(throws: VaultError.backupCorrupted(reason: "trailing bytes")) { try b.restore(sb, bytes + [0], rk) }
        var v1 = bytes; v1[6] = 0; v1[7] = 1
        #expect(throws: VaultError.unsupportedFormat(1)) { try b.restore(sb, v1, rk) }
        var v4 = bytes; v4[6] = 0; v4[7] = 4
        #expect(throws: VaultError.unsupportedFormat(4)) { try b.restore(sb, v4, rk) }
        var v2 = bytes; v2[6] = 0; v2[7] = 2   // a v3 body relabelled as v2: keys and AAD differ → fails, never parsed as v2
        #expect(throws: VaultError.backupIntegrityFailed) { try b.restore(sb, v2, rk) }
        #expect(sb.recordIDs.isEmpty && b.names("records").isEmpty)
        try await sb.close(); try await sa.close()
    }

    @Test("NT-BK-04: a legacy v2 backup restores with legacy provenance and is staged with the legacyFormat risk (empty or non-empty vault); it never counts as our own instance")
    func legacyV2() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let env = try sa.vault.seal(plaintext: Array("old".utf8), descriptor: try a.descriptor(), authorization: try sa.issuer.issue(scope: .write(.birthDate)))
        let rk = try SecureVault.generateRecoveryKey()
        let v2 = try sa.vault.exportBackup([env], recoveryKey: rk, authorization: try sa.issuer.issue(scope: .exportBackup))
        #expect(try SealedBackup.decode(v2).formatVersion == 2)
        let r = try a.restore(sa, v2, rk)
        #expect(r.provenance.formatVersion == 2 && r.provenance.isLegacy && r.provenance.deletionLedgerBytes == nil)
        let rep = try await a.admit(sa, r)                       // empty vault
        #expect(rep.risks[env.header.recordID] == [.legacyFormat] && !rep.historyMerged)
        await expectVaultError(.notEligible(reason: "restore risks must be acknowledged exactly: need 2 got ")) { try await a.activate(sa, [env.header.recordID]) }
        try await a.activate(sa, [env.header.recordID], [.legacyFormat])
        #expect(try await a.get(sa, env.header.recordID) == "old")
        let env2 = try sa.vault.seal(plaintext: Array("old2".utf8), descriptor: try a.descriptor(), authorization: try sa.issuer.issue(scope: .write(.birthDate)))
        let v2b = try sa.vault.exportBackup([env2], recoveryKey: rk, authorization: try sa.issuer.issue(scope: .exportBackup))
        let rep2 = try await a.admit(sa, try a.restore(sa, v2b, rk))   // non-empty vault, same risk set (legacy is never "foreign" and never "ours")
        #expect(rep2.risks[env2.header.recordID] == [.legacyFormat])
        try await sa.close()
    }

    @Test("NT-BK-05: the backup generation is durable and monotonic across relaunch; an older generation of our own instance reaches staging only when local history was lost (genuine path) and is marked olderBackupGeneration; export refuses a corrupt record but still burns its generation")
    func generations() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let x0 = try await f.put(s, "x0")
        let (older, rkOlder) = try await f.exportV3(s)            // generation 1 contains x0
        _ = try await f.exportV3(s)
        #expect(s.lastExportedGeneration == 2)
        try await f.delete(s, [x0])
        try await s.close()
        // lose the local history (AEAD-corrupt ledger) → x0 is no longer known as deleted; sticky distrust
        let lp = f.systemPath("ledger.v1"); var badL = Array(try Data(contentsOf: lp)); badL[100] ^= 0x01; try Data(badL).write(to: lp)
        let s2 = try await f.open()
        #expect(s2.lastExportedGeneration == 2 && s2.deletionHistoryTrusted == false)
        let x = try await f.put(s2, "x")
        _ = try await f.exportV3(s2)                               // generation 3
        let rep = try await s2.admitRestored(try f.restore(s2, older, rkOlder), authorization: try s2.issuer.issue(scope: .admitRestored))
        #expect(rep.staged == [x0] && rep.risks[x0] == [.untrustedLocalHistory, .olderBackupGeneration], Comment(rawValue: "\(rep.risks)"))
        #expect(s2.lastExportedGeneration == 3)
        // corrupt record → export fails closed; the generation was still consumed
        let path = f.rootURL.appendingPathComponent("records/\(x.hex).env")
        var bad = Array(try Data(contentsOf: path))
        let n = Int(UInt32(bad[0]) << 24 | UInt32(bad[1]) << 16 | UInt32(bad[2]) << 8 | UInt32(bad[3]))
        bad[4 + n - 3] ^= 0x01   // inside the AEAD tag: the envelope parses but fails authentication at export verification
        try Data(bad).write(to: path)
        await expectVaultError(.envelopeIntegrityFailed) { _ = try await f.exportV3(s2) }
        #expect(s2.lastExportedGeneration == 4, "the generation was committed before sealing and stays burned")
        // a record whose file no longer parses fails even earlier (before any generation is consumed)
        bad[10] ^= 0xFF; try Data(bad).write(to: path)
        await expectVaultError(.recordNotActive(state: "corrupt")) { _ = try await f.exportV3(s2) }
        #expect(s2.lastExportedGeneration == 4)
        try await s2.close()
    }

    @Test("NT-BK-06: a v3 export never includes attachments, store metadata, suspended or quarantined records; an untrusted local history is exported with deletionHistoryTrusted = false and is never merged by the importer")
    func exportScope() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "j")
        let j = try await f.put(s, "journal", .journal, purpose: "j")
        let x = try await f.put(s, "x")
        _ = try await s.revoke(purpose: "j", mode: .suspend(graceSeconds: 1000), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "j")))
        #expect(s.state(of: j) == .suspended)
        let (bytes, rk) = try await f.exportV3(s)
        let r = try f.restore(s, bytes, rk)
        #expect(r.active.map(\.header.recordID) == [x])
        try await s.close()
        // untrusted history: corrupt the ledger, reopen, export → flag false; a fresh vault does not merge it
        let lp = f.systemPath("ledger.v1"); var bad = Array(try Data(contentsOf: lp)); bad[100] ^= 0x01; try Data(bad).write(to: lp)
        let s2 = try await f.open()
        #expect(s2.deletionHistoryTrusted == false)
        let (bytes2, rk2) = try await f.exportV3(s2)
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let r2 = try g.restore(sg, bytes2, rk2)
        #expect(r2.provenance.deletionHistoryTrusted == false)
        let rep = try await g.admit(sg, r2)
        #expect(!rep.historyMerged && rep.risks[x] == [.unmergedBackupHistory])
        try await sg.close(); try await s2.close()
    }
}

@Suite("GATE 3 — restore reconciliation (verify & stage, then activate)", .serialized)
struct StoreRestoreReconciliationTests {
    @Test("NT-RR-07/13: consent inactive at restore → staged with the risk and activation refused until a grant exists; a token narrowed to one id cannot activate another")
    func consentAndScope() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        a.grant(.journal, purpose: "j")
        let j = try await a.put(sa, "entry", .journal, purpose: "j")
        let x = try await a.put(sa, "x")
        let (bytes, rk) = try await a.exportV3(sa)
        let b = StoreFixture(); defer { b.cleanup() }
        let sb = try await b.open()
        let r = try b.restore(sb, bytes, rk)
        #expect(r.quarantined.map(\.envelope.header.recordID) == [j] && r.active.map(\.header.recordID) == [x])
        let rep = try await b.admit(sb, r)
        #expect(rep.risks[j] == [.consentInactiveAtRestore] && rep.risks[x] == [])
        await expectVaultError(.notAuthorized(.consentRequired)) { try await b.activate(sb, [j], [.consentInactiveAtRestore]) }
        #expect(sb.state(of: j) == .quarantined)
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) {
            try await sb.activateRestored([x, j], acknowledging: [.consentInactiveAtRestore], authorization: try sb.issuer.issue(scope: .activateRestored(recordIDs: [x])))
        }
        #expect(sb.state(of: x) == .quarantined, "a scope mismatch activates nothing")
        b.grant(.journal, purpose: "j")
        try await b.activate(sb, [j], [.consentInactiveAtRestore])
        try await b.activate(sb, [x])
        let gj = try await b.get(sb, j, purpose: "j"), gx = try await b.get(sb, x)
        #expect(gj == "entry" && gx == "x")
        try await sb.close(); try await sa.close()
    }

    @Test("NT-RR-10/14: re-importing the same backup skips existing ids (staged or active); a staged record deleted meanwhile can never be activated and is skipped as deleted on the next import")
    func reimportAndDeletedNeverReturns() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let x = try await a.put(sa, "x"); let y = try await a.put(sa, "y")
        let (bytes, rk) = try await a.exportV3(sa)
        let b = StoreFixture(); defer { b.cleanup() }
        let sb = try await b.open()
        let rep1 = try await b.admit(sb, try b.restore(sb, bytes, rk))
        #expect(Set(rep1.staged) == [x, y])
        let rep2 = try await b.admit(sb, try b.restore(sb, bytes, rk))
        #expect(rep2.staged.isEmpty && Set(rep2.skippedExisting) == [x, y])
        try await b.activate(sb, [x])
        try await b.delete(sb, [y])
        await expectVaultError(.recordMissing) { try await b.activate(sb, [y]) }
        let rep3 = try await b.admit(sb, try b.restore(sb, bytes, rk))
        #expect(rep3.skippedExisting == [x] && rep3.skippedDeleted == [y] && rep3.staged.isEmpty)
        #expect(sb.state(of: y) == nil && !b.fileExists(y) && sb.deletionLookup(y) == .deleted)
        try await sb.close(); try await sa.close()
    }

    @Test("NT-RR-11 (NT-H1-06): the embedded history of a newer backup makes a fresh device skip ids an older backup still contains")
    func embeddedHistoryOnFreshDevice() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let x = try await a.put(sa, "x"); let y = try await a.put(sa, "y")
        let (b1, rk1) = try await a.exportV3(sa)
        try await a.delete(sa, [x])
        let (b2, rk2) = try await a.exportV3(sa)
        let c = StoreFixture(); defer { c.cleanup() }
        let sc = try await c.open()
        let rep2 = try await c.admit(sc, try c.restore(sc, b2, rk2))
        #expect(rep2.staged == [y] && rep2.historyMerged && sc.deletionLookup(x) == .deleted)
        let rep1 = try await c.admit(sc, try c.restore(sc, b1, rk1))
        #expect(rep1.skippedDeleted == [x] && rep1.skippedExisting == [y] && rep1.staged.isEmpty, "x was deleted at the source after B1: it never comes back")
        #expect(rep1.risks.isEmpty)
        try await sc.close()
        let sc2 = try await c.open()
        #expect(sc2.deletionLookup(x) == .deleted, "merged history is durable")
        try await sc2.close(); try await sa.close()
    }

    @Test("NT-RR-04/06: a corrupted local manifest refuses to open at all; a rolled-back local ledger opens read-only and refuses admission")
    func localStateDamage() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "x")
        let (bytes, rk) = try await f.exportV3(s)
        let r = try f.restore(s, bytes, rk)
        try await s.close()
        let mp = f.systemPath("manifest.v1")
        let good = try Data(contentsOf: mp)
        var bad = Array(good)
        let n = Int(UInt32(bad[0]) << 24 | UInt32(bad[1]) << 16 | UInt32(bad[2]) << 8 | UInt32(bad[3]))
        bad[4 + n - 3] ^= 0x01   // AEAD tag → authentication failure
        try Data(bad).write(to: mp)
        await expectVaultError(.authenticationFailed) { try await f.open() }
        var bad2 = Array(good); bad2[200] ^= 0x01; try Data(bad2).write(to: mp)   // a flip in a length field → structural refusal, still no open
        do { _ = try await f.open(); Issue.record("corrupted manifest opened") } catch let e as VaultError { #expect(e != .storeLocked, Comment(rawValue: "\(e)")) }
        try good.write(to: mp)
        let s2 = try await f.open()
        let x2 = try await f.put(s2, "y")
        let older = try Data(contentsOf: f.systemPath("ledger.v1"))
        try await f.delete(s2, [x2])
        try await s2.close()
        try older.write(to: f.systemPath("ledger.v1"))
        let s3 = try await f.open()
        #expect(s3.mode == .readOnly(reason: "deletion ledger does not bind to the manifest"))
        await expectVaultError(.storeReadOnly(reason: "deletion ledger does not bind to the manifest")) { try await f.admit(s3, r) }
        try await s3.close()
    }

    @Test("NT-RR-12: a crash at every syscall of an admission (3 records + history merge) is all-or-nothing after reopen; an announced-but-unwritten merge aborts the admission")
    func admissionCrashEverywhere() async throws {
        let a = StoreFixture(); defer { a.cleanup() }
        let sa = try await a.open()
        let ids = [try await a.put(sa, "1"), try await a.put(sa, "2"), try await a.put(sa, "3")]
        let gone = try await a.put(sa, "gone"); try await a.delete(sa, [gone])
        let (bytes, rk) = try await a.exportV3(sa)
        try await sa.close()
        var step = 1
        var outcomes = Set<String>()
        while true {
            let b = StoreFixture(); defer { b.cleanup() }
            let sb = try await b.open()
            let r = try b.restore(sb, bytes, rk)
            b.fs.arm(at: step)
            var crashed = false
            do { _ = try await b.admit(sb, r) } catch is SimulatedCrash { crashed = true } catch { Issue.record("step \(step): \(error)"); b.fs.disarm(); try await sb.close(); throw error }
            b.fs.disarm(); try await sb.close()
            let rb = try await b.open()
            #expect(rb.mode == .readWrite, Comment(rawValue: "step \(step): \(rb.mode)"))
            let staged = ids.filter { rb.state(of: $0) == .quarantined }
            let files = b.names("records").filter { !$0.hasPrefix(".") }
            if staged.count == 3 {
                #expect(rb.deletionLookup(gone) == .deleted && rb.deletionCount == 1 && files.count == 3, Comment(rawValue: "step \(step): staged but history/files incomplete"))
                outcomes.insert("all")
            } else {
                #expect(staged.isEmpty && files.isEmpty && rb.deletionCount == 0 && rb.deletionLookup(gone) == .notDeleted, Comment(rawValue: "step \(step): partial admission \(staged.count)/\(files.count)/\(rb.deletionCount)"))
                outcomes.insert("none")
            }
            #expect(b.names("journal").isEmpty && rb.deletionHistoryTrusted)
            try await rb.close()
            if !crashed { break }
            step += 1
            if step > 200 { Issue.record("never completed"); break }
        }
        #expect(outcomes == ["all", "none"] && step > 20, Comment(rawValue: "outcomes \(outcomes), steps \(step)"))
    }
}
