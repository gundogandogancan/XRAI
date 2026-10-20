// P03-04b GATE 1 — LEDGER_ONLY_ROLLBACK [P0]: the deletion ledger on disk is accepted only as a state
// the manifest and the pending journal PROVE (rows NT-LR-01…08).
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

@Suite("GATE 1 — ledger binding through pending journals (no rollback is ever re-trusted)", .serialized)
struct StoreLedgerBindingTests {
    /// Vault with records a, b; a deleted (ledger L1); then delete b interrupted at `tick`.
    /// Returns the ledger bytes L0 (empty history), L1 (a deleted) and the ids.
    private func pendingDelete(_ f: StoreFixture, tick: Int) async throws -> (l0: Data, l1: Data, a: RecordID, b: RecordID) {
        let s = try await f.open()
        let a = try await f.put(s, "A"), b = try await f.put(s, "B")
        let l0 = try Data(contentsOf: f.systemPath("ledger.v1"))
        try await f.delete(s, [a])
        let l1 = try Data(contentsOf: f.systemPath("ledger.v1"))
        f.fs.arm(at: tick)
        let grant = try s.vault.authorizeDeletion(of: [b], authorization: try s.issuer.issue(scope: .delete(recordIDs: [b])))
        do { try await s.delete([b], grant: grant); Issue.record("expected a simulated crash") } catch is SimulatedCrash {}
        f.fs.disarm(); try await s.close()
        #expect(f.names("journal").count == 1)
        return (l0, l1, a, b)
    }
    private func journalURL(_ f: StoreFixture) -> URL { f.rootURL.appendingPathComponent("journal/" + f.names("journal")[0]) }

    @Test("NT-LR-01: an older authentic ledger put back under a PENDING delete journal is refused (read-only, never re-trusted); the genuine pre- and post-states still recover")
    func rollbackUnderPendingJournal() async throws {
        // post-state written (crash at the manifest temp open = tick 22), then rolled back to L0
        let f = StoreFixture(); defer { f.cleanup() }
        let (l0, l1, a, b) = try await pendingDelete(f, tick: 22)
        let l2 = try Data(contentsOf: f.systemPath("ledger.v1"))
        #expect(l2 != l1 && l1 != l0, "three distinct ledger states")
        try l0.write(to: f.systemPath("ledger.v1"))
        let r = try await f.open()
        #expect(r.mode == .readOnly(reason: "deletion ledger state is not proven by the journal") && r.deletionHistoryTrusted == false)
        await expectVaultError(.storeReadOnly(reason: "deletion ledger state is not proven by the journal")) { try await f.put(r, "x") }
        #expect(f.names("journal").count == 1, "the journal is kept for forensics, not replayed")
        try await r.close()
        let r2 = try await f.open()
        #expect(r2.mode == .readOnly(reason: "deletion ledger state is not proven by the journal"), "nothing heals it")
        try await r2.close()
        // rolled back to the PRE-state (L1): indistinguishable from "not yet written" → replay rewrites L2
        try l1.write(to: f.systemPath("ledger.v1"))
        let r3 = try await f.open()
        #expect(r3.mode == .readWrite && r3.deletionHistoryTrusted && r3.deletionLookup(a) == .deleted && r3.deletionLookup(b) == .deleted && r3.state(of: b) == nil)
        #expect(r3.deletionCount == 2 && f.names("journal").isEmpty, "the replay reproduces the announced post-state (same plaintext; the envelope bytes differ by nonce)")
        try await r3.close()
        // genuine post-state on disk (fresh fixture): replay is idempotent
        let g = StoreFixture(); defer { g.cleanup() }
        let (_, _, ga, gb) = try await pendingDelete(g, tick: 22)
        let r4 = try await g.open()
        #expect(r4.mode == .readWrite && r4.deletionLookup(ga) == .deleted && r4.deletionLookup(gb) == .deleted && r4.deletionCount == 2)
        try await r4.close()
        // crash before the ledger write (tick 17): disk = pre-state, journal announces the post-state → replay
        let h = StoreFixture(); defer { h.cleanup() }
        let (_, hl1, _, hb) = try await pendingDelete(h, tick: 17)
        #expect(try Data(contentsOf: h.systemPath("ledger.v1")) == hl1)
        let r5 = try await h.open()
        #expect(r5.mode == .readWrite && r5.deletionLookup(hb) == .deleted && r5.deletionCount == 2)
        try await r5.close()
    }

