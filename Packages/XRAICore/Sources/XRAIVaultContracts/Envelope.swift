// Envelope encryption contracts (constitution §83; hardening V32-02-01H). No cryptography lives here;
// only the shapes, the ports and the authenticated-metadata rules that an adapter must honour.

/// Typed vault errors. By design NO case carries a record identifier, key identifier, name or date:
/// error values may end up in logs (V32-02-01H §4).
public enum VaultError: Error, Equatable, Sendable {
    /// AEAD authentication failed: wrong key, tampered ciphertext/tag/nonce, or tampered header.
    case authenticationFailed
    case unsupportedFormat(UInt16)
    case unsupportedAlgorithm(String)
    /// The provider has no key for the requested version (identifier intentionally omitted).
    case keyUnavailable(version: UInt32)
    case invalidLength(field: String, expected: Int, actual: Int)
    case invalidRecordID
    case privacyTierBelowMinimum(dataClass: DataClass, required: PrivacyTier, got: PrivacyTier)
    case notAuthorized(DenialReason)
    case authorizationInvalid(AuthorizationFailure)
    /// The trusted clock reports time moved backwards beyond tolerance; no authority can be gained.
    case clockRegressed
    /// A consent-gated record without an active grant for its purpose (e.g. after restore).
    case quarantined(DenialReason)
    case duplicateRecordID
    case limitExceeded(String)
    /// An envelope offered for export did not verify (tampered or mismatched); export refused.
    case envelopeIntegrityFailed
    case backupCorrupted(reason: String)
    /// Backup AEAD failed: wrong recovery key OR altered backup. Indistinguishable by design.
    case backupIntegrityFailed
    case recoveryKeyInvalid(reason: String)
    /// Keychain refused or is not reachable (locked device, missing entitlement, access denied). Status is the raw OSStatus.
    case keychainUnavailable(status: Int32)
    /// A Keychain item exists but its content is not what this provider wrote (wrong length, bad encoding, mode mismatch).
    case keychainCorrupted(reason: String)
    /// An item for this key id/version already exists with different material; never overwritten.
    case keychainConflict
    /// Secure Enclave is required by configuration but not available on this device/runtime.
    case secureEnclaveUnavailable
    /// The clock guard refuses to return time below the observed high-water mark beyond tolerance.
    case clockUnavailable
    /// `forget` was called on a version that was never retired (two-phase forgetting, P03-00 §4).
    case keyVersionNotRetired(version: UInt32)

    // P03-04 store layer (ADR-BOOT-009 Amendment H). Still identifier-free.
    /// An envelope wrapped under a key version below the store's frozen minimum was offered for writing (H2 R1).
    case staleKeyVersion(minimum: UInt32)
    /// The store directory is not in a state the recovery pass can prove consistent (symlink, foreign file, binding mismatch).
    case storeIntegrityFailed(reason: String)
    /// The manifest on disk is older than the generation recorded by the anchor / authz state (H5).
    case manifestRollback
    /// The persisted authorization state (epoch, clock mark) does not bind to the manifest (H3).
    case authzStateUntrusted
    /// A journal failed authentication in the middle; the affected ids are quarantined until recovery (H5).
    case needsRecovery
    /// The record exists but is not `active` (suspended, stale, quarantined, corrupt, pending delete).
    case recordNotActive(state: String)
    /// The manifest lists the record but its file is missing.
    case recordMissing
    /// The store is read-only (binding mismatch, anchor missing) or locked by another writer.
    case storeReadOnly(reason: String)
    case storeLocked
    /// A key version still wraps records; it cannot be forgotten (H2 R4).
    case keyVersionInUse(version: UInt32, count: Int)
    /// A retirement proof no longer matches the manifest generation it was computed for (H2 R6).
    case proofStale
    /// The system seal/open path accepts only the `storeMetadata` class.
    case unsupportedSystemClass
    /// P03-04H (F-P04-02): a POSIX file operation the durability contract depends on failed. `operation`
    /// names the syscall step (open, write, fullfsync, fsync, dirsync, rename, unlink, close, …) and
    /// `errno` is the raw value. Never carries a path or record id.
    case ioFailed(operation: String, errno: Int32)
    /// `derivedFrom` names an unknown, non-active or later record (back-edge), or itself.
    case unknownDependency
    /// A deletion grant was already consumed or does not cover the ids.
    case deletionGrantInvalid
    /// The operation is not allowed for this data class (e.g. suspension of third-party data).
    case notEligible(reason: String)
}

