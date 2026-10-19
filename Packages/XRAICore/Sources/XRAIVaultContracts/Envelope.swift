// Envelope encryption contracts (constitution §83). No cryptography lives here; only the shapes,
// the ports and the authenticated-metadata rules that an adapter must honour.

public enum VaultError: Error, Equatable, Sendable {
    /// AEAD authentication failed: wrong key, tampered ciphertext/tag/nonce, or tampered header.
    case authenticationFailed
    case unsupportedFormat(UInt16)
    case unsupportedAlgorithm(String)
    case keyUnavailable(keyID: String, version: UInt32)
    case invalidLength(field: String, expected: Int, actual: Int)
    case policyDenied(DataClass, Destination, DenialReason)
    case consentRequired(DataClass)
    case backupCorrupted(reason: String)
    /// Backup MAC mismatch: wrong recovery key OR altered backup. The two are indistinguishable by design.
    case backupIntegrityFailed
    case recoveryKeyInvalid(reason: String)
}

/// Algorithm identifiers are part of the authenticated header so downgrade is detectable.
public enum EnvelopeAlgorithm: String, Hashable, Sendable {
    case aes256gcm = "AES-256-GCM"
}

/// What a caller knows about a record before sealing it. Key identity is NOT part of this: keys
/// may rotate without re-encrypting the payload.
public struct RecordDescriptor: Hashable, Sendable {
    public let recordID: String
    public let dataClass: DataClass
    public let privacyTier: PrivacyTier
    public let retention: RetentionClass
    public let createdAtUnixSeconds: Int64

    public init(recordID: String, dataClass: DataClass, privacyTier: PrivacyTier? = nil, retention: RetentionClass, createdAtUnixSeconds: Int64) {
        self.recordID = recordID
        self.dataClass = dataClass
        self.privacyTier = privacyTier ?? dataClass.defaultTier
        self.retention = retention
        self.createdAtUnixSeconds = createdAtUnixSeconds
    }
}

/// Versioned, authenticated metadata. Its canonical bytes are the AEAD associated data for the
/// payload, so any change to any field makes `open` fail.
public struct EnvelopeHeader: Hashable, Sendable {
    public static let currentFormatVersion: UInt16 = 1

    public let formatVersion: UInt16
    public let algorithm: EnvelopeAlgorithm
    public let recordID: String
    public let dataClass: DataClass
    public let privacyTier: PrivacyTier
    public let retention: RetentionClass
    public let createdAtUnixSeconds: Int64

    public init(formatVersion: UInt16 = EnvelopeHeader.currentFormatVersion, algorithm: EnvelopeAlgorithm, descriptor d: RecordDescriptor) {
        self.formatVersion = formatVersion
        self.algorithm = algorithm
        self.recordID = d.recordID
        self.dataClass = d.dataClass
        self.privacyTier = d.privacyTier
        self.retention = d.retention
        self.createdAtUnixSeconds = d.createdAtUnixSeconds
    }

    public init(formatVersion: UInt16, algorithm: EnvelopeAlgorithm, recordID: String, dataClass: DataClass, privacyTier: PrivacyTier, retention: RetentionClass, createdAtUnixSeconds: Int64) {
        self.formatVersion = formatVersion
        self.algorithm = algorithm
        self.recordID = recordID
        self.dataClass = dataClass
        self.privacyTier = privacyTier
        self.retention = retention
        self.createdAtUnixSeconds = createdAtUnixSeconds
    }