    @Test("NT-LR-02: a pending journal from another history (same keys, same generation, different pre-state) does not bind to the manifest → read-only")
    func foreignJournalRefused() async throws {
        let keys = InMemoryKeyProvider(keyID: "device")
        let fa = StoreFixture(keys: keys); defer { fa.cleanup() }
        let sa = try await fa.open()
        let x = try await fa.put(sa, "x"); _ = try await fa.put(sa, "y")
        try await fa.delete(sa, [x])                       // A: generation 4, ledger L1(x)
        try await sa.close()
        let fb = StoreFixture(keys: keys); defer { fb.cleanup() }
        let sb = try await fb.open()
        let p = try await fb.put(sb, "p"); _ = try await fb.put(sb, "q"); _ = try await fb.put(sb, "r")   // B: generation 4, empty ledger
        fb.fs.arm(at: 22)
        let grant = try sb.vault.authorizeDeletion(of: [p], authorization: try sb.issuer.issue(scope: .delete(recordIDs: [p])))
        do { try await sb.delete([p], grant: grant) } catch is SimulatedCrash {}
        fb.fs.disarm(); try await sb.close()
        let jb = journalURL(fb)
        try FileManager.default.copyItem(at: jb, to: fa.rootURL.appendingPathComponent("journal/" + jb.lastPathComponent))
        let ra = try await fa.open()
        #expect(ra.mode == .readOnly(reason: "journal does not bind to the manifest") && ra.deletionHistoryTrusted == false)
        #expect(ra.state(of: x) == nil && ra.recordIDs.count == 1, "A's own state is untouched")
        try await ra.close()
    }