/// How a key-encryption key is protected at rest. Surfaced by every `KeyProvider` so the app can
/// show the truth and tests can refuse silent downgrades.
public enum KeyProtection: Hashable, Sendable {
    /// Process memory only. Test/development double; never production.
    case inMemoryTestOnly
    /// macOS login (file-based) keychain used because the data-protection keychain needs an
    /// entitlement the test host lacks. Test-only; not device-bound.
    case keychainLegacyMacOSTestOnly
    /// Data-protection keychain, non-synchronizable, this-device-only, with the given accessibility.
    case keychainDeviceBound(accessibility: String)
    /// As above, and the KEK is additionally wrapped by a Secure Enclave P-256 key (non-extractable).
    case secureEnclaveWrapped(accessibility: String)

    public var isProductionGrade: Bool {
        switch self {
        case .inMemoryTestOnly, .keychainLegacyMacOSTestOnly: return false
        case .keychainDeviceBound, .secureEnclaveWrapped: return true
        }
    }
}

/// Port: trusted registry of quarantined record ids. The vault consults it on every read; a
/// `QuarantinedRecord` value held by a caller is not the source of truth.
public protocol QuarantineAuthority: Sendable {
    func isQuarantined(_ recordID: RecordID) -> Bool
    func quarantine(_ recordID: RecordID, reason: DenialReason)
    func release(_ recordID: RecordID)
}

/// Algorithm identifiers are part of the authenticated header so downgrade is detectable.
public enum EnvelopeAlgorithm: String, Hashable, Sendable {
    case aes256gcm = "AES-256-GCM"
}

/// Random, non-sensitive record identifier: 128 bits from the system CSPRNG, lower-case hex.
/// Contract: NEVER derived from content, names, dates or user identity. Redacted in descriptions.
public struct RecordID: Hashable, Sendable {
    public static let byteCount = 16
    public let hex: String

    /// Generates a fresh random identifier.
    public init() {
        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: RecordID.byteCount)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        self.hex = RecordID.hexString(bytes)
    }

    /// Accepts only exactly 32 lower-case hex characters.
    public init(hex: String) throws {
        guard hex.count == RecordID.byteCount * 2 else { throw VaultError.invalidRecordID }
        for c in hex.unicodeScalars {
            let v = c.value
            let isDigit = v >= 48 && v <= 57
            let isLowerHex = v >= 97 && v <= 102
            guard isDigit || isLowerHex else { throw VaultError.invalidRecordID }
        }
        self.hex = hex
    }

    static func hexString(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        var s = ""
        s.reserveCapacity(bytes.count * 2)
        for b in bytes { s.append(digits[Int(b >> 4)]); s.append(digits[Int(b & 0x0f)]) }
        return s
    }
}

extension RecordID: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "RecordID(redacted)" }
    public var debugDescription: String { "RecordID(redacted)" }
}

/// What a caller knows about a record before sealing it. Construction fails closed when the tier is
/// below the class floor. Key identity is NOT part of this: keys may rotate without re-encrypting.
public struct RecordDescriptor: Hashable, Sendable {
    public static let maxPurposeLength = 128
    /// P03-04: upper bound on `derivedFrom` entries (header v3).
    public static let maxDerivedFrom = 64

