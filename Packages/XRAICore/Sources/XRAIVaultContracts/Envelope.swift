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

    public let recordID: RecordID
    public let dataClass: DataClass
    public let privacyTier: PrivacyTier
    public let retention: RetentionClass
    /// The purpose the user consented to for this record (empty for consent-free classes).
    /// Bound into the authenticated header so a record can never be read under another purpose.
    public let consentPurpose: String
    public let createdAtUnixSeconds: Int64

    public init(recordID: RecordID = RecordID(), dataClass: DataClass, privacyTier: PrivacyTier? = nil, retention: RetentionClass, consentPurpose: String = "", createdAtUnixSeconds: Int64) throws {
        let tier = privacyTier ?? dataClass.minimumTier
        try VaultPolicy.validateTier(tier, for: dataClass)
        guard consentPurpose.utf8.count <= RecordDescriptor.maxPurposeLength else { throw VaultError.limitExceeded("purpose length") }
        if dataClass.requiresPurposeConsentToStore && consentPurpose.isEmpty { throw VaultError.notAuthorized(.consentRequired) }
        self.recordID = recordID
        self.dataClass = dataClass
        self.privacyTier = tier
        self.retention = retention
        self.consentPurpose = consentPurpose
        self.createdAtUnixSeconds = createdAtUnixSeconds
    }
}

/// Versioned, authenticated metadata. Its canonical bytes are the AEAD associated data for the
/// payload, so any change to any field makes `open` fail. Validated again on every read and import.
public struct EnvelopeHeader: Hashable, Sendable {
    /// v2 (H2): adds the authenticated `consentPurpose`. v1 envelopes are rejected (none were ever persisted).
    public static let currentFormatVersion: UInt16 = 2

    public let formatVersion: UInt16
    public let algorithm: EnvelopeAlgorithm
    public let recordID: RecordID
    public let dataClass: DataClass
    public let privacyTier: PrivacyTier
    public let retention: RetentionClass
    public let consentPurpose: String
    public let createdAtUnixSeconds: Int64

    public init(formatVersion: UInt16 = EnvelopeHeader.currentFormatVersion, algorithm: EnvelopeAlgorithm, descriptor d: RecordDescriptor) {
        self.formatVersion = formatVersion
        self.algorithm = algorithm
        self.recordID = d.recordID
        self.dataClass = d.dataClass
        self.privacyTier = d.privacyTier
        self.retention = d.retention
        self.consentPurpose = d.consentPurpose
        self.createdAtUnixSeconds = d.createdAtUnixSeconds
    }

    /// Unchecked constructor for decoding and adversarial tests; callers must run `validate()`.
    public init(formatVersion: UInt16, algorithm: EnvelopeAlgorithm, recordID: RecordID, dataClass: DataClass, privacyTier: PrivacyTier, retention: RetentionClass, consentPurpose: String, createdAtUnixSeconds: Int64) {
        self.formatVersion = formatVersion
        self.algorithm = algorithm
        self.recordID = recordID
        self.dataClass = dataClass
        self.privacyTier = privacyTier
        self.retention = retention
        self.consentPurpose = consentPurpose
        self.createdAtUnixSeconds = createdAtUnixSeconds
    }

    /// Fail-closed structural validation: supported version/algorithm, tier floor, purpose rules.
    public func validate() throws {
        guard formatVersion == EnvelopeHeader.currentFormatVersion else { throw VaultError.unsupportedFormat(formatVersion) }
        guard algorithm == .aes256gcm else { throw VaultError.unsupportedAlgorithm(algorithm.rawValue) }
        try VaultPolicy.validateTier(privacyTier, for: dataClass)
        guard consentPurpose.utf8.count <= RecordDescriptor.maxPurposeLength else { throw VaultError.limitExceeded("purpose length") }
        if dataClass.requiresPurposeConsentToStore && consentPurpose.isEmpty { throw VaultError.notAuthorized(.consentRequired) }
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
        let h = EnvelopeHeader(formatVersion: v, algorithm: alg, recordID: rid, dataClass: dc, privacyTier: tier, retention: ret, consentPurpose: purpose, createdAtUnixSeconds: t)
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
    func wrapDataKey(_ dek: [UInt8], boundTo recordID: RecordID) throws -> WrappedKey
    func unwrapDataKey(_ wrapped: WrappedKey) throws -> [UInt8]
    /// Creates a new KEK version. Old versions stay available for unwrapping until `forget`.
    func rotate() throws -> KeyIdentity
    func forget(version: UInt32) throws
}

/// Port: seals and opens record payloads. Adapters expose this ONLY behind an authorized facade.
public protocol EnvelopeSealer: Sendable {
    func seal(plaintext: [UInt8], descriptor: RecordDescriptor) throws -> RecordEnvelope
    func open(_ envelope: RecordEnvelope) throws -> [UInt8]
    /// Re-wraps the DEK under the provider's current key without touching the payload.
    func rewrap(_ envelope: RecordEnvelope) throws -> RecordEnvelope
}
