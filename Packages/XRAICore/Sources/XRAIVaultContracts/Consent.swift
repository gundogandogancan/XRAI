// P03-05A GATE 2 — production purpose & consent model (constitution §84, P03_03_CONSENT_AUTHORITY_SPEC
// §1, reconciled in P03_05A_CANONICAL_RECONCILIATION). Stdlib only.
//
// - A `PurposeDefinition` is versioned and immutable: what the user is shown for PurposeID@version is
//   exactly what a grant covers. A later version that WIDENS classes or destinations is a new consent
//   question; a grant for v1 never covers v2 (`PurposeRegistry.covers`).
// - A `ConsentEvent` is immutable and payload-free (ids, purpose, classes, destination, time, proof id,
//   hash of the previous event). Grants and revocations never modify earlier events; the active state
//   is DERIVED by replaying the chain (`ConsentLedger.activeGrant`).
// - Free text is never an authority: `purposeID` must resolve in the registry at the recorded version.

/// How derived results behave when the source consent ends.
public enum DerivedDataPolicy: String, Hashable, Sendable, CaseIterable {
    /// Derived records are deleted with the source (cascade) — the default for personal classes.
    case cascadeDelete = "CASCADE_DELETE"
    /// Derived records are invalidated (unreadable) and deleted at the next maintenance pass.
    case invalidate = "INVALIDATE"
}

/// What happens to stored records when the purpose is revoked (shown to the user before granting).
public enum RevocationConsequence: String, Hashable, Sendable, CaseIterable {
    /// Reads stop immediately; the user chooses "delete now" or (grace-eligible classes only) "suspend".
    case stopReadsThenUserChoosesDeleteOrSuspend = "STOP_READS_THEN_DELETE_OR_SUSPEND"
    /// Reads stop immediately and the records are deleted now (third-party classes).
    case stopReadsAndDeleteNow = "STOP_READS_AND_DELETE_NOW"
}

/// One versioned purpose the app may ask consent for. Immutable value; the registry holds all versions.
public struct PurposeDefinition: Hashable, Sendable {
    public let id: String
    public let version: UInt32
    public let titleTR: String
    public let titleEN: String
    public let explanationTR: String
    public let explanationEN: String
    public let allowedDataClasses: Set<DataClass>
    public let allowedDestinations: Set<Destination>
    public let retention: RetentionClass
    public let derivedPolicy: DerivedDataPolicy
    public let revocation: RevocationConsequence
    /// Whether the data may ever be sent to an AI model/provider under this purpose (always false today).
    public let sendsToAI: Bool

    public init(id: String, version: UInt32, titleTR: String, titleEN: String, explanationTR: String, explanationEN: String, allowedDataClasses: Set<DataClass>, allowedDestinations: Set<Destination>, retention: RetentionClass, derivedPolicy: DerivedDataPolicy, revocation: RevocationConsequence, sendsToAI: Bool = false) throws {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), version > 0 else { throw VaultError.limitExceeded("purpose id/version") }
        guard !allowedDataClasses.isEmpty, !allowedDestinations.isEmpty else { throw VaultError.limitExceeded("purpose scope") }
        guard allowedDestinations.isDisjoint(with: VaultPolicy.hardDeniedForPersonalData) else { throw VaultError.notAuthorized(.hardRule) }
        guard !allowedDataClasses.contains(.storeMetadata) else { throw VaultError.unsupportedSystemClass }
        self.id = id; self.version = version; self.titleTR = titleTR; self.titleEN = titleEN
        self.explanationTR = explanationTR; self.explanationEN = explanationEN
        self.allowedDataClasses = allowedDataClasses; self.allowedDestinations = allowedDestinations
        self.retention = retention; self.derivedPolicy = derivedPolicy; self.revocation = revocation; self.sendsToAI = sendsToAI
    }

    /// True when `later` asks for nothing beyond this version (a grant for this version still covers it).
    public func covers(_ later: PurposeDefinition) -> Bool {
        later.id == id && later.allowedDataClasses.isSubset(of: allowedDataClasses) && later.allowedDestinations.isSubset(of: allowedDestinations) && !(later.sendsToAI && !sendsToAI)
    }
}