    public let recordID: RecordID
    public let dataClass: DataClass
    public let privacyTier: PrivacyTier
    public let retention: RetentionClass
    /// The purpose the user consented to for this record (empty for consent-free classes).
    /// Bound into the authenticated header so a record can never be read under another purpose.
    public let consentPurpose: String
    public let createdAtUnixSeconds: Int64
    /// P03-04 (header v3): source records this record was derived from. Authenticated; a derived
    /// record never outlives, outranks or out-consents its sources (lifecycle matrix §2).
    public let derivedFrom: [RecordID]
    /// P03-04 (header v3): application schema version of the plaintext. 0 = unspecified.
    public let schemaVersion: UInt16

    public init(recordID: RecordID = RecordID(), dataClass: DataClass, privacyTier: PrivacyTier? = nil, retention: RetentionClass, consentPurpose: String = "", createdAtUnixSeconds: Int64, derivedFrom: [RecordID] = [], schemaVersion: UInt16 = 0) throws {
        let tier = privacyTier ?? dataClass.minimumTier
        try VaultPolicy.validateTier(tier, for: dataClass)
        guard consentPurpose.utf8.count <= RecordDescriptor.maxPurposeLength else { throw VaultError.limitExceeded("purpose length") }
        if dataClass.requiresPurposeConsentToStore && consentPurpose.isEmpty { throw VaultError.notAuthorized(.consentRequired) }
        try EnvelopeHeader.validateDerivedFrom(derivedFrom, recordID: recordID)
        self.recordID = recordID
        self.dataClass = dataClass
        self.privacyTier = tier
        self.retention = retention
        self.consentPurpose = consentPurpose
        self.createdAtUnixSeconds = createdAtUnixSeconds
        self.derivedFrom = derivedFrom
        self.schemaVersion = schemaVersion
    }
}

/// Versioned, authenticated metadata. Its canonical bytes are the AEAD associated data for the
/// payload, so any change to any field makes `open` fail. Validated again on every read and import.
public struct EnvelopeHeader: Hashable, Sendable {
    /// v2 (H2): adds the authenticated `consentPurpose`. v1 envelopes are rejected (none were ever persisted).
    /// v3 (P03-04, ADR-BOOT-009 D2): adds authenticated `derivedFrom` and `schemaVersion`. A v2 header
    /// is byte-identical to before and is read as a leaf (no sources). v3 is produced only when a
    /// descriptor carries sources or a schema version, so existing records and tests are unchanged.
    public static let currentFormatVersion: UInt16 = 2
    public static let derivedFormatVersion: UInt16 = 3
    public static let supportedFormatVersions: Set<UInt16> = [2, 3]

    public let formatVersion: UInt16
    public let algorithm: EnvelopeAlgorithm
    public let recordID: RecordID
    public let dataClass: DataClass
    public let privacyTier: PrivacyTier
    public let retention: RetentionClass
    public let consentPurpose: String
    public let createdAtUnixSeconds: Int64
    /// v3 only (empty for v2).
    public let derivedFrom: [RecordID]
    /// v3 only (0 for v2).
    public let schemaVersion: UInt16

    public init(formatVersion: UInt16? = nil, algorithm: EnvelopeAlgorithm, descriptor d: RecordDescriptor) {
        let needsV3 = !d.derivedFrom.isEmpty || d.schemaVersion != 0
        self.formatVersion = formatVersion ?? (needsV3 ? EnvelopeHeader.derivedFormatVersion : EnvelopeHeader.currentFormatVersion)
        self.algorithm = algorithm
        self.recordID = d.recordID
        self.dataClass = d.dataClass
        self.privacyTier = d.privacyTier
        self.retention = d.retention
        self.consentPurpose = d.consentPurpose
        self.createdAtUnixSeconds = d.createdAtUnixSeconds
        self.derivedFrom = d.derivedFrom
        self.schemaVersion = d.schemaVersion
    }