    public func canonicalBytes() -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-ENV")
        e.appendU16(formatVersion)
        e.appendString(algorithm.rawValue)
        e.appendString(recordID)
        e.appendString(dataClass.rawValue)
        e.appendString(privacyTier.rawValue)
        e.appendString(retention.rawValue)
        e.appendI64(createdAtUnixSeconds)
        return e.bytes
    }

    public func encode(into e: inout CanonicalEncoder) {
        e.appendU16(formatVersion)
        e.appendString(algorithm.rawValue)
        e.appendString(recordID)
        e.appendString(dataClass.rawValue)
        e.appendString(privacyTier.rawValue)
        e.appendString(retention.rawValue)
        e.appendI64(createdAtUnixSeconds)
    }

    public static func decode(from d: inout CanonicalDecoder) throws -> EnvelopeHeader {
        let v = try d.readU16()
        let algRaw = try d.readString()
        guard let alg = EnvelopeAlgorithm(rawValue: algRaw) else { throw VaultError.unsupportedAlgorithm(algRaw) }
        let rid = try d.readString()
        guard let dc = DataClass(rawValue: try d.readString()) else { throw VaultError.backupCorrupted(reason: "data class") }
        guard let tier = PrivacyTier(rawValue: try d.readString()) else { throw VaultError.backupCorrupted(reason: "tier") }
        guard let ret = RetentionClass(rawValue: try d.readString()) else { throw VaultError.backupCorrupted(reason: "retention") }
        let t = try d.readI64()
        return EnvelopeHeader(formatVersion: v, algorithm: alg, recordID: rid, dataClass: dc, privacyTier: tier, retention: ret, createdAtUnixSeconds: t)
    }
}

/// A data-encryption key (DEK) wrapped by a key-encryption key (KEK) that a `KeyProvider` controls.
/// Bound to its record so DEKs cannot be swapped between records.
public struct WrappedKey: Hashable, Sendable {
    public let keyID: String
    public let keyVersion: UInt32
    public let boundRecordID: String
    public let nonce: [UInt8]
    public let ciphertext: [UInt8]
    public let tag: [UInt8]

    public init(keyID: String, keyVersion: UInt32, boundRecordID: String, nonce: [UInt8], ciphertext: [UInt8], tag: [UInt8]) {
        self.keyID = keyID
        self.keyVersion = keyVersion
        self.boundRecordID = boundRecordID
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    /// Associated data for wrapping: binds the wrapped DEK to key identity and record.
    public static func associatedData(keyID: String, keyVersion: UInt32, recordID: String) -> [UInt8] {
        var e = CanonicalEncoder()
        e.appendString("XRAI-WRAP")
        e.appendString(keyID)
        e.appendU32(keyVersion)
        e.appendString(recordID)
        return e.bytes
    }

    public func encode(into e: inout CanonicalEncoder) {
        e.appendString(keyID); e.appendU32(keyVersion); e.appendString(boundRecordID)
        e.appendBytes(nonce); e.appendBytes(ciphertext); e.appendBytes(tag)
    }
    public static func decode(from d: inout CanonicalDecoder) throws -> WrappedKey {
        WrappedKey(keyID: try d.readString(), keyVersion: try d.readU32(), boundRecordID: try d.readString(),
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
    public var description: String {
        "RecordEnvelope(record: " + header.recordID + ", class: " + header.dataClass.rawValue
            + ", tier: " + header.privacyTier.rawValue + ", alg: " + header.algorithm.rawValue
            + ", key: " + wrappedDEK.keyID + "#" + String(wrappedDEK.keyVersion)
            + ", bytes: " + String(ciphertext.count) + ", payload: <encrypted>)"
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
    func wrapDataKey(_ dek: [UInt8], boundTo recordID: String) throws -> WrappedKey
    func unwrapDataKey(_ wrapped: WrappedKey) throws -> [UInt8]
    /// Creates a new KEK version. Old versions stay available for unwrapping until `forget`.
    func rotate() throws -> KeyIdentity
    func forget(version: UInt32) throws
}

/// Port: seals and opens record payloads.
public protocol EnvelopeSealer: Sendable {
    func seal(plaintext: [UInt8], descriptor: RecordDescriptor) throws -> RecordEnvelope
    func open(_ envelope: RecordEnvelope) throws -> [UInt8]
    /// Re-wraps the DEK under the provider's current key without touching the payload.
    func rewrap(_ envelope: RecordEnvelope) throws -> RecordEnvelope
}