/// Versioned, immutable registry shipped with the app. Lookups are by (id, version); `latest(id)`
/// is what the consent screen shows; a grant always records the version it was shown for.
public struct PurposeRegistry: Sendable {
    private let byKey: [String: PurposeDefinition]
    public let definitions: [PurposeDefinition]

    public init(_ definitions: [PurposeDefinition]) throws {
        var map: [String: PurposeDefinition] = [:]
        for d in definitions {
            let key = PurposeRegistry.key(d.id, d.version)
            guard map[key] == nil else { throw VaultError.limitExceeded("duplicate purpose version") }
            map[key] = d
        }
        byKey = map
        self.definitions = definitions.sorted { ($0.id, $0.version) < ($1.id, $1.version) }
    }

    static func key(_ id: String, _ version: UInt32) -> String { id + "@" + String(version) }

    public func definition(_ id: String, version: UInt32) -> PurposeDefinition? { byKey[PurposeRegistry.key(id, version)] }
    public func latest(_ id: String) -> PurposeDefinition? { definitions.filter { $0.id == id }.max { $0.version < $1.version } }
    public var purposeIDs: [String] { Array(Set(definitions.map(\.id))).sorted() }

    /// Whether a grant recorded for `grantedVersion` of `id` covers a request against `requestedVersion`.
    /// Same version → yes; an older grant covers a newer version only if the newer version asks for a
    /// subset (never widened); an unknown version never covers anything (fail closed).
    public func covers(id: String, grantedVersion: UInt32, requestedVersion: UInt32) -> Bool {
        guard let g = definition(id, version: grantedVersion), let r = definition(id, version: requestedVersion) else { return false }
        if grantedVersion == requestedVersion { return true }
        return g.covers(r)
    }
}

/// Immutable, payload-free consent event. The chain hash is computed by the ledger from the canonical
/// encoding of the previous event (stdlib only: FNV-1a 64-bit over canonical bytes; the AEAD envelope
/// around the whole ledger provides the cryptographic integrity, the chain provides ORDER evidence).
public struct ConsentEvent: Hashable, Sendable {
    public enum Kind: UInt8, Sendable, Hashable {
        case granted = 1
        case revoked = 2
    }
    public let id: String
    public let kind: Kind
    public let purposeID: String
    public let purposeVersion: UInt32
    public let dataClasses: Set<DataClass>
    public let destination: Destination
    public let atUnixSeconds: Int64
    /// Id of the interaction proof (or operation token) that authorized the event — an id, never a payload.
    public let authorizationID: String
    /// For `.revoked`: the id of the granted event being revoked.
    public let revokesEventID: String?
    /// Chain: FNV-1a 64 of the previous event's canonical bytes (0 for the first event).
    public let previousChain: UInt64

    public init(id: String, kind: Kind, purposeID: String, purposeVersion: UInt32, dataClasses: Set<DataClass>, destination: Destination, atUnixSeconds: Int64, authorizationID: String, revokesEventID: String?, previousChain: UInt64) {
        self.id = id; self.kind = kind; self.purposeID = purposeID; self.purposeVersion = purposeVersion; self.dataClasses = dataClasses
        self.destination = destination; self.atUnixSeconds = atUnixSeconds; self.authorizationID = authorizationID; self.revokesEventID = revokesEventID; self.previousChain = previousChain
    }

    public func encode(into e: inout CanonicalEncoder) {
        e.appendString(id); e.appendU8(kind.rawValue); e.appendString(purposeID); e.appendU32(purposeVersion)
        let classes = dataClasses.map(\.rawValue).sorted()
        e.appendU32(UInt32(classes.count)); for c in classes { e.appendString(c) }
        e.appendString(destination.rawValue); e.appendI64(atUnixSeconds); e.appendString(authorizationID)
        e.appendString(revokesEventID ?? ""); e.appendU64(previousChain)
    }