    /// Unchecked constructor for decoding and adversarial tests; callers must run `validate()`.
    public init(formatVersion: UInt16, algorithm: EnvelopeAlgorithm, recordID: RecordID, dataClass: DataClass, privacyTier: PrivacyTier, retention: RetentionClass, consentPurpose: String, createdAtUnixSeconds: Int64, derivedFrom: [RecordID] = [], schemaVersion: UInt16 = 0) {
        self.formatVersion = formatVersion
        self.algorithm = algorithm
        self.recordID = recordID
        self.dataClass = dataClass
        self.privacyTier = privacyTier
        self.retention = retention
        self.consentPurpose = consentPurpose
        self.createdAtUnixSeconds = createdAtUnixSeconds
        self.derivedFrom = derivedFrom
        self.schemaVersion = schemaVersion
    }

    /// `derivedFrom` rules: bounded, no duplicates, never self-referential.
    public static func validateDerivedFrom(_ sources: [RecordID], recordID: RecordID) throws {
        guard sources.count <= RecordDescriptor.maxDerivedFrom else { throw VaultError.limitExceeded("derivedFrom count") }
        var seen = Set<String>()
        for s in sources {
            guard s != recordID else { throw VaultError.unknownDependency }
            guard seen.insert(s.hex).inserted else { throw VaultError.unknownDependency }
        }
    }

    /// Fail-closed structural validation: supported version/algorithm, tier floor, purpose rules.
    public func validate() throws {
        guard EnvelopeHeader.supportedFormatVersions.contains(formatVersion) else { throw VaultError.unsupportedFormat(formatVersion) }
        if formatVersion == EnvelopeHeader.currentFormatVersion {
            guard derivedFrom.isEmpty, schemaVersion == 0 else { throw VaultError.unsupportedFormat(formatVersion) }
        }
        guard algorithm == .aes256gcm else { throw VaultError.unsupportedAlgorithm(algorithm.rawValue) }
        try VaultPolicy.validateTier(privacyTier, for: dataClass)
        guard consentPurpose.utf8.count <= RecordDescriptor.maxPurposeLength else { throw VaultError.limitExceeded("purpose length") }
        if dataClass.requiresPurposeConsentToStore && consentPurpose.isEmpty { throw VaultError.notAuthorized(.consentRequired) }
        try EnvelopeHeader.validateDerivedFrom(derivedFrom, recordID: recordID)
    }

    public func canonicalBytes() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-ENV")
        encode(into: &e)
        return e.bytes
    }

    public func encode(into e: inout CanonicalEncoder) {
        e.appendU16(formatVersion)
        e.appendString(algorithm.rawValue)
        e.appendString(recordID.hex)
        e.appendString(dataClass.rawValue)
        e.appendString(privacyTier.rawValue)
        e.appendString(retention.rawValue)
        e.appendString(consentPurpose)
        e.appendI64(createdAtUnixSeconds)
        if formatVersion >= EnvelopeHeader.derivedFormatVersion {
            e.appendU16(schemaVersion)
            e.appendU32(UInt32(derivedFrom.count))
            for s in derivedFrom { e.appendString(s.hex) }
        }
    }

    /// Decodes AND validates (tier floor, version, algorithm). Import of a downgraded header fails here.
    public static func decode(from d: inout CanonicalDecoder) throws -> EnvelopeHeader {
        let v = try d.readU16()
        let algRaw = try d.readString()
        guard let alg = EnvelopeAlgorithm(rawValue: algRaw) else { throw VaultError.unsupportedAlgorithm(algRaw) }
        let rid = try RecordID(hex: try d.readString())
        guard let dc = DataClass(rawValue: try d.readString()) else { throw VaultError.backupCorrupted(reason: "data class") }
        guard let tier = PrivacyTier(rawValue: try d.readString()) else { throw VaultError.backupCorrupted(reason: "tier") }
        guard let ret = RetentionClass(rawValue: try d.readString()) else { throw VaultError.backupCorrupted(reason: "retention") }
        let purpose = try d.readString()
        let t = try d.readI64()
        var derived: [RecordID] = []
        var schema: UInt16 = 0
        if v >= EnvelopeHeader.derivedFormatVersion {
            schema = try d.readU16()
            let n = Int(try d.readU32())
            guard n <= RecordDescriptor.maxDerivedFrom else { throw VaultError.limitExceeded("derivedFrom count") }
            for _ in 0..<n { derived.append(try RecordID(hex: try d.readString())) }
        }
        let h = EnvelopeHeader(formatVersion: v, algorithm: alg, recordID: rid, dataClass: dc, privacyTier: tier, retention: ret, consentPurpose: purpose, createdAtUnixSeconds: t, derivedFrom: derived, schemaVersion: schema)
        try h.validate()
        return h
    }
}

