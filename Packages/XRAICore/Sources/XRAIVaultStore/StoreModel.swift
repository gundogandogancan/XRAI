// Store model: manifest, deletion ledger (+ fail-closed Bloom digest), authorization state,
// journal entries. All are plaintext structures that the store seals as `storeMetadata` envelopes
// through `SecureVault.sealSystem`. Encodings are canonical so hashes are stable.
import Foundation
import XRAIVaultContracts
import XRAIVaultCryptoKit

public enum RecordState: UInt8, Sendable, Hashable {
    case active = 1
    case stale = 2
    case suspended = 3
    case quarantined = 4
    case pendingDelete = 5
    case corrupt = 6

    public var name: String {
        switch self {
        case .active: return "active"
        case .stale: return "stale"
        case .suspended: return "suspended"
        case .quarantined: return "quarantined"
        case .pendingDelete: return "pendingDelete"
        case .corrupt: return "corrupt"
        }
    }
}

public enum RecordProvenance: UInt8, Sendable, Hashable {
    case created = 0
    case restoredFromBackup = 1
    case reimportedAfterDeletion = 2
}

/// What a manifest entry describes (P03-04b): a record envelope file or a chunked attachment file.
public enum EntryKind: UInt8, Sendable, Hashable {
    case record = 0
    case attachment = 1
}

/// Risks noted at restore admission (P03-04b GATE 3). Persisted in the manifest so that activation
/// after a relaunch still requires the user to acknowledge exactly these.
public enum RestoreRisk: UInt16, Sendable, Hashable, CaseIterable {
    /// The backup names another vault instance while this vault already holds data.
    case foreignInstance = 1
    /// Legacy (v2) backup: no instance id, no generation, no embedded deletion history.
    case legacyFormat = 2
    /// This vault's own deletion history is not trusted (corrupt earlier, or unverifiable).
    case untrustedLocalHistory = 4
    /// The id hits the compacted deletion digest (possibly deleted).
    case possiblyDeleted = 8
    /// The backup's generation is older than the newest export this vault made.
    case olderBackupGeneration = 16
    /// The record arrived quarantined from the vault facade (consent not active at restore time).
    case consentInactiveAtRestore = 32
    /// The backup carried a history this vault could not (or must not) merge: untrusted at the
    /// source, or a compacted digest incompatible with the local one.
    case unmergedBackupHistory = 64

    public static func mask(_ set: Set<RestoreRisk>) -> UInt16 { set.reduce(0) { $0 | $1.rawValue } }
    public static func set(_ mask: UInt16) -> Set<RestoreRisk> { Set(allCases.filter { mask & $0.rawValue != 0 }) }
}

public struct ManifestEntry: Sendable, Hashable {
    public var dataClass: DataClass
    public var privacyTier: PrivacyTier
    public var retention: RetentionClass
    public var consentPurpose: String
    public var createdAtUnixSeconds: Int64
    public var keyVersion: UInt32
    public var state: RecordState
    public var suspendedUntilUnixSeconds: Int64
    public var schemaVersion: UInt16
    public var derivedFrom: [RecordID]
    public var provenance: RecordProvenance
    /// P03-04b: entry kind, attachment facts (0 for records) and restore risks still to be acknowledged.
    public var kind: EntryKind
    public var attachmentBytes: UInt64
    public var chunkCount: UInt32
    public var restoreRisks: UInt16

    public init(header h: EnvelopeHeader, keyVersion: UInt32, state: RecordState = .active, provenance: RecordProvenance = .created, kind: EntryKind = .record, attachmentBytes: UInt64 = 0, chunkCount: UInt32 = 0, restoreRisks: UInt16 = 0) {
        dataClass = h.dataClass; privacyTier = h.privacyTier; retention = h.retention; consentPurpose = h.consentPurpose
        createdAtUnixSeconds = h.createdAtUnixSeconds; self.keyVersion = keyVersion; self.state = state
        suspendedUntilUnixSeconds = 0; schemaVersion = h.schemaVersion; derivedFrom = h.derivedFrom; self.provenance = provenance
        self.kind = kind; self.attachmentBytes = attachmentBytes; self.chunkCount = chunkCount; self.restoreRisks = restoreRisks
    }
}

