// SecureVault — the single authorized entry point of the vault library (V32-02-01H §2–§5, H2 G1–G4).
//
// Access contract (every call):
//   1. an OperationAuthorization is consumed from the trusted issuer (single use, in window, scope match);
//   2. time comes from the trusted VaultClock, never from parameters;
//   3. consent-gated classes need an ACTIVE grant for the purpose bound into the record;
//   4. headers are validated (version, algorithm, tier floor, purpose) before any cryptography.
// User reads return plaintext. Maintenance operations never do. Export and delete are explicit
// user-rights paths that do not depend on consent being active (the user owns the data), but
// restore quarantines consent-gated records whose grant is no longer active.
//
// Still NO persistence: envelopes are returned to the caller; storing them is P02-02+.
// Access control here is NOT an OS boundary; see docs/security/VAULT_THREAT_MODEL_P02.md T23–T26.
import CryptoKit
import Foundation
import XRAIVaultContracts

public struct SecureVault: Sendable {
    // Composition root wiring. Nothing is public: callers cannot reach the key provider or the
    // raw sealer through a vault instance.
    private let keyProvider: any KeyProvider
    private let consentAuthority: any ConsentAuthority
    private let clock: any VaultClock
    private let authorizations: any AuthorizationValidator
    private let quarantine: any QuarantineAuthority
    private let sealer: AESGCMEnvelopeSealer

    /// The composition root constructs this once, injecting production ports. `InMemoryKeyProvider`
    /// lives in the `XRAIVaultTesting` target and is not available to production modules.
    public init(keyProvider: any KeyProvider, consentAuthority: any ConsentAuthority, clock: any VaultClock, authorizations: any AuthorizationValidator, quarantine: any QuarantineAuthority) {
        self.keyProvider = keyProvider
        self.consentAuthority = consentAuthority
        self.clock = clock
        self.authorizations = authorizations
        self.quarantine = quarantine
        self.sealer = AESGCMEnvelopeSealer(keyProvider: keyProvider)
    }

    /// Key identity only (no material), for status screens and audits.
    public var currentKeyIdentity: KeyIdentity { keyProvider.currentKey }
    /// Truthful key-protection level of the active provider.
    public var keyProtection: KeyProtection { keyProvider.protection }

    // MARK: Authorization helpers

    private func authorize(_ token: OperationAuthorization, for op: OperationScope, recordID: RecordID?, purpose: String?) throws -> (OperationAuthorization, Int64) {
        let now = try clock.now()
        let trusted = try authorizations.consume(tokenID: token.id, atUnixSeconds: now)
        guard trusted.scope.covers(op, recordID: recordID) else { throw VaultError.authorizationInvalid(.scopeMismatch) }
        if let purpose, trusted.purpose != purpose { throw VaultError.authorizationInvalid(.purposeMismatch) }
        return (trusted, now)
    }

    private func requireActiveConsent(_ header: EnvelopeHeader, now: Int64) throws {
        if case .denied(let reason) = VaultPolicy.mayRead(header.dataClass, consentPurpose: header.consentPurpose, authority: consentAuthority, atUnixSeconds: now) {
            throw VaultError.notAuthorized(reason)
        }
    }

    // MARK: User operations (plaintext in / out)

    /// Seals a record. Requires a `.write(class)` token whose purpose equals the descriptor's
    /// consent purpose, and for consent-gated classes an active grant at the trusted time.
    public func seal(plaintext: [UInt8], descriptor: RecordDescriptor, authorization: OperationAuthorization) throws -> RecordEnvelope {
        try VaultPolicy.validateTier(descriptor.privacyTier, for: descriptor.dataClass)
        let (_, now) = try authorize(authorization, for: .write(descriptor.dataClass), recordID: descriptor.recordID, purpose: descriptor.consentPurpose)
        if case .denied(let reason) = VaultPolicy.mayStore(descriptor.dataClass, purpose: descriptor.consentPurpose, authority: consentAuthority, atUnixSeconds: now) {
            throw VaultError.notAuthorized(reason)
        }
        return try sealer.seal(plaintext: plaintext, descriptor: descriptor)
    }

