// FileVaultStore — the first persistent vault (P03-04, ADR-BOOT-009 + Amendment H).
//
// Single writer: a Swift actor; every mutation runs to completion inside one isolated, synchronous
// method body (no `await` inside), so no suspension point can invalidate a verified state (GATE A).
// Every mutation is journaled before its first side effect and finished by the same durable tail:
// [ledger] → manifest(generation+1, prevHash) → journal "manifestWritten" → authz state → Keychain
// anchor → journal "commit" → journal removed. Recovery at open replays or reconciles any
// uncommitted journal, verifies the manifest/authz/ledger/anchor bindings and fails closed to a
// read-only mode on any mismatch (GATE B, H5).
//
// Crypto: only through `SecureVault` (records via the authorized user path; the store's own
// metadata via the `storeMetadata` system path). No second decryption route exists (GATE C).
// No personal data is written by the app: the app does not link this module yet (P03-05).
import Foundation
import XRAIVaultContracts
import XRAIVaultCryptoKit

/// Ports the composition root provides. The store builds the issuer and the guarded clock itself
/// so that the persisted epoch and clock mark are applied before any token can be issued.
public struct VaultComposition: Sendable {
    public let consentAuthority: any ConsentAuthority
    public let quarantine: any QuarantineAuthority
    public let baseClock: any VaultClock
    public let toleranceSeconds: Int64
    public init(consentAuthority: any ConsentAuthority, quarantine: any QuarantineAuthority, baseClock: any VaultClock, toleranceSeconds: Int64 = 300) {
        self.consentAuthority = consentAuthority; self.quarantine = quarantine; self.baseClock = baseClock; self.toleranceSeconds = toleranceSeconds
    }
}

public struct StoreLimits: Sendable {
    public var ledgerCompactionThreshold: Int
    public var ledgerRecentKept: Int
    public var ledgerDigestCapacity: Int
    public var maxRecordBytes: Int
    /// P03-04b GATE 4: attachment chunk size (plaintext bytes per AEAD chunk) and the per-attachment cap.
    public var attachmentChunkBytes: Int
    public var maxAttachmentBytes: Int
    /// P03-04b GATE 5: recovery refuses (read-only) a directory with more entries than this.
    public var maxDirectoryEntries: Int
    public init(ledgerCompactionThreshold: Int = 200_000, ledgerRecentKept: Int = 100_000, ledgerDigestCapacity: Int = 1_000_000, maxRecordBytes: Int = BackupLimits.maxRecordCiphertextBytes, attachmentChunkBytes: Int = 1 << 20, maxAttachmentBytes: Int = 64 << 20, maxDirectoryEntries: Int = 500_000) {
        self.ledgerCompactionThreshold = ledgerCompactionThreshold; self.ledgerRecentKept = ledgerRecentKept
        self.ledgerDigestCapacity = ledgerDigestCapacity; self.maxRecordBytes = maxRecordBytes
        self.attachmentChunkBytes = attachmentChunkBytes; self.maxAttachmentBytes = maxAttachmentBytes; self.maxDirectoryEntries = maxDirectoryEntries
    }
}

/// P03-04b: where attachment plaintext comes from. Read chunk by chunk so the store never holds the
/// whole attachment in memory. Implementations must return exactly `maxBytes` until the final chunk.
public protocol AttachmentSource: AnyObject, Sendable {
    var totalBytes: UInt64 { get }
    func readChunk(maxBytes: Int) throws -> [UInt8]
}

/// In-memory source (small attachments, tests).
public final class InMemoryAttachmentSource: AttachmentSource, @unchecked Sendable {
    private var bytes: [UInt8]
    private var offset = 0
    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public var totalBytes: UInt64 { UInt64(bytes.count) }
    public func readChunk(maxBytes: Int) throws -> [UInt8] {
        let n = min(maxBytes, bytes.count - offset)
        defer { offset += n }
        return Array(bytes[offset..<offset + n])
    }
}

/// Streams a regular file through the store's file-system port (no symlinks, bounded reads).
public final class FileAttachmentSource: AttachmentSource, @unchecked Sendable {
    private let fs: any VaultFileSystem
    private let fd: Int32
    public let totalBytes: UInt64
    public init(path: String, fileSystem: any VaultFileSystem = RealFileSystem()) throws {
        fs = fileSystem
        let (fd, size) = try fileSystem.openRegularForRead(path)
        self.fd = fd; totalBytes = UInt64(size)
    }
    deinit { try? fs.close(fd) }
    public func readChunk(maxBytes: Int) throws -> [UInt8] { try fs.read(fd, maxBytes: maxBytes) }
}

/// What to do when the Keychain anchor exists but the directory holds no manifest (app reinstall,
/// REINSTALL_KEY_POLICY). Default: refuse. Never silently reuse the old state.
public enum ReinstallPolicy: Sendable {
    case refuse
    /// Explicit, user-confirmed fresh start: the stale anchor is cleared and a new vault is created.
    case recreateAfterConfirmation(acknowledgesPreviousDataUnrecoverable: Bool)
}

public enum StoreMode: Sendable, Equatable, Hashable {
    case readWrite
    case readOnly(reason: String)
}

public enum RevokeMode: Sendable, Equatable {
    /// H4: "Geri çek ve hemen sil" — immediate cascade delete.
    case deleteNow
    /// H4: "Geri çek, askıda tut" — suspended for `graceSeconds`, then deleted; only for grace-eligible classes.
    case suspend(graceSeconds: Int64)
}

/// P03-04b GATE 3: phase-1 outcome of a restore. Nothing is active after admission; every staged
/// record is quarantined with the risks the user must acknowledge in `activateRestored`.
public struct AdmissionReport: Sendable, Hashable {
    public let staged: [RecordID]
    public let risks: [RecordID: Set<RestoreRisk>]
    public let skippedDeleted: [RecordID]
    public let skippedExisting: [RecordID]
    /// The backup's deletion history was merged into this vault's ledger.
    public let historyMerged: Bool
}

public struct StoreIntegrityReport: Sendable, Equatable {
    public let mode: StoreMode
    public let epoch: UInt64
    public let manifestGeneration: UInt64
    public let deletionHistoryTrusted: Bool
    public let missingFiles: [RecordID]
    public let orphansQuarantined: Int
    public let journalsReplayed: Int
    public let journalsReconciled: Int
    public let needsRecovery: [RecordID]
    public let pendingRetirementVersion: UInt32?
}

