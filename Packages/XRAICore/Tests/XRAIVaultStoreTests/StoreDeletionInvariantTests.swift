// P03-04bH2 — GLOBAL DELETION INVARIANT: a record identity that has been deleted, or may have been
// deleted, can never become active under the same RecordID — at ANY entry point (rows NT-GD-01…).
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

@Suite("P03-04bH2 — global deletion invariant at every entry point", .serialized)
struct StoreDeletionInvariantTests {
    @Test("NT-GD-01 (attack A): create → delete → put(same id) → get → reopen: the deleted identity never becomes active and the ledger keeps it deleted")
    func attackA_putSameID() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.put(s, "original")
        try await f.delete(s, [id])
        #expect(s.deletionLookup(id) == .deleted && !f.fileExists(id))
        let d = try RecordDescriptor(recordID: id, dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: try f.base.now())
        await expectVaultError(.recordIDDeleted) { try await s.put(plaintext: Array("resurrected".utf8), descriptor: d, authorization: try s.issuer.issue(scope: .write(.birthDate))) }
        #expect(s.state(of: id) == nil && !f.fileExists(id) && f.names("journal").isEmpty && s.deletionLookup(id) == .deleted)
        await expectVaultError(.recordMissing) { try await f.get(s, id) }
        try await s.close()
        let r = try await f.open()
        #expect(r.mode == .readWrite && r.state(of: id) == nil && !f.fileExists(id) && r.deletionLookup(id) == .deleted && r.deletionCount == 1)
        try await r.close()
    }
}