    /// Reads plaintext. Requires a `.read` token covering the record with purpose equal to the
    /// record's bound purpose, and an active grant for consent-gated classes (revoked/expired → denied).
    public func open(_ envelope: RecordEnvelope, authorization: OperationAuthorization) throws -> [UInt8] {
        try envelope.header.validate()
        let (_, now) = try authorize(authorization, for: .read(recordIDs: nil), recordID: envelope.header.recordID, purpose: envelope.header.consentPurpose)
        // GATE 0B: quarantine is enforced by the trusted registry, not by the caller's value.
        if quarantine.isQuarantined(envelope.header.recordID) { throw VaultError.quarantined(.consentRequired) }
        try requireActiveConsent(envelope.header, now: now)
        return try sealer.open(envelope)
    }

    // MARK: Maintenance operations (never return plaintext)

    /// Technical integrity check. Requires `.maintenance(.integrityCheck)`; no consent needed because
    /// no plaintext leaves the vault.
    public func verify(_ envelope: RecordEnvelope, maintenance: OperationAuthorization) throws {
        try envelope.header.validate()
        _ = try authorize(maintenance, for: .maintenance(.integrityCheck), recordID: nil, purpose: nil)
        _ = try sealer.open(envelope)
    }

    /// Re-wraps the DEK under the current key AFTER verifying payload integrity (G4).
    public func rewrap(_ envelope: RecordEnvelope, maintenance: OperationAuthorization) throws -> RecordEnvelope {
        try envelope.header.validate()
        _ = try authorize(maintenance, for: .maintenance(.rewrap), recordID: nil, purpose: nil)
        return try sealer.rewrap(envelope)
    }

    // MARK: User rights: export, restore, delete

    private func verifyForExport(_ envelopes: [RecordEnvelope]) throws {
        guard envelopes.count <= BackupLimits.maxEntries else { throw VaultError.limitExceeded("entry count") }
        var seen = Set<String>()
        for env in envelopes {
            try env.header.validate()
            if case .denied(let reason) = VaultPolicy.mayBackup(env.header.dataClass, retention: env.header.retention, userInitiated: true) {
                throw VaultError.notAuthorized(reason)
            }
            guard seen.insert(env.header.recordID.hex).inserted else { throw VaultError.duplicateRecordID }
            try BackupBody.validateLimits(env)
            do { _ = try sealer.open(env) } catch { throw VaultError.envelopeIntegrityFailed }
        }
    }

    /// LEGACY v2 export (store-less, no provenance). Kept only so v2 compatibility stays testable;
    /// the store exports v3 through `exportBackup(_:facts:recoveryKey:authorization:)`.
    /// Requires an `.exportBackup` token. Every envelope must verify under the device key;
    /// duplicates, session-only records and foreign/tampered envelopes are refused.
    public func exportBackup(_ envelopes: [RecordEnvelope], recoveryKey: RecoveryKey, authorization: OperationAuthorization) throws -> [UInt8] {
        let (_, now) = try authorize(authorization, for: .exportBackup, recordID: nil, purpose: nil)
        try verifyForExport(envelopes)
        return try BackupCodec.export(verified: envelopes, from: keyProvider, recoveryKey: recoveryKey, nowUnixSeconds: now)
    }

    /// P03-04b: v3 export with the store's facts (instance id, backup generation, manifest binding,
    /// deletion history). Same token, same verification as the legacy path.
    public func exportBackup(_ envelopes: [RecordEnvelope], facts: BackupExportFacts, recoveryKey: RecoveryKey, authorization: OperationAuthorization) throws -> [UInt8] {
        let (_, now) = try authorize(authorization, for: .exportBackup, recordID: nil, purpose: nil)
        try verifyForExport(envelopes)
        return try BackupCodec.exportV3(verified: envelopes, from: keyProvider, recoveryKey: recoveryKey, nowUnixSeconds: now, facts: facts)
    }

    /// Restores onto THIS device's keys. Requires a `.restoreBackup` token. Every envelope is
    /// payload-verified. Consent-gated records whose grant is not active NOW are returned as
    /// quarantined, never silently re-enabled (G4).
    public func restoreBackup(bytes: [UInt8], recoveryKey: RecoveryKey, authorization: OperationAuthorization) throws -> RestoreResult {
        let (_, now) = try authorize(authorization, for: .restoreBackup, recordID: nil, purpose: nil)
        let (provenance, envelopes) = try BackupCodec.restore(bytes: bytes, recoveryKey: recoveryKey, into: keyProvider)
        var active: [RecordEnvelope] = []
        var quarantined: [QuarantinedRecord] = []
        for env in envelopes {
            try env.header.validate()
            if case .denied(let reason) = VaultPolicy.mayBackup(env.header.dataClass, retention: env.header.retention, userInitiated: true) {
                throw VaultError.notAuthorized(reason)
            }
            do { _ = try sealer.open(env) } catch { throw VaultError.backupIntegrityFailed }
            if case .denied(let reason) = VaultPolicy.mayRead(env.header.dataClass, consentPurpose: env.header.consentPurpose, authority: consentAuthority, atUnixSeconds: now) {
                quarantine.quarantine(env.header.recordID, reason: reason)
                quarantined.append(QuarantinedRecord(envelope: env, reason: reason))
            } else {
                active.append(env)
            }
        }
        return RestoreResult(active: active, quarantined: quarantined, provenance: provenance)
    }