/// A data-encryption key (DEK) wrapped by a key-encryption key (KEK) that a `KeyProvider` controls.
/// Bound to its record so DEKs cannot be swapped between records.
public struct WrappedKey: Hashable, Sendable {
    public let keyID: String
    public let keyVersion: UInt32
    public let boundRecordID: RecordID
    public let nonce: [UInt8]
    public let ciphertext: [UInt8]
    public let tag: [UInt8]

    public init(keyID: String, keyVersion: UInt32, boundRecordID: RecordID, nonce: [UInt8], ciphertext: [UInt8], tag: [UInt8]) {
        self.keyID = keyID
        self.keyVersion = keyVersion
        self.boundRecordID = boundRecordID
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    /// Associated data for wrapping: binds the wrapped DEK to key identity and record.
    public static func associatedData(keyID: String, keyVersion: UInt32, recordID: RecordID) -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-WRAP")
        e.appendString(keyID)
        e.appendU32(keyVersion)
        e.appendString(recordID.hex)
        return e.bytes
    }

    public func encode(into e: inout CanonicalEncoder) {
        e.appendString(keyID); e.appendU32(keyVersion); e.appendString(boundRecordID.hex)
        e.appendBytes(nonce); e.appendBytes(ciphertext); e.appendBytes(tag)
    }
    public static func decode(from d: inout CanonicalDecoder) throws -> WrappedKey {
        let keyID = try d.readString()
        guard keyID.count <= 64 else { throw VaultError.limitExceeded("keyID length") }
        return WrappedKey(keyID: keyID, keyVersion: try d.readU32(), boundRecordID: try RecordID(hex: try d.readString()),
                          nonce: try d.readBytes(), ciphertext: try d.readBytes(), tag: try d.readBytes())
    }
}

/// The stored form of one record. Holds NO plaintext and no key material.
public struct RecordEnvelope: Hashable, Sendable {
    public let header: EnvelopeHeader
    public let wrappedDEK: WrappedKey
    public let nonce: [UInt8]
    public let ciphertext: [UInt8]
    public let tag: [UInt8]

    public init(header: EnvelopeHeader, wrappedDEK: WrappedKey, nonce: [UInt8], ciphertext: [UInt8], tag: [UInt8]) {
        self.header = header
        self.wrappedDEK = wrappedDEK
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    /// Same payload, different key wrapping (key rotation / device migration).
    public func replacingWrappedDEK(_ w: WrappedKey) -> RecordEnvelope {
        RecordEnvelope(header: header, wrappedDEK: w, nonce: nonce, ciphertext: ciphertext, tag: tag)
    }

    public func encode(into e: inout CanonicalEncoder) {
        header.encode(into: &e)
        wrappedDEK.encode(into: &e)
        e.appendBytes(nonce); e.appendBytes(ciphertext); e.appendBytes(tag)
    }
    public static func decode(from d: inout CanonicalDecoder) throws -> RecordEnvelope {
        let h = try EnvelopeHeader.decode(from: &d)
        let w = try WrappedKey.decode(from: &d)
        return RecordEnvelope(header: h, wrappedDEK: w, nonce: try d.readBytes(), ciphertext: try d.readBytes(), tag: try d.readBytes())
    }
}

extension RecordEnvelope: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted: no record id, no key id, no timestamps. Class and tier only (not identifying).
    public var description: String {
        "RecordEnvelope(class: " + header.dataClass.rawValue + ", tier: " + header.privacyTier.rawValue
            + ", alg: " + header.algorithm.rawValue + ", keyVersion: " + String(wrappedDEK.keyVersion)
            + ", id: <redacted>, payload: <encrypted>)"
    }
    public var debugDescription: String { description }
}