@Suite("P03-04bH2 — adversarial state transitions B–G (persistent state checked after reopen)", .serialized)
struct StoreDeletionAttackTests {
    @Test("NT-GD-02 (attack B): create attachment → delete → putAttachment(same id) → readAttachment → reopen")
    func attackB_attachmentSameID() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let parent = try await f.put(s, "p"); f.base.advance(1)
        let id = try await f.putAttachment(s, pattern(5000), derivedFrom: [parent])
        try await f.delete(s, [id])
        #expect(!f.attachmentExists(id) && s.deletionLookup(id) == .deleted)
        let d = try RecordDescriptor(recordID: id, dataClass: .evidenceFiles, retention: .untilUserDeletes, createdAtUnixSeconds: try f.base.now(), derivedFrom: [parent])
        await expectVaultError(.recordIDDeleted) { try await s.putAttachment(from: InMemoryAttachmentSource(pattern(5000)), descriptor: d, authorization: try s.issuer.issue(scope: .write(.evidenceFiles))) }
        #expect(s.state(of: id) == nil && !f.attachmentExists(id) && f.names("attachments").isEmpty && f.names("journal").isEmpty)
        await expectVaultError(.recordMissing) { try await f.readAttachment(s, id) }
        try await s.close()
        let r = try await f.open()
        #expect(r.mode == .readWrite && r.state(of: id) == nil && r.deletionLookup(id) == .deleted && f.names("attachments").isEmpty)
        try await r.close()
    }

    @Test("NT-GD-03 (attack C): delete → Bloom compaction → put(same id) and putAttachment(same id) → reopen: possiblyDeleted is refused at creation too")
    func attackC_afterCompaction() async throws {
        let f = StoreFixture(limits: StoreLimits(ledgerCompactionThreshold: 4, ledgerRecentKept: 2, ledgerDigestCapacity: 1_000)); defer { f.cleanup() }
        let s = try await f.open()
        var ids: [RecordID] = []
        for i in 0..<6 { ids.append(try await f.put(s, "r\(i)")) }
        try await f.delete(s, Set(ids))
        let compacted = ids.filter { s.deletionLookup($0) == .possiblyDeleted }
        #expect(compacted.count == 4)
        for id in compacted {
            let d = try RecordDescriptor(recordID: id, dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: try f.base.now())
            await expectVaultError(.possiblyDeletedForever) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .write(.birthDate))) }
            let da = try RecordDescriptor(recordID: id, dataClass: .evidenceFiles, retention: .untilUserDeletes, createdAtUnixSeconds: try f.base.now())
            await expectVaultError(.possiblyDeletedForever) { try await s.putAttachment(from: InMemoryAttachmentSource([1]), descriptor: da, authorization: try s.issuer.issue(scope: .write(.evidenceFiles))) }
        }
        #expect(s.recordIDs.isEmpty && f.names("records").isEmpty && f.names("attachments").isEmpty && f.names("journal").isEmpty)
        try await s.close()
        let r = try await f.open()
        #expect(r.mode == .readWrite && r.recordIDs.isEmpty && r.deletionCount == 6 && compacted.allSatisfy { r.deletionLookup($0) == .possiblyDeleted })
        try await r.close()
    }

    @Test("NT-GD-04 (attack D): delete → compact → restore → reimport under a NEW id → the OLD id stays denied at every entry point (put, putAttachment, activation, get) and across reopen")
    func attackD_oldIDAfterReimport() async throws {
        let f = StoreFixture(limits: StoreLimits(ledgerCompactionThreshold: 4, ledgerRecentKept: 2, ledgerDigestCapacity: 1_000)); defer { f.cleanup() }
        let s = try await f.open()
        var ids: [RecordID] = []
        for i in 0..<6 { ids.append(try await f.put(s, "r\(i)")) }
        let (bytes, rk) = try await f.exportV3(s)
        try await f.delete(s, Set(ids))
        let rep = try await f.admit(s, try f.restore(s, bytes, rk))
        let old = rep.staged[0]
        let newID = try await s.reimportUnderNewID(old, authorization: try s.issuer.issue(scope: .reimport(recordID: old)))
        #expect(newID != old && s.deletionLookup(old) == .deleted)
        let d = try RecordDescriptor(recordID: old, dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: try f.base.now())
        await expectVaultError(.recordIDDeleted) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .write(.birthDate))) }
        await expectVaultError(.recordMissing) { try await s.activateRestored([old], acknowledging: [], authorization: try s.issuer.issue(scope: .activateRestored(recordIDs: [old]))) }
        await expectVaultError(.recordMissing) { try await f.get(s, old) }
        let rep2 = try await f.admit(s, try f.restore(s, bytes, rk))
        #expect(rep2.skippedDeleted.contains(old))
        try await s.close()
        let r = try await f.open()
        #expect(r.deletionLookup(old) == .deleted && r.state(of: old) == nil && r.state(of: newID) == .active)
        await expectVaultError(.recordIDDeleted) { try await r.put(plaintext: [1], descriptor: d, authorization: try r.issuer.issue(scope: .write(.birthDate))) }
        try await r.close()
    }

    @Test("NT-GD-05 (attack E): a crafted journal that would re-create or activate a deleted id is never replayed into an active record; a put of a fresh id crashed at every syscall after a delete never revives the deleted one")
    func attackE_journalReplay() async throws {
        // E1: crash-at-every-syscall of a put AFTER a delete of another id: the deleted id never returns
        let f = StoreFixture(); defer { f.cleanup() }
        let s0 = try await f.open()
        let victim = try await f.put(s0, "victim")
        try await f.delete(s0, [victim])
        try await s0.close()
        var step = 1
        while true {
            let s = try await f.open()
            f.fs.arm(at: step)
            var crashed = false
            do { _ = try await f.put(s, "fresh") } catch is SimulatedCrash { crashed = true }
            f.fs.disarm(); try await s.close()
            let r = try await f.open()
            #expect(r.mode == .readWrite && r.state(of: victim) == nil && r.deletionLookup(victim) == .deleted && !f.fileExists(victim), Comment(rawValue: "step \(step)"))
            try await r.close()
            if !crashed { break }
            step += 1
        }
        // E2: a put journal (begin + file) for the DELETED id planted on disk → replay refuses to adopt it; the file is removed
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let v = try await g.put(sg, "v")
        let envBytes = try Data(contentsOf: g.rootURL.appendingPathComponent("records/\(v.hex).env"))
        try await g.delete(sg, [v])
        // craft: crash a put of a fresh record after its file landed (begin + file durable), then swap the file for the deleted id's bytes and rewrite the journal's begin for the deleted id
        g.fs.arm(at: 11)   // begin(5) + file(5) + step journal open → crash with begin only + file present
        do { _ = try await g.put(sg, "fresh") } catch is SimulatedCrash {}
        g.fs.disarm(); try await sg.close()
        let journals = g.names("journal")
        #expect(journals.count == 1)
        // open once to settle the crashed put, then plant the deleted id's envelope and a journal whose begin
        // (correct epoch, target generation and ledger binding) claims a put of that id
        let planted = try await g.open()
        #expect(planted.mode == .readWrite)
        let target = planted.manifestGeneration + 1
        let begin = JournalEntry.begin(op: "put", tokenID: "", ids: [v], targetGeneration: target, epoch: planted.epoch, params: [0, 0], ledgerHash: planted.boundLedgerHash)
        let sealed = try planted.vault.sealSystem(plaintext: begin.encode(), descriptor: try RecordDescriptor(dataClass: .storeMetadata, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0))
        var enc = CanonicalEncoder(); sealed.encode(into: &enc)
        var frame = CanonicalEncoder(); frame.appendBytes(enc.bytes)
        try await planted.close()
        try envBytes.write(to: g.rootURL.appendingPathComponent("records/\(v.hex).env"))
        try Data(frame.bytes).write(to: g.rootURL.appendingPathComponent("journal/" + String(target, radix: 16) + ".j"))
        let r2 = try await g.open()
        #expect(r2.state(of: v) == nil && r2.deletionLookup(v) == .deleted, "a replayed put never adopts a deleted id")
        #expect(!g.fileExists(v) || r2.integrityReport().orphansQuarantined >= 1, "the planted file is removed or quarantined, never adopted")
        await expectVaultError(.recordMissing) { try await g.get(r2, v) }
        try await r2.close()
    }

    @Test("NT-GD-06 (attack F): a manifest that lists an id the ledger says is deleted / possibly deleted opens read-only (contradiction), and the record cannot be read")
    func attackF_contradiction() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let a = try await f.put(s, "a")
        let snapManifest = try Data(contentsOf: f.systemPath("manifest.v1"))
        let snapAuthz = try Data(contentsOf: f.systemPath("authz.v1"))
        let fileBytes = try Data(contentsOf: f.rootURL.appendingPathComponent("records/\(a.hex).env"))
        try await f.delete(s, [a])
        try await s.close()
        // put the pre-delete manifest + authz back (ledger stays post-delete): generation chain + anchor break first
        try snapManifest.write(to: f.systemPath("manifest.v1")); try snapAuthz.write(to: f.systemPath("authz.v1"))
        try fileBytes.write(to: f.rootURL.appendingPathComponent("records/\(a.hex).env"))
        let r = try await f.open()
        if case .readOnly(let reason) = r.mode { #expect(["manifest rollback detected", "manifest contradicts the deletion ledger", "deletion ledger does not bind to the manifest"].contains(reason), Comment(rawValue: reason)) } else { Issue.record("opened read-write on a contradiction") }
        await expectVaultError(.recordIDDeleted) { try await f.get(r, a) }
        try await r.close()
        // in-memory contradiction through the policy itself (unit): active entry vs deleted / possiblyDeleted verdicts
        let hdr = EnvelopeHeader(formatVersion: 2, algorithm: .aes256gcm, recordID: a, dataClass: .birthDate, privacyTier: .deviceSensitive, retention: .untilUserDeletes, consentPurpose: "", createdAtUnixSeconds: storeT0)
        let active = ManifestEntry(header: hdr, keyVersion: 1)
        let staged = ManifestEntry(header: hdr, keyVersion: 1, state: .quarantined, provenance: .restoredFromBackup, restoreRisks: RestoreRisk.mask([.possiblyDeleted]))
        #expect(IdentityPolicy.contradicts(active, verdict: .deleted) && IdentityPolicy.contradicts(active, verdict: .possiblyDeleted) && !IdentityPolicy.contradicts(active, verdict: .clear))
        #expect(!IdentityPolicy.contradicts(staged, verdict: .possiblyDeleted) && IdentityPolicy.contradicts(staged, verdict: .deleted))
    }

    @Test("NT-GD-07 (attack G): unauthorized or wrong-purpose attempts (put, delete grant reuse, reimport, activation) never alter the deletion history or the manifest")
    func attackG_historyUnchanged() async throws {
        let f = StoreFixture(limits: StoreLimits(ledgerCompactionThreshold: 4, ledgerRecentKept: 2, ledgerDigestCapacity: 1_000)); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "j", id: "g-j")
        var ids: [RecordID] = []
        for i in 0..<6 { ids.append(try await s.put(plaintext: Array("e\(i)".utf8), descriptor: try f.descriptor(.journal, purpose: "j"), authorization: try s.issuer.issue(scope: .write(.journal), purpose: "j"))) }
        let (bytes, rk) = try await f.exportV3(s)
        try await f.delete(s, Set(ids))
        let rep = try await f.admit(s, try f.restore(s, bytes, rk))
        let staged = rep.staged[0]
        let exact = rep.skippedDeleted[0]   // an id with EXACT deletion evidence (not staged)
        let ledgerBefore = try Data(contentsOf: f.systemPath("ledger.v1")), manifestBefore = try Data(contentsOf: f.systemPath("manifest.v1"))
        let gen = s.manifestGeneration, count = s.deletionCount
        let d = try RecordDescriptor(recordID: exact, dataClass: .journal, retention: .untilUserDeletes, consentPurpose: "j", createdAtUnixSeconds: try f.base.now())
        await expectVaultError(.authorizationInvalid(.purposeMismatch)) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .write(.journal), purpose: "other")) }
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .read(recordIDs: nil), purpose: "j")) }
        await expectVaultError(.authorizationInvalid(.purposeMismatch)) { try await s.reimportUnderNewID(staged, authorization: try s.issuer.issue(scope: .reimport(recordID: staged), purpose: "other")) }
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.activateRestored([staged], acknowledging: [.possiblyDeleted], authorization: try s.issuer.issue(scope: .read(recordIDs: nil))) }
        f.authority.revoke(id: "g-j", atUnixSeconds: (try? f.base.now()) ?? storeT0)
        await expectVaultError(.notAuthorized(.consentRequired)) { try await s.reimportUnderNewID(staged, authorization: try s.issuer.issue(scope: .reimport(recordID: staged), purpose: "j")) }
        // a correctly authorized put of the exactly-deleted id is refused AFTER authorization (no oracle before it)
        f.grant(.journal, purpose: "j", id: "g-j2")
        await expectVaultError(.recordIDDeleted) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .write(.journal), purpose: "j")) }
        let grant = try s.vault.authorizeDeletion(of: [exact], authorization: try s.issuer.issue(scope: .delete(recordIDs: [exact])))
        try await s.delete([exact], grant: grant)   // already deleted: no-op, no mutation
        await expectVaultError(.deletionGrantInvalid) { try await s.delete([exact], grant: grant) }
        #expect(try Data(contentsOf: f.systemPath("ledger.v1")) == ledgerBefore && Data(contentsOf: f.systemPath("manifest.v1")) == manifestBefore)
        #expect(s.manifestGeneration == gen && s.deletionCount == count && s.state(of: staged) == .quarantined && f.names("journal").isEmpty)
        try await s.close()
        let r = try await f.open()
        #expect(r.deletionCount == count && r.state(of: staged) == .quarantined && r.manifestGeneration == gen + 0)
        try await r.close()
    }
}