public actor FileVaultStore {
    // MARK: Immutable wiring (safe to read from anywhere)
    public nonisolated let root: String
    public nonisolated let vault: SecureVault
    public nonisolated let issuer: AuthorizationIssuer
    public nonisolated let clock: MonotonicGuardClock
    public nonisolated let epoch: UInt64
    public nonisolated let limits: StoreLimits
    private nonisolated let fs: any VaultFileSystem
    private nonisolated let keyProvider: any RetirableKeyProvider
    private nonisolated let anchorStore: any VaultAnchorStore
    private nonisolated let composition: VaultComposition

    // MARK: Isolated state
    private var manifest: Manifest
    private var ledger: DeletionLedger
    private var authz: AuthzState
    private var modeValue: StoreMode
    private var ledgerTrusted: Bool
    private var missingFiles: Set<String> = []
    private var corruptFiles: Set<String> = []
    private var needsRecoveryIDs: Set<String> = []
    private var consumedGrants: Set<DeletionGrant> = []
    private var section: (token: [UInt8], version: UInt32)?
    private var pendingRetirement: UInt32?
    private var journalsReplayed = 0
    private var journalsReconciled = 0
    private var orphansMoved = 0
    private var pendingJournals: [(name: String, entries: [JournalEntry], truncated: Bool, bytes: [UInt8])]
    private var closed = false

    // MARK: Open

    /// Opens (or creates) the vault at `root`, runs recovery, applies the persisted epoch and clock
    /// mark, and takes the single-writer lock. Fails closed; see `StoreMode` for read-only reasons.
    public static func open(root: URL, keyProvider: any RetirableKeyProvider, anchor: any VaultAnchorStore, composition: VaultComposition, limits: StoreLimits = StoreLimits(), fileSystem: any VaultFileSystem = RealFileSystem(), reinstall: ReinstallPolicy = .refuse) async throws -> FileVaultStore {
        let loaded = try Loader.load(root: root.path, keyProvider: keyProvider, anchor: anchor, composition: composition, limits: limits, fs: fileSystem, reinstall: reinstall)
        let store = FileVaultStore(loaded: loaded, keyProvider: keyProvider, anchor: anchor, composition: composition, limits: limits, fs: fileSystem)
        try await store.recover()
        return store
    }

    private init(loaded l: Loader.Loaded, keyProvider: any RetirableKeyProvider, anchor: any VaultAnchorStore, composition: VaultComposition, limits: StoreLimits, fs: any VaultFileSystem) {
        root = l.root; vault = l.vault; issuer = l.issuer; clock = l.clock; epoch = l.epoch; self.limits = limits
        self.fs = fs; self.keyProvider = keyProvider; anchorStore = anchor; self.composition = composition
        manifest = l.manifest; ledger = l.ledger; authz = l.authz; modeValue = l.mode; ledgerTrusted = l.ledgerTrusted
        pendingJournals = l.journals
        needsRecoveryIDs = Set(l.untrustedIDs.map { $0.hex })
    }

    // MARK: Paths

    private nonisolated func path(_ parts: String...) -> String { parts.reduce(root) { ($0 as NSString).appendingPathComponent($1) } }
    private nonisolated func recordPath(_ id: RecordID) -> String { path(StoreLayout.recordsDir, id.hex + StoreLayout.recordSuffix) }
    private nonisolated func attachmentPath(_ id: RecordID) -> String { path(StoreLayout.attachmentsDir, id.hex + StoreLayout.attachmentSuffix) }
    private nonisolated func filePath(_ id: RecordID, kind: EntryKind) -> String { kind == .attachment ? attachmentPath(id) : recordPath(id) }
    private nonisolated func journalPath(_ generation: UInt64) -> String { path(StoreLayout.journalDir, String(generation, radix: 16) + StoreLayout.journalSuffix) }
    private nonisolated func tempName() -> String { StoreLayout.tempPrefix + RecordID().hex }

    // MARK: Public read API (nonisolated snapshot; published by the actor after every committed change)

    /// Read-only mirror of committed state so status screens and tests can read without entering the
    /// actor. Written only from inside the actor; readers see the last committed snapshot.
    private final class Mirror: @unchecked Sendable {
        private let lock = NSLock()
        private var manifest = Manifest(generation: 0, prevHash: Manifest.zeroHash, vaultInstanceID: [UInt8](repeating: 0, count: 16), minimumWrapVersion: 0, ledgerHash: Manifest.zeroHash)
        private var ledger = DeletionLedger()
        private var report = StoreIntegrityReport(mode: .readOnly(reason: "not open"), epoch: 0, manifestGeneration: 0, deletionHistoryTrusted: false, missingFiles: [], orphansQuarantined: 0, journalsReplayed: 0, journalsReconciled: 0, needsRecovery: [], pendingRetirementVersion: nil)
        func publish(_ m: Manifest, _ l: DeletionLedger, _ r: StoreIntegrityReport) { lock.lock(); manifest = m; ledger = l; report = r; lock.unlock() }
        func read<T>(_ f: (Manifest, DeletionLedger, StoreIntegrityReport) -> T) -> T { lock.lock(); defer { lock.unlock() }; return f(manifest, ledger, report) }
    }
    private nonisolated let mirror = Mirror()

    private func publish() {
        let r = StoreIntegrityReport(mode: modeValue, epoch: epoch, manifestGeneration: manifest.generation, deletionHistoryTrusted: ledgerTrusted,
                                     missingFiles: missingFiles.sorted().compactMap { try? RecordID(hex: $0) }, orphansQuarantined: orphansMoved,
                                     journalsReplayed: journalsReplayed, journalsReconciled: journalsReconciled,
                                     needsRecovery: needsRecoveryIDs.sorted().compactMap { try? RecordID(hex: $0) }, pendingRetirementVersion: pendingRetirement)
        mirror.publish(manifest, ledger, r)
    }

    public nonisolated var mode: StoreMode { mirror.read { _, _, r in r.mode } }
    public nonisolated var manifestGeneration: UInt64 { mirror.read { m, _, _ in m.generation } }
    public nonisolated var manifestHash: [UInt8] { mirror.read { m, _, _ in m.hash } }
    public nonisolated var vaultInstanceID: [UInt8] { mirror.read { m, _, _ in m.vaultInstanceID } }
    public nonisolated var minimumWrapVersion: UInt32 { mirror.read { m, _, _ in m.minimumWrapVersion } }
    /// P03-04b: the newest backup generation this vault exported (durable, monotonic).
    public nonisolated var lastExportedGeneration: UInt64 { mirror.read { m, _, _ in m.lastExportedGeneration } }
    public nonisolated var deletionHistoryTrusted: Bool { mirror.read { _, _, r in r.deletionHistoryTrusted } }
    public nonisolated var deletionCount: Int { mirror.read { _, l, _ in l.totalCount } }
    public nonisolated var keyUsage: [UInt32: Int] { mirror.read { m, _, _ in m.keyUsage } }
    public nonisolated var recordIDs: [RecordID] { mirror.read { m, _, _ in m.records.keys.sorted().compactMap { try? RecordID(hex: $0) } } }
    public nonisolated func state(of id: RecordID) -> RecordState? { mirror.read { m, _, _ in m.records[id.hex]?.state } }
    public nonisolated func entry(of id: RecordID) -> ManifestEntry? { mirror.read { m, _, _ in m.records[id.hex] } }
    public nonisolated func deletionLookup(_ id: RecordID) -> DeletionLookup { mirror.read { _, l, _ in l.lookup(id) } }
    public nonisolated func integrityReport() -> StoreIntegrityReport { mirror.read { _, _, r in r } }

    /// Releases the single-writer lock. The instance must not be used afterwards.
    public func close() throws {
        guard !closed else { return }
        closed = true
        modeValue = .readOnly(reason: "closed")
        publish()
        try fs.remove(path(StoreLayout.lockFile))
    }

    // MARK: Read

    /// Plaintext of an ACTIVE record. Every denial is typed; nothing but an active, source-consistent,
    /// consent-covered record is ever decrypted. Uses `SecureVault.open` (token, consent, quarantine).
    public func get(_ id: RecordID, authorization: OperationAuthorization) throws -> [UInt8] {
        guard !closed else { throw VaultError.storeReadOnly(reason: "closed") }
        if case .readOnly(let r) = modeValue, r == Self.reopenRequiredReason { throw VaultError.storeReadOnly(reason: r) }
        guard let e = manifest.records[id.hex] else { throw VaultError.recordMissing }
        guard e.kind == .record else { throw VaultError.notEligible(reason: "attachment: use readAttachment") }
        guard !needsRecoveryIDs.contains(id.hex) else { throw VaultError.needsRecovery }
        guard e.state == .active else { throw VaultError.recordNotActive(state: e.state.name) }
        guard !missingFiles.contains(id.hex) else { throw VaultError.recordMissing }
        guard !corruptFiles.contains(id.hex) else { throw VaultError.recordNotActive(state: "corrupt") }
        let now = try clock.now()
        for src in e.derivedFrom {
            guard let s = manifest.records[src.hex], s.state == .active, !missingFiles.contains(src.hex) else { throw VaultError.recordNotActive(state: "sourceInactive") }
            if case .denied(let reason) = VaultPolicy.mayRead(s.dataClass, consentPurpose: s.consentPurpose, authority: composition.consentAuthority, atUnixSeconds: now) {
                throw VaultError.notAuthorized(reason)
            }
        }
        let env = try readRecordFile(id)
        do { return try vault.open(env, authorization: authorization) } catch VaultError.authenticationFailed {
            corruptFiles.insert(id.hex)
            throw VaultError.recordNotActive(state: "corrupt")
        }
    }

    private func readRecordFile(_ id: RecordID) throws -> RecordEnvelope {
        let p = recordPath(id)
        let kind = try fs.kind(of: p)
        guard kind != .missing else { missingFiles.insert(id.hex); throw VaultError.recordMissing }
        guard kind == .regular else { throw VaultError.storeIntegrityFailed(reason: "record path is not a regular file") }
        let env: RecordEnvelope
        do { env = try EnvelopeCodec.decode(try FileFraming.unframe(try fs.readRegular(p, maxBytes: limits.maxRecordBytes + 2 * FileFraming.block))) }
        catch { corruptFiles.insert(id.hex); throw VaultError.recordNotActive(state: "corrupt") }
        guard env.header.recordID == id else { corruptFiles.insert(id.hex); throw VaultError.storeIntegrityFailed(reason: "record id mismatch") }
        return env
    }

    private func readAttachmentHeader(_ id: RecordID) throws -> RecordEnvelope {
        let p = attachmentPath(id)
        let kind = try fs.kind(of: p)
        guard kind != .missing else { missingFiles.insert(id.hex); throw VaultError.recordMissing }
        guard kind == .regular else { throw VaultError.storeIntegrityFailed(reason: "attachment path is not a regular file") }
        let env: RecordEnvelope
        do { env = try EnvelopeCodec.decode(try AttachmentFile.readHeaderFrame(p, fileSystem: fs)) }
        catch { corruptFiles.insert(id.hex); throw VaultError.recordNotActive(state: "corrupt") }
        guard env.header.recordID == id else { corruptFiles.insert(id.hex); throw VaultError.storeIntegrityFailed(reason: "attachment id mismatch") }
        return env
    }

    // MARK: Attachments (P03-04b GATE 4): one DEK, streamed chunks, manifest-bound, cascade-aware

    /// Stores an attachment streamed from `source` (never whole in memory): header record sealed through
    /// `SecureVault.createAttachment` (`.write(class)` token + consent), chunks sealed with the derived
    /// chunk key, file written atomically, journaled like a record. `derivedFrom` binds it to its
    /// parent record(s) so cascade delete and source-consent rules apply.
    @discardableResult
    public func putAttachment(from source: any AttachmentSource, descriptor: RecordDescriptor, authorization: OperationAuthorization, provenance: RecordProvenance = .created) throws -> RecordID {
        try requireWritable()
        try validateSources(descriptor.derivedFrom, newCreatedAt: descriptor.createdAtUnixSeconds, newID: descriptor.recordID)
        guard manifest.records[descriptor.recordID.hex] == nil else { throw VaultError.duplicateRecordID }
        guard vault.currentKeyIdentity.version >= manifest.minimumWrapVersion else { throw VaultError.staleKeyVersion(minimum: manifest.minimumWrapVersion) }
        guard descriptor.dataClass != .storeMetadata else { throw VaultError.unsupportedSystemClass }
        let total = source.totalBytes
        guard total <= UInt64(limits.maxAttachmentBytes) else { throw VaultError.limitExceeded("attachment size") }
        let chunk = UInt32(limits.attachmentChunkBytes)
        let count = UInt32(total == 0 ? 1 : (total + UInt64(chunk) - 1) / UInt64(chunk))
        var prefix = [UInt8](repeating: 0, count: AttachmentLayout.noncePrefixBytes)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<prefix.count { prefix[i] = UInt8.random(in: 0...255, using: &rng) }
        let layout = try AttachmentLayout(chunkBytes: chunk, chunkCount: count, totalBytes: total, noncePrefix: prefix)
        let (header, cipher) = try vault.createAttachment(descriptor: descriptor, layout: layout, authorization: authorization)
        let id = header.header.recordID
        let headerFrame = AttachmentFile.frameBytes(EnvelopeCodec.encode(header))
        try runMutation(op: "put", tokenID: authorization.id, ids: [id], params: [Int64(provenance.rawValue), Int64(EntryKind.attachment.rawValue), Int64(bitPattern: total), Int64(count)]) { m, _, step in
            try AtomicWriter.replaceStreaming(self.fs, at: self.attachmentPath(id), tempName: self.tempName()) { fd in
                try self.fs.write(fd, headerFrame)
                var written = 0
                var delivered: UInt64 = 0
                for index in 0..<count {
                    let want = layout.length(ofChunk: index)
                    let plain = try source.readChunk(maxBytes: want)
                    guard plain.count == want else { throw VaultError.limitExceeded("attachment source short read") }
                    let sealed = try cipher.seal(chunk: plain, index: index)
                    let frame = AttachmentFile.frameBytes(sealed)
                    try self.fs.write(fd, frame)
                    written += frame.count
                    delivered += UInt64(plain.count)
                }
                guard delivered == total, try source.readChunk(maxBytes: 1).isEmpty else { throw VaultError.limitExceeded("attachment source size mismatch") }
                let used = headerFrame.count + written
                let rem = used % FileFraming.block
                if rem != 0 { try self.fs.write(fd, [UInt8](repeating: 0, count: FileFraming.block - rem)) }
            }
            try step("file", 0)
            m.records[id.hex] = ManifestEntry(header: header.header, keyVersion: header.wrappedDEK.keyVersion, provenance: provenance, kind: .attachment, attachmentBytes: total, chunkCount: count)
            return true
        }
        return id
    }

    /// Streams an attachment's plaintext to `sink` chunk by chunk after the SAME checks as `get`
    /// (active, sources active + consented, `.read` token, quarantine, consent) PLUS a full
    /// authentication pass over every chunk BEFORE the first plaintext byte is delivered: a corrupt,
    /// truncated, reordered or duplicated chunk yields no plaintext at all (two passes, bounded memory).
    public func readAttachment(_ id: RecordID, authorization: OperationAuthorization, sink: (UInt32, [UInt8]) throws -> Void) throws {
        guard !closed else { throw VaultError.storeReadOnly(reason: "closed") }
        if case .readOnly(let r) = modeValue, r == Self.reopenRequiredReason { throw VaultError.storeReadOnly(reason: r) }
        guard let e = manifest.records[id.hex] else { throw VaultError.recordMissing }
        guard e.kind == .attachment else { throw VaultError.notEligible(reason: "record: use get") }
        guard !needsRecoveryIDs.contains(id.hex) else { throw VaultError.needsRecovery }
        guard e.state == .active else { throw VaultError.recordNotActive(state: e.state.name) }
        guard !missingFiles.contains(id.hex) else { throw VaultError.recordMissing }
        guard !corruptFiles.contains(id.hex) else { throw VaultError.recordNotActive(state: "corrupt") }
        let now = try clock.now()
        for src in e.derivedFrom {
            guard let sEntry = manifest.records[src.hex], sEntry.state == .active, !missingFiles.contains(src.hex) else { throw VaultError.recordNotActive(state: "sourceInactive") }
            if case .denied(let reason) = VaultPolicy.mayRead(sEntry.dataClass, consentPurpose: sEntry.consentPurpose, authority: composition.consentAuthority, atUnixSeconds: now) {
                throw VaultError.notAuthorized(reason)
            }
        }
        let header = try readAttachmentHeader(id)
        let (layout, cipher): (AttachmentLayout, AttachmentCipher)
        do { (layout, cipher) = try vault.openAttachment(header, authorization: authorization) } catch VaultError.authenticationFailed {
            corruptFiles.insert(id.hex); throw VaultError.recordNotActive(state: "corrupt")
        }
        guard layout.totalBytes == e.attachmentBytes, layout.chunkCount == e.chunkCount else { corruptFiles.insert(id.hex); throw VaultError.recordNotActive(state: "corrupt") }
        // P03-04bH: both passes read the SAME open descriptor (inode): a file replaced under the path
        // between the passes cannot change what pass 2 reads; in-place writes by a same-UID process remain
        // out of the model (every chunk is still authenticated in pass 2, so they fail, never leak).
        let (fd, _) = try fs.openRegularForRead(attachmentPath(id))
        defer { try? fs.close(fd) }
        do {
            try streamChunks(fd, layout: layout, cipher: cipher) { _, _ in }            // pass 1: authenticate everything
            try fs.rewind(fd)
            try streamChunks(fd, layout: layout, cipher: cipher, deliver: sink)         // pass 2: decrypt and deliver
        } catch VaultError.authenticationFailed { corruptFiles.insert(id.hex); throw VaultError.recordNotActive(state: "corrupt") }
        catch VaultError.storeIntegrityFailed { corruptFiles.insert(id.hex); throw VaultError.recordNotActive(state: "corrupt") }
    }

    private func streamChunks(_ fd: Int32, layout: AttachmentLayout, cipher: AttachmentCipher, deliver: (UInt32, [UInt8]) throws -> Void) throws {
        guard try AttachmentFile.readFrame(fd, fileSystem: fs, maxBytes: AttachmentFile.maxHeaderFrameBytes) != nil else { throw VaultError.storeIntegrityFailed(reason: "attachment header missing") }
        let maxChunkFrame = Int(layout.chunkBytes) + 16
        for index in 0..<layout.chunkCount {
            guard let sealed = try AttachmentFile.readFrame(fd, fileSystem: fs, maxBytes: maxChunkFrame) else { throw VaultError.storeIntegrityFailed(reason: "attachment chunk missing") }
            let plain = try cipher.open(chunk: sealed, index: index)
            try deliver(index, plain)
        }
        // Nothing but zero padding may follow the last chunk (an appended or duplicated chunk fails here).
        while true {
            let rest = try fs.read(fd, maxBytes: FileFraming.block)
            if rest.isEmpty { break }
            guard rest.allSatisfy({ $0 == 0 }) else { throw VaultError.storeIntegrityFailed(reason: "attachment trailing data") }
        }
    }

    /// Rewrites only the header frame of an attachment under a new wrapping (chunks copied verbatim,
    /// bounded buffer). Used by key maintenance.
    private func rewriteAttachmentHeader(_ id: RecordID, header: RecordEnvelope) throws {
        let src = attachmentPath(id)
        let (inFD, _) = try fs.openRegularForRead(src)
        defer { try? fs.close(inFD) }
        guard try AttachmentFile.readFrame(inFD, fileSystem: fs, maxBytes: AttachmentFile.maxHeaderFrameBytes) != nil else { throw VaultError.storeIntegrityFailed(reason: "attachment header missing") }
        let newHeader = AttachmentFile.frameBytes(EnvelopeCodec.encode(header))
        try AtomicWriter.replaceStreaming(fs, at: src, tempName: tempName()) { outFD in
            try self.fs.write(outFD, newHeader)
            var written = newHeader.count
            while true {
                let block = try self.fs.read(inFD, maxBytes: FileFraming.block * 64)
                if block.isEmpty { break }
                try self.fs.write(outFD, block)
                written += block.count
            }
            // the old padding was copied too; re-pad only if the header length changed the alignment
            let rem = written % FileFraming.block
            if rem != 0 { try self.fs.write(outFD, [UInt8](repeating: 0, count: FileFraming.block - rem)) }
        }
    }

    // MARK: Write

    /// Seals and stores a new record. `.write(class)` token + consent (via `SecureVault.seal`),
    /// `derivedFrom` must name existing active EARLIER records (no back-edges), key version must not
    /// be below the frozen minimum (H2 R1).
    @discardableResult
    public func put(plaintext: [UInt8], descriptor: RecordDescriptor, authorization: OperationAuthorization, provenance: RecordProvenance = .created) throws -> RecordID {
        try requireWritable()
        try validateSources(descriptor.derivedFrom, newCreatedAt: descriptor.createdAtUnixSeconds, newID: descriptor.recordID)
        guard manifest.records[descriptor.recordID.hex] == nil else { throw VaultError.duplicateRecordID }
        guard vault.currentKeyIdentity.version >= manifest.minimumWrapVersion else { throw VaultError.staleKeyVersion(minimum: manifest.minimumWrapVersion) }
        guard plaintext.count <= limits.maxRecordBytes else { throw VaultError.limitExceeded("record size") }
        let env = try vault.seal(plaintext: plaintext, descriptor: descriptor, authorization: authorization)
        try storeEnvelope(env, tokenID: authorization.id, provenance: provenance)
        return env.header.recordID
    }

    // P03-04bH (F-P04B-02): `putEnvelope` (a caller-sealed envelope stored with only a `.write` token) was
    // REMOVED. Every personal write now goes through `SecureVault.seal` / `createAttachment` (purpose,
    // consent, tier, key binding, AEAD) or through the verified restore path (`admitRestored`).

    private func storeEnvelope(_ env: RecordEnvelope, tokenID: String, provenance: RecordProvenance) throws {
        guard env.header.dataClass != .storeMetadata else { throw VaultError.unsupportedSystemClass }
        guard env.wrappedDEK.keyVersion >= manifest.minimumWrapVersion else { throw VaultError.staleKeyVersion(minimum: manifest.minimumWrapVersion) }
        guard env.wrappedDEK.keyID == vault.currentKeyIdentity.keyID else { throw VaultError.keyUnavailable(version: env.wrappedDEK.keyVersion) }
        let id = env.header.recordID
        let bytes = FileFraming.frame(EnvelopeCodec.encode(env))
        try runMutation(op: "put", tokenID: tokenID, ids: [id], params: [Int64(provenance.rawValue)]) { m, _, step in
            try AtomicWriter.replace(self.fs, bytes: bytes, at: self.recordPath(id), tempName: self.tempName())
            try step("file", 0)
            m.records[id.hex] = ManifestEntry(header: env.header, keyVersion: env.wrappedDEK.keyVersion, provenance: provenance)
            return true
        }
    }

    private func validateSources(_ sources: [RecordID], newCreatedAt: Int64, newID: RecordID) throws {
        for s in sources {
            guard let e = manifest.records[s.hex] else { throw VaultError.unknownDependency }
            guard e.state == .active, e.createdAtUnixSeconds <= newCreatedAt else { throw VaultError.unknownDependency }
            guard s != newID else { throw VaultError.unknownDependency }
        }
    }

    // MARK: Delete (H1/H4): immediate, cascading, ledgered; never graced

    public func delete(_ ids: Set<RecordID>, grant: DeletionGrant) throws {
        try requireWritable()
        guard ids.isSubset(of: grant.recordIDs), !consumedGrants.contains(grant) else { throw VaultError.deletionGrantInvalid }
        consumedGrants.insert(grant)
        let present = ids.filter { manifest.records[$0.hex] != nil }
        guard !present.isEmpty else { return }
        let order = manifest.cascadeOrder(from: present)
        let now = try clock.now()
        try runMutation(op: "delete", tokenID: "", ids: order, params: [now]) { m, l, step in
            try self.applyDelete(order, deletedAt: now, m: &m, l: &l, step: step)
            return true
        }
    }

    private func applyDelete(_ order: [RecordID], deletedAt: Int64, m: inout Manifest, l: inout DeletionLedger, step: (String, UInt32) throws -> Void) throws {
        for (i, id) in order.enumerated() {
            try fs.remove(filePath(id, kind: m.records[id.hex]?.kind ?? .record))
            l.append(DeletionLedger.Entry(recordID: id, deletedAtUnixSeconds: deletedAt, manifestGeneration: m.generation + 1))
            m.records[id.hex] = nil
            missingFiles.remove(id.hex); corruptFiles.remove(id.hex)
            composition.quarantine.release(id)
            try step("unlink", UInt32(i))
        }
        l.compactIfNeeded(threshold: limits.ledgerCompactionThreshold, keepRecent: limits.ledgerRecentKept, digestCapacity: limits.ledgerDigestCapacity)
    }

    // MARK: Consent revocation (H4) — distinct from delete

    public static let graceEligibleClasses: Set<DataClass> = [.journal, .goalRoadmap, .psychometrics, .spiritualPractices]

    /// Stops every read of records bound to `purpose` at once. Derived records are deleted now.
    /// `.deleteNow` cascades immediately; `.suspend` keeps the ciphertext unreadable for the grace
    /// period (only for grace-eligible, own-authored classes) and never reactivates by itself.
    @discardableResult
    public func revoke(purpose: String, mode: RevokeMode, authorization: OperationAuthorization) throws -> (deleted: [RecordID], suspended: [RecordID]) {
        try requireWritable()
        let now = try vault.consumeAuthorization(authorization, for: .revokeConsent(purpose: purpose))
        let affected = manifest.records.filter { $0.value.consentPurpose == purpose && $0.value.dataClass.requiresPurposeConsentToStore && $0.value.state != .pendingDelete }
            .keys.sorted().compactMap { try? RecordID(hex: $0) }
        guard !affected.isEmpty else { return ([], []) }
        var toSuspend: [RecordID] = []
        var deleteRoots = Set<RecordID>()
        var graceSeconds: Int64 = 0
        switch mode {
        case .deleteNow:
            deleteRoots = Set(affected)
        case .suspend(let g):
            guard g > 0 else { throw VaultError.limitExceeded("grace") }
            for id in affected {
                let e = manifest.records[id.hex]!
                guard FileVaultStore.graceEligibleClasses.contains(e.dataClass) else { throw VaultError.notEligible(reason: "class not grace-eligible: " + e.dataClass.rawValue) }
                toSuspend.append(id)
                for d in manifest.dependents(of: id) { deleteRoots.insert(d) }
            }
            graceSeconds = g
        }
        let deleteOrder = manifest.cascadeOrder(from: deleteRoots).filter { !toSuspend.contains($0) }
        let until = now + graceSeconds
        let ids = deleteOrder + toSuspend
        try runMutation(op: "revoke", tokenID: authorization.id, ids: ids, params: [Int64(deleteOrder.count), now, until]) { m, l, step in
            try self.applyDelete(deleteOrder, deletedAt: now, m: &m, l: &l, step: step)
            for id in toSuspend {
                guard var e = m.records[id.hex] else { continue }
                e.state = .suspended; e.suspendedUntilUnixSeconds = until
                m.records[id.hex] = e
            }
            try step("suspend", 0)
            return true
        }
        return (deleteOrder, toSuspend)
    }

    /// Brings suspended records back after the user granted consent again AND explicitly asked.
    public func restoreSuspended(_ ids: Set<RecordID>, authorization: OperationAuthorization) throws {
        try requireWritable()
        let now = try vault.consumeAuthorization(authorization, for: .restoreSuspended(recordIDs: ids))
        for id in ids {
            guard let e = manifest.records[id.hex], e.state == .suspended else { throw VaultError.recordNotActive(state: manifest.records[id.hex]?.state.name ?? "missing") }
            if case .denied(let reason) = VaultPolicy.mayRead(e.dataClass, consentPurpose: e.consentPurpose, authority: composition.consentAuthority, atUnixSeconds: now) {
                throw VaultError.notAuthorized(reason)
            }
        }
        let list = ids.sorted { $0.hex < $1.hex }
        try runMutation(op: "unsuspend", tokenID: authorization.id, ids: list, params: []) { m, _, step in
            for id in list { if var e = m.records[id.hex] { e.state = .active; e.suspendedUntilUnixSeconds = 0; m.records[id.hex] = e } }
            try step("activate", 0)
            return true
        }
    }

    /// Deletes suspended records whose grace expired at the trusted effective time. Runs at open
    /// and on demand; the deletion was authorized when the user chose suspension.
    @discardableResult
    public func expireSuspended() throws -> [RecordID] {
        guard modeValue == .readWrite else { return [] }
        let now = try clock.now()
        let expired = manifest.records.filter { $0.value.state == .suspended && $0.value.suspendedUntilUnixSeconds <= now }.keys.sorted().compactMap { try? RecordID(hex: $0) }
        guard !expired.isEmpty else { return [] }
        let order = manifest.cascadeOrder(from: Set(expired))
        try runMutation(op: "delete", tokenID: "", ids: order, params: [now]) { m, l, step in
            try self.applyDelete(order, deletedAt: now, m: &m, l: &l, step: step)
            return true
        }
        return order
    }

    // MARK: Restore (H1 + P03-04b GATE 2/3): export v3, two-phase reconciliation

    /// P03-04b: exports every active record (attachments excluded in this phase) as a v3 backup bound
    /// to this vault: instance id, a durable monotonic backup generation, manifest generation + hash,
    /// and the deletion history (with its trust flag). The generation is committed BEFORE sealing so
    /// it never repeats. Any corrupt/missing record fails the export closed (typed error).
    public func exportBackup(recoveryKey: RecoveryKey, authorization: OperationAuthorization) throws -> [UInt8] {
        try requireWritable()
        let keys = manifest.records.filter { $0.value.state == .active && $0.value.kind == .record }.keys.sorted()
        var envs: [RecordEnvelope] = []
        envs.reserveCapacity(keys.count)
        for key in keys { envs.append(try readRecordFile(try RecordID(hex: key))) }
        let gen = manifest.lastExportedGeneration + 1
        try runMutation(op: "export", tokenID: authorization.id, ids: [], params: [Int64(gen)]) { m, _, step in
            m.lastExportedGeneration = gen
            try step("generation", 0)
            return true
        }
        let lb = ledger.encode()
        let excluded = manifest.records.values.filter { $0.kind == .attachment && $0.state == .active }.count
        let facts = try BackupExportFacts(vaultInstanceID: manifest.vaultInstanceID, backupGeneration: gen, sourceManifestGeneration: manifest.generation, sourceManifestHash: manifest.hash, deletionLedgerBytes: lb, deletionLedgerHash: VaultDigest.sha256(lb), deletionHistoryTrusted: ledgerTrusted, excludedAttachmentCount: UInt32(clamping: excluded))
        return try vault.exportBackup(envs, facts: facts, recoveryKey: recoveryKey, authorization: authorization)
    }

    /// Phase 1 — verify and stage. Every record returned by `SecureVault.restoreBackup` is written and
    /// QUARANTINED with the risks the user must acknowledge; nothing becomes active here. Known-deleted
    /// ids (local history, merged history, or the backup's own history) are skipped forever; existing
    /// ids are left as they are. The backup's history is merged only when it is our own instance's or
    /// this vault is empty (adoption on a fresh device), and only when the source trusted it.
    public func admitRestored(_ result: RestoreResult, authorization: OperationAuthorization) throws -> AdmissionReport {
        try requireWritable()
        _ = try vault.consumeAuthorization(authorization, for: .admitRestored)
        // F-P04B-03: only a result this facade produced and that is unchanged since carries trust.
        guard vault.isVerified(result) else { throw VaultError.restoreUnverified }
        let prov = result.provenance
        var embedded: DeletionLedger? = nil
        if let lb = prov.deletionLedgerBytes {
            guard let lh = prov.deletionLedgerHash, ConstantTime.equal(VaultDigest.sha256(lb), lh) else { throw VaultError.backupCorrupted(reason: "ledger digest") }
            guard let l = try? DeletionLedger.decode(lb) else { throw VaultError.backupCorrupted(reason: "ledger encoding") }
            embedded = l
        }
        let legacy = prov.isLegacy
        let sameInstance = !legacy && prov.vaultInstanceID! == manifest.vaultInstanceID
        let vaultEmpty = manifest.records.isEmpty
        let foreign = !vaultEmpty && !sameInstance
        let older = sameInstance && (prov.backupGeneration ?? 0) < manifest.lastExportedGeneration
        var merged = ledger
        var historyMerged = false
        var unmerged = embedded != nil && !prov.deletionHistoryTrusted
        if let e = embedded, prov.deletionHistoryTrusted, sameInstance || vaultEmpty {
            unmerged = !merged.merge(e, manifestGeneration: manifest.generation + 1)
            historyMerged = true
        }
        var base: Set<RestoreRisk> = []
        if legacy { base.insert(.legacyFormat) }
        if foreign && !legacy { base.insert(.foreignInstance) }
        if !ledgerTrusted { base.insert(.untrustedLocalHistory) }
        if older { base.insert(.olderBackupGeneration) }
        if unmerged { base.insert(.unmergedBackupHistory) }
        if prov.excludedAttachmentCount > 0 { base.insert(.attachmentsMissing) }
        var staged: [(RecordEnvelope, Set<RestoreRisk>)] = []
        var skippedDeleted: [RecordID] = [], skippedExisting: [RecordID] = []
        for (env, pre) in result.active.map({ ($0, false) }) + result.quarantined.map({ ($0.envelope, true) }) {
            try env.header.validate()
            guard env.header.dataClass != .storeMetadata else { continue }
            let id = env.header.recordID
            guard !env.header.derivedFrom.contains(id) else { throw VaultError.unknownDependency }
            if manifest.records[id.hex] != nil { skippedExisting.append(id); continue }
            var risks = base
            switch merged.lookup(id) {
            case .deleted: skippedDeleted.append(id); continue
            case .possiblyDeleted: risks.insert(.possiblyDeleted)
            case .notDeleted: break
            }
            if let e = embedded, !historyMerged, e.lookup(id) != .notDeleted { skippedDeleted.append(id); continue }
            if pre { risks.insert(.consentInactiveAtRestore) }
            guard env.wrappedDEK.keyVersion >= manifest.minimumWrapVersion else { throw VaultError.staleKeyVersion(minimum: manifest.minimumWrapVersion) }
            staged.append((env, risks))
        }
        let riskMap = Dictionary(uniqueKeysWithValues: staged.map { ($0.0.header.recordID, $0.1) })
        let report = AdmissionReport(staged: staged.map { $0.0.header.recordID }, risks: riskMap, skippedDeleted: skippedDeleted, skippedExisting: skippedExisting, historyMerged: historyMerged)
        guard !staged.isEmpty else {
            if historyMerged && merged != ledger {
                try runMutation(op: "history", tokenID: authorization.id, ids: [], params: []) { _, l, step in l = merged; try step("merge", 0); return true }
            }
            return report
        }
        let ids = staged.map { $0.0.header.recordID }
        let params = staged.map { Int64(RestoreRisk.mask($0.1)) } + [historyMerged ? 1 : 0]   // trailing flag: a merge is part of this batch
        try runMutation(op: "admit", tokenID: authorization.id, ids: ids, params: params) { m, l, step in
            if historyMerged { l = merged }
            for (i, (env, risks)) in staged.enumerated() {
                let id = env.header.recordID
                try AtomicWriter.replace(self.fs, bytes: FileFraming.frame(EnvelopeCodec.encode(env)), at: self.recordPath(id), tempName: self.tempName())
                m.records[id.hex] = ManifestEntry(header: env.header, keyVersion: env.wrappedDEK.keyVersion, state: .quarantined, provenance: .restoredFromBackup, restoreRisks: RestoreRisk.mask(risks))
                self.composition.quarantine.quarantine(id, reason: .pendingUserConfirmation)
                try step("file", UInt32(i))
            }
            return true
        }
        return report
    }

    /// Phase 2 — activate staged records after the user acknowledged EXACTLY their recorded risks.
    /// Re-checks at the trusted time: still staged, not deleted meanwhile, sources active (or in the
    /// same batch), consent active now, file present and parsable. Scope narrows to the listed ids.
    public func activateRestored(_ ids: Set<RecordID>, acknowledging risks: Set<RestoreRisk>, authorization: OperationAuthorization) throws {
        try requireWritable()
        let now = try vault.consumeAuthorization(authorization, for: .activateRestored(recordIDs: ids))
        let list = ids.sorted { $0.hex < $1.hex }
        for id in list {
            guard let e = manifest.records[id.hex] else { throw VaultError.recordMissing }
            guard e.state == .quarantined, e.provenance == .restoredFromBackup else { throw VaultError.recordNotActive(state: e.state.name) }
            let need = RestoreRisk.set(e.restoreRisks)
            // F-P04B-01: compacted deletion evidence is permanent — never activatable under this id.
            guard !need.contains(.possiblyDeleted) else { throw VaultError.possiblyDeletedForever }
            // Exact acknowledgment (documented UX contract): the UI must show precisely these risks.
            guard need == risks else {
                throw VaultError.notEligible(reason: "restore risks must be acknowledged exactly: need " + need.map { String($0.rawValue) }.sorted().joined(separator: ",") + " got " + risks.map { String($0.rawValue) }.sorted().joined(separator: ","))
            }
            switch ledger.lookup(id) {
            case .deleted: throw VaultError.notEligible(reason: "known deleted")
            case .possiblyDeleted: throw VaultError.possiblyDeletedForever
            case .notDeleted: break
            }
            for src in e.derivedFrom {
                guard let sEntry = manifest.records[src.hex], sEntry.state == .active || ids.contains(src) else { throw VaultError.recordNotActive(state: "sourceInactive") }
                guard sEntry.createdAtUnixSeconds <= e.createdAtUnixSeconds else { throw VaultError.unknownDependency }
            }
            if case .denied(let reason) = VaultPolicy.mayRead(e.dataClass, consentPurpose: e.consentPurpose, authority: composition.consentAuthority, atUnixSeconds: now) {
                throw VaultError.notAuthorized(reason)
            }
            guard !missingFiles.contains(id.hex), !corruptFiles.contains(id.hex) else { throw VaultError.recordMissing }
            _ = try readRecordFile(id)
        }
        // Derived-data graph: no cycle may be admitted through a restored batch (DFS over the batch's edges).
        try Self.refuseCycles(among: ids, in: manifest)
        try runMutation(op: "activate", tokenID: authorization.id, ids: list, params: []) { m, _, step in
            for id in list { if var e = m.records[id.hex] { e.state = .active; e.restoreRisks = 0; m.records[id.hex] = e } }
            try step("activate", 0)
            return true
        }
        for id in list { composition.quarantine.release(id) }
    }

    /// Refuses a batch whose `derivedFrom` edges (restricted to the batch) contain a cycle.
    static func refuseCycles(among ids: Set<RecordID>, in m: Manifest) throws {
        var state: [String: UInt8] = [:]   // 1 = visiting, 2 = done
        func visit(_ id: RecordID) throws {
            if state[id.hex] == 2 { return }
            if state[id.hex] == 1 { throw VaultError.unknownDependency }
            state[id.hex] = 1
            for src in m.records[id.hex]?.derivedFrom ?? [] where ids.contains(src) { try visit(src) }
            state[id.hex] = 2
        }
        for id in ids { try visit(id) }
    }

    /// P03-04bH (F-P04B-01): explicit re-import of ONE staged record whose old id can never be active
    /// again (compacted deletion evidence). `.reimport(recordID:)` token with the record's purpose, an
    /// active grant, verified payload (through `SecureVault.reimport`), NEW id and fresh DEK; the old
    /// id is deleted (file removed, ledger entry) in the same journaled mutation. Refused while any
    /// record derives from the old id (dependency migration is not implemented: fail closed).
    @discardableResult
    public func reimportPossiblyDeleted(_ id: RecordID, authorization: OperationAuthorization) throws -> RecordID {
        try requireWritable()
        guard let e = manifest.records[id.hex] else { throw VaultError.recordMissing }
        guard e.state == .quarantined, e.provenance == .restoredFromBackup, e.kind == .record else { throw VaultError.recordNotActive(state: e.state.name) }
        guard RestoreRisk.set(e.restoreRisks).contains(.possiblyDeleted) else { throw VaultError.notEligible(reason: "reimport is only for compacted-deletion quarantine") }
        guard manifest.dependents(of: id).isEmpty else { throw VaultError.notEligible(reason: "records derive from this id") }
        for src in e.derivedFrom {
            guard let sEntry = manifest.records[src.hex], sEntry.state == .active else { throw VaultError.recordNotActive(state: "sourceInactive") }
        }
        let env = try readRecordFile(id)
        let now = try clock.now()
        let d = try RecordDescriptor(dataClass: e.dataClass, privacyTier: e.privacyTier, retention: e.retention, consentPurpose: e.consentPurpose, createdAtUnixSeconds: now, derivedFrom: e.derivedFrom)
        let fresh = try vault.reimport(env, newDescriptor: d, authorization: authorization)
        let newID = fresh.header.recordID
        let bytes = FileFraming.frame(EnvelopeCodec.encode(fresh))
        try runMutation(op: "reimport", tokenID: authorization.id, ids: [newID, id], params: [now]) { m, l, step in
            try AtomicWriter.replace(self.fs, bytes: bytes, at: self.recordPath(newID), tempName: self.tempName())
            try step("file", 0)
            try self.fs.remove(self.recordPath(id))
            l.append(DeletionLedger.Entry(recordID: id, deletedAtUnixSeconds: now, manifestGeneration: m.generation + 1))
            m.records[id.hex] = nil
            m.records[newID.hex] = ManifestEntry(header: fresh.header, keyVersion: fresh.wrappedDEK.keyVersion, provenance: .reimportedAfterDeletion)
            try step("unlink", 0)
            return true
        }
        composition.quarantine.release(id)
        return newID
    }

    /// Releases ONE quarantined record: `.releaseQuarantine` token + active consent now (checked by
    /// `SecureVault.releaseQuarantine`), then the manifest state becomes active.
    public func releaseQuarantined(_ id: RecordID, authorization: OperationAuthorization) throws {
        try requireWritable()
        guard let e = manifest.records[id.hex] else { throw VaultError.recordMissing }
        guard e.state == .quarantined else { throw VaultError.recordNotActive(state: e.state.name) }
        // P03-04b: restored records carry risks and go through `activateRestored` only.
        guard e.provenance != .restoredFromBackup else { throw VaultError.notEligible(reason: "restored records activate through activateRestored") }
        let env = try readRecordFile(id)
        _ = try vault.releaseQuarantine(QuarantinedRecord(envelope: env, reason: .consentRequired), authorization: authorization)
        try runMutation(op: "release", tokenID: authorization.id, ids: [id], params: []) { m, _, step in
            if var r = m.records[id.hex] { r.state = .active; m.records[id.hex] = r }
            try step("activate", 0)
            return true
        }
    }

    // MARK: Key maintenance (H2)

    /// Re-wraps every record (and the ledger) wrapped under a version older than the current key.
    /// One maintenance token for the batch; each file replaced atomically and journaled.
    @discardableResult
    public func rewrapAll(maintenance: OperationAuthorization) throws -> Int {
        try requireWritable()
        return try rewrapBelowCurrent(maintenance: maintenance, op: "rewrap")
    }

    private func rewrapBelowCurrent(maintenance: OperationAuthorization, op: String, retiring: UInt32? = nil) throws -> Int {
        let current = vault.currentKeyIdentity.version
        let stale = manifest.records.filter { $0.value.keyVersion < current && $0.value.state != .pendingDelete }.keys.sorted().compactMap { try? RecordID(hex: $0) }
        var envs: [RecordEnvelope] = []
        for id in stale { envs.append(manifest.records[id.hex]?.kind == .attachment ? try readAttachmentHeader(id) : try readRecordFile(id)) }
        let rewrapped = try vault.rewrapBatch(envs, maintenance: maintenance)   // consumes the token even when the list is empty
        try runMutation(op: op, tokenID: maintenance.id, ids: stale, params: [Int64(current)] + (retiring.map { [Int64($0)] } ?? [])) { m, l, step in
            for (i, env) in rewrapped.enumerated() {
                let id = env.header.recordID
                if m.records[id.hex]?.kind == .attachment {
                    try self.rewriteAttachmentHeader(id, header: env)
                } else {
                    try AtomicWriter.replace(self.fs, bytes: FileFraming.frame(EnvelopeCodec.encode(env)), at: self.recordPath(id), tempName: self.tempName())
                }
                if var e = m.records[id.hex] { e.keyVersion = env.wrappedDEK.keyVersion; m.records[id.hex] = e }
                try step("rewrap", UInt32(i))
            }
            _ = l  // ledger/authz/manifest are re-sealed under the current key by the tail
            return true
        }
        return rewrapped.count
    }

    /// Protocol v2 steps R0–R5 (R0 = caller rotated the provider already): freeze the minimum wrap
    /// version, rewrap everything below it, verify the full on-disk inventory against the manifest,
    /// and return a proof bound to the resulting manifest generation and this section.
    public func prepareRetirement(of version: UInt32, authorization: OperationAuthorization, maintenance: OperationAuthorization) throws -> KeyRetirementProof {
        try requireWritable()
        let now = try vault.consumeAuthorization(authorization, for: .retireKey(version: version))
        let current = vault.currentKeyIdentity.version
        guard version < current, !manifest.retiredVersions.contains(version) else { throw VaultError.keyUnavailable(version: version) }
        // R1 freeze — durable before any scan.
        if manifest.minimumWrapVersion < current {
            try runMutation(op: "freeze", tokenID: authorization.id, ids: [], params: [Int64(current)]) { m, _, step in
                m.minimumWrapVersion = current
                try step("freeze", 0)
                return true
            }
        }
        // R2 rewrap (journaled; records then system files via the tail).
        let count = try rewrapBelowCurrent(maintenance: maintenance, op: "prepare", retiring: version)
        // R3 full inventory from file headers; R4 three-way cross-check.
        let inv = try KeyRetirementVerifier.inventory(root: root, fileSystem: fs)
        guard inv.unparsablePaths.isEmpty else { throw VaultError.storeIntegrityFailed(reason: "unparsable files during retirement scan") }
        let scanned = inv.countsByVersion[version] ?? 0
        let manifestCount = manifest.keyUsage[version] ?? 0
        guard scanned == 0, manifestCount == 0 else { throw VaultError.keyVersionInUse(version: version, count: max(scanned, manifestCount)) }
        // R5 proof bound to the manifest generation and a fresh section token.
        var token = [UInt8](repeating: 0, count: 16)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<16 { token[i] = UInt8.random(in: 0...255, using: &rng) }
        section = (token, version)
        pendingRetirement = nil
        return KeyRetirementProof(keyVersion: version, manifestGeneration: manifest.generation, manifestHash: manifest.hash, scanDigest: inv.digest, rewrappedCount: count, sectionToken: token, issuedAtUnixSeconds: now)
    }

    /// Protocol v2 steps R6–R7: with a proof for the CURRENT manifest generation and the open section,
    /// retire then forget the version in the provider and record it in the manifest. Any mutation
    /// since the proof (generation changed) refuses with `proofStale`.
    public func forgetRetired(_ version: UInt32, proof: KeyRetirementProof) throws {
        try requireWritable()
        guard let s = section, s.version == version, ConstantTime.equal(s.token, proof.sectionToken) else { throw VaultError.proofStale }
        guard proof.keyVersion == version, proof.manifestGeneration == manifest.generation, ConstantTime.equal(proof.manifestHash, manifest.hash) else { throw VaultError.proofStale }
        guard (manifest.keyUsage[version] ?? 0) == 0 else { throw VaultError.keyVersionInUse(version: version, count: manifest.keyUsage[version] ?? 0) }
        guard version < vault.currentKeyIdentity.version else { throw VaultError.keyUnavailable(version: version) }
        try runMutation(op: "forget", tokenID: "", ids: [], params: [Int64(version)]) { m, _, step in
            try self.keyProvider.retire(version: version)
            try step("retire", 0)
            try self.keyProvider.forget(version: version)
            try step("forget", 0)
            if !m.retiredVersions.contains(version) { m.retiredVersions.append(version) }
            return true
        }
        section = nil
    }

    /// R0–R7 in ONE exclusive actor section (no suspension between proof and forget).
    @discardableResult
    public func retireKey(_ version: UInt32, authorization: OperationAuthorization, maintenance: OperationAuthorization) throws -> KeyRetirementProof {
        let proof = try prepareRetirement(of: version, authorization: authorization, maintenance: maintenance)
        try forgetRetired(version, proof: proof)
        return proof
    }

    // MARK: Mutation engine (journal → effects → durable tail)

    private func requireWritable() throws {
        guard !closed else { throw VaultError.storeReadOnly(reason: "closed") }
        if case .readOnly(let r) = modeValue { throw VaultError.storeReadOnly(reason: r) }
    }

    /// Runs one journaled mutation. `body` applies effects to files and to the in-memory copies of
    /// the manifest/ledger; it must be idempotent (recovery may re-run it). Returns false to abort.
    /// Read-only reason after a mutation failed part-way (P03-04H, F-P04-02): the on-disk journal is
    /// the only truth, in-memory state may no longer match the files, so this instance refuses reads
    /// and writes until a reopen replays or reconciles the journal (GATE B).
    public static let reopenRequiredReason = "mutation interrupted: reopen required"

    private func runMutation(op: String, tokenID: String, ids: [RecordID], params: [Int64], body: (inout Manifest, inout DeletionLedger, (String, UInt32) throws -> Void) throws -> Bool) throws {
        let target = manifest.generation + 1
        // GATE 1: the begin entry binds the op to the ledger state the manifest proves (pre-state).
        var entries: [JournalEntry] = [.begin(op: op, tokenID: tokenID, ids: ids, targetGeneration: target, epoch: epoch, params: params, ledgerHash: manifest.ledgerHash)]
        do {
            try writeJournal(target, entries)
            var m = manifest
            var l = ledger
            let ledgerBefore = ledger
            let proceed = try body(&m, &l) { name, index in
                entries.append(.step(name: name, index: index))
                try self.writeJournal(target, entries)
            }
            guard proceed else { try fs.remove(journalPath(target)); return }
            try commitTail(target: target, newManifest: m, newLedger: l, ledgerChanged: l != ledgerBefore, entries: &entries)
        } catch {
            // Any failed syscall or crash inside the critical section (journal, effects, ledger, manifest,
            // authz, anchor, commit) leaves the operation to recovery. Success was never reported; the
            // store fails closed instead of continuing on state it cannot prove.
            modeValue = .readOnly(reason: Self.reopenRequiredReason)
            publish()
            throw error
        }
    }

    private func commitTail(target: UInt64, newManifest: Manifest, newLedger: DeletionLedger, ledgerChanged: Bool, entries: inout [JournalEntry]) throws {
        var m = newManifest
        // The ledger is re-sealed when it changed, is missing, or is still wrapped under an older key
        // version (so key retirement never finds a stale system envelope — H2 R2 covers system files).
        let ledgerStale = (systemFileKeyVersion(StoreLayout.ledgerFile) ?? 0) < vault.currentKeyIdentity.version
        if ledgerChanged || ledgerStale {
            // GATE 1: announce the exact post-state in the journal BEFORE replacing the file, so recovery
            // can accept the disk ledger only as the proven pre-state or this announced post-state.
            let encoded = newLedger.encode()
            let postHash = VaultDigest.sha256(encoded)
            entries.append(.ledgerWritten(hash: postHash))
            try writeJournal(target, entries)
            try writeSystem(StoreLayout.ledgerFile, encoded)
            m.ledgerHash = postHash
        }
        // Sticky distrust: a history found corrupt or unverifiable never becomes trusted by rewriting.
        if !ledgerTrusted { m.ledgerHistoryTrusted = false }
        m.prevHash = manifest.hash
        m.generation = target
        try writeSystem(StoreLayout.manifestFile, m.encode())
        entries.append(.manifestWritten(generation: target))
        try writeJournal(target, entries)
        try finishTail(target: target, m: m, l: newLedger, entries: &entries)
    }

    /// authz → anchor → commit → journal removed. Also used by recovery when the manifest was durable.
    private func finishTail(target: UInt64, m: Manifest, l: DeletionLedger, entries: inout [JournalEntry]) throws {
        let hash = m.hash
        let a = AuthzState(epoch: epoch, clockHighWaterMark: clock.highWaterMark, lastManifestGeneration: target, lastManifestHash: hash)
        try writeSystem(StoreLayout.authzFile, a.encode())
        try anchorStore.writeAnchor(try VaultAnchor(vaultInstanceID: m.vaultInstanceID, manifestGeneration: target, manifestHash: hash))
        entries.append(.commit)
        try writeJournal(target, entries)
        try fs.remove(journalPath(target))
        manifest = m; ledger = l; authz = a
        publish()
    }

    /// Time for system envelope headers: the effective time, or the persisted mark when the clock has
    /// regressed beyond tolerance (the vault still opens read-only-in-effect: no token can be issued).
    private func systemTime() -> Int64 { (try? clock.now()) ?? clock.highWaterMark ?? 0 }

    private func writeJournal(_ target: UInt64, _ entries: [JournalEntry]) throws {
        var sealed: [[UInt8]] = []
        let now = systemTime()
        for e in entries {
            let d = try RecordDescriptor(dataClass: .storeMetadata, retention: .untilUserDeletes, createdAtUnixSeconds: now)
            sealed.append(EnvelopeCodec.encode(try vault.sealSystem(plaintext: e.encode(), descriptor: d)))
        }
        try AtomicWriter.replace(fs, bytes: FileFraming.frameJournal(sealed), at: journalPath(target), tempName: tempName())
    }

    /// Key version an on-disk system envelope is wrapped under (nil when missing/unparsable).
    private func systemFileKeyVersion(_ name: String) -> UInt32? {
        let p = path(StoreLayout.systemDir, name)
        guard (try? fs.kind(of: p)) == .regular, let bytes = try? fs.readRegular(p, maxBytes: 256 * 1024 * 1024),
              let env = try? EnvelopeCodec.decode(try FileFraming.unframe(bytes)) else { return nil }
        return env.wrappedDEK.keyVersion
    }

    private func writeSystem(_ name: String, _ plaintext: [UInt8]) throws {
        let d = try RecordDescriptor(dataClass: .storeMetadata, retention: .untilUserDeletes, createdAtUnixSeconds: systemTime())
        let env = try vault.sealSystem(plaintext: plaintext, descriptor: d)
        try AtomicWriter.replace(fs, bytes: FileFraming.frame(EnvelopeCodec.encode(env)), at: path(StoreLayout.systemDir, name), tempName: tempName())
    }

    // MARK: Recovery (GATE B / H5)

    /// Resolves pending journals, re-registers quarantined ids, reconciles files with the manifest,
    /// persists the new epoch. Read-only modes skip every write.
    private func recover() throws {
        publish()
        // 1. Journals (the loader already classified truncated/untrusted ones).
        for j in pendingJournals {
            guard case .readWrite = modeValue else { break }
            try resolveJournal(j)
        }
        pendingJournals = []
        // 2. Quarantine registry mirrors the manifest (P03-04bH: an id activated by a replayed journal is
        //    released here too, so a crash between the commit and the in-memory release cannot leave a
        //    stale registry entry behind).
        for (key, e) in manifest.records {
            guard let id = try? RecordID(hex: key) else { continue }
            if e.state == .quarantined { composition.quarantine.quarantine(id, reason: e.provenance == .restoredFromBackup ? .pendingUserConfirmation : .consentRequired) }
            else if !needsRecoveryIDs.contains(key) { composition.quarantine.release(id) }   // untrusted-journal ids stay quarantined
        }
        // 3. Files ↔ manifest (records/ and attachments/). Bounded: a directory above the entry limit
        //    is not scanned at all — the vault opens read-only (GATE 5 resource limit, fail closed).
        var seen = Set<String>()
        for (sub, suffix, kind) in [(StoreLayout.recordsDir, StoreLayout.recordSuffix, EntryKind.record), (StoreLayout.attachmentsDir, StoreLayout.attachmentSuffix, EntryKind.attachment)] {
            let dir = path(sub)
            guard try fs.entryCount(dir) <= limits.maxDirectoryEntries else { modeValue = .readOnly(reason: "file count exceeds limit"); break }
            for name in try fs.listNames(dir) {
                if name.hasPrefix(StoreLayout.tempPrefix) { continue }
                let p = (dir as NSString).appendingPathComponent(name)
                guard try fs.kind(of: p) == .regular else { throw VaultError.storeIntegrityFailed(reason: "non-regular entry in " + sub + "/") }
                let base = name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : ""
                if let id = try? RecordID(hex: base), let e = manifest.records[id.hex], e.kind == kind { seen.insert(id.hex); continue }
                // Orphan: never adopted, moved aside for the user to review/delete.
                if case .readWrite = modeValue {
                    try fs.rename(p, path(StoreLayout.orphansDir, name.hasPrefix(".") ? "x" + name : name))
                    orphansMoved += 1
                }
            }
        }
        if case .readWrite = modeValue { for key in manifest.records.keys where !seen.contains(key) { missingFiles.insert(key) } }
        // 4. Grace expiry at the trusted time. A clock regressed beyond tolerance skips expiry (nothing
        //    is deleted or revived on untrusted time); reads and tokens fail closed until time is sane.
        if case .readWrite = modeValue {
            do { _ = try expireSuspended() } catch VaultError.clockRegressed {}
        }
        // 5. Persist the new epoch (authz) — the manifest is unchanged so the anchor stays valid.
        if case .readWrite = modeValue {
            let a = AuthzState(epoch: epoch, clockHighWaterMark: clock.highWaterMark, lastManifestGeneration: manifest.generation, lastManifestHash: manifest.hash)
            try writeSystem(StoreLayout.authzFile, a.encode())
            authz = a
        }
        publish()
    }

    private func resolveJournal(_ j: (name: String, entries: [JournalEntry], truncated: Bool, bytes: [UInt8])) throws {
        guard case .begin(let op, _, let ids, let target, _, let params, _) = j.entries.first ?? .commit else {
            try fs.remove(path(StoreLayout.journalDir, j.name)); return
        }
        if j.entries.contains(.commit) {
            // Crash after commit but before the journal was removed: nothing left to do.
            try fs.remove(path(StoreLayout.journalDir, j.name)); journalsReplayed += 1; return
        }
        let manifestDurable = j.entries.contains(.manifestWritten(generation: target)) || manifest.generation == target
        var entries = j.entries
        if manifestDurable {
            // Effects and manifest are on disk; only authz/anchor/commit may be missing.
            guard manifest.generation == target else { throw VaultError.storeIntegrityFailed(reason: "journal/manifest generation disagree") }
            try finishTail(target: target, m: manifest, l: ledger, entries: &entries)
            journalsReplayed += 1
            return
        }
        guard manifest.generation + 1 == target else { throw VaultError.storeIntegrityFailed(reason: "stale journal generation") }
        // GATE 1: whether the ledger on disk is already the post-state the journal announced (the loader
        // proved it is either that or the pre-state).
        var preHash = Manifest.zeroHash
        if case .begin(_, _, _, _, _, _, let lh) = j.entries[0] { preHash = lh }
        var announced: [UInt8]? = nil
        for e in j.entries { if case .ledgerWritten(let h) = e { announced = h } }
        let diskIsPost = announced.map { !ConstantTime.equal($0, preHash) && ConstantTime.equal(ledger.hash, $0) } ?? false
        switch op {
        case "put", "admit":
            // put: a file that exists is adopted from its authenticated header; a missing one never happened.
            // admit (P03-04b): ALL-OR-NOTHING — the batch is adopted only when every file is present and,
            // if a history merge was part of it, the merged ledger is the one on disk (announced post-state).
            // Otherwise the batch is aborted (files removed, journal dropped) and the user re-runs the restore:
            // the merge cannot be rebuilt from the journal, and a half batch would hide that.
            if op == "admit" {
                let mergeIntended = params.count > ids.count && params[ids.count] == 1
                var allPresent = true
                for id in ids where (try? fs.kind(of: recordPath(id))) != .regular || (try? readRecordFile(id)) == nil { allPresent = false; break }
                if !allPresent || (mergeIntended && !diskIsPost) {
                    for id in ids { try fs.remove(recordPath(id)); composition.quarantine.release(id); missingFiles.remove(id.hex); corruptFiles.remove(id.hex) }
                    try fs.remove(path(StoreLayout.journalDir, j.name)); journalsReconciled += 1; return
                }
            }
            var m = manifest
            var any = false
            let putKind: EntryKind = (op == "put" && params.count > 1 && params[1] == Int64(EntryKind.attachment.rawValue)) ? .attachment : .record
            for (i, id) in ids.enumerated() {
                let env: RecordEnvelope
                if putKind == .attachment {
                    guard try fs.kind(of: attachmentPath(id)) == .regular, let h = try? readAttachmentHeader(id) else { continue }
                    env = h
                } else {
                    guard try fs.kind(of: recordPath(id)) == .regular, let r = try? readRecordFile(id) else { continue }
                    env = r
                }
                let flag = i < params.count ? params[i] : 0
                let state: RecordState = op == "admit" ? .quarantined : .active
                let prov: RecordProvenance = op == "admit" ? .restoredFromBackup : (RecordProvenance(rawValue: UInt8(clamping: params.first ?? 0)) ?? .created)
                let total = putKind == .attachment && params.count > 3 ? UInt64(bitPattern: params[2]) : 0
                let chunks = putKind == .attachment && params.count > 3 ? UInt32(clamping: params[3]) : 0
                m.records[id.hex] = ManifestEntry(header: env.header, keyVersion: env.wrappedDEK.keyVersion, state: state, provenance: prov, kind: putKind, attachmentBytes: total, chunkCount: chunks, restoreRisks: op == "admit" ? UInt16(clamping: flag) : 0)
                if op == "admit" { composition.quarantine.quarantine(id, reason: .pendingUserConfirmation) }
                any = true
            }
            if any || diskIsPost { try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: diskIsPost, entries: &entries) } else { try fs.remove(path(StoreLayout.journalDir, j.name)) }
            journalsReplayed += 1
        case "reimport":
            // ids = [new, old]; params = [deletedAt]. All-or-nothing: the new file must exist, else nothing happened.
            guard ids.count == 2, try fs.kind(of: recordPath(ids[0])) == .regular, let fresh = try? readRecordFile(ids[0]) else {
                if ids.count == 2 { try fs.remove(recordPath(ids[0])) }
                try fs.remove(path(StoreLayout.journalDir, j.name)); journalsReconciled += 1; return
            }
            var m = manifest, l = ledger
            try fs.remove(recordPath(ids[1]))
            l.append(DeletionLedger.Entry(recordID: ids[1], deletedAtUnixSeconds: params.first ?? 0, manifestGeneration: target))
            m.records[ids[1].hex] = nil
            composition.quarantine.release(ids[1])
            m.records[ids[0].hex] = ManifestEntry(header: fresh.header, keyVersion: fresh.wrappedDEK.keyVersion, provenance: .reimportedAfterDeletion)
            try commitTail(target: target, newManifest: m, newLedger: l, ledgerChanged: true, entries: &entries)
            journalsReplayed += 1
        case "history":
            if diskIsPost { try commitTail(target: target, newManifest: manifest, newLedger: ledger, ledgerChanged: true, entries: &entries) } else { try fs.remove(path(StoreLayout.journalDir, j.name)) }
            journalsReplayed += 1
        case "export":
            var m = manifest
            m.lastExportedGeneration = max(m.lastExportedGeneration, UInt64(clamping: params.first ?? 0))
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: diskIsPost, entries: &entries)
            journalsReplayed += 1
        case "delete":
            var m = manifest, l = ledger
            try applyDelete(ids, deletedAt: params.first ?? 0, m: &m, l: &l) { _, _ in }
            try commitTail(target: target, newManifest: m, newLedger: l, ledgerChanged: true, entries: &entries)
            journalsReplayed += 1
        case "revoke":
            let deleteCount = Int(params.count > 0 ? params[0] : 0)
            let now = params.count > 1 ? params[1] : 0
            let until = params.count > 2 ? params[2] : 0
            var m = manifest, l = ledger
            try applyDelete(Array(ids.prefix(deleteCount)), deletedAt: now, m: &m, l: &l) { _, _ in }
            for id in ids.dropFirst(deleteCount) { if var e = m.records[id.hex] { e.state = .suspended; e.suspendedUntilUnixSeconds = until; m.records[id.hex] = e } }
            try commitTail(target: target, newManifest: m, newLedger: l, ledgerChanged: deleteCount > 0, entries: &entries)
            journalsReplayed += 1
        case "unsuspend", "release", "activate":
            var m = manifest
            for id in ids { if var e = m.records[id.hex] { e.state = .active; e.suspendedUntilUnixSeconds = 0; if op == "activate" { e.restoreRisks = 0; composition.quarantine.release(id) }; m.records[id.hex] = e } }
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: diskIsPost, entries: &entries)
            journalsReplayed += 1
        case "freeze":
            var m = manifest
            if let v = params.first { m.minimumWrapVersion = max(m.minimumWrapVersion, UInt32(clamping: v)) }
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: diskIsPost, entries: &entries)
            journalsReplayed += 1
        case "rewrap", "prepare":
            // Resumable, not replayable (needs a fresh maintenance token): sync key versions from the
            // authenticated file headers, drop the journal; the caller re-runs rewrap/retirement.
            var m = manifest
            for id in ids { if var e = m.records[id.hex], let env = try? (e.kind == .attachment ? readAttachmentHeader(id) : readRecordFile(id)) { e.keyVersion = env.wrappedDEK.keyVersion; m.records[id.hex] = e } }
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: diskIsPost, entries: &entries)
            if op == "prepare" { pendingRetirement = params.count > 1 ? UInt32(clamping: params[1]) : UInt32(clamping: m.minimumWrapVersion > 0 ? Int64(m.minimumWrapVersion) - 1 : 0) }
            journalsReconciled += 1
        case "forget":
            var m = manifest
            let v = UInt32(clamping: params.first ?? 0)
            if j.entries.contains(.step(name: "forget", index: 0)) { if !m.retiredVersions.contains(v) { m.retiredVersions.append(v) } }
            else { pendingRetirement = v }   // retire may have happened; forget did not: nothing lost, re-run the protocol
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: diskIsPost, entries: &entries)
            journalsReconciled += 1
        default:
            needsRecoveryIDs.formUnion(ids.map { $0.hex })
            modeValue = .readOnly(reason: "unknown journal operation")
        }
    }

    // MARK: Loader (nonisolated, runs before the actor exists)

    enum Loader {
        struct Loaded {
            let root: String; let vault: SecureVault; let issuer: AuthorizationIssuer; let clock: MonotonicGuardClock; let epoch: UInt64
            let manifest: Manifest; let ledger: DeletionLedger; let authz: AuthzState; let mode: StoreMode; let ledgerTrusted: Bool
            let journals: [(name: String, entries: [JournalEntry], truncated: Bool, bytes: [UInt8])]
            /// Ids of an untrusted (mid-file damaged) journal: quarantined and flagged `needsRecovery`.
            let untrustedIDs: [RecordID]
        }

        /// Validator that accepts nothing: the bootstrap vault only opens system records.
        struct RejectAll: AuthorizationValidator {
            func consume(tokenID: String, atUnixSeconds now: Int64) throws -> OperationAuthorization { throw VaultError.authorizationInvalid(.unknownToken) }
        }

        static func load(root: String, keyProvider: any RetirableKeyProvider, anchor: any VaultAnchorStore, composition: VaultComposition, limits: StoreLimits, fs: any VaultFileSystem, reinstall: ReinstallPolicy) throws -> Loaded {
            func p(_ parts: String...) -> String { parts.reduce(root) { ($0 as NSString).appendingPathComponent($1) } }
            // Root must be a real directory (never a symlink); subdirectories created, excluded from OS backups.
            switch try fs.kind(of: root) {
            case .missing: try fs.createDirectory(root)
            case .directory: break
            default: throw VaultError.storeIntegrityFailed(reason: "vault root is not a directory")
            }
            for sub in [StoreLayout.recordsDir, StoreLayout.systemDir, StoreLayout.journalDir, StoreLayout.orphansDir, StoreLayout.attachmentsDir] {
                let d = p(sub)
                switch try fs.kind(of: d) {
                case .missing: try fs.createDirectory(d)
                case .directory: break
                default: throw VaultError.storeIntegrityFailed(reason: "vault subdirectory is not a directory")
                }
            }
            try fs.excludeFromBackup(root)
            // Temp files from interrupted writes are garbage by construction — but only once THIS process
            // holds the writer lock (P03-04H: a locked-out opener must not touch a live writer's files).
            func removeTempFiles() throws {
                for sub in [StoreLayout.recordsDir, StoreLayout.systemDir, StoreLayout.journalDir, StoreLayout.orphansDir, StoreLayout.attachmentsDir, ""] {
                    let d = sub.isEmpty ? root : p(sub)
                    for name in try fs.listNames(d) where name.hasPrefix(StoreLayout.tempPrefix) { try fs.remove((d as NSString).appendingPathComponent(name)) }
                }
            }
            // Bootstrap vault: system records only (no tokens can be consumed through it).
            let bootstrapClock = MonotonicGuardClock(wrapping: composition.baseClock, toleranceSeconds: composition.toleranceSeconds)
            let bootstrap = SecureVault(keyProvider: keyProvider, consentAuthority: composition.consentAuthority, clock: bootstrapClock, authorizations: RejectAll(), quarantine: composition.quarantine)
            func readSystem(_ name: String) throws -> [UInt8]? {
                let path = p(StoreLayout.systemDir, name)
                switch try fs.kind(of: path) {
                case .missing: return nil
                case .regular: return try bootstrap.openSystem(try EnvelopeCodec.decode(try FileFraming.unframe(try fs.readRegular(path, maxBytes: 256 * 1024 * 1024))))
                default: throw VaultError.storeIntegrityFailed(reason: "system file is not a regular file")
                }
            }
            let anchorValue = try anchor.readAnchor()
            let manifestBytes = try readSystem(StoreLayout.manifestFile)

            // Fresh vault / reinstall handling.
            if manifestBytes == nil {
                if anchorValue != nil {
                    guard case .recreateAfterConfirmation(let ack) = reinstall, ack else { throw VaultError.storeIntegrityFailed(reason: "anchor present but manifest missing (reinstall): explicit confirmation required") }
                }
                try takeLock(root: root, fs: fs, persistedEpoch: 0)   // before anything is removed
                if anchorValue != nil { try anchor.clearAnchor() }
                try removeTempFiles()
                for name in try fs.listNames(p(StoreLayout.recordsDir)) { try fs.remove(p(StoreLayout.recordsDir, name)) }   // nothing can be adopted without a manifest
                for name in try fs.listNames(p(StoreLayout.attachmentsDir)) { try fs.remove(p(StoreLayout.attachmentsDir, name)) }
                for name in try fs.listNames(p(StoreLayout.systemDir)) { try fs.remove(p(StoreLayout.systemDir, name)) }
                for name in try fs.listNames(p(StoreLayout.journalDir)) { try fs.remove(p(StoreLayout.journalDir, name)) }
                let epoch: UInt64 = 1
                let clock = MonotonicGuardClock(wrapping: composition.baseClock, toleranceSeconds: composition.toleranceSeconds)
                let issuer = AuthorizationIssuer(clock: clock, epoch: epoch)
                let vault = SecureVault(keyProvider: keyProvider, consentAuthority: composition.consentAuthority, clock: clock, authorizations: issuer, quarantine: composition.quarantine)
                var rng = SystemRandomNumberGenerator()
                let instance = (0..<VaultAnchor.instanceIDBytes).map { _ in UInt8.random(in: 0...255, using: &rng) }
                let ledger = DeletionLedger()
                let manifest = Manifest(generation: 1, prevHash: Manifest.zeroHash, vaultInstanceID: instance, minimumWrapVersion: keyProvider.currentKey.version, ledgerHash: ledger.hash)
                let now = try clock.now()
                func writeSystem(_ name: String, _ plain: [UInt8]) throws {
                    let d = try RecordDescriptor(dataClass: .storeMetadata, retention: .untilUserDeletes, createdAtUnixSeconds: now)
                    try AtomicWriter.replace(fs, bytes: FileFraming.frame(EnvelopeCodec.encode(try vault.sealSystem(plaintext: plain, descriptor: d))), at: p(StoreLayout.systemDir, name), tempName: StoreLayout.tempPrefix + RecordID().hex)
                }
                try writeSystem(StoreLayout.ledgerFile, ledger.encode())
                try writeSystem(StoreLayout.manifestFile, manifest.encode())
                let authz = AuthzState(epoch: epoch, clockHighWaterMark: clock.highWaterMark, lastManifestGeneration: 1, lastManifestHash: manifest.hash)
                try writeSystem(StoreLayout.authzFile, authz.encode())
                try anchor.writeAnchor(try VaultAnchor(vaultInstanceID: instance, manifestGeneration: 1, manifestHash: manifest.hash))
                return Loaded(root: root, vault: vault, issuer: issuer, clock: clock, epoch: epoch, manifest: manifest, ledger: ledger, authz: authz, mode: .readWrite, ledgerTrusted: true, journals: [], untrustedIDs: [])
            }

            // Existing vault: decode and bind.
            let manifest = try Manifest.decode(manifestBytes!)
            let mHash = manifest.hash
            var mode: StoreMode = .readWrite
            var ledgerTrusted = true
            var authz: AuthzState
            if let ab = try readSystem(StoreLayout.authzFile) { authz = try AuthzState.decode(ab) }
            else { authz = AuthzState(epoch: 0, clockHighWaterMark: nil, lastManifestGeneration: 0, lastManifestHash: Manifest.zeroHash); mode = .readOnly(reason: "authz state missing") }
            let persistedEpoch = authz.epoch
            try takeLock(root: root, fs: fs, persistedEpoch: persistedEpoch)
            try removeTempFiles()

            // Journals: parse; truncated tails are discarded; a failure before the tail = untrusted.
            var journals: [(name: String, entries: [JournalEntry], truncated: Bool, bytes: [UInt8])] = []
            var untrustedIDs: [RecordID] = []
            for name in try fs.listNames(p(StoreLayout.journalDir)) where !name.hasPrefix(StoreLayout.tempPrefix) {
                let path = p(StoreLayout.journalDir, name)
                guard try fs.kind(of: path) == .regular else { throw VaultError.storeIntegrityFailed(reason: "journal entry is not a regular file") }
                let bytes = try fs.readRegular(path, maxBytes: 64 * 1024 * 1024)
                let (raw, truncated) = FileFraming.unframeJournal(bytes)
                var entries: [JournalEntry] = []
                var failedAt: Int? = nil
                var legacy = false
                for (i, r) in raw.enumerated() {
                    do { entries.append(try JournalEntry.decode(try bootstrap.openSystem(try EnvelopeCodec.decode(r)))) }
                    catch VaultError.unsupportedFormat { legacy = true; break }
                    catch { failedAt = i; break }
                }
                if legacy { mode = .readOnly(reason: "journal format unsupported"); continue }
                if let f = failedAt {
                    if f == raw.count - 1 && !truncated { /* a damaged LAST entry behaves like a truncated tail */ }
                    else if f < raw.count - 1 {
                        if case .begin(_, _, let ids, _, _, _, _) = entries.first ?? .commit { untrustedIDs.append(contentsOf: ids) }
                        mode = .readOnly(reason: "journal failed authentication mid-file")
                        continue
                    }
                }
                journals.append((name, entries, truncated || failedAt != nil, bytes))
            }
            if journals.count > 1 { mode = .readOnly(reason: "multiple pending journals") }
            let pendingTarget: UInt64? = journals.first.flatMap { j in if case .begin(_, _, _, let t, _, _, _) = j.entries.first ?? .commit { return t } else { return nil } }

            // Ledger (GATE 1, P03-04b): present + authenticated + PROVEN by the manifest and the pending
            // journal (`LedgerBinding.verify`). Sticky distrust from the manifest is honoured first.
            var ledger = DeletionLedger()
            if !manifest.ledgerHistoryTrusted { ledgerTrusted = false }
            if try fs.kind(of: p(StoreLayout.systemDir, StoreLayout.ledgerFile)) == .missing {
                // NT-H1-03: a manifest that references a ledger which is gone → no deletion history can be
                // proven at all: read-only, restore refused.
                ledgerTrusted = false
                mode = .readOnly(reason: "deletion ledger missing")
            } else if let lb = try? readSystem(StoreLayout.ledgerFile), let l = try? DeletionLedger.decode(lb) {
                ledger = l
                if let reason = LedgerBinding.verify(manifest: manifest, diskLedgerHash: VaultDigest.sha256(lb), journal: journals.count == 1 ? journals[0].entries : nil, persistedEpoch: persistedEpoch) {
                    // Older-but-authentic ledger (with or without a pending journal), foreign journal, epoch
                    // mismatch: read-only, no restore, never "healed" by replay or by the next mutation.
                    ledgerTrusted = false
                    if case .readWrite = mode { mode = .readOnly(reason: reason) }
                }
            } else {
                // NT-H1-02: present but unauthenticated/undecodable → never "empty": every admission
                // quarantines, and the manifest records the distrust permanently at the next commit.
                ledgerTrusted = false
                if pendingTarget != nil, case .readWrite = mode {
                    // A replay would rebuild the history from an empty ledger: refuse instead.
                    mode = .readOnly(reason: "deletion ledger unreadable with a pending operation")
                }
            }

            func finish() -> Loaded {
                let epoch = persistedEpoch + 1
                let clock = MonotonicGuardClock(wrapping: composition.baseClock, toleranceSeconds: composition.toleranceSeconds, initialHighWaterSeconds: authz.clockHighWaterMark)
                let issuer = AuthorizationIssuer(clock: clock, epoch: epoch)
                let vault = SecureVault(keyProvider: keyProvider, consentAuthority: composition.consentAuthority, clock: clock, authorizations: issuer, quarantine: composition.quarantine)
                for id in untrustedIDs { composition.quarantine.quarantine(id, reason: .unverifiedDeletionHistory) }
                return Loaded(root: root, vault: vault, issuer: issuer, clock: clock, epoch: epoch, manifest: manifest, ledger: ledger, authz: authz, mode: mode, ledgerTrusted: ledgerTrusted, journals: journals, untrustedIDs: untrustedIDs)
            }

            // Anchor ↔ manifest binding (GATE B). An earlier read-only reason (journal damage) is kept.
            if case .readOnly = mode { return finish() }
            if let a = anchorValue {
                guard a.vaultInstanceID == manifest.vaultInstanceID else { throw VaultError.storeIntegrityFailed(reason: "anchor belongs to another vault instance") }
                if a.manifestGeneration == manifest.generation {
                    guard ConstantTime.equal(a.manifestHash, mHash) else { mode = .readOnly(reason: "manifest hash differs from anchor"); return finish() }
                } else if a.manifestGeneration + 1 == manifest.generation, ConstantTime.equal(manifest.prevHash, a.manifestHash), pendingTarget == manifest.generation {
                    // Crash between manifest write and anchor write: provable by the chain + the open journal; recovery finishes the tail.
                } else if a.manifestGeneration > manifest.generation {
                    mode = .readOnly(reason: "manifest rollback detected"); return finish()
                } else {
                    mode = .readOnly(reason: "manifest/anchor generation mismatch"); return finish()
                }
            } else {
                mode = .readOnly(reason: "anchor missing")
            }
            // Authz ↔ manifest binding (H3).
            if case .readWrite = mode {
                let authzOK = (authz.lastManifestGeneration == manifest.generation && ConstantTime.equal(authz.lastManifestHash, mHash))
                    || (authz.lastManifestGeneration + 1 == manifest.generation && ConstantTime.equal(authz.lastManifestHash, manifest.prevHash) && pendingTarget == manifest.generation)
                if !authzOK { mode = .readOnly(reason: "authorization state does not bind to the manifest") }
            }
            return finish()
        }

        /// Single-writer lock: "pid:epoch". Stale when the pid is gone or the epoch predates the persisted one.
        static func takeLock(root: String, fs: any VaultFileSystem, persistedEpoch: UInt64) throws {
            let lock = (root as NSString).appendingPathComponent(StoreLayout.lockFile)
            if try fs.kind(of: lock) == .regular {
                let text = String(decoding: try fs.readRegular(lock, maxBytes: 256), as: UTF8.self)
                let parts = text.split(separator: ":")
                let pid = parts.count == 2 ? Int32(parts[0]) : nil
                let ep = parts.count == 2 ? UInt64(parts[1]) : nil
                let stale = pid == nil || ep == nil || !fs.processExists(pid!) || ep! < persistedEpoch
                guard stale else { throw VaultError.storeLocked }
                try fs.remove(lock)
            } else if try fs.kind(of: lock) != .missing {
                throw VaultError.storeIntegrityFailed(reason: "lock path is not a regular file")
            }
            let fd = try fs.openExclusive(lock)
            try fs.write(fd, Array("\(fs.currentPID):\(persistedEpoch + 1)".utf8))
            try fs.close(fd)
        }
    }
}
