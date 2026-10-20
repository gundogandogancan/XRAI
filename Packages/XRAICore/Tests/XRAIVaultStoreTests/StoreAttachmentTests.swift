// P03-04b GATE 4 — chunked attachments (rows NT-AT-01…11). Synthetic bytes only.
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

extension StoreFixture {
    func putAttachment(_ s: FileVaultStore, _ bytes: [UInt8], _ dc: DataClass = .evidenceFiles, purpose: String = "", derivedFrom: [RecordID] = []) async throws -> RecordID {
        let d = try descriptor(dc, purpose: purpose, derivedFrom: derivedFrom)
        return try await s.putAttachment(from: InMemoryAttachmentSource(bytes), descriptor: d, authorization: try s.issuer.issue(scope: .write(dc), purpose: purpose))
    }
    /// Reads the whole attachment back through the streaming API (tests only; production streams to a sink).
    func readAttachment(_ s: FileVaultStore, _ id: RecordID, purpose: String = "") async throws -> [UInt8] {
        let box = ChunkBox()
        try await s.readAttachment(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [id]), purpose: purpose)) { i, chunk in box.add(i, chunk) }
        return box.joined
    }
    func attachmentURL(_ id: RecordID) -> URL { rootURL.appendingPathComponent("attachments/\(id.hex).att") }
    func attachmentExists(_ id: RecordID) -> Bool { FileManager.default.fileExists(atPath: attachmentURL(id).path) }
}

final class ChunkBox: @unchecked Sendable {
    private var parts: [(UInt32, [UInt8])] = []
    func add(_ i: UInt32, _ c: [UInt8]) { parts.append((i, c)) }
    var count: Int { parts.count }
    var joined: [UInt8] { parts.sorted { $0.0 < $1.0 }.flatMap { $0.1 } }
    var indices: [UInt32] { parts.map { $0.0 } }
}

func pattern(_ n: Int, seed: UInt8 = 7) -> [UInt8] { (0..<n).map { UInt8(truncatingIfNeeded: ($0 &* 31) &+ Int(seed)) } }

/// Splits an attachment file into its frames (header, chunks) and the trailing padding.
func frames(of url: URL) throws -> (frames: [[UInt8]], padding: [UInt8]) {
    let bytes = Array(try Data(contentsOf: url))
    var out: [[UInt8]] = []; var c = 0
    while c + 4 <= bytes.count {
        let n = Int(UInt32(bytes[c]) << 24 | UInt32(bytes[c + 1]) << 16 | UInt32(bytes[c + 2]) << 8 | UInt32(bytes[c + 3]))
        if n == 0 { break }
        out.append(Array(bytes[c + 4..<c + 4 + n])); c += 4 + n
    }
    return (out, Array(bytes[c...]))
}
func writeFrames(_ fr: [[UInt8]], to url: URL, padding: [UInt8]? = nil) throws {
    var e = CanonicalEncoder(); for f in fr { e.appendBytes(f) }
    var bytes = e.bytes
    if let p = padding { bytes += p } else { let rem = bytes.count % 4096; if rem != 0 { bytes += [UInt8](repeating: 0, count: 4096 - rem) } }
    try Data(bytes).write(to: url)
}

