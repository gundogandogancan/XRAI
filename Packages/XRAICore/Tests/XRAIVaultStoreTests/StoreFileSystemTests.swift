// P03-04H — FILESYSTEM ATOMICITY & DURABILITY SECURITY GATE (F-P04-01, F-P04-02, GATE 3 neighbours).
// Rows NT-FS-01…12 of the P03-04H addendum to the acceptance matrix. Real syscalls on real
// directories; the store-level rows use the test-only fault injector in its "failed syscall" mode.
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

final class Counter: @unchecked Sendable {
    private let l = NSLock(); private var v = 0; private var fds: [Int32] = []
    func add(fd: Int32) { l.lock(); v += 1; fds.append(fd); l.unlock() }
    var count: Int { l.lock(); defer { l.unlock() }; return v }
    var all: [Int32] { l.lock(); defer { l.unlock() }; return fds }
}

@Suite("P03-04H — exclusive creation, durable commit, cleanup ownership (real file system)", .serialized)
struct StoreFileSystemTests {
    let fs = RealFileSystem()

    private func freshDir() throws -> String {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("xrai-fs-" + RecordID().hex, isDirectory: true).path
        try fs.createDirectory(p)
        return p
    }
    private func cleanup(_ p: String) { try? FileManager.default.removeItem(atPath: p) }
    private func mode(_ fd: Int32) -> (type: mode_t, perm: mode_t, nlink: UInt16, size: Int64)? {
        var st = stat(); guard fstat(fd, &st) == 0 else { return nil }
        return (st.st_mode & S_IFMT, st.st_mode & 0o777, st.st_nlink, st.st_size)
    }

    @Test("NT-FS-01: a pre-existing regular file is refused untouched — no truncation, no replacement, same inode")
    func preExistingFileRefused() throws {
        let d = try freshDir(); defer { cleanup(d) }
        let p = d + "/existing"
        try Data("KEEP ME".utf8).write(to: URL(fileURLWithPath: p))
        var before = stat(); #expect(lstat(p, &before) == 0)
        #expect(throws: VaultError.storeIntegrityFailed(reason: "exclusive create refused: path exists")) { _ = try fs.openExclusive(p) }
        var after = stat(); #expect(lstat(p, &after) == 0)
        #expect(try Data(contentsOf: URL(fileURLWithPath: p)) == Data("KEEP ME".utf8), "content intact")
        #expect(before.st_ino == after.st_ino && before.st_size == after.st_size, "same inode, not truncated")
        #expect(try fs.kind(of: p) == .regular)
    }

