import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

let storeT0: Int64 = 1_760_000_000

/// Thrown by the fault-injecting file system to simulate a crash at an exact syscall.
struct SimulatedCrash: Error, Equatable { let step: Int; let op: String }

/// What the armed syscall does: `.crash` throws `SimulatedCrash` (process death model); `.fail` makes the
/// syscall return an error (`VaultError.ioFailed`) WITHOUT performing it — the process goes on (P03-04H).
enum Injection: Equatable { case crash, fail(errno: Int32) }

/// TEST ONLY: wraps the real file system and crashes/fails the k-th mutating syscall after arming.
/// Lives in the test target; the production module has no fault seams (checked by a source scan).
final class FaultingFileSystem: VaultFileSystem, @unchecked Sendable {
    private let real = RealFileSystem()
    private let lock = NSLock()
    private var armedAt: Int? = nil
    private var injection: Injection = .crash
    private var count = 0
    private(set) var log: [String] = []

    func arm(at step: Int, _ injection: Injection = .crash) { lock.lock(); armedAt = step; self.injection = injection; count = 0; log = []; lock.unlock() }
    func disarm() { lock.lock(); armedAt = nil; lock.unlock() }
    var mutatingCalls: Int { lock.lock(); defer { lock.unlock() }; return count }

    private func tick(_ op: String) throws {
        lock.lock(); defer { lock.unlock() }
        count += 1
        log.append(op)
        if let a = armedAt, count == a {
            switch injection {
            case .crash: throw SimulatedCrash(step: a, op: op)
            case .fail(let e): throw VaultError.ioFailed(operation: op, errno: e)
            }
        }
    }

    func kind(of path: String) throws -> FileKind { try real.kind(of: path) }
    func createDirectory(_ path: String) throws { try real.createDirectory(path) }
    func listNames(_ dir: String) throws -> [String] { try real.listNames(dir) }
    func readRegular(_ path: String, maxBytes: Int) throws -> [UInt8] { try real.readRegular(path, maxBytes: maxBytes) }
    func openRegularForRead(_ path: String) throws -> (fd: Int32, size: Int64) { try real.openRegularForRead(path) }
    func read(_ fd: Int32, maxBytes: Int) throws -> [UInt8] { try real.read(fd, maxBytes: maxBytes) }
    func entryCount(_ dir: String) throws -> Int { try real.entryCount(dir) }
    func rewind(_ fd: Int32) throws { try real.rewind(fd) }
    func openExclusive(_ path: String) throws -> Int32 { try tick("open"); return try real.openExclusive(path) }
    func write(_ fd: Int32, _ bytes: [UInt8]) throws { try tick("write"); try real.write(fd, bytes) }
    func sync(_ fd: Int32) throws { try tick("fsync"); try real.sync(fd) }
    func close(_ fd: Int32) throws { try real.close(fd) }
    func rename(_ from: String, _ to: String) throws { try tick("rename"); try real.rename(from, to) }
    func syncDirectory(_ path: String) throws { try tick("dirsync"); try real.syncDirectory(path) }
    func remove(_ path: String) throws { try tick("unlink"); try real.remove(path) }
    func removeIfOwned(_ path: String, by fd: Int32) throws -> Bool { try real.removeIfOwned(path, by: fd) }   // cleanup only; not counted
    func excludeFromBackup(_ path: String) throws { try real.excludeFromBackup(path) }
    func protectionClass(_ path: String) throws -> String? { try real.protectionClass(path) }
    func processExists(_ pid: Int32) -> Bool { real.processExists(pid) }
    var currentPID: Int32 { real.currentPID }
}

/// One wired store over a temp directory with in-memory keys/consent/anchor and a manual base clock.
final class StoreFixture: @unchecked Sendable {
    let rootURL: URL
    let keys: InMemoryKeyProvider
    let authority: InMemoryConsentAuthority
    let quarantine: InMemoryQuarantineRegistry
    let anchor: InMemoryAnchorStore
    let base: ManualClock
    let fs: FaultingFileSystem
    var limits: StoreLimits