/// Encrypted manifest (H5): generation chain, frozen minimum wrap version, record table.
public struct Manifest: Sendable, Hashable {
    public static let magic = "XRAI-MANIFEST-2"
    /// P03-04b compatibility policy: an older manifest format is refused (`unsupportedFormat`), never converted silently.
    public static let legacyMagics = ["XRAI-MANIFEST-1"]
    public static let hashBytes = 32
    public static let zeroHash = [UInt8](repeating: 0, count: 32)

    public var generation: UInt64
    public var prevHash: [UInt8]
    public var vaultInstanceID: [UInt8]
    public var minimumWrapVersion: UInt32
    public var retiredVersions: [UInt32]
    public var lastExportedGeneration: UInt64
    public var ledgerHash: [UInt8]
    /// P03-04b GATE 1: once the deletion history was found corrupt or unverifiable, this stays false
    /// forever (sticky): a rewritten ledger can never launder a lost history back into "trusted".
    public var ledgerHistoryTrusted: Bool
    public var records: [String: ManifestEntry]   // key = RecordID.hex

    public init(generation: UInt64, prevHash: [UInt8], vaultInstanceID: [UInt8], minimumWrapVersion: UInt32, retiredVersions: [UInt32] = [], lastExportedGeneration: UInt64 = 0, ledgerHash: [UInt8], ledgerHistoryTrusted: Bool = true, records: [String: ManifestEntry] = [:]) {
        self.generation = generation; self.prevHash = prevHash; self.vaultInstanceID = vaultInstanceID
        self.minimumWrapVersion = minimumWrapVersion; self.retiredVersions = retiredVersions
        self.lastExportedGeneration = lastExportedGeneration; self.ledgerHash = ledgerHash; self.ledgerHistoryTrusted = ledgerHistoryTrusted; self.records = records
    }