    /// Releases a quarantined record after the user granted consent again. Requires BOTH a
    /// `.releaseQuarantine` token and an active grant for the record's purpose NOW; only then is the
    /// id removed from the trusted quarantine registry. Re-granting consent alone never releases.
    public func releaseQuarantine(_ record: QuarantinedRecord, authorization: OperationAuthorization) throws -> RecordEnvelope {
        try record.envelope.header.validate()
        let id = record.envelope.header.recordID
        let (_, now) = try authorize(authorization, for: .releaseQuarantine, recordID: nil, purpose: nil)
        guard quarantine.isQuarantined(id) else { throw VaultError.quarantined(.notListed) }
        if case .denied(let reason) = VaultPolicy.mayRead(record.envelope.header.dataClass, consentPurpose: record.envelope.header.consentPurpose, authority: consentAuthority, atUnixSeconds: now) {
            throw VaultError.quarantined(reason)
        }
        _ = try sealer.open(record.envelope)
        quarantine.release(id)
        return record.envelope
    }

    /// User deletion right. Requires a `.delete(recordIDs)` token covering the ids. The store layer
    /// (future) must consume the returned grant; consent state never blocks deletion.
    public func authorizeDeletion(of recordIDs: Set<RecordID>, authorization: OperationAuthorization) throws -> DeletionGrant {
        let (_, now) = try authorize(authorization, for: .delete(recordIDs: recordIDs), recordID: nil, purpose: nil)
        return DeletionGrant(recordIDs: recordIDs, authorizedAtUnixSeconds: now)
    }

    public static func generateRecoveryKey() throws -> RecoveryKey { try BackupCodec.generateRecoveryKey() }

    // MARK: P03-04 store support (ADR-BOOT-009). Still the only crypto entry point.

    /// Consumes a token for an operation the STORE executes (revoke, restore suspended, retire key,
    /// admit restored). Same issuer, same clock, same single-use rule as every other call; returns
    /// the trusted time. Nothing is decrypted here.
    public func consumeAuthorization(_ token: OperationAuthorization, for op: OperationScope) throws -> Int64 {
        try authorize(token, for: op, recordID: nil, purpose: nil).1
    }

    /// Seals one of the store's own system records (manifest, deletion ledger, authorization state,
    /// journal entries). Accepts ONLY `DataClass.storeMetadata` — the class that never holds record
    /// contents and is never exported — and fails closed for every other class. No user token is
    /// required because the content is store metadata the store itself produced; the personal-data
    /// path (`seal`/`open`) is untouched. GATE C tests cover both directions.
    public func sealSystem(plaintext: [UInt8], descriptor: RecordDescriptor) throws -> RecordEnvelope {
        guard descriptor.dataClass == .storeMetadata else { throw VaultError.unsupportedSystemClass }
        return try sealer.seal(plaintext: plaintext, descriptor: descriptor)
    }

    /// Opens a system record. Same restriction as `sealSystem`.
    public func openSystem(_ envelope: RecordEnvelope) throws -> [UInt8] {
        try envelope.header.validate()
        guard envelope.header.dataClass == .storeMetadata else { throw VaultError.unsupportedSystemClass }
        return try sealer.open(envelope)
    }

    /// Re-wraps every envelope under the current key AFTER verifying each payload (G4), with one
    /// maintenance token for the batch (the store writes the results file by file, journaled).
    public func rewrapBatch(_ envelopes: [RecordEnvelope], maintenance: OperationAuthorization) throws -> [RecordEnvelope] {
        _ = try authorize(maintenance, for: .maintenance(.rewrap), recordID: nil, purpose: nil)
        var out: [RecordEnvelope] = []
        out.reserveCapacity(envelopes.count)
        for env in envelopes {
            try env.header.validate()
            out.append(try sealer.rewrap(env))
        }
        return out
    }