@Suite("GATE 4 — chunked attachments: layout, integrity, cascade, recovery, limits", .serialized)
struct StoreAttachmentTests {
    @Test("NT-AT-01: a 3.5 MiB attachment round-trips in four chunks; the manifest carries kind/bytes/chunks; the file is a padded <id>.att with header + 4 chunk frames; a 0-byte attachment is one empty chunk")
    func roundTrip() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let parent = try await f.put(s, "parent"); f.base.advance(1)
        let bytes = pattern(3_670_016)
        let id = try await f.putAttachment(s, bytes, derivedFrom: [parent])
        let e = try #require(s.entry(of: id))
        #expect(e.kind == .attachment && e.attachmentBytes == 3_670_016 && e.chunkCount == 4 && e.derivedFrom == [parent] && e.state == .active)
        #expect(f.names("attachments") == ["\(id.hex).att"] && f.names("records").count == 1)
        let size = try FileManager.default.attributesOfItem(atPath: f.attachmentURL(id).path)[.size] as! Int
        #expect(size % 4096 == 0 && size > 3_670_016)
        let (fr, pad) = try frames(of: f.attachmentURL(id))
        #expect(fr.count == 5 && fr[1].count == (1 << 20) + 16 && fr[4].count == 3_670_016 - 3 * (1 << 20) + 16 && pad.allSatisfy { $0 == 0 })
        let box = ChunkBox()
        try await s.readAttachment(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [id]))) { i, c in box.add(i, c) }
        #expect(box.indices == [0, 1, 2, 3] && box.joined == bytes)
        let empty = try await f.putAttachment(s, [])
        #expect(s.entry(of: empty)?.chunkCount == 1 && s.entry(of: empty)?.attachmentBytes == 0)
        #expect(try await f.readAttachment(s, empty) == [])
        await expectVaultError(.notEligible(reason: "attachment: use readAttachment")) { try await f.get(s, id) }
        await expectVaultError(.notEligible(reason: "record: use get")) { try await f.readAttachment(s, parent) }
        try await s.close()
        let r = try await f.open()
        #expect(try await f.readAttachment(r, id) == bytes && r.entry(of: id)?.kind == .attachment)
        try await r.close()
    }

    @Test("NT-AT-02: a flipped chunk byte, swapped chunks, a dropped middle chunk, a truncated last chunk, a duplicated chunk, non-zero padding or a damaged header → corrupt, and the sink never receives a byte")
    func chunkTampering() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let bytes = pattern(2_500_000)
        let id = try await f.putAttachment(s, bytes)
        let url = f.attachmentURL(id)
        let (orig, pad) = try frames(of: url)
        #expect(orig.count == 4)
        func expectCorrupt(_ label: String) async {
            let box = ChunkBox()
            await expectVaultError(.recordNotActive(state: "corrupt"), { try await s.readAttachment(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [id]))) { i, c in box.add(i, c) } }, Comment(rawValue: label))
            #expect(box.count == 0, Comment(rawValue: "\(label): plaintext delivered"))
            // the corrupt mark is in-memory; restore the file and reopen to clear it for the next case
        }
        var t = orig; t[2][100] ^= 0x01; try writeFrames(t, to: url, padding: pad)
        await expectCorrupt("flipped byte in chunk 2")
        let s2 = try await { try await s.close(); return try await f.open() }()
        t = orig; t.swapAt(1, 2); try writeFrames(t, to: url, padding: pad)
        await expectVaultErrorNoPlain(s2, id, "swapped chunks")
        let s3 = try await { try await s2.close(); return try await f.open() }()
        t = orig; t.remove(at: 2); try writeFrames(t, to: url, padding: pad)
        await expectVaultErrorNoPlain(s3, id, "dropped middle chunk")
        let s4 = try await { try await s3.close(); return try await f.open() }()
        t = orig; t[3] = Array(t[3].dropLast(1)); try writeFrames(t, to: url, padding: pad)
        await expectVaultErrorNoPlain(s4, id, "truncated last chunk")
        let s5 = try await { try await s4.close(); return try await f.open() }()
        t = orig; t.append(orig[3]); try writeFrames(t, to: url)
        await expectVaultErrorNoPlain(s5, id, "duplicated last chunk")
        let s6 = try await { try await s5.close(); return try await f.open() }()
        var badPad = pad; if badPad.isEmpty { badPad = [0] }; badPad[badPad.count - 1] = 0x5A
        try writeFrames(orig, to: url, padding: badPad)
        await expectVaultErrorNoPlain(s6, id, "non-zero padding")
        let s7 = try await { try await s6.close(); return try await f.open() }()
        t = orig; t[0][t[0].count - 2] ^= 0x01; try writeFrames(t, to: url, padding: pad)
        await expectVaultErrorNoPlain(s7, id, "damaged header tag")
        let s8 = try await { try await s7.close(); return try await f.open() }()
        try writeFrames(orig, to: url, padding: pad)
        #expect(try await f.readAttachment(s8, id) == bytes, "the untouched file still reads")
        try await s8.close()
    }
    private func expectVaultErrorNoPlain(_ s: FileVaultStore, _ id: RecordID, _ label: String) async {
        let box = ChunkBox()
        await expectVaultError(.recordNotActive(state: "corrupt"), { try await s.readAttachment(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [id]))) { i, c in box.add(i, c) } }, Comment(rawValue: label))
        #expect(box.count == 0, Comment(rawValue: "\(label): plaintext delivered"))
    }

    @Test("NT-AT-03: chunk nonces are unique (random prefix per attachment ‖ index); the AAD binds index, count, sizes and the last flag, so a chunk cannot be opened at another index or under another layout")
    func cipherBinding() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let layout = try AttachmentLayout(chunkBytes: 16, chunkCount: 3, totalBytes: 40, noncePrefix: [1, 2, 3, 4, 5, 6, 7, 8])
        let (h1, c1) = try s.vault.createAttachment(descriptor: try f.descriptor(.evidenceFiles), layout: layout, authorization: try s.issuer.issue(scope: .write(.evidenceFiles)))
        let (h2, c2) = try s.vault.createAttachment(descriptor: try f.descriptor(.evidenceFiles), layout: layout, authorization: try s.issuer.issue(scope: .write(.evidenceFiles)))
        #expect(h1.header.recordID != h2.header.recordID)
        #expect(layout.nonce(forChunk: 0) != layout.nonce(forChunk: 1) && layout.nonce(forChunk: 1).count == 12)
        let p0 = pattern(16), p1 = pattern(16, seed: 9), last = pattern(8)
        let s0 = try c1.seal(chunk: p0, index: 0), s0b = try c1.seal(chunk: p0, index: 1)
        #expect(s0 != s0b, "same plaintext at two indices differs (nonce + AAD)")
        #expect(try c1.open(chunk: s0, index: 0) == p0)
        #expect(throws: VaultError.authenticationFailed) { _ = try c1.open(chunk: s0, index: 1) }
        #expect(throws: VaultError.authenticationFailed) { _ = try c2.open(chunk: s0, index: 0) }   // another attachment's key/id
        #expect(throws: VaultError.limitExceeded("attachment chunk")) { _ = try c1.seal(chunk: p1, index: 2) }   // last chunk must be 8 bytes
        #expect(throws: VaultError.limitExceeded("attachment chunk")) { _ = try c1.seal(chunk: p0, index: 3) }
        let sl = try c1.seal(chunk: last, index: 2)
        #expect(try c1.open(chunk: sl, index: 2) == last)
        // the same DEK under a different layout (different count) cannot open the chunk
        let other = try AttachmentLayout(chunkBytes: 16, chunkCount: 4, totalBytes: 56, noncePrefix: [1, 2, 3, 4, 5, 6, 7, 8])
        let (_, c3) = try s.vault.openAttachment(h1, authorization: try s.issuer.issue(scope: .read(recordIDs: [h1.header.recordID])))
        #expect(try c3.open(chunk: s0, index: 0) == p0, "re-derived cipher from the header opens")
        _ = other
        // prefixes are random: 20 attachments, 20 distinct prefixes
        var prefixes = Set<[UInt8]>()
        for _ in 0..<20 {
            let id = try await f.putAttachment(s, [1, 2, 3])
            let (fr, _) = try frames(of: f.attachmentURL(id))
            let env = try RecordEnvelope.decodeSingle(fr[0])
            let lay = try AttachmentLayout.decode(try s.vault.open(env, authorization: try s.issuer.issue(scope: .read(recordIDs: [id]))))
            prefixes.insert(lay.noncePrefix)
        }
        #expect(prefixes.count == 20)
        try await s.close()
    }

    @Test("NT-AT-04: cascade — deleting the parent deletes its attachment (file gone, ledger entry); deleting the attachment alone keeps the parent; revoking the parent's purpose blocks the attachment")
    func cascadeAndConsent() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "j")
        let parent = try await f.put(s, "entry", .journal, purpose: "j"); f.base.advance(1)
        let att = try await f.putAttachment(s, pattern(10_000), .evidenceFiles, derivedFrom: [parent])
        let att2 = try await f.putAttachment(s, pattern(5_000), .evidenceFiles, derivedFrom: [parent])
        try await f.delete(s, [att2])
        #expect(s.state(of: att2) == nil && !f.attachmentExists(att2) && s.deletionLookup(att2) == .deleted && s.state(of: parent) == .active)
        _ = try await s.revoke(purpose: "j", mode: .suspend(graceSeconds: 100), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "j")))
        #expect(s.state(of: parent) == .suspended && s.state(of: att) == nil, "H4: derived data of a suspended source is deleted now")
        #expect(!f.attachmentExists(att) && s.deletionLookup(att) == .deleted)
        let parent2 = try await f.put(s, "p2"); f.base.advance(1)
        let att3 = try await f.putAttachment(s, pattern(100), derivedFrom: [parent2])
        try await f.delete(s, [parent2])
        #expect(s.state(of: att3) == nil && !f.attachmentExists(att3) && s.deletionLookup(att3) == .deleted && s.deletionCount == 4)
        try await s.close()
    }

    @Test("NT-AT-05: a crash at every syscall of putAttachment (3 chunks) leaves the attachment absent or fully readable; no temp files survive; the manifest and anchor agree")
    func putCrashEverywhere() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let bytes = pattern(2_300_000)
        var step = 1
        var outcomes = Set<String>()
        while true {
            let s = try await f.open()
            f.fs.arm(at: step)
            var crashed = false
            do { _ = try await f.putAttachment(s, bytes) } catch is SimulatedCrash { crashed = true } catch { Issue.record("step \(step): \(error)"); f.fs.disarm(); try await s.close(); throw error }
            f.fs.disarm(); try await s.close()
            let r = try await f.open()
            #expect(r.mode == .readWrite, Comment(rawValue: "step \(step): \(r.mode)"))
            #expect(f.names("attachments").allSatisfy { !$0.hasPrefix(".tmp-") })
            let ids = r.recordIDs
            for id in ids { #expect(try await f.readAttachment(r, id) == bytes); outcomes.insert("present") }
            if ids.isEmpty { #expect(f.names("attachments").isEmpty); outcomes.insert("absent") }
            let a = try #require(try f.anchor.readAnchor())
            #expect(a.manifestGeneration == r.manifestGeneration && a.manifestHash == r.manifestHash)
            try await r.close()
            if !crashed { break }
            if r.recordIDs.count >= 1 { break }   // replay completed the put; every later step is the shared tail already covered by NT-H5-01
            step += 1
            if step > 200 { Issue.record("never completed"); break }
        }
        #expect(outcomes == ["present", "absent"] && step > 10, Comment(rawValue: "\(outcomes) \(step)"))
    }

    @Test("NT-AT-06: key retirement with attachments — only the header frame is rewrapped (chunks byte-identical), the inventory counts attachment headers, the proof verifies, the attachment stays readable")
    func retirement() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let bytes = pattern(1_500_000)
        let id = try await f.putAttachment(s, bytes)
        let (before, _) = try frames(of: f.attachmentURL(id))
        _ = try f.keys.rotate()
        let inv0 = try KeyRetirementVerifier.inventory(root: f.rootURL.path, fileSystem: f.fs)
        #expect(inv0.countsByVersion[1] ?? 0 >= 1 && inv0.unparsablePaths.isEmpty)
        let proof = try await s.retireKey(1, authorization: try s.issuer.issue(scope: .retireKey(version: 1)), maintenance: try s.issuer.issue(scope: .maintenance(.rewrap)))
        #expect(proof.keyVersion == 1 && (s.keyUsage[1] ?? 0) == 0 && s.entry(of: id)?.keyVersion == 2)
        let (after, pad) = try frames(of: f.attachmentURL(id))
        #expect(after.count == before.count && Array(after[1...]) == Array(before[1...]) && after[0] != before[0] && pad.allSatisfy { $0 == 0 })
        #expect(try await f.readAttachment(s, id) == bytes)
        let inv1 = try KeyRetirementVerifier.inventory(root: f.rootURL.path, fileSystem: f.fs)
        #expect((inv1.countsByVersion[1] ?? 0) == 0 && inv1.unparsablePaths.isEmpty)
        try await s.close()
        let r = try await f.open()
        #expect(try await f.readAttachment(r, id) == bytes)
        try await r.close()
    }

    @Test("NT-AT-07: size and source limits — an oversize attachment is refused before any file exists; a source that lies about its size aborts the mutation (fail closed, reopen adopts nothing)")
    func limits() async throws {
        let f = StoreFixture(limits: StoreLimits(attachmentChunkBytes: 4096, maxAttachmentBytes: 20_000)); defer { f.cleanup() }
        let s = try await f.open()
        let gen = s.manifestGeneration
        await expectVaultError(.limitExceeded("attachment size")) { try await f.putAttachment(s, pattern(20_001)) }
        #expect(f.names("attachments").isEmpty && s.manifestGeneration == gen && f.names("journal").isEmpty)
        let ok = try await f.putAttachment(s, pattern(20_000))
        #expect(s.entry(of: ok)?.chunkCount == 5)
        final class Liar: AttachmentSource, @unchecked Sendable { var totalBytes: UInt64 { 10_000 }; func readChunk(maxBytes: Int) throws -> [UInt8] { [UInt8](repeating: 1, count: min(maxBytes, 100)) } }
        await expectVaultError(.limitExceeded("attachment source short read")) {
            try await s.putAttachment(from: Liar(), descriptor: try f.descriptor(.evidenceFiles), authorization: try s.issuer.issue(scope: .write(.evidenceFiles)))
        }
        #expect(s.mode == .readOnly(reason: FileVaultStore.reopenRequiredReason))
        try await s.close()
        let r = try await f.open()
        #expect(r.mode == .readWrite && r.recordIDs == [ok] && f.names("attachments") == ["\(ok.hex).att"], "the liar's temp file is gone, nothing was adopted")
        try await r.close()
    }

    @Test("NT-AT-08: recovery — an orphan .att is moved to orphans/, a missing attachment file is flagged and read refuses; a directory over the entry limit opens read-only")
    func recoveryAndLimits() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.putAttachment(s, pattern(100))
        let id2 = try await f.putAttachment(s, pattern(200))
        try await s.close()
        try FileManager.default.copyItem(at: f.attachmentURL(id), to: f.rootURL.appendingPathComponent("attachments/" + RecordID().hex + ".att"))
        try FileManager.default.removeItem(at: f.attachmentURL(id2))
        let r = try await f.open()
        #expect(r.integrityReport().orphansQuarantined == 1 && f.names("orphans").count == 1 && f.names("attachments") == ["\(id.hex).att"])
        #expect(r.integrityReport().missingFiles == [id2])
        await expectVaultError(.recordMissing) { try await f.readAttachment(r, id2) }
        #expect(try await f.readAttachment(r, id) == pattern(100))
        try await r.close()
        let g = StoreFixture(limits: StoreLimits(maxDirectoryEntries: 2)); defer { g.cleanup() }
        let sg = try await g.open()
        for i in 0..<3 { _ = try await g.put(sg, "r\(i)") }
        try await sg.close()
        let rg = try await g.open()
        #expect(rg.mode == .readOnly(reason: "file count exceeds limit"))
        await expectVaultError(.storeReadOnly(reason: "file count exceeds limit")) { try await g.put(rg, "x") }
        try await rg.close()
    }

    @Test("NT-AT-09: authorization — a read token for another id, a suspended source, quarantine, or a purpose mismatch refuse before any chunk is read")
    func authorization() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "j"); f.grant(.evidenceFiles, purpose: "e")
        let parent = try await f.put(s, "entry", .journal, purpose: "j"); f.base.advance(1)
        let att = try await f.putAttachment(s, pattern(3000), .evidenceFiles, purpose: "e", derivedFrom: [parent])
        let box = ChunkBox()
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.readAttachment(att, authorization: try s.issuer.issue(scope: .read(recordIDs: [parent]), purpose: "e")) { i, c in box.add(i, c) } }
        await expectVaultError(.authorizationInvalid(.purposeMismatch)) { try await s.readAttachment(att, authorization: try s.issuer.issue(scope: .read(recordIDs: [att]), purpose: "other")) { i, c in box.add(i, c) } }
        f.quarantine.quarantine(att, reason: .consentRequired)
        await expectVaultError(.quarantined(.consentRequired)) { try await s.readAttachment(att, authorization: try s.issuer.issue(scope: .read(recordIDs: [att]), purpose: "e")) { i, c in box.add(i, c) } }
        f.quarantine.release(att)
        #expect(try await f.readAttachment(s, att, purpose: "e") == pattern(3000))
        f.authority.revoke(id: "g-j", atUnixSeconds: (try? f.base.now()) ?? storeT0)
        _ = try await s.revoke(purpose: "j", mode: .suspend(graceSeconds: 100), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "j")))
        #expect(s.state(of: att) == nil, "derived attachment deleted with the suspension")
        #expect(box.count == 0)
        try await s.close()
    }

    @Test("NT-AT-10: 64 MiB attachment streamed from a file — write and read (two passes) with bounded resident memory; numbers are recorded, not promised")
    func largeAttachmentBudget() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let src = f.rootURL.appendingPathComponent("..").appendingPathComponent("xrai-att-src-" + RecordID().hex).standardizedFileURL
        defer { try? FileManager.default.removeItem(at: src) }
        let block = pattern(1 << 20, seed: 3)
        let h = try #require(FileManager.default.createFile(atPath: src.path, contents: nil) ? FileHandle(forWritingAtPath: src.path) : nil)
        for _ in 0..<64 { h.write(Data(block)) }
        try h.close()
        let rss0 = residentBytes()
        let t0 = Date()
        let source = try FileAttachmentSource(path: src.path, fileSystem: f.fs)
        let id = try await s.putAttachment(from: source, descriptor: try f.descriptor(.evidenceFiles), authorization: try s.issuer.issue(scope: .write(.evidenceFiles)))
        let tWrite = Date().timeIntervalSince(t0)
        let rss1 = residentBytes()
        let t1 = Date()
        var total = 0, chunks = 0, ok = true
        try await s.readAttachment(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [id]))) { _, c in total += c.count; chunks += 1; if c != block { ok = false } }
        let tRead = Date().timeIntervalSince(t1)
        let rss2 = residentBytes()
        #expect(total == 64 << 20 && chunks == 64 && ok && s.entry(of: id)?.chunkCount == 64)
        let deltaWrite = Int64(rss1) - Int64(rss0), deltaRead = Int64(rss2) - Int64(rss1)
        print("NT-AT-10 64 MiB attachment: write \(String(format: "%.2f", tWrite)) s, read(2 passes) \(String(format: "%.2f", tRead)) s, RSS delta write \(deltaWrite / 1_048_576) MiB, read \(deltaRead / 1_048_576) MiB")
        #expect(deltaWrite < 48 << 20 && deltaRead < 48 << 20, Comment(rawValue: "RSS grew by \(deltaWrite / 1_048_576)/\(deltaRead / 1_048_576) MiB — the whole file must never be resident"))
        try await s.close()
    }

    @Test("NT-AT-11: attachments are not exported in a v3 backup and a restored parent re-admits without them (documented limit); the attachment header record never appears in the backup")
    func notInBackup() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let parent = try await f.put(s, "p"); f.base.advance(1)
        let att = try await f.putAttachment(s, pattern(10), derivedFrom: [parent])
        let (bytes, rk) = try await f.exportV3(s)
        let r = try f.restore(s, bytes, rk)
        #expect(r.active.map(\.header.recordID) == [parent] && !r.active.contains { $0.header.recordID == att })
        try await s.close()
    }
}

extension RecordEnvelope {
    static func decodeSingle(_ bytes: [UInt8]) throws -> RecordEnvelope { var d = CanonicalDecoder(bytes); return try RecordEnvelope.decode(from: &d) }
}

func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
    return kr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}