    public func encode() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString(Manifest.magic)
        e.appendU64(generation); e.appendBytes(prevHash); e.appendBytes(vaultInstanceID)
        e.appendU32(minimumWrapVersion)
        e.appendU32(UInt32(retiredVersions.count)); for v in retiredVersions.sorted() { e.appendU32(v) }
        e.appendU64(lastExportedGeneration); e.appendBytes(ledgerHash); e.appendU8(ledgerHistoryTrusted ? 1 : 0)
        e.appendU32(UInt32(records.count))
        for key in records.keys.sorted() {
            let r = records[key]!
            e.appendString(key); e.appendString(r.dataClass.rawValue); e.appendString(r.privacyTier.rawValue); e.appendString(r.retention.rawValue)
            e.appendString(r.consentPurpose); e.appendI64(r.createdAtUnixSeconds); e.appendU32(r.keyVersion); e.appendU8(r.state.rawValue)
            e.appendI64(r.suspendedUntilUnixSeconds); e.appendU16(r.schemaVersion); e.appendU8(r.provenance.rawValue)
            e.appendU8(r.kind.rawValue); e.appendU64(r.attachmentBytes); e.appendU32(r.chunkCount); e.appendU16(r.restoreRisks)
            e.appendU32(UInt32(r.derivedFrom.count)); for s in r.derivedFrom { e.appendString(s.hex) }
        }
        return e.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> Manifest {
        var d = CanonicalDecoder(bytes)
        let m = try d.readString()
        if let i = legacyMagics.firstIndex(of: m) { throw VaultError.unsupportedFormat(UInt16(i + 1)) }
        guard m == magic else { throw VaultError.storeIntegrityFailed(reason: "manifest magic") }
        let gen = try d.readU64(); let prev = try d.readBytes(); let inst = try d.readBytes()
        guard prev.count == hashBytes, inst.count == VaultAnchor.instanceIDBytes else { throw VaultError.storeIntegrityFailed(reason: "manifest lengths") }
        let minV = try d.readU32()
        let nr = Int(try d.readU32()); guard nr <= 4096 else { throw VaultError.limitExceeded("retired versions") }
        var retired: [UInt32] = []; for _ in 0..<nr { retired.append(try d.readU32()) }
        let lastExp = try d.readU64(); let lh = try d.readBytes()
        guard lh.count == hashBytes else { throw VaultError.storeIntegrityFailed(reason: "ledger hash length") }
        let trustedByte = try d.readU8(); guard trustedByte <= 1 else { throw VaultError.storeIntegrityFailed(reason: "manifest trust flag") }
        let n = Int(try d.readU32()); guard n <= BackupLimits.maxEntries * 10 else { throw VaultError.limitExceeded("manifest entries") }
        var records: [String: ManifestEntry] = [:]
        for _ in 0..<n {
            let key = try RecordID(hex: try d.readString()).hex
            guard let dc = DataClass(rawValue: try d.readString()), let tier = PrivacyTier(rawValue: try d.readString()), let ret = RetentionClass(rawValue: try d.readString()) else {
                throw VaultError.storeIntegrityFailed(reason: "manifest enum")
            }
            let purpose = try d.readString(); let created = try d.readI64(); let kv = try d.readU32()
            guard let state = RecordState(rawValue: try d.readU8()) else { throw VaultError.storeIntegrityFailed(reason: "manifest state") }
            let until = try d.readI64(); let schema = try d.readU16()
            guard let prov = RecordProvenance(rawValue: try d.readU8()) else { throw VaultError.storeIntegrityFailed(reason: "manifest provenance") }
            guard let kind = EntryKind(rawValue: try d.readU8()) else { throw VaultError.storeIntegrityFailed(reason: "manifest entry kind") }
            let abytes = try d.readU64(); let chunks = try d.readU32(); let risks = try d.readU16()
            guard RestoreRisk.mask(RestoreRisk.set(risks)) == risks else { throw VaultError.storeIntegrityFailed(reason: "manifest risk bits") }
            let nd = Int(try d.readU32()); guard nd <= RecordDescriptor.maxDerivedFrom else { throw VaultError.limitExceeded("derivedFrom count") }
            var derived: [RecordID] = []; for _ in 0..<nd { derived.append(try RecordID(hex: try d.readString())) }
            let h = EnvelopeHeader(formatVersion: derived.isEmpty && schema == 0 ? 2 : 3, algorithm: .aes256gcm, recordID: try RecordID(hex: key), dataClass: dc, privacyTier: tier, retention: ret, consentPurpose: purpose, createdAtUnixSeconds: created, derivedFrom: derived, schemaVersion: schema)
            var entry = ManifestEntry(header: h, keyVersion: kv, state: state, provenance: prov, kind: kind, attachmentBytes: abytes, chunkCount: chunks, restoreRisks: risks)
            entry.suspendedUntilUnixSeconds = until
            guard records[key] == nil else { throw VaultError.storeIntegrityFailed(reason: "duplicate manifest entry") }
            records[key] = entry
        }
        guard d.isAtEnd else { throw VaultError.storeIntegrityFailed(reason: "manifest trailing bytes") }
        return Manifest(generation: gen, prevHash: prev, vaultInstanceID: inst, minimumWrapVersion: minV, retiredVersions: retired, lastExportedGeneration: lastExp, ledgerHash: lh, ledgerHistoryTrusted: trustedByte == 1, records: records)
    }

    public var hash: [UInt8] { VaultDigest.sha256(encode()) }

    /// Records whose `derivedFrom` contains `id` (reverse index, computed on demand).
    public func dependents(of id: RecordID) -> [RecordID] {
        records.compactMap { key, r in r.derivedFrom.contains(id) ? try? RecordID(hex: key) : nil }
    }

    /// Transitive dependents, dependents-first (leaves before their sources), roots last.
    public func cascadeOrder(from roots: Set<RecordID>) -> [RecordID] {
        var visited = Set<String>()
        var order: [RecordID] = []
        func visit(_ id: RecordID) {
            guard visited.insert(id.hex).inserted else { return }
            for dep in dependents(of: id) { visit(dep) }
            order.append(id)
        }
        for r in roots.sorted(by: { $0.hex < $1.hex }) { visit(r) }
        return order
    }

    public var keyUsage: [UInt32: Int] {
        var out: [UInt32: Int] = [:]
        for r in records.values { out[r.keyVersion, default: 0] += 1 }
        return out
    }
}

/// Bloom filter with SHA-256 double hashing. Used ONLY as a fail-closed digest of compacted deletion
/// history: a hit means "possibly deleted" → quarantine, never "live".
public struct BloomFilter: Sendable, Hashable {
    public let bitCount: UInt64
    public let hashCount: UInt32
    public private(set) var insertedCount: UInt64
    public private(set) var bits: [UInt8]

