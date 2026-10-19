// SecureVault — the single authorized entry point of the vault library (V32-02-01H §2, §3, §5).
// Every seal/open/export/restore passes policy, consent-authority and tier-floor checks first.
// Still NO persistence: envelopes are returned to the caller; storing them is P02-02+.
import CryptoKit
import Foundation
import XRAIVaultContracts

public struct SecureVault: Sendable {
    public let keyProvider: any KeyProvider
    public let consentAuthority: any ConsentAuthority
    private let sealer: AESGCMEnvelopeSealer

    public init(keyProvider: any KeyProvider, consentAuthority: any ConsentAuthority) {
        self.keyProvider = keyProvider
        self.consentAuthority = consentAuthority
        self.sealer = AESGCMEnvelopeSealer(keyProvider: keyProvider)
    }

    // MARK: Records

    /// Seals a record. Denied unless: tier ≥ class floor (descriptor already enforces), and for
    /// consent-gated classes the authority holds an active grant for (class, purpose, deviceVault).
    public func seal(plaintext: [UInt8], descriptor: RecordDescriptor, purpose: String, nowUnixSeconds now: Int64) throws -> RecordEnvelope {
        try VaultPolicy.validateTier(descriptor.privacyTier, for: descriptor.dataClass)
        if case .denied(let reason) = VaultPolicy.mayStore(descriptor.dataClass, purpose: purpose, authority: consentAuthority, atUnixSeconds: now) {
            throw VaultError.notAuthorized(reason)
        }
        return try sealer.seal(plaintext: plaintext, descriptor: descriptor)
    }

    /// Opens a record after re-validating its header (version, algorithm, tier floor).
    public func open(_ envelope: RecordEnvelope) throws -> [UInt8] {
        try envelope.header.validate()
        return try sealer.open(envelope)
    }

    /// Verifies integrity without returning plaintext (plaintext is decrypted and discarded).
    public func verify(_ envelope: RecordEnvelope) throws {
        _ = try open(envelope)
    }

    public func rewrap(_ envelope: RecordEnvelope) throws -> RecordEnvelope { try sealer.rewrap(envelope) }

    // MARK: Backup (user-initiated only)

    /// Exports a sealed backup. Refused unless `userInitiated`, every record passes `mayBackup`
    /// (no session-only records), record ids are unique, and every envelope verifies under the
    /// device key (a tampered or foreign envelope is never silently exported).
    public func exportBackup(_ envelopes: [RecordEnvelope], recoveryKey: RecoveryKey, userInitiated: Bool, nowUnixSeconds now: Int64) throws -> [UInt8] {
        guard userInitiated else { throw VaultError.notAuthorized(.userInitiationRequired) }
        guard envelopes.count <= BackupLimits.maxEntries else { throw VaultError.limitExceeded("entry count") }
        var seen = Set<String>()
        for env in envelopes {
            try env.header.validate()
            if case .denied(let reason) = VaultPolicy.mayBackup(env.header.dataClass, retention: env.header.retention, userInitiated: userInitiated) {
                throw VaultError.notAuthorized(reason)
            }
            guard seen.insert(env.header.recordID.hex).inserted else { throw VaultError.duplicateRecordID }
            try BackupBody.validateLimits(env)
            do { try verify(env) } catch { throw VaultError.envelopeIntegrityFailed }
        }
        return try BackupCodec.export(verified: envelopes, from: keyProvider, recoveryKey: recoveryKey, nowUnixSeconds: now)
    }

    /// Restores a sealed backup onto THIS device's keys. Refused unless `userInitiated`. Every
    /// restored envelope is payload-verified under the new keys before it is returned (fail closed).
    public func restoreBackup(bytes: [UInt8], recoveryKey: RecoveryKey, userInitiated: Bool) throws -> [RecordEnvelope] {
        guard userInitiated else { throw VaultError.notAuthorized(.userInitiationRequired) }
        let (_, envelopes) = try BackupCodec.restore(bytes: bytes, recoveryKey: recoveryKey, into: keyProvider)
        for env in envelopes {
            try env.header.validate()
            if case .denied(let reason) = VaultPolicy.mayBackup(env.header.dataClass, retention: env.header.retention, userInitiated: true) {
                throw VaultError.notAuthorized(reason)
            }
            do { try verify(env) } catch { throw VaultError.backupIntegrityFailed }
        }
        return envelopes
    }

    public static func generateRecoveryKey() throws -> RecoveryKey { try BackupCodec.generateRecoveryKey() }
}
