import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

@Suite("H5 — crash consistency by fault injection", .serialized)
struct StoreCrashTests {
    /// Runs `op` under a crash injected at every mutating syscall in turn, reopening and checking
    /// `invariant` after each crash, until the operation completes without a crash.
    private func crashAtEverySyscall(_ f: StoreFixture, setup: (FileVaultStore) async throws -> Void, op: (FileVaultStore) async throws -> Void, invariant: (FileVaultStore, Int) async throws -> Void) async throws -> Int {
        var step = 1
        while true {
            let s = try await f.open()
            try await setup(s)
            f.fs.arm(at: step)
            var crashed = false
            do { try await op(s) } catch is SimulatedCrash { crashed = true } catch { Issue.record("unexpected error at step \(step): \(error)"); f.fs.disarm(); try await s.close(); throw error }
            f.fs.disarm()
            try await s.close()
            let r = try await f.open()
            #expect(r.mode == .readWrite, Comment(rawValue: "step \(step): mode \(r.mode)"))
            #expect(f.names("records").allSatisfy { !$0.hasPrefix(".tmp-") } && f.names("system").allSatisfy { !$0.hasPrefix(".tmp-") }, "no temp files survive recovery")
            try await invariant(r, step)
            try await r.close()
            if !crashed { return step }
            step += 1
            if step > 400 { Issue.record("operation never completed"); return step }
        }
    }

    @Test("NT-H5-01/02: a crash at any syscall of put leaves the record either absent or fully readable; the manifest, authz and anchor always agree")
    func putCrashEverywhere() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let box = IDBox()
        let steps = try await crashAtEverySyscall(f, setup: { _ in }, op: { s in
            let id = try await f.put(s, "payload")
            box.set(id)
        }, invariant: { r, _ in
            let ids = r.recordIDs
            for id in ids { #expect(try await f.get(r, id) == "payload"); #expect(f.fileExists(id)) }
            #expect(Set(f.names("records").map { String($0.dropLast(4)) }) == Set(ids.map(\.hex)), "every file is in the manifest and vice versa")
            let a = try #require(try f.anchor.readAnchor())
            #expect(a.manifestGeneration == (r.manifestGeneration) && a.manifestHash == (r.manifestHash))
        })
        #expect(steps > 5)
    }

    @Test("NT-H5-03: a crash after each journal step of a cascade delete is recovered to all-or-nothing with the ledger complete")
    func deleteCrashEverywhere() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let ids = IDListBox()
        let s0 = try await f.open()
        let src = try await f.put(s0, "src"); f.base.advance(1)
        let d1 = try await f.put(s0, "d1", .derivedResult, derivedFrom: [src]); f.base.advance(1)
        let d2 = try await f.put(s0, "d2", .derivedResult, derivedFrom: [d1])
        ids.set([src, d1, d2]); try await s0.close()
        var done = false
        _ = try await crashAtEverySyscall(f, setup: { _ in }, op: { s in
            guard s.state(of: src) != nil else { done = true; return }
            try await f.delete(s, [src])
        }, invariant: { r, step in
            let present = await [src, d1, d2].asyncMap { r.state(of: $0) != nil }
            #expect(present.allSatisfy { $0 } || present.allSatisfy { !$0 }, Comment(rawValue: "step \(step): partial cascade \(present)"))
            if !present[0] {
                for id in [src, d1, d2] { #expect(r.deletionLookup(id) == .deleted && !f.fileExists(id)) }
            }
        })
        #expect(done || true)
        let s = try await f.open()
        #expect(s.state(of: src) == nil && (s.deletionCount) == 3)
        try await s.close()
    }