    /// Sized for `expectedEntries` at `falsePositiveRate` (default 1e-6 → ~28.8 bits/entry, k = 20).
    public init(expectedEntries: Int, falsePositiveRate: Double = 1e-6) {
        let n = Double(max(expectedEntries, 1))
        let m = (-n * log(falsePositiveRate) / (log(2) * log(2))).rounded(.up)
        let k = max(1, Int((m / n * log(2)).rounded()))
        self.bitCount = UInt64(m)
        self.hashCount = UInt32(k)
        self.insertedCount = 0
        self.bits = [UInt8](repeating: 0, count: Int((m / 8).rounded(.up)))
    }

    init(bitCount: UInt64, hashCount: UInt32, insertedCount: UInt64, bits: [UInt8]) {
        self.bitCount = bitCount; self.hashCount = hashCount; self.insertedCount = insertedCount; self.bits = bits
    }

    private func indices(_ id: RecordID) -> [UInt64] {
        let h = VaultDigest.sha256(Array(id.hex.utf8))
        var h1: UInt64 = 0, h2: UInt64 = 0
        for i in 0..<8 { h1 = (h1 << 8) | UInt64(h[i]); h2 = (h2 << 8) | UInt64(h[8 + i]) }
        if h2 == 0 { h2 = 0x9E37_79B9_7F4A_7C15 }
        return (0..<hashCount).map { i in (h1 &+ UInt64(i) &* h2) % bitCount }
    }

    public mutating func insert(_ id: RecordID) {
        for i in indices(id) { bits[Int(i / 8)] |= UInt8(1 << (i % 8)) }
        insertedCount += 1
    }

    /// Bitwise union of two digests with identical geometry (P03-04b history merge).
    public mutating func formUnion(_ other: BloomFilter) -> Bool {
        guard other.bitCount == bitCount, other.hashCount == hashCount, other.bits.count == bits.count else { return false }
        for i in 0..<bits.count { bits[i] |= other.bits[i] }
        insertedCount += other.insertedCount
        return true
    }

    public func mayContain(_ id: RecordID) -> Bool {
        for i in indices(id) where bits[Int(i / 8)] & UInt8(1 << (i % 8)) == 0 { return false }
        return true
    }
}

public enum DeletionLookup: Sendable, Equatable { case deleted, possiblyDeleted, notDeleted }

/// Permanent deletion history (H1). Exact entries forever by default; above the compaction threshold
/// the oldest entries fold into a Bloom digest whose false positives quarantine, never resurrect.
public struct DeletionLedger: Sendable, Hashable {
    public static let magic = "XRAI-LEDGER-1"
    public struct Entry: Sendable, Hashable {
        public let recordID: RecordID
        public let deletedAtUnixSeconds: Int64
        public let manifestGeneration: UInt64
        public init(recordID: RecordID, deletedAtUnixSeconds: Int64, manifestGeneration: UInt64) {
            self.recordID = recordID; self.deletedAtUnixSeconds = deletedAtUnixSeconds; self.manifestGeneration = manifestGeneration
        }
    }
    public private(set) var entries: [Entry]
    public private(set) var digest: BloomFilter?
    public private(set) var digestedCount: UInt64
    /// Exact-entry index (not encoded; rebuilt on decode) so lookups are O(1).
    private var index: Set<String>

    public init(entries: [Entry] = [], digest: BloomFilter? = nil, digestedCount: UInt64 = 0) {
        self.entries = entries; self.digest = digest; self.digestedCount = digestedCount
        self.index = Set(entries.map { $0.recordID.hex })
    }

    public static func == (a: DeletionLedger, b: DeletionLedger) -> Bool { a.entries == b.entries && a.digest == b.digest && a.digestedCount == b.digestedCount }
    public func hash(into h: inout Hasher) { h.combine(entries.count); h.combine(digestedCount) }

    public var totalCount: Int { entries.count + Int(digestedCount) }

    public func lookup(_ id: RecordID) -> DeletionLookup {
        if index.contains(id.hex) { return .deleted }
        if let d = digest, d.mayContain(id) { return .possiblyDeleted }
        return .notDeleted
    }

    /// Idempotent append (an id already present is not duplicated).
    public mutating func append(_ e: Entry) {
        guard lookup(e.recordID) == .notDeleted else { return }
        entries.append(e)
        index.insert(e.recordID.hex)
    }