    @Test("NT-FS-02: a symlink at the path (dangling or pointing at a real file) is refused; neither the link nor its target changes")
    func symlinkRefused() throws {
        let d = try freshDir(); defer { cleanup(d) }
        let target = d + "/target"
        try Data("TARGET".utf8).write(to: URL(fileURLWithPath: target))
        let link = d + "/link", dangling = d + "/dangling"
        #expect(symlink(target, link) == 0 && symlink(d + "/nowhere", dangling) == 0)
        for p in [link, dangling] {
            #expect(throws: VaultError.storeIntegrityFailed(reason: "exclusive create refused: path exists")) { _ = try fs.openExclusive(p) }
            #expect(try fs.kind(of: p) == .symlink, "the link itself is still there")
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: target)) == Data("TARGET".utf8), "target untouched")
        #expect(try fs.kind(of: d + "/nowhere") == .missing, "a dangling link never creates its target")
        // the same path through a symlinked DIRECTORY component is refused by the directory flush (O_NOFOLLOW) too
        let dirLink = d + "/dirlink"
        #expect(symlink(d, dirLink) == 0)
        do { try fs.syncDirectory(dirLink); Issue.record("a symlinked directory must not be flushed through") }
        catch VaultError.ioFailed(let op, let e) { #expect(op == "opendir" && (e == ENOTDIR || e == ELOOP), Comment(rawValue: "errno \(e)")) }   // XNU reports ENOTDIR for O_DIRECTORY|O_NOFOLLOW on a link
    }

    @Test("NT-FS-03: 16 concurrent writers on one path — exactly one creation succeeds, every other sees 'path exists'")
    func concurrentWriters() throws {
        let d = try freshDir(); defer { cleanup(d) }
        let p = d + "/race"
        let ok = Counter(), refused = Counter(), other = Counter()
        let fsys = fs
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            do { ok.add(fd: try fsys.openExclusive(p)) }
            catch VaultError.storeIntegrityFailed(let r) where r == "exclusive create refused: path exists" { refused.add(fd: -1) }
            catch { other.add(fd: -1) }
        }
        #expect(ok.count == 1 && refused.count == 15 && other.count == 0, Comment(rawValue: "ok \(ok.count) refused \(refused.count) other \(other.count)"))
        for fd in ok.all { try fs.close(fd) }
        #expect(try fs.kind(of: p) == .regular)
    }

    @Test("NT-FS-04: the created descriptor is a fresh regular file, one link, 0600, close-on-exec, empty; on a physical iPhone it carries NSFileProtectionComplete both inside a vault directory and in a plain directory")
    func createdFileAttributes() throws {
        let d = try freshDir(); defer { cleanup(d) }
        let p = d + "/fresh"
        let saved = umask(0o000); defer { _ = umask(saved) }   // the permissive umask must not loosen the file
        let fd = try fs.openExclusive(p)
        let m = try #require(mode(fd))
        #expect(m.type == S_IFREG && m.nlink == 1 && m.perm == 0o600 && m.size == 0)
        #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0)
        try fs.write(fd, [1, 2, 3]); try fs.sync(fd); try fs.close(fd)
        #if os(iOS) && !targetEnvironment(simulator)
        #expect(try fs.protectionClass(p) == FileProtectionType.complete.rawValue, "inherited from the vault directory, verified on the descriptor")
        // a directory WITHOUT the attribute: the descriptor path must set and verify the class itself
        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("xrai-plain-" + RecordID().hex, isDirectory: true).path
        try FileManager.default.createDirectory(atPath: plain, withIntermediateDirectories: true)
        defer { cleanup(plain) }
        let q = plain + "/set"
        let fd2 = try fs.openExclusive(q)
        try fs.write(fd2, [9]); try fs.close(fd2)
        #expect(try fs.protectionClass(q) == FileProtectionType.complete.rawValue, "class A set on the empty descriptor before any byte")
        #elseif targetEnvironment(simulator)
        // KNOWN_LIMITATION: the Simulator stores the attribute via fcntl but FileManager does not report a class; asserted on device only.
        #expect(try fs.protectionClass(p) == nil || fs.protectionClass(p) == FileProtectionType.complete.rawValue)
        #endif
    }

    @Test("NT-FS-05: cleanup removes only the inode this writer created — a file another writer put at the same name survives")
    func cleanupNeverDeletesAnotherWritersFile() throws {
        let d = try freshDir(); defer { cleanup(d) }
        let p = d + "/temp"
        let fd = try fs.openExclusive(p)
        // another writer replaces the name: unlink + create with other content
        #expect(unlink(p) == 0)
        try Data("OTHER".utf8).write(to: URL(fileURLWithPath: p))
        #expect(try fs.removeIfOwned(p, by: fd) == false)
        #expect(try Data(contentsOf: URL(fileURLWithPath: p)) == Data("OTHER".utf8), "the other writer's file is intact")
        try fs.close(fd)
        // the owned case removes exactly once
        let q = d + "/mine"
        let fd2 = try fs.openExclusive(q)
        #expect(try fs.removeIfOwned(q, by: fd2) == true && fs.kind(of: q) == .missing)
        #expect(try fs.removeIfOwned(q, by: fd2) == false)
        try fs.close(fd2)
        // a symlink planted at the name is never followed or removed as "ours"
        let r = d + "/sym"
        let fd3 = try fs.openExclusive(r)
        #expect(unlink(r) == 0 && symlink(d + "/elsewhere", r) == 0)
        #expect(try fs.removeIfOwned(r, by: fd3) == false && fs.kind(of: r) == .symlink)
        try fs.close(fd3)
    }

    @Test("NT-FS-06: every durability syscall failure surfaces as a typed ioFailed with the step and errno (no result is ignored)")
    func typedSyscallErrors() throws {
        let d = try freshDir(); defer { cleanup(d) }
        let file = d + "/regular"
        try Data([1]).write(to: URL(fileURLWithPath: file))
        #expect(throws: VaultError.ioFailed(operation: "fullfsync", errno: EBADF)) { try fs.sync(-1) }
        #expect(throws: VaultError.ioFailed(operation: "opendir", errno: ENOTDIR)) { try fs.syncDirectory(file) }
        #expect(throws: VaultError.ioFailed(operation: "opendir", errno: ENOENT)) { try fs.syncDirectory(d + "/missing") }
        #expect(throws: VaultError.ioFailed(operation: "rename", errno: ENOENT)) { try fs.rename(d + "/missing", d + "/x") }
        #expect(throws: VaultError.ioFailed(operation: "write", errno: EBADF)) { try fs.write(-1, [1]) }
        #expect(throws: VaultError.ioFailed(operation: "close", errno: EBADF)) { try fs.close(-1) }
        #expect(throws: VaultError.ioFailed(operation: "open", errno: ENOENT)) { _ = try fs.openExclusive(d + "/nodir/file") }
        do { try fs.remove(d); Issue.record("unlink of a directory must fail") }
        catch VaultError.ioFailed(let op, let e) { #expect(op == "unlink" && (e == EPERM || e == EISDIR)) }
        #expect(try fs.kind(of: d) == .directory)
        try fs.remove(d + "/never-existed")   // ENOENT is not an error for remove
    }

    @Test("NT-FS-07: platform fact — F_FULLFSYNC is accepted on file AND directory descriptors here (the fallback path is not what this host runs)")
    func fullFsyncSupported() throws {
        let d = try freshDir(); defer { cleanup(d) }
        let p = d + "/f"
        let fd = try fs.openExclusive(p)
        try fs.write(fd, [7]); try fs.sync(fd); try fs.close(fd)
        try fs.syncDirectory(d)
        let dfd = open(d, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        #expect(dfd >= 0)
        #expect(fcntl(dfd, F_FULLFSYNC) == 0, Comment(rawValue: "F_FULLFSYNC on a directory returned errno \(errno)"))
        _ = Darwin.close(dfd)
    }
}

@Suite("P03-04H — failed durability steps inside the store (fsync, dirsync, rename, unlink, journal commit)", .serialized)
struct StoreDurabilityFailureTests {
    /// Fails the k-th mutating syscall (returns EIO, not performed) for every k until the operation
    /// completes. After each failure: a typed error, no success reported, the instance fails closed,
    /// reopen recovers to all-or-nothing with no temp files.
    private func failAtEverySyscall(_ f: StoreFixture, setup: (FileVaultStore) async throws -> Void = { _ in }, op: (FileVaultStore) async throws -> Void, invariant: (FileVaultStore, Int, String) async throws -> Void) async throws -> [String] {
        var step = 1
        var failedOps: [String] = []
        while true {
            let s = try await f.open()
            #expect(s.mode == .readWrite)
            try await setup(s)
            f.fs.arm(at: step, .fail(errno: EIO))
            var failed: String? = nil
            do { try await op(s) }
            catch VaultError.ioFailed(let o, let e) { failed = o; #expect(e == EIO) }
            catch { Issue.record("step \(step): unexpected \(error)"); f.fs.disarm(); try await s.close(); throw error }
            f.fs.disarm()
            if let o = failed {
                failedOps.append(o)
                #expect(s.mode == .readOnly(reason: FileVaultStore.reopenRequiredReason), Comment(rawValue: "step \(step) (\(o)): \(s.mode)"))
                await expectVaultError(.storeReadOnly(reason: FileVaultStore.reopenRequiredReason)) { try await f.put(s, "after failure") }
                if let id = s.recordIDs.first { await expectVaultError(.storeReadOnly(reason: FileVaultStore.reopenRequiredReason)) { try await f.get(s, id) } }
            }
            try await s.close()
            let r = try await f.open()
            #expect(r.mode == .readWrite, Comment(rawValue: "step \(step): \(r.mode)"))
            #expect(f.names("records").allSatisfy { !$0.hasPrefix(".tmp-") } && f.names("system").allSatisfy { !$0.hasPrefix(".tmp-") } && f.names("journal").allSatisfy { !$0.hasPrefix(".tmp-") })
            try await invariant(r, step, failed ?? "none")
            try await r.close()
            if failed == nil { return failedOps }
            step += 1
            if step > 400 { Issue.record("operation never completed"); return failedOps }
        }
    }

    @Test("NT-FS-08a: put — a failed fsync/dirsync/rename/unlink at any step is reported, never masked; after reopen the record is absent or fully readable and the anchor agrees")
    func putFailEverywhere() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let ops = try await failAtEverySyscall(f, op: { s in _ = try await f.put(s, "payload") }, invariant: { r, _, _ in
            for id in r.recordIDs { #expect(try await f.get(r, id) == "payload"); #expect(f.fileExists(id)) }
            #expect(Set(f.names("records").map { String($0.dropLast(4)) }) == Set(r.recordIDs.map(\.hex)))
            let a = try #require(try f.anchor.readAnchor())
            #expect(a.manifestGeneration == r.manifestGeneration && a.manifestHash == r.manifestHash)
            #expect(f.names("journal").isEmpty)
        })
        #expect(Set(ops).isSuperset(of: ["open", "write", "fsync", "rename", "dirsync", "unlink"]), Comment(rawValue: "failed steps: \(ops)"))
    }

    @Test("NT-FS-08b: cascade delete — every failed step keeps all-or-nothing; once the begin entry is durable the delete completes at reopen; the ledger is complete whenever the source is gone")
    func deleteFailEverywhere() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let pair = IDListBox()
        var pairsUsed = 0
        let ops = try await failAtEverySyscall(f, setup: { s in
            // a delete whose begin entry became durable completes at reopen (NT-H3-03): start a new pair then
            if pair.value.isEmpty || s.state(of: pair.value[0]) == nil {
                let src = try await f.put(s, "src"); f.base.advance(1)
                let d1 = try await f.put(s, "d1", .derivedResult, derivedFrom: [src])
                pair.set([src, d1]); pairsUsed += 1
            }
        }, op: { s in
            try await f.delete(s, [pair.value[0]])
        }, invariant: { r, step, _ in
            let ids = pair.value
            let present = ids.map { r.state(of: $0) != nil }
            #expect(present.allSatisfy { $0 } || present.allSatisfy { !$0 }, Comment(rawValue: "step \(step): partial cascade \(present)"))
            if !present[0] { for id in ids { #expect(r.deletionLookup(id) == .deleted && !f.fileExists(id)) } }
            else { for id in ids { #expect(f.fileExists(id) && r.deletionLookup(id) == .notDeleted) } }
        })
        #expect(Set(ops).isSuperset(of: ["open", "write", "fsync", "rename", "dirsync", "unlink"]), Comment(rawValue: "failed steps: \(ops)"))
        #expect(pairsUsed >= 2, "the begin-durable replay path was exercised")
        let s = try await f.open()
        #expect(s.state(of: pair.value[0]) == nil && s.deletionCount == 2 * pairsUsed)
        try await s.close()
    }

    @Test("NT-FS-09: an authentic older ledger put back under a newer manifest (ledger-only rollback) opens read-only with restore and writes refused — never healed by the next mutation")
    func ledgerRollbackAlone() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let a = try await f.put(s, "A")
        try await s.close()
        let lp = f.systemPath("ledger.v1")
        let older = try Data(contentsOf: lp)
        let s2 = try await f.open()
        try await f.delete(s2, [a])
        #expect(s2.deletionLookup(a) == .deleted)
        try await s2.close()
        try older.write(to: lp)
        let s3 = try await f.open()
        #expect(s3.mode == .readOnly(reason: "deletion ledger does not bind to the manifest") && s3.deletionHistoryTrusted == false)
        await expectVaultError(.storeReadOnly(reason: "deletion ledger does not bind to the manifest")) { try await f.put(s3, "x") }
        await expectVaultError(.storeReadOnly(reason: "deletion ledger does not bind to the manifest")) {
            try await s3.admitRestored(RestoreResult(active: [], quarantined: []), authorization: try s3.issuer.issue(scope: .admitRestored))
        }
        try await s3.close()
        // the manifest still names the file as gone; nothing was resurrected on disk
        #expect(!f.fileExists(a))
    }

    @Test("NT-FS-10: admission refuses a batch with an envelope below the frozen key version BEFORE any file is written (all-or-nothing)")
    func admissionAllOrNothing() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let old = try s.vault.seal(plaintext: [1], descriptor: try f.descriptor(), authorization: try s.issuer.issue(scope: .write(.birthDate)))
        _ = try f.keys.rotate()
        _ = try await s.prepareRetirement(of: 1, authorization: try s.issuer.issue(scope: .retireKey(version: 1)), maintenance: try s.issuer.issue(scope: .maintenance(.rewrap)))
        #expect(s.minimumWrapVersion == 2)
        let fresh = try s.vault.seal(plaintext: [2], descriptor: try f.descriptor(), authorization: try s.issuer.issue(scope: .write(.birthDate)))
        let gen = s.manifestGeneration
        // P03-04bH: a caller-built result is refused before any check (restoreUnverified); a VERIFIED result can
        // never carry a stale key version because the facade re-wraps every DEK under the current key, so the
        // `staleKeyVersion` admission guard is defense in depth (unreachable by construction, like NT-H2-01).
        await expectVaultError(.restoreUnverified) {
            try await s.admitRestored(RestoreResult(active: [fresh, old], quarantined: []), authorization: try s.issuer.issue(scope: .admitRestored))
        }
        for env in [fresh, old] { #expect(s.state(of: env.header.recordID) == nil && !f.fileExists(env.header.recordID)) }
        #expect(s.mode == .readWrite && s.manifestGeneration == gen && f.names("journal").isEmpty && f.names("records").isEmpty)
        try await s.close()
    }

    @Test("NT-FS-11: an opener that cannot take the writer lock touches nothing — a live writer's temp file survives; after the lock is released it is cleaned")
    func lockBeforeCleanup() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let temp = f.rootURL.appendingPathComponent("records/.tmp-live-writer")
        try Data("in flight".utf8).write(to: temp)
        await expectVaultError(.storeLocked) { try await f.open() }
        #expect(FileManager.default.fileExists(atPath: temp.path), "locked-out opener removed a live writer's temp file")
        try await s.close()
        let r = try await f.open()
        #expect(!FileManager.default.fileExists(atPath: temp.path) && r.mode == .readWrite)
        try await r.close()
    }

    @Test("NT-FS-12: reads fail closed after close and after an interrupted mutation; a fresh open serves them again")
    func readsRefusedAfterCloseAndInterruption() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.put(s, "p")
        f.fs.arm(at: 7, .fail(errno: EIO))   // inside the second put's tail
        do { _ = try await f.put(s, "q"); Issue.record("expected ioFailed") } catch VaultError.ioFailed(_, let e) { #expect(e == EIO) }
        f.fs.disarm()
        await expectVaultError(.storeReadOnly(reason: FileVaultStore.reopenRequiredReason)) { try await f.get(s, id) }
        try await s.close()
        await expectVaultError(.storeReadOnly(reason: "closed")) { try await f.get(s, id) }
        let r = try await f.open()
        #expect(try await f.get(r, id) == "p")
        try await r.close()
    }
}
