import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultTesting

// P02-02 GATE 0: clock rollback and quarantine enforcement fixes.

@Suite("GATE 0A — effective time never goes backwards")
struct ClockRollbackTests {
    @Test("a revoked consent does not re-activate when the base clock is set back 1…300 s; beyond tolerance the clock refuses")
    func revokedStaysRevoked() throws {
        let base = ManualClock(t0)
        let clock = MonotonicGuardClock(wrapping: base, toleranceSeconds: 300)
        let authority = InMemoryConsentAuthority()
        let issuer = AuthorizationIssuer(clock: clock)
        let vault = SecureVault(keyProvider: InMemoryKeyProvider(keyID: "d"), consentAuthority: authority, clock: clock, authorizations: issuer, quarantine: InMemoryQuarantineRegistry())
        authority.register(ConsentReceipt(id: "c", scopes: [ConsentScope(dataClass: .journal, purpose: "p", destination: .deviceVault)], grantedAtUnixSeconds: t0))
        let env = try vault.seal(plaintext: Array("x".utf8), descriptor: try RecordDescriptor(dataClass: .journal, retention: .untilUserDeletes, consentPurpose: "p", createdAtUnixSeconds: t0), authorization: try issuer.issue(scope: .write(.journal), purpose: "p"))
        base.set(t0 + 1000)
        _ = try clock.now()                      // high-water mark = t0 + 1000
        authority.revoke(id: "c", atUnixSeconds: t0 + 1000)
        #expect(throws: VaultError.notAuthorized(.consentRequired)) { try vault.open(env, authorization: try issuer.issue(scope: .read(recordIDs: nil), purpose: "p")) }
        for back in [Int64(1), 60, 150, 299, 300] {
            base.set(t0 + 1000 - back)
            #expect(try clock.now() == t0 + 1000, "effective time must stay at the mark (back \(back)s)")
            #expect(throws: VaultError.notAuthorized(.consentRequired)) { try vault.open(env, authorization: try issuer.issue(scope: .read(recordIDs: nil), purpose: "p")) }
        }
        base.set(t0 + 1000 - 301)
        #expect(throws: VaultError.clockRegressed) { try clock.now() }
        #expect(throws: VaultError.clockRegressed) { try issuer.issue(scope: .read(recordIDs: nil), purpose: "p") }
        base.set(t0 + 2000)
        #expect(try clock.now() == t0 + 2000)
    }

    @Test("an expired token cannot be revived by moving the clock back within tolerance")
    func expiredTokenStaysExpired() throws {
        let base = ManualClock(t0)
        let clock = MonotonicGuardClock(wrapping: base, toleranceSeconds: 300)
        let issuer = AuthorizationIssuer(clock: clock)
        let tok = try issuer.issue(scope: .exportBackup, ttlSeconds: 10)
        base.set(t0 + 100); _ = try clock.now()
        base.set(t0 + 5)
        #expect(throws: VaultError.authorizationInvalid(.expired)) { try issuer.consume(tokenID: tok.id, atUnixSeconds: try clock.now()) }
    }
}

@Suite("GATE 0B — quarantine is enforced by the trusted registry")
struct QuarantineEnforcementTests {
    private func setup() throws -> (Harness, [UInt8], RecoveryKey, RecordEnvelope) {
        let h = Harness()
        h.grant(.parentsNames, purpose: "family", id: "c")
        let sensitive = try h.seal("names", .parentsNames, purpose: "family")
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try h.export([sensitive], rk)
        h.authority.revoke(id: "c", atUnixSeconds: t0 + 1); h.clock.set(t0 + 1)
        return (h, bytes, rk, sensitive)
    }

    @Test("direct open() of a quarantined envelope is refused even after consent is re-granted; release needs token AND grant")
    func reGrantAlone() throws {
        let (h, bytes, rk, _) = try setup()
        let result = try h.restore(bytes, rk)
        let q = try #require(result.quarantined.first)
        #expect(h.quarantine.isQuarantined(q.envelope.header.recordID))
        // 1. still revoked: open denied with quarantine (registry consulted before consent)
        #expect(throws: VaultError.quarantined(.consentRequired)) { try h.open(q.envelope) }
        // 2. consent re-granted: open STILL denied — quarantine is a separate state
        h.grant(.parentsNames, purpose: "family", id: "c2")
        #expect(throws: VaultError.quarantined(.consentRequired)) { try h.open(q.envelope) }
        #expect(throws: VaultError.quarantined(.consentRequired)) { try h.vault.open(q.envelope, authorization: try h.token(.read(recordIDs: [q.envelope.header.recordID]), purpose: "family")) }
        // 3. unauthorized release attempts
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.releaseQuarantine(q, authorization: try h.token(.read(recordIDs: nil), purpose: "family")) }
        #expect(throws: VaultError.authorizationInvalid(.unknownToken)) { try h.vault.releaseQuarantine(q, authorization: OperationAuthorization(id: RecordID().hex, scope: .releaseQuarantine, purpose: "", issuedAtUnixSeconds: t0, expiresAtUnixSeconds: t0 + 999)) }
        #expect(h.quarantine.isQuarantined(q.envelope.header.recordID), "failed attempts never release")
        // 4. proper release: token + active grant → readable
        let released = try h.vault.releaseQuarantine(q, authorization: try h.token(.releaseQuarantine))
        #expect(!h.quarantine.isQuarantined(released.header.recordID))
        #expect(try h.open(released) == Array("names".utf8))
        // 5. releasing something not quarantined is an error, not a no-op
        #expect(throws: VaultError.quarantined(.notListed)) { try h.vault.releaseQuarantine(q, authorization: try h.token(.releaseQuarantine)) }
    }

    @Test("release with a valid token but WITHOUT an active grant is refused and the record stays quarantined")
    func tokenAlone() throws {
        let (h, bytes, rk, _) = try setup()
        let q = try #require(try h.restore(bytes, rk).quarantined.first)
        #expect(throws: VaultError.quarantined(.consentRequired)) { try h.vault.releaseQuarantine(q, authorization: try h.token(.releaseQuarantine)) }
        #expect(h.quarantine.isQuarantined(q.envelope.header.recordID))
        h.grant(.parentsNames, purpose: "other")   // wrong purpose
        #expect(throws: VaultError.quarantined(.consentRequired)) { try h.vault.releaseQuarantine(q, authorization: try h.token(.releaseQuarantine)) }
    }

    @Test("the same envelope value restored into a vault whose registry is pre-marked stays quarantined; the registry, not the value, is the source of truth")
    func registryIsSourceOfTruth() throws {
        let h = Harness()
        let env = try h.seal("dob")
        #expect(try h.open(env) == Array("dob".utf8))
        h.quarantine.quarantine(env.header.recordID, reason: .consentRequired)
        #expect(throws: VaultError.quarantined(.consentRequired)) { try h.open(env) }
        // maintenance still works (no plaintext), export (user right) still works
        try h.vault.verify(env, maintenance: try h.token(.maintenance(.integrityCheck)))
        _ = try h.export([env], try SecureVault.generateRecoveryKey())
    }
}