    /// P03-04b: merges another vault's (or an older export's) history into this one. Exact entries are
    /// appended idempotently at `manifestGeneration`; a digest is adopted or OR-ed when the geometry
    /// matches. Returns false when the other digest could not be merged (its entries still were).
    public mutating func merge(_ other: DeletionLedger, manifestGeneration g: UInt64) -> Bool {
        var ok = true
        if let od = other.digest {
            if digest == nil { digest = od; digestedCount += other.digestedCount }
            else if digest!.formUnion(od) { digestedCount += other.digestedCount }
            else { ok = false }
        }
        for e in other.entries { append(Entry(recordID: e.recordID, deletedAtUnixSeconds: e.deletedAtUnixSeconds, manifestGeneration: g)) }
        return ok
    }

    /// Fold the oldest entries into the digest once the exact list exceeds `threshold`, keeping
    /// `keepRecent` exact entries. The digest is sized for `digestCapacity` total entries.
    public mutating func compactIfNeeded(threshold: Int, keepRecent: Int, digestCapacity: Int) {
        guard entries.count > threshold, entries.count > keepRecent else { return }
        let fold = entries.count - keepRecent
        var d = digest ?? BloomFilter(expectedEntries: max(digestCapacity, fold))
        for e in entries.prefix(fold) { d.insert(e.recordID); index.remove(e.recordID.hex) }
        entries.removeFirst(fold)
        digest = d
        digestedCount += UInt64(fold)
    }

    public func encode() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString(DeletionLedger.magic)
        if let d = digest {
            e.appendU8(1); e.appendU64(d.bitCount); e.appendU32(d.hashCount); e.appendU64(d.insertedCount); e.appendBytes(d.bits)
        } else { e.appendU8(0) }
        e.appendU64(digestedCount)
        e.appendU32(UInt32(entries.count))
        for en in entries { e.appendString(en.recordID.hex); e.appendI64(en.deletedAtUnixSeconds); e.appendU64(en.manifestGeneration) }
        return e.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> DeletionLedger {
        var d = CanonicalDecoder(bytes)
        guard try d.readString() == magic else { throw VaultError.storeIntegrityFailed(reason: "ledger magic") }
        var digest: BloomFilter?
        if try d.readU8() == 1 {
            let m = try d.readU64(); let k = try d.readU32(); let c = try d.readU64(); let bits = try d.readBytes()
            guard m > 0, k > 0, k <= 64, UInt64(bits.count) * 8 >= m else { throw VaultError.storeIntegrityFailed(reason: "ledger digest") }
            digest = BloomFilter(bitCount: m, hashCount: k, insertedCount: c, bits: bits)
        }
        let dc = try d.readU64()
        let n = Int(try d.readU32()); guard n <= 10_000_000 else { throw VaultError.limitExceeded("ledger entries") }
        var entries: [Entry] = []; entries.reserveCapacity(n)
        for _ in 0..<n { entries.append(Entry(recordID: try RecordID(hex: try d.readString()), deletedAtUnixSeconds: try d.readI64(), manifestGeneration: try d.readU64())) }
        guard d.isAtEnd else { throw VaultError.storeIntegrityFailed(reason: "ledger trailing bytes") }
        return DeletionLedger(entries: entries, digest: digest, digestedCount: dc)
    }

    public var hash: [UInt8] { VaultDigest.sha256(encode()) }
}

/// Persisted authorization state (H3): epoch, clock high-water mark, manifest binding. Never exported.
public struct AuthzState: Sendable, Hashable {
    public static let magic = "XRAI-AUTHZ-1"
    public var epoch: UInt64
    public var clockHighWaterMark: Int64?
    public var lastManifestGeneration: UInt64
    public var lastManifestHash: [UInt8]

    public init(epoch: UInt64, clockHighWaterMark: Int64?, lastManifestGeneration: UInt64, lastManifestHash: [UInt8]) {
        self.epoch = epoch; self.clockHighWaterMark = clockHighWaterMark; self.lastManifestGeneration = lastManifestGeneration; self.lastManifestHash = lastManifestHash
    }

