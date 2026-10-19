import Foundation
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultTesting

let t0: Int64 = 1_760_000_000

/// One fully wired vault for tests: in-memory keys, consent registry, manual clock, token issuer.
struct Harness {
    let keys: InMemoryKeyProvider
    let authority: InMemoryConsentAuthority
    let clock: ManualClock
    let issuer: AuthorizationIssuer
    let quarantine: InMemoryQuarantineRegistry
    let vault: SecureVault

    init(keyID: String = "device", start: Int64 = t0) {
        keys = InMemoryKeyProvider(keyID: keyID)
        authority = InMemoryConsentAuthority()
        clock = ManualClock(start)
        issuer = AuthorizationIssuer(clock: clock)
        quarantine = InMemoryQuarantineRegistry()
        vault = SecureVault(keyProvider: keys, consentAuthority: authority, clock: clock, authorizations: issuer, quarantine: quarantine)
    }

    func token(_ scope: OperationScope, purpose: String = "", ttl: Int64 = 60) throws -> OperationAuthorization {
        try issuer.issue(scope: scope, purpose: purpose, ttlSeconds: ttl)
    }

    func grant(_ dc: DataClass, purpose: String, id: String = "r-\(Int.random(in: 0...1_000_000))", expires: Int64? = nil) {
        authority.register(ConsentReceipt(id: id, scopes: [ConsentScope(dataClass: dc, purpose: purpose, destination: .deviceVault)], grantedAtUnixSeconds: try! clock.now(), expiresAtUnixSeconds: expires))
    }

    func descriptor(_ dc: DataClass = .birthDate, purpose: String = "", retention: RetentionClass = .untilUserDeletes, tier: PrivacyTier? = nil) throws -> RecordDescriptor {
        try RecordDescriptor(dataClass: dc, privacyTier: tier, retention: retention, consentPurpose: purpose, createdAtUnixSeconds: try clock.now())
    }

    func seal(_ text: String, _ dc: DataClass = .birthDate, purpose: String = "", retention: RetentionClass = .untilUserDeletes) throws -> RecordEnvelope {
        try vault.seal(plaintext: Array(text.utf8), descriptor: try descriptor(dc, purpose: purpose, retention: retention), authorization: try token(.write(dc), purpose: purpose))
    }

    func open(_ env: RecordEnvelope) throws -> [UInt8] {
        try vault.open(env, authorization: try token(.read(recordIDs: [env.header.recordID]), purpose: env.header.consentPurpose))
    }

    func export(_ envs: [RecordEnvelope], _ rk: RecoveryKey) throws -> [UInt8] {
        try vault.exportBackup(envs, recoveryKey: rk, authorization: try token(.exportBackup))
    }

    func restore(_ bytes: [UInt8], _ rk: RecoveryKey) throws -> RestoreResult {
        try vault.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try token(.restoreBackup))
    }
}

func bytesContain(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, haystack.count >= needle.count else { return false }
    for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] {
        if Array(haystack[i..<i + needle.count]) == needle { return true }
    }
    return false
}

func flipByte(_ bytes: [UInt8], at i: Int) -> [UInt8] { var b = bytes; b[i] ^= 0x01; return b }

func header(_ h: EnvelopeHeader, version: UInt16? = nil, dc: DataClass? = nil, tier: PrivacyTier? = nil, ret: RetentionClass? = nil, purpose: String? = nil, t: Int64? = nil, id: RecordID? = nil) -> EnvelopeHeader {
    EnvelopeHeader(formatVersion: version ?? h.formatVersion, algorithm: h.algorithm, recordID: id ?? h.recordID, dataClass: dc ?? h.dataClass,
                   privacyTier: tier ?? h.privacyTier, retention: ret ?? h.retention, consentPurpose: purpose ?? h.consentPurpose, createdAtUnixSeconds: t ?? h.createdAtUnixSeconds)
}