    // MARK: P03-04b GATE 4 — chunked attachments (one DEK per attachment, chunk key derived from it)

    /// Creates an attachment: the layout becomes the plaintext of a header record sealed exactly like
    /// `seal` (`.write(class)` token, consent, tier floor); the returned cipher seals the chunks.
    public func createAttachment(descriptor: RecordDescriptor, layout: AttachmentLayout, authorization: OperationAuthorization) throws -> (header: RecordEnvelope, cipher: AttachmentCipher) {
        let header = try seal(plaintext: layout.encode(), descriptor: descriptor, authorization: authorization)
        let dek = try keyProvider.unwrapDataKey(header.wrappedDEK)
        return (header, try AttachmentCipher(dek: dek, recordID: descriptor.recordID, layout: layout))
    }

    /// Opens an attachment header exactly like `open` (`.read` token, quarantine, consent) and returns
    /// the layout plus the chunk cipher. No chunk is decrypted here.
    public func openAttachment(_ header: RecordEnvelope, authorization: OperationAuthorization) throws -> (layout: AttachmentLayout, cipher: AttachmentCipher) {
        let layout = try AttachmentLayout.decode(try open(header, authorization: authorization))
        let dek = try keyProvider.unwrapDataKey(header.wrappedDEK)
        return (layout, try AttachmentCipher(dek: dek, recordID: header.header.recordID, layout: layout))
    }

    /// Re-wraps a system record (no token; same class restriction as `openSystem`).
    public func rewrapSystem(_ envelope: RecordEnvelope) throws -> RecordEnvelope {
        try envelope.header.validate()
        guard envelope.header.dataClass == .storeMetadata else { throw VaultError.unsupportedSystemClass }
        return try sealer.rewrap(envelope)
    }
}

/// SHA-256 for store bindings (manifest hash, scan digest, Bloom indices). Lives here because this
/// is the only module allowed to import CryptoKit.
public enum VaultDigest {
    public static func sha256(_ bytes: [UInt8]) -> [UInt8] { Array(SHA256.hash(data: bytes)) }
}

/// AES-256-GCM over attachment chunks with a key derived (HKDF-SHA256, context-separated, record-bound)
/// from the attachment's DEK. Only `SecureVault` can construct it; it never exposes key material.
/// Each chunk: nonce = prefix ‖ index, AAD = layout facts + index + last flag, output = ciphertext ‖ tag.
public struct AttachmentCipher: Sendable {
    private let keyBytes: [UInt8]
    public let recordID: RecordID
    public let layout: AttachmentLayout

    init(dek: [UInt8], recordID: RecordID, layout: AttachmentLayout) throws {
        guard dek.count == CryptoConstants.keyBytes else { throw VaultError.invalidLength(field: "dek", expected: CryptoConstants.keyBytes, actual: dek.count) }
        let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: dek), salt: Array(recordID.hex.utf8), info: Array("xrai.attachment.chunk.v1".utf8), outputByteCount: 32)
        keyBytes = derived.withUnsafeBytes { Array($0) }
        self.recordID = recordID; self.layout = layout
    }

    public func seal(chunk plaintext: [UInt8], index: UInt32) throws -> [UInt8] {
        guard index < layout.chunkCount, plaintext.count == layout.length(ofChunk: index) else { throw VaultError.limitExceeded("attachment chunk") }
        let nonce = try AES.GCM.Nonce(data: layout.nonce(forChunk: index))
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyBytes), nonce: nonce, authenticating: layout.associatedData(recordID: recordID, chunkIndex: index))
        return Array(box.ciphertext) + Array(box.tag)
    }

    public func open(chunk sealed: [UInt8], index: UInt32) throws -> [UInt8] {
        guard index < layout.chunkCount, sealed.count == layout.length(ofChunk: index) + CryptoConstants.gcmTagBytes else { throw VaultError.authenticationFailed }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: layout.nonce(forChunk: index)), ciphertext: sealed.dropLast(CryptoConstants.gcmTagBytes), tag: sealed.suffix(CryptoConstants.gcmTagBytes))
            return Array(try AES.GCM.open(box, using: SymmetricKey(data: keyBytes), authenticating: layout.associatedData(recordID: recordID, chunkIndex: index)))
        } catch { throw VaultError.authenticationFailed }
    }
}