    public func encode() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString(AuthzState.magic); e.appendU64(epoch)
        if let m = clockHighWaterMark { e.appendU8(1); e.appendI64(m) } else { e.appendU8(0) }
        e.appendU64(lastManifestGeneration); e.appendBytes(lastManifestHash)
        return e.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> AuthzState {
        var d = CanonicalDecoder(bytes)
        guard try d.readString() == magic else { throw VaultError.storeIntegrityFailed(reason: "authz magic") }
        let epoch = try d.readU64()
        let mark: Int64? = try d.readU8() == 1 ? try d.readI64() : nil
        let g = try d.readU64(); let h = try d.readBytes()
        guard h.count == Manifest.hashBytes, d.isAtEnd else { throw VaultError.storeIntegrityFailed(reason: "authz shape") }
        return AuthzState(epoch: epoch, clockHighWaterMark: mark, lastManifestGeneration: g, lastManifestHash: h)
    }
}

/// Journal entries (H5). A journal file holds a sequence of length-prefixed sealed entries.
public enum JournalEntry: Sendable, Hashable {
    /// Operation start: kind, consumed token id, affected ids, target manifest generation, epoch,
    /// parameters, and (P03-04b GATE 1) the hash of the deletion ledger the manifest binds BEFORE the op.
    case begin(op: String, tokenID: String, ids: [RecordID], targetGeneration: UInt64, epoch: UInt64, params: [Int64], ledgerHash: [UInt8])
    case step(name: String, index: UInt32)
    /// Written BEFORE the ledger file is replaced: announces the exact post-state hash. Recovery
    /// accepts the ledger on disk only as the pre-state (begin) or this announced post-state.
    case ledgerWritten(hash: [UInt8])
    case manifestWritten(generation: UInt64)
    case commit

    static let magic = "XRAI-J-2"
    /// Compatibility policy: a journal of an older format opens the vault read-only; it is never converted.
    static let legacyMagics = ["XRAI-J-1"]

    public func encode() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString(JournalEntry.magic)
        switch self {
        case .begin(let op, let token, let ids, let g, let epoch, let params, let lh):
            e.appendU8(1); e.appendString(op); e.appendString(token); e.appendU32(UInt32(ids.count)); for i in ids { e.appendString(i.hex) }
            e.appendU64(g); e.appendU64(epoch); e.appendU32(UInt32(params.count)); for p in params { e.appendI64(p) }
            e.appendBytes(lh)
        case .step(let name, let index): e.appendU8(2); e.appendString(name); e.appendU32(index)
        case .manifestWritten(let g): e.appendU8(3); e.appendU64(g)
        case .commit: e.appendU8(4)
        case .ledgerWritten(let h): e.appendU8(5); e.appendBytes(h)
        }
        return e.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> JournalEntry {
        var d = CanonicalDecoder(bytes)
        let m = try d.readString()
        if let i = legacyMagics.firstIndex(of: m) { throw VaultError.unsupportedFormat(UInt16(i + 1)) }
        guard m == magic else { throw VaultError.storeIntegrityFailed(reason: "journal magic") }
        switch try d.readU8() {
        case 1:
            let op = try d.readString(); let token = try d.readString()
            let n = Int(try d.readU32()); guard n <= BackupLimits.maxEntries else { throw VaultError.limitExceeded("journal ids") }
            var ids: [RecordID] = []; for _ in 0..<n { ids.append(try RecordID(hex: try d.readString())) }
            let g = try d.readU64(); let epoch = try d.readU64()
            let np = Int(try d.readU32()); guard np <= 64 else { throw VaultError.limitExceeded("journal params") }
            var params: [Int64] = []; for _ in 0..<np { params.append(try d.readI64()) }
            let lh = try d.readBytes(); guard lh.count == Manifest.hashBytes else { throw VaultError.storeIntegrityFailed(reason: "journal ledger hash") }
            return .begin(op: op, tokenID: token, ids: ids, targetGeneration: g, epoch: epoch, params: params, ledgerHash: lh)
        case 2: return .step(name: try d.readString(), index: try d.readU32())
        case 3: return .manifestWritten(generation: try d.readU64())
        case 4: return .commit
        case 5:
            let h = try d.readBytes(); guard h.count == Manifest.hashBytes else { throw VaultError.storeIntegrityFailed(reason: "journal ledger hash") }
            return .ledgerWritten(hash: h)
        default: throw VaultError.storeIntegrityFailed(reason: "journal kind")
        }
    }
}