    init(limits: StoreLimits = StoreLimits(), keys: InMemoryKeyProvider? = nil) {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("xrai-store-" + RecordID().hex, isDirectory: true)
        self.keys = keys ?? InMemoryKeyProvider(keyID: "device")
        authority = InMemoryConsentAuthority()
        quarantine = InMemoryQuarantineRegistry()
        anchor = InMemoryAnchorStore()
        base = ManualClock(storeT0)
        fs = FaultingFileSystem()
        self.limits = limits
    }

    var composition: VaultComposition { VaultComposition(consentAuthority: authority, quarantine: quarantine, baseClock: base) }

    func open(reinstall: ReinstallPolicy = .refuse) async throws -> FileVaultStore {
        try await FileVaultStore.open(root: rootURL, keyProvider: keys, anchor: anchor, composition: composition, limits: limits, fileSystem: fs, reinstall: reinstall)
    }

    func cleanup() { try? FileManager.default.removeItem(at: rootURL) }

    func grant(_ dc: DataClass, purpose: String, id: String = "r-" + RecordID().hex) {
        authority.register(ConsentReceipt(id: id, scopes: [ConsentScope(dataClass: dc, purpose: purpose, destination: .deviceVault)], grantedAtUnixSeconds: (try? base.now()) ?? storeT0))
    }
    func revokeGrants(purpose: String) {
        // The in-memory authority revokes by receipt id; tests register with purpose-named ids.
        authority.revoke(id: "g-" + purpose, atUnixSeconds: (try? base.now()) ?? storeT0)
    }

    func descriptor(_ dc: DataClass = .birthDate, purpose: String = "", derivedFrom: [RecordID] = [], retention: RetentionClass = .untilUserDeletes, at: Int64? = nil) throws -> RecordDescriptor {
        try RecordDescriptor(dataClass: dc, retention: retention, consentPurpose: purpose, createdAtUnixSeconds: at ?? (try base.now()), derivedFrom: derivedFrom)
    }

    @discardableResult
    func put(_ store: FileVaultStore, _ text: String, _ dc: DataClass = .birthDate, purpose: String = "", derivedFrom: [RecordID] = []) async throws -> RecordID {
        let d = try descriptor(dc, purpose: purpose, derivedFrom: derivedFrom)
        return try await store.put(plaintext: Array(text.utf8), descriptor: d, authorization: try store.issuer.issue(scope: .write(dc), purpose: purpose))
    }

    func get(_ store: FileVaultStore, _ id: RecordID, purpose: String = "") async throws -> String {
        String(decoding: try await store.get(id, authorization: try store.issuer.issue(scope: .read(recordIDs: [id]), purpose: purpose)), as: UTF8.self)
    }

    func delete(_ store: FileVaultStore, _ ids: Set<RecordID>) async throws {
        let grant = try store.vault.authorizeDeletion(of: ids, authorization: try store.issuer.issue(scope: .delete(recordIDs: ids)))
        try await store.delete(ids, grant: grant)
    }

    func fileExists(_ id: RecordID) -> Bool { FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("records/\(id.hex).env").path) }
    func systemPath(_ name: String) -> URL { rootURL.appendingPathComponent("system/\(name)") }
    func names(_ sub: String) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: rootURL.appendingPathComponent(sub).path)) ?? []).sorted() }
}

func expectVaultError<T>(_ expected: VaultError, _ body: () async throws -> T, _ comment: Comment? = nil) async {
    do { _ = try await body(); Issue.record("expected \(expected), no error thrown \(comment?.rawValue ?? "")") }
    catch let e as VaultError { #expect(e == expected, comment ?? Comment(rawValue: "got \(e)")) }
    catch { Issue.record("unexpected error \(error)") }
}