    public static func decode(from d: inout CanonicalDecoder) throws -> ConsentEvent {
        let id = try d.readString()
        guard let kind = Kind(rawValue: try d.readU8()) else { throw VaultError.storeIntegrityFailed(reason: "consent event kind") }
        let pid = try d.readString(); let pv = try d.readU32()
        let n = Int(try d.readU32()); guard n <= DataClass.allCases.count else { throw VaultError.limitExceeded("consent classes") }
        var classes = Set<DataClass>()
        for _ in 0..<n { guard let c = DataClass(rawValue: try d.readString()) else { throw VaultError.storeIntegrityFailed(reason: "consent class") }; classes.insert(c) }
        guard let dest = Destination(rawValue: try d.readString()) else { throw VaultError.storeIntegrityFailed(reason: "consent destination") }
        let at = try d.readI64(); let auth = try d.readString(); let rev = try d.readString(); let prev = try d.readU64()
        return ConsentEvent(id: id, kind: kind, purposeID: pid, purposeVersion: pv, dataClasses: classes, destination: dest, atUnixSeconds: at, authorizationID: auth, revokesEventID: rev.isEmpty ? nil : rev, previousChain: prev)
    }

    /// FNV-1a 64-bit over the canonical bytes (order evidence only; see the type comment).
    public var chainValue: UInt64 {
        var e = CanonicalEncoder(); encode(into: &e)
        var h: UInt64 = 0xcbf29ce484222325
        for b in e.bytes { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }
}

/// Append-only consent event chain. Active grants are DERIVED; nothing is ever edited.
public struct ConsentLedger: Hashable, Sendable {
    public static let magic = "XRAI-CONSENT-1"
    public private(set) var events: [ConsentEvent]

    public init(events: [ConsentEvent] = []) { self.events = events }

    public var lastChain: UInt64 { events.last?.chainValue ?? 0 }

    /// Appends an event whose `previousChain` must equal the current chain head (no insertion, no edit).
    public mutating func append(_ e: ConsentEvent) throws {
        guard e.previousChain == lastChain else { throw VaultError.storeIntegrityFailed(reason: "consent chain") }
        guard !events.contains(where: { $0.id == e.id }) else { throw VaultError.duplicateRecordID }
        if e.kind == .revoked {
            guard let target = e.revokesEventID, events.contains(where: { $0.id == target && $0.kind == .granted }) else { throw VaultError.storeIntegrityFailed(reason: "consent revoke target") }
        }
        events.append(e)
    }

    /// Replays the chain: a granted event is active until a later `revoked` event names it.
    public func activeGrants(atUnixSeconds now: Int64) -> [ConsentEvent] {
        var revoked = Set<String>()
        for e in events where e.kind == .revoked && e.atUnixSeconds <= now { if let t = e.revokesEventID { revoked.insert(t) } }
        return events.filter { $0.kind == .granted && $0.atUnixSeconds <= now && !revoked.contains($0.id) }
    }

    /// The grant that covers (class, purpose, destination) now under the registry's version rule, if any.
    public func activeGrant(for dataClass: DataClass, purpose: String, destination: Destination, atUnixSeconds now: Int64, registry: PurposeRegistry) -> ConsentGrant? {
        guard let requested = registry.latest(purpose) else { return nil }
        guard requested.allowedDataClasses.contains(dataClass), requested.allowedDestinations.contains(destination) else { return nil }
        for g in activeGrants(atUnixSeconds: now) where g.purposeID == purpose && g.dataClasses.contains(dataClass) && g.destination == destination {
            if registry.covers(id: purpose, grantedVersion: g.purposeVersion, requestedVersion: requested.version) {
                return ConsentGrant(receiptID: g.id, scope: ConsentScope(dataClass: dataClass, purpose: purpose, destination: destination))
            }
        }
        return nil
    }