/// GATE 1 (P03-04b, closes LEDGER_ONLY_ROLLBACK): decides whether the deletion ledger on disk is a
/// state the manifest and the pending journal PROVE. Pure function; `nil` = proven, otherwise the
/// read-only reason. Rules:
/// - no pending journal → the ledger must be exactly the one the manifest binds;
/// - pending journal for generation g+1 → its begin must name the manifest's ledger hash (pre-state),
///   and the disk ledger must be that pre-state or the post-state the journal announced before writing;
/// - pending journal for generation g (manifest durable) → the manifest must bind the announced
///   post-state (or the pre-state when nothing was announced) and the disk must match it;
/// - the journal's epoch must be the persisted epoch; any other generation is stale.
/// An older-but-authentic ledger therefore never becomes trusted through a journal replay.
public enum LedgerBinding {
    public static func verify(manifest: Manifest, diskLedgerHash: [UInt8], journal: [JournalEntry]?, persistedEpoch: UInt64) -> String? {
        guard let j = journal, let first = j.first, case .begin(_, _, _, let target, let epoch, _, let pre) = first else {
            return ConstantTime.equal(diskLedgerHash, manifest.ledgerHash) ? nil : "deletion ledger does not bind to the manifest"
        }
        guard epoch == persistedEpoch else { return "journal does not bind to the authorization state" }
        var post: [UInt8]? = nil
        for e in j { if case .ledgerWritten(let h) = e { post = h } }
        if target == manifest.generation + 1 {
            guard ConstantTime.equal(pre, manifest.ledgerHash) else { return "journal does not bind to the manifest" }
            if ConstantTime.equal(diskLedgerHash, pre) { return nil }
            if let p = post, ConstantTime.equal(diskLedgerHash, p) { return nil }
            return "deletion ledger state is not proven by the journal"
        } else if target == manifest.generation {
            let expected = post ?? pre
            guard ConstantTime.equal(manifest.ledgerHash, expected) else { return "journal does not bind to the manifest" }
            return ConstantTime.equal(diskLedgerHash, manifest.ledgerHash) ? nil : "deletion ledger does not bind to the manifest"
        }
        return "stale journal generation"
    }
}

/// Framing shared by every file in the store: [u32 length][payload][zero padding to 4 KiB].
enum FileFraming {
    static let block = BackupLimits.paddingBlockBytes

    static func frame(_ payload: [UInt8]) -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendBytes(payload)
        var out = e.bytes
        let rem = out.count % block
        if rem != 0 { out.append(contentsOf: [UInt8](repeating: 0, count: block - rem)) }
        return out
    }

    static func unframe(_ bytes: [UInt8]) throws -> [UInt8] {
        var d = CanonicalDecoder(bytes)
        let payload = try d.readBytes()
        // Padding must be zeros (a truncated or appended file fails here or at AEAD).
        let rest = bytes[(4 + payload.count)...]
        guard rest.allSatisfy({ $0 == 0 }) else { throw VaultError.storeIntegrityFailed(reason: "padding") }
        return payload
    }

    /// Journal framing: repeated [u32 length][sealed entry]. Returns entries plus whether the tail was truncated.
    static func unframeJournal(_ bytes: [UInt8]) -> (entries: [[UInt8]], truncatedTail: Bool) {
        var out: [[UInt8]] = []
        var cursor = 0
        while cursor < bytes.count {
            guard cursor + 4 <= bytes.count else { return (out, true) }
            let n = Int(UInt32(bytes[cursor]) << 24 | UInt32(bytes[cursor + 1]) << 16 | UInt32(bytes[cursor + 2]) << 8 | UInt32(bytes[cursor + 3]))
            cursor += 4
            guard n > 0, cursor + n <= bytes.count else { return (out, true) }
            out.append(Array(bytes[cursor..<cursor + n]))
            cursor += n
        }
        return (out, false)
    }

    static func frameJournal(_ entries: [[UInt8]]) -> [UInt8] {
        var e = CanonicalEncoder()
        for en in entries { e.appendBytes(en) }
        return e.bytes
    }
}

enum EnvelopeCodec {
    static func encode(_ env: RecordEnvelope) -> [UInt8] { var e = CanonicalEncoder(); env.encode(into: &e); return e.bytes }
    static func decode(_ bytes: [UInt8]) throws -> RecordEnvelope {
        var d = CanonicalDecoder(bytes)
        let env = try RecordEnvelope.decode(from: &d)
        guard d.isAtEnd else { throw VaultError.storeIntegrityFailed(reason: "envelope trailing bytes") }
        return env
    }
}