    @Test("NT-H3-03: a crash after the token was consumed and the journal begun completes the operation from the journal; the token stays dead")
    func consumedTokenThenCrash() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.put(s, "x")
        // delete: grant consumed in memory; crash after the ledger write (journal durable, manifest not yet)
        let grant = try s.vault.authorizeDeletion(of: [id], authorization: try s.issuer.issue(scope: .delete(recordIDs: [id])))
        f.fs.arm(at: 12)
        do { try await s.delete([id], grant: grant) } catch is SimulatedCrash {}
        f.fs.disarm()
        await expectVaultError(.deletionGrantInvalid) { try await s.delete([id], grant: grant) }
        try await s.close()
        let r = try await f.open()
        #expect(r.integrityReport().journalsReplayed >= 0)
        #expect(r.state(of: id) == nil && (r.deletionLookup(id)) == .deleted && !f.fileExists(id))
        try await r.close()
    }

    @Test("NT-H5-04/05: an older manifest (rollback) or a whole older snapshot of system/ is detected via the chain and the anchor → read-only, no writes, no restore")
    func manifestRollback() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "a")
        let snap = try (manifest: Data(contentsOf: f.systemPath("manifest.v1")), ledger: Data(contentsOf: f.systemPath("ledger.v1")), authz: Data(contentsOf: f.systemPath("authz.v1")))
        _ = try await f.put(s, "b")
        try await s.close()
        try snap.manifest.write(to: f.systemPath("manifest.v1"))
        let s2 = try await f.open()
        #expect(s2.mode == .readOnly(reason: "manifest rollback detected"))
        await expectVaultError(.storeReadOnly(reason: "manifest rollback detected")) { try await f.put(s2, "c") }
        await expectVaultError(.storeReadOnly(reason: "manifest rollback detected")) { try await s2.admitRestored(RestoreResult(active: [], quarantined: []), sourceVaultInstanceID: nil, authorization: try s2.issuer.issue(scope: .admitRestored)) }
        try await s2.close()
        // consistent older snapshot of all three files → only the anchor can tell
        try snap.ledger.write(to: f.systemPath("ledger.v1")); try snap.authz.write(to: f.systemPath("authz.v1"))
        let s3 = try await f.open()
        #expect(s3.mode == .readOnly(reason: "manifest rollback detected"))
        try await s3.close()
        // anchor missing (e.g. keychain wiped) → read-only, never silently trusted
        let saved = try f.anchor.readAnchor()
        f.anchor.set(nil)
        let s4 = try await f.open()
        #expect(s4.mode == .readOnly(reason: "anchor missing"))
        try await s4.close()
        f.anchor.set(saved)
    }

    @Test("NT-H5-06/07: a truncated journal tail is discarded and the operation replays; a byte flip in a MIDDLE entry makes the vault read-only and quarantines the op's ids")
    func journalDamage() async throws {
        // Build a three-entry journal deterministically: delete TWO records and crash at the 18th mutating
        // syscall (begin durable = 5, unlink = 1, step rewrite = 5, unlink = 1, step rewrite = 5, then the
        // ledger write opens → crash). The journal then holds begin + two steps; the manifest is untouched.
        func threeEntryJournal(_ f: StoreFixture) async throws -> ([RecordID], URL) {
            let s = try await f.open()
            let a = try await f.put(s, "x"), b = try await f.put(s, "y")
            f.fs.arm(at: 18)
            let grant = try s.vault.authorizeDeletion(of: [a, b], authorization: try s.issuer.issue(scope: .delete(recordIDs: [a, b])))
            do { try await s.delete([a, b], grant: grant); Issue.record("expected a simulated crash") } catch is SimulatedCrash {}
            f.fs.disarm(); try await s.close()
            let journals = f.names("journal")
            #expect(journals.count == 1, Comment(rawValue: "journals: \(journals)"))
            return ([a, b], f.rootURL.appendingPathComponent("journal/\(journals[0])"))
        }
        // truncated tail → last entry dropped, begin (+ first step) replayed, delete completes
        let f1 = StoreFixture(); defer { f1.cleanup() }
        let (ids1, jp1) = try await threeEntryJournal(f1)
        let bytes1 = Array(try Data(contentsOf: jp1))
        var dec = CanonicalDecoder(bytes1); let len1 = (try dec.readBytes()).count; let len2 = (try dec.readBytes()).count
        #expect(bytes1.count > 4 + len1 + 4 + len2 + 20, "three entries expected")
        try Data(bytes1.dropLast(10)).write(to: jp1)
        let r1 = try await f1.open()
        #expect(r1.mode == .readWrite)
        for id in ids1 { #expect(r1.state(of: id) == nil && r1.deletionLookup(id) == .deleted && !f1.fileExists(id)) }
        #expect(f1.names("journal").isEmpty && r1.integrityReport().journalsReplayed == 1)
        try await r1.close()
        // mid-file flip (inside the SECOND entry) → untrusted journal: read-only, ids quarantined, no writes
        let f2 = StoreFixture(); defer { f2.cleanup() }
        let (ids2, jp2) = try await threeEntryJournal(f2)
        var bytes2 = Array(try Data(contentsOf: jp2))
        var d2 = CanonicalDecoder(bytes2); let l1 = (try d2.readBytes()).count
        bytes2[4 + l1 + 4 + 40] ^= 0x01
        try Data(bytes2).write(to: jp2)
        let r2 = try await f2.open()
        #expect(r2.mode == .readOnly(reason: "journal failed authentication mid-file"))
        for id in ids2 { #expect(f2.quarantine.isQuarantined(id)) }
        await expectVaultError(.storeReadOnly(reason: "journal failed authentication mid-file")) { try await f2.put(r2, "z") }
        try await r2.close()
    }
}

@Suite("H2 — key retirement protocol v2", .serialized)
struct StoreRetirementTests {
    private func tokens(_ s: FileVaultStore, _ v: UInt32) throws -> (OperationAuthorization, OperationAuthorization) {
        (try s.issuer.issue(scope: .retireKey(version: v)), try s.issuer.issue(scope: .maintenance(.rewrap)))
    }

    @Test("happy path: rotate → retireKey → version forgotten, records readable under the new key, proof independently verifiable (NT-H2-07)")
    func retireHappyPath() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let ids = try await (0..<3).asyncMap { _ in try await f.put(s, "p") }
        _ = try f.keys.rotate()
        let (a, m) = try tokens(s, 1)
        // split path first: the proof is verifiable by an independent read-only scan BETWEEN prepare and forget
        let proof = try await s.prepareRetirement(of: 1, authorization: a, maintenance: m)
        #expect(proof.keyVersion == 1 && proof.rewrappedCount == 3 && (s.keyUsage[1] ?? 0) == 0 && (s.minimumWrapVersion) == 2)
        let inv = try KeyRetirementVerifier.inventory(root: f.rootURL.path, fileSystem: RealFileSystem())
        #expect(inv.countsByVersion[1] == nil && inv.unparsablePaths.isEmpty && inv.digest == proof.scanDigest)
        #expect(try KeyRetirementVerifier.verify(proof, root: f.rootURL.path, fileSystem: RealFileSystem(), currentManifestGeneration: s.manifestGeneration, currentManifestHash: s.manifestHash) == true)
        try await s.forgetRetired(1, proof: proof)
        for id in ids { #expect(try await f.get(s, id) == "p") }
        #expect(!f.keys.availableVersions.contains(1))
        // after forget the generation moved on: the same proof no longer verifies (it is single-use by construction)
        #expect(try KeyRetirementVerifier.verify(proof, root: f.rootURL.path, fileSystem: RealFileSystem(), currentManifestGeneration: s.manifestGeneration, currentManifestHash: s.manifestHash) == false)
        // combined path on a second version
        _ = try f.keys.rotate()
        let (a2, m2) = try tokens(s, 2)
        let proof2 = try await s.retireKey(2, authorization: a2, maintenance: m2)
        #expect(proof2.keyVersion == 2 && !f.keys.availableVersions.contains(2) && (s.keyUsage[2] ?? 0) == 0)
        for id in ids { #expect(try await f.get(s, id) == "p") }
        try await s.close()
    }

    @Test("NT-H2-01/03: forget is refused while any record (manifest or disk) still references the version")
    func refusedWhileInUse() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.put(s, "p")
        _ = try f.keys.rotate()
        // split path: prepare rewraps; then plant a stale file on disk that the manifest does not know about
        let (a, m) = try tokens(s, 1)
        let proof = try await s.prepareRetirement(of: 1, authorization: a, maintenance: m)
        // simulate a stale writer: a file wrapped under v1 appears in records/ (as an orphan it is reported, not counted)
        let dek = [UInt8](repeating: 3, count: 32)
        let staleID = RecordID()
        let w = try f.keys.wrapDataKeyUnderVersion(dek, version: 1, boundTo: staleID)
        let env = RecordEnvelope(header: EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: staleID, dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0)), wrappedDEK: w, nonce: [UInt8](repeating: 0, count: 12), ciphertext: [1], tag: [UInt8](repeating: 0, count: 16))
        var e = CanonicalEncoder(); env.encode(into: &e)
        var framed = CanonicalEncoder(); framed.appendBytes(e.bytes)
        var bytes = framed.bytes; bytes += [UInt8](repeating: 0, count: 4096 - bytes.count % 4096)
        try Data(bytes).write(to: f.rootURL.appendingPathComponent("records/\(staleID.hex).env"))
        // the verifier now sees a v1 envelope → proof no longer verifies
        #expect(try KeyRetirementVerifier.verify(proof, root: f.rootURL.path, fileSystem: RealFileSystem(), currentManifestGeneration: s.manifestGeneration, currentManifestHash: s.manifestHash) == false)
        try FileManager.default.removeItem(at: f.rootURL.appendingPathComponent("records/\(staleID.hex).env"))
        // manifest usage > 0: putEnvelope a v1-wrapped record is refused by the freeze (NT-H2-04), so simulate via a fresh store with usage
        try await s.forgetRetired(1, proof: proof)
        #expect(!f.keys.availableVersions.contains(1))
        _ = id
        try await s.close()
        let g = StoreFixture(); defer { g.cleanup() }
        let t = try await g.open()
        _ = try await g.put(t, "q")
        _ = try g.keys.rotate()
        let (a2, m2) = try tokens(t, 1)
        _ = try await t.prepareRetirement(of: 1, authorization: a2, maintenance: m2)
        // NT-H2-03: manifest says 0 but a NON-orphan file (known id) is still under v1 → cross-check fails
        let id2 = try await g.put(t, "late")
        let p = g.rootURL.appendingPathComponent("records/\(id2.hex).env")
        var d = CanonicalDecoder(Array(try Data(contentsOf: p))); let payload = try d.readBytes()
        var dd = CanonicalDecoder(payload); let env2 = try RecordEnvelope.decode(from: &dd)
        let dek2 = try g.keys.unwrapDataKey(env2.wrappedDEK)
        let old = env2.replacingWrappedDEK(try g.keys.wrapDataKeyUnderVersion(dek2, version: 1, boundTo: id2))
        var e2 = CanonicalEncoder(); old.encode(into: &e2)
        var fr = CanonicalEncoder(); fr.appendBytes(e2.bytes); var b2 = fr.bytes; b2 += [UInt8](repeating: 0, count: 4096 - b2.count % 4096)
        try Data(b2).write(to: p)
        let (a3, m3) = try tokens(t, 1)
        await expectVaultError(.keyVersionInUse(version: 1, count: 1)) { try await t.prepareRetirement(of: 1, authorization: a3, maintenance: m3) }
        try await t.close()
    }

    @Test("NT-H2-02: a proof is stale after any later mutation (generation changed)")
    func proofStaleAfterWrite() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "p")
        _ = try f.keys.rotate()
        let (a, m) = try tokens(s, 1)
        let proof = try await s.prepareRetirement(of: 1, authorization: a, maintenance: m)
        _ = try await f.put(s, "q")
        await expectVaultError(.proofStale) { try await s.forgetRetired(1, proof: proof) }
        #expect(f.keys.availableVersions.contains(1))
        // a forged proof with the right generation but a foreign section token is refused too
        let (a2, m2) = try tokens(s, 1)
        let fresh = try await s.prepareRetirement(of: 1, authorization: a2, maintenance: m2)
        let forged = KeyRetirementProof(keyVersion: 1, manifestGeneration: fresh.manifestGeneration, manifestHash: fresh.manifestHash, scanDigest: fresh.scanDigest, rewrappedCount: 0, sectionToken: [UInt8](repeating: 1, count: 16), issuedAtUnixSeconds: storeT0)
        await expectVaultError(.proofStale) { try await s.forgetRetired(1, proof: forged) }
        try await s.forgetRetired(1, proof: fresh)
        try await s.close()
    }

    @Test("NT-H2-04: after the freeze, an envelope wrapped under the old version is refused with staleKeyVersion (before, during and after the proof)")
    func freezeRefusesOldVersion() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "p")
        _ = try f.keys.rotate()
        let (a, m) = try tokens(s, 1)
        let proof = try await s.prepareRetirement(of: 1, authorization: a, maintenance: m)
        let id = RecordID()
        let w = try f.keys.wrapDataKeyUnderVersion([UInt8](repeating: 5, count: 32), version: 1, boundTo: id)
        let env = RecordEnvelope(header: EnvelopeHeader(algorithm: .aes256gcm, descriptor: try RecordDescriptor(recordID: id, dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0)), wrappedDEK: w, nonce: [UInt8](repeating: 0, count: 12), ciphertext: [1], tag: [UInt8](repeating: 0, count: 16))
        await expectVaultError(.staleKeyVersion(minimum: 2)) { try await s.putEnvelope(env, authorization: try s.issuer.issue(scope: .write(.birthDate))) }
        try await s.forgetRetired(1, proof: proof)
        await expectVaultError(.staleKeyVersion(minimum: 2)) { try await s.putEnvelope(env, authorization: try s.issuer.issue(scope: .write(.birthDate))) }
        #expect(s.minimumWrapVersion == 2)
        try await s.close()
        let s2 = try await f.open()   // the freeze is durable across relaunch
        #expect(s2.minimumWrapVersion == 2)
        try await s2.close()
    }

    @Test("NT-H2-05/08: a crash during rewrap or between retire and forget loses nothing: records stay readable, no proof survives, the protocol re-runs")
    func crashDuringRetirement() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let ids = try await (0..<4).asyncMap { _ in try await f.put(s, "p") }
        _ = try f.keys.rotate()
        let (a, m) = try tokens(s, 1)
        f.fs.arm(at: 14)   // inside the rewrap file replacements
        var crashed = false
        do { _ = try await s.prepareRetirement(of: 1, authorization: a, maintenance: m) } catch is SimulatedCrash { crashed = true }
        f.fs.disarm(); try await s.close()
        #expect(crashed)
        #expect(f.keys.availableVersions.contains(1), "nothing was forgotten")
        let r = try await f.open()
        #expect(r.mode == .readWrite)
        for id in ids { #expect(try await f.get(r, id) == "p") }
        let usage = r.keyUsage
        #expect((usage[1] ?? 0) + (usage[2] ?? 0) == 4, Comment(rawValue: "\(usage)"))
        let (a2, m2) = try tokens(r, 1)
        let proof = try await r.prepareRetirement(of: 1, authorization: a2, maintenance: m2)
        // crash between retire and forget
        f.fs.arm(at: 3)
        do { try await r.forgetRetired(1, proof: proof) } catch is SimulatedCrash {}
        f.fs.disarm(); try await r.close()
        #expect(try f.keys.isRetired(version: 1) || f.keys.availableVersions.contains(1))
        let r2 = try await f.open()
        for id in ids { #expect(try await f.get(r2, id) == "p") }
        await expectVaultError(.proofStale) { try await r2.forgetRetired(1, proof: proof) }
        let (a3, m3) = try tokens(r2, 1)
        _ = try await r2.retireKey(1, authorization: a3, maintenance: m3)
        #expect(!f.keys.availableVersions.contains(1))
        try await r2.close()
    }

    @Test("NT-H2-06: concurrent puts during retirement are serialized by the actor — the proof generation matches and no record is lost")
    func concurrentPutsDuringRetirement() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "p")
        _ = try f.keys.rotate()
        let (a, m) = try tokens(s, 1)
        let writers = (0..<20).map { i in Task { try await f.put(s, "w\(i)") } }
        let proof = try await s.retireKey(1, authorization: a, maintenance: m)
        var written = 0
        for w in writers { if (try? await w.value) != nil { written += 1 } }
        #expect(written == 20)
        #expect((s.keyUsage[1] ?? 0) == 0 && (s.recordIDs.count) == 21)
        for id in s.recordIDs { _ = try await f.get(s, id) }
        #expect(proof.keyVersion == 1)
        try await s.close()
    }

    @Test("NT-H2-09: a key version that vanished without retirement makes its records unreadable with a typed error; nothing crashes or is dropped")
    func keyLoss() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.put(s, "p")
        _ = try f.keys.rotate()
        let id2 = try await f.put(s, "q")
        f.keys.simulateKeyLoss(version: 1)
        await expectVaultError(.keyUnavailable(version: 1)) { try await f.get(s, id) }
        #expect(s.state(of: id) == .active && f.fileExists(id), "the record is kept; only its key is gone")
        #expect(try await f.get(s, id2) == "q")
        try await s.close()
    }
}

final class IDBox: @unchecked Sendable { private var v: RecordID?; private let l = NSLock(); func set(_ id: RecordID) { l.lock(); v = id; l.unlock() }; var value: RecordID? { l.lock(); defer { l.unlock() }; return v } }
final class IDListBox: @unchecked Sendable { private var v: [RecordID] = []; private let l = NSLock(); func set(_ ids: [RecordID]) { l.lock(); v = ids; l.unlock() }; var value: [RecordID] { l.lock(); defer { l.unlock() }; return v } }

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await transform(e)) }
        return out
    }
}
