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
    public init(ledgerCompactionThreshold: Int = 200_000, ledgerRecentKept: Int = 100_000, ledgerDigestCapacity: Int = 1_000_000, maxRecordBytes: Int = BackupLimits.maxRecordCiphertextBytes) {
        self.ledgerCompactionThreshold = ledgerCompactionThreshold; self.ledgerRecentKept = ledgerRecentKept
        self.ledgerDigestCapacity = ledgerDigestCapacity; self.maxRecordBytes = maxRecordBytes
    }
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

public struct AdmissionReport: Sendable, Hashable {
    public let admittedActive: [RecordID]
    public let quarantined: [RecordID]
    public let skippedDeleted: [RecordID]
    public let skippedExisting: [RecordID]
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
    }

    // MARK: Paths

    private nonisolated func path(_ parts: String...) -> String { parts.reduce(root) { ($0 as NSString).appendingPathComponent($1) } }
    private nonisolated func recordPath(_ id: RecordID) -> String { path(StoreLayout.recordsDir, id.hex + StoreLayout.recordSuffix) }
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
        guard let e = manifest.records[id.hex] else { throw VaultError.recordMissing }
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

    /// Stores an already-sealed envelope (restore/migration paths). Requires a `.write(class)` token
    /// consumed through `SecureVault`; the payload is verified at read time by AEAD.
    public func putEnvelope(_ env: RecordEnvelope, authorization: OperationAuthorization, provenance: RecordProvenance = .created) throws {
        try requireWritable()
        try env.header.validate()
        _ = try vault.consumeAuthorization(authorization, for: .write(env.header.dataClass))
        try validateSources(env.header.derivedFrom, newCreatedAt: env.header.createdAtUnixSeconds, newID: env.header.recordID)
        guard manifest.records[env.header.recordID.hex] == nil else { throw VaultError.duplicateRecordID }
        try storeEnvelope(env, tokenID: authorization.id, provenance: provenance)
    }

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
            try fs.remove(recordPath(id))
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

    // MARK: Restore admission (H1) — fail-closed reconciliation foundations

    /// Admits records returned by `SecureVault.restoreBackup`. Known-deleted ids are skipped (never
    /// reactivated under their id); possibly-deleted ids, an untrusted local ledger, and backups from
    /// another/unknown vault instance (while this vault holds data) are quarantined pending per-class
    /// review. Existing ids are kept as they are.
    public func admitRestored(_ result: RestoreResult, sourceVaultInstanceID: [UInt8]?, authorization: OperationAuthorization) throws -> AdmissionReport {
        try requireWritable()
        _ = try vault.consumeAuthorization(authorization, for: .admitRestored)
        let foreign = !manifest.records.isEmpty && (sourceVaultInstanceID == nil || sourceVaultInstanceID! != manifest.vaultInstanceID)
        var active: [RecordID] = [], quarantined: [RecordID] = [], skippedDeleted: [RecordID] = [], skippedExisting: [RecordID] = []
        var toWrite: [(RecordEnvelope, Bool, DenialReason?)] = []
        for (env, preQuarantined) in result.active.map({ ($0, false) }) + result.quarantined.map({ ($0.envelope, true) }) {
            try env.header.validate()
            guard env.header.dataClass != .storeMetadata else { continue }
            let id = env.header.recordID
            if manifest.records[id.hex] != nil { skippedExisting.append(id); continue }
            switch ledger.lookup(id) {
            case .deleted: skippedDeleted.append(id); continue
            case .possiblyDeleted: toWrite.append((env, true, .possiblyDeleted)); continue
            case .notDeleted: break
            }
            if !ledgerTrusted { toWrite.append((env, true, .unverifiedDeletionHistory)); continue }
            if foreign { toWrite.append((env, true, .foreignBackupPendingReview)); continue }
            toWrite.append((env, preQuarantined, preQuarantined ? .consentRequired : nil))
        }
        guard !toWrite.isEmpty else { return AdmissionReport(admittedActive: [], quarantined: [], skippedDeleted: skippedDeleted, skippedExisting: skippedExisting) }
        let ids = toWrite.map { $0.0.header.recordID }
        let flags = toWrite.map { Int64($0.1 ? 1 : 0) }
        try runMutation(op: "admit", tokenID: authorization.id, ids: ids, params: flags) { m, _, step in
            for (i, (env, q, reason)) in toWrite.enumerated() {
                let id = env.header.recordID
                guard env.wrappedDEK.keyVersion >= m.minimumWrapVersion else { throw VaultError.staleKeyVersion(minimum: m.minimumWrapVersion) }
                try AtomicWriter.replace(self.fs, bytes: FileFraming.frame(EnvelopeCodec.encode(env)), at: self.recordPath(id), tempName: self.tempName())
                m.records[id.hex] = ManifestEntry(header: env.header, keyVersion: env.wrappedDEK.keyVersion, state: q ? .quarantined : .active, provenance: .restoredFromBackup)
                if q { self.composition.quarantine.quarantine(id, reason: reason ?? .consentRequired); quarantined.append(id) } else { active.append(id) }
                try step("file", UInt32(i))
            }
            return true
        }
        return AdmissionReport(admittedActive: active, quarantined: quarantined, skippedDeleted: skippedDeleted, skippedExisting: skippedExisting)
    }

    /// Releases ONE quarantined record: `.releaseQuarantine` token + active consent now (checked by
    /// `SecureVault.releaseQuarantine`), then the manifest state becomes active.
    public func releaseQuarantined(_ id: RecordID, authorization: OperationAuthorization) throws {
        try requireWritable()
        guard let e = manifest.records[id.hex] else { throw VaultError.recordMissing }
        guard e.state == .quarantined else { throw VaultError.recordNotActive(state: e.state.name) }
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

    private func rewrapBelowCurrent(maintenance: OperationAuthorization, op: String) throws -> Int {
        let current = vault.currentKeyIdentity.version
        let stale = manifest.records.filter { $0.value.keyVersion < current && $0.value.state != .pendingDelete }.keys.sorted().compactMap { try? RecordID(hex: $0) }
        var envs: [RecordEnvelope] = []
        for id in stale { envs.append(try readRecordFile(id)) }
        let rewrapped = try vault.rewrapBatch(envs, maintenance: maintenance)   // consumes the token even when the list is empty
        try runMutation(op: op, tokenID: maintenance.id, ids: stale, params: [Int64(current)]) { m, l, step in
            for (i, env) in rewrapped.enumerated() {
                let id = env.header.recordID
                try AtomicWriter.replace(self.fs, bytes: FileFraming.frame(EnvelopeCodec.encode(env)), at: self.recordPath(id), tempName: self.tempName())
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
        let count = try rewrapBelowCurrent(maintenance: maintenance, op: "prepare")
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
    private func runMutation(op: String, tokenID: String, ids: [RecordID], params: [Int64], body: (inout Manifest, inout DeletionLedger, (String, UInt32) throws -> Void) throws -> Bool) throws {
        let target = manifest.generation + 1
        var entries: [JournalEntry] = [.begin(op: op, tokenID: tokenID, ids: ids, targetGeneration: target, epoch: epoch, params: params)]
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
    }

    private func commitTail(target: UInt64, newManifest: Manifest, newLedger: DeletionLedger, ledgerChanged: Bool, entries: inout [JournalEntry]) throws {
        var m = newManifest
        // The ledger is re-sealed when it changed, is missing, or is still wrapped under an older key
        // version (so key retirement never finds a stale system envelope — H2 R2 covers system files).
        let ledgerStale = (systemFileKeyVersion(StoreLayout.ledgerFile) ?? 0) < vault.currentKeyIdentity.version
        if ledgerChanged || ledgerStale {
            try writeSystem(StoreLayout.ledgerFile, newLedger.encode())
            m.ledgerHash = newLedger.hash
        }
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
        // 2. Quarantine registry mirrors the manifest.
        for (key, e) in manifest.records where e.state == .quarantined { if let id = try? RecordID(hex: key) { composition.quarantine.quarantine(id, reason: .consentRequired) } }
        // 3. Files ↔ manifest.
        let rdir = path(StoreLayout.recordsDir)
        var seen = Set<String>()
        for name in try fs.listNames(rdir) {
            if name.hasPrefix(StoreLayout.tempPrefix) { continue }
            let p = (rdir as NSString).appendingPathComponent(name)
            guard try fs.kind(of: p) == .regular else { throw VaultError.storeIntegrityFailed(reason: "non-regular entry in records/") }
            let base = name.hasSuffix(StoreLayout.recordSuffix) ? String(name.dropLast(StoreLayout.recordSuffix.count)) : ""
            if let id = try? RecordID(hex: base), manifest.records[id.hex] != nil { seen.insert(id.hex); continue }
            // Orphan: never adopted, moved aside for the user to review/delete.
            if case .readWrite = modeValue {
                try fs.rename(p, path(StoreLayout.orphansDir, name.hasPrefix(".") ? "x" + name : name))
                orphansMoved += 1
            }
        }
        for key in manifest.records.keys where !seen.contains(key) { missingFiles.insert(key) }
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
        guard case .begin(let op, _, let ids, let target, _, let params) = j.entries.first ?? .commit else {
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
        switch op {
        case "put", "admit":
            // Files that exist are adopted from their authenticated headers; missing ones never happened.
            var m = manifest
            var any = false
            for (i, id) in ids.enumerated() {
                guard try fs.kind(of: recordPath(id)) == .regular, let env = try? readRecordFile(id) else { continue }
                let flag = i < params.count ? params[i] : 0
                let state: RecordState = (op == "admit" && flag == 1) ? .quarantined : .active
                let prov: RecordProvenance = op == "admit" ? .restoredFromBackup : (RecordProvenance(rawValue: UInt8(clamping: params.first ?? 0)) ?? .created)
                m.records[id.hex] = ManifestEntry(header: env.header, keyVersion: env.wrappedDEK.keyVersion, state: state, provenance: prov)
                any = true
            }
            if any { try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: false, entries: &entries) } else { try fs.remove(path(StoreLayout.journalDir, j.name)) }
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
        case "unsuspend", "release":
            var m = manifest
            for id in ids { if var e = m.records[id.hex] { e.state = .active; e.suspendedUntilUnixSeconds = 0; m.records[id.hex] = e } }
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: false, entries: &entries)
            journalsReplayed += 1
        case "freeze":
            var m = manifest
            if let v = params.first { m.minimumWrapVersion = max(m.minimumWrapVersion, UInt32(clamping: v)) }
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: false, entries: &entries)
            journalsReplayed += 1
        case "rewrap", "prepare":
            // Resumable, not replayable (needs a fresh maintenance token): sync key versions from the
            // authenticated file headers, drop the journal; the caller re-runs rewrap/retirement.
            var m = manifest
            for id in ids { if let env = try? readRecordFile(id), var e = m.records[id.hex] { e.keyVersion = env.wrappedDEK.keyVersion; m.records[id.hex] = e } }
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: false, entries: &entries)
            if op == "prepare" { pendingRetirement = UInt32(clamping: m.minimumWrapVersion > 0 ? Int64(m.minimumWrapVersion) - 1 : 0) }
            journalsReconciled += 1
        case "forget":
            var m = manifest
            let v = UInt32(clamping: params.first ?? 0)
            if j.entries.contains(.step(name: "forget", index: 0)) { if !m.retiredVersions.contains(v) { m.retiredVersions.append(v) } }
            else { pendingRetirement = v }   // retire may have happened; forget did not: nothing lost, re-run the protocol
            try commitTail(target: target, newManifest: m, newLedger: ledger, ledgerChanged: false, entries: &entries)
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
            for sub in [StoreLayout.recordsDir, StoreLayout.systemDir, StoreLayout.journalDir, StoreLayout.orphansDir] {
                let d = p(sub)
                switch try fs.kind(of: d) {
                case .missing: try fs.createDirectory(d)
                case .directory: break
                default: throw VaultError.storeIntegrityFailed(reason: "vault subdirectory is not a directory")
                }
            }
            try fs.excludeFromBackup(root)
            // Temp files from interrupted writes are garbage by construction.
            for sub in [StoreLayout.recordsDir, StoreLayout.systemDir, StoreLayout.journalDir, StoreLayout.orphansDir, ""] {
                let d = sub.isEmpty ? root : p(sub)
                for name in try fs.listNames(d) where name.hasPrefix(StoreLayout.tempPrefix) { try fs.remove((d as NSString).appendingPathComponent(name)) }
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
                    try anchor.clearAnchor()
                }
                for name in try fs.listNames(p(StoreLayout.recordsDir)) { try fs.remove(p(StoreLayout.recordsDir, name)) }   // nothing can be adopted without a manifest
                for name in try fs.listNames(p(StoreLayout.systemDir)) { try fs.remove(p(StoreLayout.systemDir, name)) }
                for name in try fs.listNames(p(StoreLayout.journalDir)) { try fs.remove(p(StoreLayout.journalDir, name)) }
                try takeLock(root: root, fs: fs, persistedEpoch: 0)
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
                return Loaded(root: root, vault: vault, issuer: issuer, clock: clock, epoch: epoch, manifest: manifest, ledger: ledger, authz: authz, mode: .readWrite, ledgerTrusted: true, journals: [])
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
                for (i, r) in raw.enumerated() {
                    do { entries.append(try JournalEntry.decode(try bootstrap.openSystem(try EnvelopeCodec.decode(r)))) }
                    catch { failedAt = i; break }
                }
                if let f = failedAt {
                    if f == raw.count - 1 && !truncated { /* a damaged LAST entry behaves like a truncated tail */ }
                    else if f < raw.count - 1 {
                        if case .begin(_, _, let ids, _, _, _) = entries.first ?? .commit { untrustedIDs.append(contentsOf: ids) }
                        mode = .readOnly(reason: "journal failed authentication mid-file")
                        continue
                    }
                }
                journals.append((name, entries, truncated || failedAt != nil, bytes))
            }
            if journals.count > 1 { mode = .readOnly(reason: "multiple pending journals") }
            let pendingTarget: UInt64? = journals.first.flatMap { j in if case .begin(_, _, _, let t, _, _) = j.entries.first ?? .commit { return t } else { return nil } }

            // Ledger: present + authenticated + bound (or bound by the pending journal's target).
            var ledger = DeletionLedger()
            if try fs.kind(of: p(StoreLayout.systemDir, StoreLayout.ledgerFile)) == .missing {
                // NT-H1-03: a manifest that references a ledger which is gone → no deletion history can be
                // proven at all: read-only, restore refused.
                ledgerTrusted = false
                mode = .readOnly(reason: "deletion ledger missing")
            } else if let lb = try? readSystem(StoreLayout.ledgerFile), let l = try? DeletionLedger.decode(lb) {
                ledger = l
                if !ConstantTime.equal(l.hash, manifest.ledgerHash) && pendingTarget != manifest.generation + 1 { ledgerTrusted = false }
            } else {
                // NT-H1-02: present but unauthenticated/undecodable → never "empty": every admission quarantines.
                ledgerTrusted = false
            }

            func finish() -> Loaded {
                let epoch = persistedEpoch + 1
                let clock = MonotonicGuardClock(wrapping: composition.baseClock, toleranceSeconds: composition.toleranceSeconds, initialHighWaterSeconds: authz.clockHighWaterMark)
                let issuer = AuthorizationIssuer(clock: clock, epoch: epoch)
                let vault = SecureVault(keyProvider: keyProvider, consentAuthority: composition.consentAuthority, clock: clock, authorizations: issuer, quarantine: composition.quarantine)
                for id in untrustedIDs { composition.quarantine.quarantine(id, reason: .unverifiedDeletionHistory) }
                return Loaded(root: root, vault: vault, issuer: issuer, clock: clock, epoch: epoch, manifest: manifest, ledger: ledger, authz: authz, mode: mode, ledgerTrusted: ledgerTrusted, journals: journals)
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