    public func encode() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString(ConsentLedger.magic)
        e.appendU32(UInt32(events.count))
        for ev in events { ev.encode(into: &e) }
        return e.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> ConsentLedger {
        var d = CanonicalDecoder(bytes)
        guard try d.readString() == magic else { throw VaultError.storeIntegrityFailed(reason: "consent ledger magic") }
        let n = Int(try d.readU32()); guard n <= 1_000_000 else { throw VaultError.limitExceeded("consent events") }
        var l = ConsentLedger()
        for _ in 0..<n { try l.append(try ConsentEvent.decode(from: &d)) }   // re-validates the chain on load
        guard d.isAtEnd else { throw VaultError.storeIntegrityFailed(reason: "consent ledger trailing bytes") }
        return l
    }
}

/// The purposes XRAI ships today (version 1 each). Shown on the consent screen; a grant records the
/// version. Widening any of these requires a NEW version (and a new consent question), never an edit.
public enum XRAIPurposes {
    public static func registryV1() throws -> PurposeRegistry {
        try PurposeRegistry([
            try PurposeDefinition(id: "life_path_calculation", version: 1,
                titleTR: "Yaşam Yolu hesabı", titleEN: "Life Path calculation",
                explanationTR: "Doğum tarihin cihazında saklanır ve yalnızca sayısal Yaşam Yolu hesabı için kullanılır. Kişilik, sağlık veya kader iddiası üretmez.",
                explanationEN: "Your birth date is stored on this device and used only for the arithmetic Life Path calculation. It makes no personality, health or destiny claim.",
                allowedDataClasses: [.birthDate], allowedDestinations: [.deviceVault, .userEncryptedBackup], retention: .untilUserDeletes, derivedPolicy: .cascadeDelete, revocation: .stopReadsThenUserChoosesDeleteOrSuspend),
            try PurposeDefinition(id: "symbolic_family_lens", version: 1,
                titleTR: "Sembolik aile merceği", titleEN: "Symbolic family lens",
                explanationTR: "Ebeveyn isimleri ve kardeş sırası, yalnızca sembolik gelenek yorumları için ve senin seçimine bağlı olarak saklanır. Üçüncü kişilerin verisidir; askıya alma seçeneği yoktur, geri çekince hemen silinir.",
                explanationEN: "Parents' names and sibling order are stored only for symbolic-tradition readings and only by your choice. This is third-party data: no suspension option; revoking deletes it immediately.",
                allowedDataClasses: [.parentsNames, .siblingOrder], allowedDestinations: [.deviceVault], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsAndDeleteNow),
            try PurposeDefinition(id: "journal_reflection", version: 1,
                titleTR: "Günlük ve yansıma", titleEN: "Journal and reflection",
                explanationTR: "Günlük girdilerin cihazında şifreli saklanır; hiçbir modele gönderilmez. Geri çekince okumalar durur; silmeyi ya da askıya almayı sen seçersin.",
                explanationEN: "Your journal entries are stored encrypted on this device and never sent to any model. Revoking stops reads; you choose deletion or suspension.",
                allowedDataClasses: [.journal], allowedDestinations: [.deviceVault, .userEncryptedBackup], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsThenUserChoosesDeleteOrSuspend),
            try PurposeDefinition(id: "psychometric_exploration", version: 1,
                titleTR: "Psikometrik keşif", titleEN: "Psychometric exploration",
                explanationTR: "Anket cevapların yalnızca cihazında saklanır ve tanı değil, keşif amaçlıdır.",
                explanationEN: "Your questionnaire answers are stored only on this device, for exploration, not diagnosis.",
                allowedDataClasses: [.psychometrics], allowedDestinations: [.deviceVault, .userEncryptedBackup], retention: .untilConsentRevoked, derivedPolicy: .invalidate, revocation: .stopReadsThenUserChoosesDeleteOrSuspend),
            try PurposeDefinition(id: "spiritual_practice_log", version: 1,
                titleTR: "Uygulama kaydı", titleEN: "Practice log",
                explanationTR: "Seçtiğin uygulamalar (meditasyon, ritüel vb.) cihazında saklanır; hiçbir inanç iddiası taşımaz.",
                explanationEN: "The practices you choose to log are stored on this device; no belief claim is attached.",
                allowedDataClasses: [.spiritualPractices], allowedDestinations: [.deviceVault, .userEncryptedBackup], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsThenUserChoosesDeleteOrSuspend),
        ])
    }
}

// MARK: - Restore risks (moved from XRAIVaultStore in P03-05A so the app can present them without linking the store)

/// Risks noted at restore admission (P03-04b GATE 3; contract shared with the UI since P03-05A). Persisted in the manifest so that activation
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
    /// P03-04bH: the source vault held attachments that this backup does not contain (incomplete recovery).
    case attachmentsMissing = 128

    public static func mask(_ set: Set<RestoreRisk>) -> UInt16 { set.reduce(0) { $0 | $1.rawValue } }
    public static func set(_ mask: UInt16) -> Set<RestoreRisk> { Set(allCases.filter { mask & $0.rawValue != 0 }) }
}