// MARK: - Ports (implemented by adapters, mocked in tests)

/// Identity of a key-encryption key held by a provider (Keychain / Secure Enclave / memory / backup).
public struct KeyIdentity: Hashable, Sendable {
    public let keyID: String
    public let version: UInt32
    public init(keyID: String, version: UInt32) { self.keyID = keyID; self.version = version }
}

/// Port: wraps and unwraps data keys without ever exposing the KEK to callers.
/// A Secure Enclave-backed implementation can satisfy this with non-extractable keys.
public protocol KeyProvider: Sendable {
    var currentKey: KeyIdentity { get }
    /// Truthful statement of how the KEK is protected.
    var protection: KeyProtection { get }
    func wrapDataKey(_ dek: [UInt8], boundTo recordID: RecordID) throws -> WrappedKey
    func unwrapDataKey(_ wrapped: WrappedKey) throws -> [UInt8]
    /// Creates a new KEK version. Old versions stay available for unwrapping until `forget`.
    func rotate() throws -> KeyIdentity
    func forget(version: UInt32) throws
}

/// Port (P03-04): a key provider that supports two-phase forgetting. The store's retirement
/// coordinator is the only caller of `forget` and does so only with a verified store proof (H2).
public protocol RetirableKeyProvider: KeyProvider {
    func retire(version: UInt32) throws
    func isRetired(version: UInt32) throws -> Bool
}

/// Out-of-directory reference to the newest committed manifest (H5 rollback detection). Lives in
/// a separate persistence domain (Keychain in production). Holds no personal data.
public struct VaultAnchor: Hashable, Sendable {
    public static let instanceIDBytes = 16
    public static let hashBytes = 32
    public let vaultInstanceID: [UInt8]
    public let manifestGeneration: UInt64
    public let manifestHash: [UInt8]

    public init(vaultInstanceID: [UInt8], manifestGeneration: UInt64, manifestHash: [UInt8]) throws {
        guard vaultInstanceID.count == VaultAnchor.instanceIDBytes else { throw VaultError.invalidLength(field: "instance id", expected: VaultAnchor.instanceIDBytes, actual: vaultInstanceID.count) }
        guard manifestHash.count == VaultAnchor.hashBytes else { throw VaultError.invalidLength(field: "manifest hash", expected: VaultAnchor.hashBytes, actual: manifestHash.count) }
        self.vaultInstanceID = vaultInstanceID
        self.manifestGeneration = manifestGeneration
        self.manifestHash = manifestHash
    }

    public func encode() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-ANCHOR-1")
        e.appendBytes(vaultInstanceID)
        e.appendU64(manifestGeneration)
        e.appendBytes(manifestHash)
        return e.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> VaultAnchor {
        var d = CanonicalDecoder(bytes)
        guard try d.readString() == "XRAI-ANCHOR-1" else { throw VaultError.storeIntegrityFailed(reason: "anchor magic") }
        let id = try d.readBytes()
        let g = try d.readU64()
        let h = try d.readBytes()
        guard d.isAtEnd else { throw VaultError.storeIntegrityFailed(reason: "anchor trailing bytes") }
        return try VaultAnchor(vaultInstanceID: id, manifestGeneration: g, manifestHash: h)
    }
}

/// Port: where the anchor is kept. Production: Keychain (ThisDeviceOnly). Tests: memory.
public protocol VaultAnchorStore: Sendable {
    func readAnchor() throws -> VaultAnchor?
    func writeAnchor(_ anchor: VaultAnchor) throws
    func clearAnchor() throws
}