    @Test("NT-LR-03: a written post-state whose announcement is missing from the journal is not proven → read-only")
    func postStateWithoutAnnouncement() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        _ = try await pendingDelete(f, tick: 22)
        let jp = journalURL(f)
        let bytes = Array(try Data(contentsOf: jp))
        var d = CanonicalDecoder(bytes); let n1 = (try d.readBytes()).count; let n2 = (try d.readBytes()).count
        let kept = 4 + n1 + 4 + n2
        #expect(kept < bytes.count, "the third entry (ledgerWritten) exists and is dropped")
        try Data(bytes.prefix(kept)).write(to: jp)
        let r = try await f.open()
        #expect(r.mode == .readOnly(reason: "deletion ledger state is not proven by the journal"))
        try await r.close()
    }

    @Test("NT-LR-04: an older journal format or an older manifest format is never converted — journal → read-only, manifest → open refused")
    func legacyFormatsRefused() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "x")
        var e = CanonicalEncoder(); e.appendString("XRAI-J-1"); e.appendU8(4)
        let d = try RecordDescriptor(dataClass: .storeMetadata, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0)
        let sealed = try s.vault.sealSystem(plaintext: e.bytes, descriptor: d)
        var enc = CanonicalEncoder(); sealed.encode(into: &enc)
        var frame = CanonicalEncoder(); frame.appendBytes(enc.bytes)
        try await s.close()
        try Data(frame.bytes).write(to: f.rootURL.appendingPathComponent("journal/3.j"))
        let r = try await f.open()
        #expect(r.mode == .readOnly(reason: "journal format unsupported"))
        await expectVaultError(.storeReadOnly(reason: "journal format unsupported")) { try await f.put(r, "y") }
        try await r.close()
        try FileManager.default.removeItem(at: f.rootURL.appendingPathComponent("journal/3.j"))
        // legacy manifest magic
        let r2 = try await f.open()
        var me = CanonicalEncoder(); me.appendString("XRAI-MANIFEST-1"); me.appendU64(2)
        let sealedM = try r2.vault.sealSystem(plaintext: me.bytes, descriptor: d)
        var encM = CanonicalEncoder(); sealedM.encode(into: &encM)
        var frameM = CanonicalEncoder(); frameM.appendBytes(encM.bytes)
        var padded = frameM.bytes; padded += [UInt8](repeating: 0, count: 4096 - padded.count % 4096)
        try await r2.close()
        let good = try Data(contentsOf: f.systemPath("manifest.v1"))
        try Data(padded).write(to: f.systemPath("manifest.v1"))
        await expectVaultError(.unsupportedFormat(1)) { try await f.open() }
        try good.write(to: f.systemPath("manifest.v1"))
        let r3 = try await f.open(); #expect(r3.mode == .readWrite); try await r3.close()
    }

    @Test("NT-LR-05: LedgerBinding rules — epoch mismatch, stale generation, manifest-durable post/pre binding; manifest v2 round-trips kinds and risks")
    func bindingRules() throws {
        let h0 = [UInt8](repeating: 1, count: 32), h1 = [UInt8](repeating: 2, count: 32), h2 = [UInt8](repeating: 3, count: 32)
        var m = Manifest(generation: 4, prevHash: Manifest.zeroHash, vaultInstanceID: [UInt8](repeating: 7, count: 16), minimumWrapVersion: 1, ledgerHash: h1)
        func begin(_ target: UInt64, epoch: UInt64 = 3, pre: [UInt8]) -> JournalEntry { .begin(op: "delete", tokenID: "", ids: [], targetGeneration: target, epoch: epoch, params: [], ledgerHash: pre) }
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h1, journal: nil, persistedEpoch: 3) == nil)
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h0, journal: nil, persistedEpoch: 3) == "deletion ledger does not bind to the manifest")
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h1, journal: [begin(5, epoch: 2, pre: h1)], persistedEpoch: 3) == "journal does not bind to the authorization state")
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h1, journal: [begin(7, pre: h1)], persistedEpoch: 3) == "stale journal generation")
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h1, journal: [begin(5, pre: h0)], persistedEpoch: 3) == "journal does not bind to the manifest")
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h1, journal: [begin(5, pre: h1)], persistedEpoch: 3) == nil)
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h2, journal: [begin(5, pre: h1)], persistedEpoch: 3) == "deletion ledger state is not proven by the journal")
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h2, journal: [begin(5, pre: h1), .ledgerWritten(hash: h2)], persistedEpoch: 3) == nil)
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h0, journal: [begin(5, pre: h1), .ledgerWritten(hash: h2)], persistedEpoch: 3) == "deletion ledger state is not proven by the journal")
        // manifest durable (target == generation): it must bind the announced post-state
        m.generation = 5; m.ledgerHash = h2
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h2, journal: [begin(5, pre: h1), .ledgerWritten(hash: h2), .manifestWritten(generation: 5)], persistedEpoch: 3) == nil)
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h1, journal: [begin(5, pre: h1), .ledgerWritten(hash: h2), .manifestWritten(generation: 5)], persistedEpoch: 3) == "deletion ledger does not bind to the manifest")
        #expect(LedgerBinding.verify(manifest: m, diskLedgerHash: h2, journal: [begin(5, pre: h1), .manifestWritten(generation: 5)], persistedEpoch: 3) == "journal does not bind to the manifest")
        // manifest v2 round trip
        let id = RecordID()
        let hdr = EnvelopeHeader(formatVersion: 2, algorithm: .aes256gcm, recordID: id, dataClass: .evidenceFiles, privacyTier: .deviceHighSensitivity, retention: .untilUserDeletes, consentPurpose: "", createdAtUnixSeconds: storeT0)
        m.records[id.hex] = ManifestEntry(header: hdr, keyVersion: 1, state: .quarantined, provenance: .restoredFromBackup, kind: .attachment, attachmentBytes: 12_345, chunkCount: 3, restoreRisks: RestoreRisk.mask([.foreignInstance, .olderBackupGeneration]))
        m.ledgerHistoryTrusted = false
        let back = try Manifest.decode(m.encode())
        #expect(back == m && back.records[id.hex]?.kind == .attachment && RestoreRisk.set(back.records[id.hex]!.restoreRisks) == [.foreignInstance, .olderBackupGeneration] && back.ledgerHistoryTrusted == false)
        var bad = m.encode(); bad[bad.count - 1] = 0xFF
        #expect(throws: VaultError.self) { try Manifest.decode(bad) }
        // journal v2 round trip + legacy magic
        let j = JournalEntry.begin(op: "x", tokenID: "t", ids: [id], targetGeneration: 9, epoch: 2, params: [1, -1], ledgerHash: h2)
        #expect(try JournalEntry.decode(j.encode()) == j && JournalEntry.decode(JournalEntry.ledgerWritten(hash: h1).encode()) == .ledgerWritten(hash: h1))
        var legacy = CanonicalEncoder(); legacy.appendString("XRAI-J-1"); legacy.appendU8(4)
        #expect(throws: VaultError.unsupportedFormat(1)) { try JournalEntry.decode(legacy.bytes) }
    }

    @Test("NT-LR-06: a corrupt ledger makes distrust STICKY — a later delete rewrites the ledger but the manifest keeps the history untrusted across relaunch; restores keep quarantining")
    func corruptLedgerStaysUntrusted() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let a = try await f.put(s, "A"), b = try await f.put(s, "B")
        try await f.delete(s, [a])
        try await s.close()
        let lp = f.systemPath("ledger.v1")
        var bad = Array(try Data(contentsOf: lp)); bad[100] ^= 0x01; try Data(bad).write(to: lp)
        let s2 = try await f.open()
        #expect(s2.mode == .readWrite && s2.deletionHistoryTrusted == false)
        try await f.delete(s2, [b])              // rewrites the ledger from the (empty) in-memory copy
        #expect(s2.deletionLookup(b) == .deleted && s2.deletionLookup(a) == .notDeleted, "the lost history is gone, and that is now recorded")
        try await s2.close()
        let s3 = try await f.open()
        #expect(s3.mode == .readWrite && s3.deletionHistoryTrusted == false, "sticky across relaunch (manifest flag)")
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let foreignID = try await g.put(sg, "from another vault")
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try await sg.exportBackup(recoveryKey: rk, authorization: try sg.issuer.issue(scope: .exportBackup))
        try await sg.close()
        let rep = try await s3.admitRestored(try s3.vault.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try s3.issuer.issue(scope: .restoreBackup)), authorization: try s3.issuer.issue(scope: .admitRestored))
        #expect(rep.staged == [foreignID] && rep.risks[foreignID]?.contains(.untrustedLocalHistory) == true)
        try await s3.close()
    }

    @Test("NT-LR-07: a corrupt ledger together with a pending operation is never replayed from an empty history → read-only")
    func corruptLedgerWithPendingJournal() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        _ = try await pendingDelete(f, tick: 22)
        let lp = f.systemPath("ledger.v1")
        var bad = Array(try Data(contentsOf: lp)); bad[100] ^= 0x01; try Data(bad).write(to: lp)
        let r = try await f.open()
        #expect(r.mode == .readOnly(reason: "deletion ledger unreadable with a pending operation") && r.deletionHistoryTrusted == false)
        #expect(f.names("journal").count == 1)
        try await r.close()
    }

    @Test("NT-LR-08: the journal begin entry of every op carries the manifest's ledger hash; a put that re-seals a stale ledger announces an identical post-state (no content change)")
    func beginCarriesLedgerHash() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "x")
        _ = try f.keys.rotate()
        f.fs.arm(at: 22)   // put under the new key: begin, file, step, ledgerWritten (stale re-seal), ledger, manifest open → crash
        do { _ = try await f.put(s, "y") } catch is SimulatedCrash {}
        f.fs.disarm(); try await s.close()
        let jp = journalURL(f)
        let (raw, _) = unframe(Array(try Data(contentsOf: jp)))
        #expect(raw.count == 3, Comment(rawValue: "entries: \(raw.count)"))
        let r = try await f.open()
        #expect(r.mode == .readWrite && r.recordIDs.count == 2 && r.deletionHistoryTrusted)
        try await r.close()
    }

    private func unframe(_ bytes: [UInt8]) -> ([[UInt8]], Bool) {
        var out: [[UInt8]] = []; var c = 0
        while c + 4 <= bytes.count {
            let n = Int(UInt32(bytes[c]) << 24 | UInt32(bytes[c + 1]) << 16 | UInt32(bytes[c + 2]) << 8 | UInt32(bytes[c + 3])); c += 4
            guard n > 0, c + n <= bytes.count else { return (out, true) }
            out.append(Array(bytes[c..<c + n])); c += n
        }
        return (out, false)
    }
}