/// Port: seals and opens record payloads. Adapters expose this ONLY behind an authorized facade.
public protocol EnvelopeSealer: Sendable {
    func seal(plaintext: [UInt8], descriptor: RecordDescriptor) throws -> RecordEnvelope
    func open(_ envelope: RecordEnvelope) throws -> [UInt8]
    /// Re-wraps the DEK under the provider's current key without touching the payload.
    func rewrap(_ envelope: RecordEnvelope) throws -> RecordEnvelope
}

// MARK: - P03-04b GATE 4: chunked attachments

/// Plaintext payload of an attachment's HEADER record (a normal `RecordEnvelope` with its own DEK).
/// Chunks are sealed with a key derived from that DEK; nonce = `noncePrefix` ‖ chunk index.
public struct AttachmentLayout: Hashable, Sendable {
    public static let magic = "XRAI-ATT-1"
    public static let noncePrefixBytes = 8
    public let chunkBytes: UInt32
    public let chunkCount: UInt32
    public let totalBytes: UInt64
    public let noncePrefix: [UInt8]

    public init(chunkBytes: UInt32, chunkCount: UInt32, totalBytes: UInt64, noncePrefix: [UInt8]) throws {
        guard noncePrefix.count == AttachmentLayout.noncePrefixBytes else { throw VaultError.invalidLength(field: "noncePrefix", expected: AttachmentLayout.noncePrefixBytes, actual: noncePrefix.count) }
        guard chunkBytes > 0, chunkCount > 0 else { throw VaultError.limitExceeded("attachment layout") }
        let expected = totalBytes == 0 ? 1 : (totalBytes + UInt64(chunkBytes) - 1) / UInt64(chunkBytes)
        guard UInt64(chunkCount) == expected else { throw VaultError.limitExceeded("attachment chunk count") }
        self.chunkBytes = chunkBytes; self.chunkCount = chunkCount; self.totalBytes = totalBytes; self.noncePrefix = noncePrefix
    }

    /// Plaintext length of chunk `index` (the last one may be shorter; a 0-byte attachment has one empty chunk).
    public func length(ofChunk index: UInt32) -> Int {
        guard index < chunkCount else { return 0 }
        if index + 1 < chunkCount { return Int(chunkBytes) }
        let rem = totalBytes - UInt64(index) * UInt64(chunkBytes)
        return Int(rem)
    }

    public func encode() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString(AttachmentLayout.magic); e.appendU32(chunkBytes); e.appendU32(chunkCount); e.appendU64(totalBytes); e.appendBytes(noncePrefix)
        return e.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> AttachmentLayout {
        var d = CanonicalDecoder(bytes)
        guard try d.readString() == magic else { throw VaultError.storeIntegrityFailed(reason: "attachment layout magic") }
        let cb = try d.readU32(); let cc = try d.readU32(); let tb = try d.readU64(); let np = try d.readBytes()
        guard d.isAtEnd else { throw VaultError.storeIntegrityFailed(reason: "attachment layout trailing bytes") }
        return try AttachmentLayout(chunkBytes: cb, chunkCount: cc, totalBytes: tb, noncePrefix: np)
    }

    /// Associated data of chunk `index`: binds record id, index, count, sizes and the last-chunk flag,
    /// so chunks cannot be reordered, duplicated, dropped or moved between attachments.
    public func associatedData(recordID: RecordID, chunkIndex: UInt32) -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("xrai.attachment.chunk.v1"); e.appendBytes(Array(recordID.hex.utf8)); e.appendU32(chunkIndex); e.appendU32(chunkCount)
        e.appendU64(totalBytes); e.appendU32(chunkBytes); e.appendU8(chunkIndex + 1 == chunkCount ? 1 : 0)
        return e.bytes
    }

    /// 96-bit nonce of chunk `index`: random per-attachment prefix ‖ big-endian index (unique per chunk).
    public func nonce(forChunk index: UInt32) -> [UInt8] {
        noncePrefix + [UInt8(index >> 24), UInt8((index >> 16) & 0xFF), UInt8((index >> 8) & 0xFF), UInt8(index & 0xFF)]
    }
}

