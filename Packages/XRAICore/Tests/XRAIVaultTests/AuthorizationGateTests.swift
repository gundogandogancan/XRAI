import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultTesting

// H2 G5 negative tests: authorization gate, consent lifecycle on read, clock, tokens, quarantine.

@Suite("G1 — unauthorized decryption is impossible through the facade")
struct ReadAccessTests {
    @Test("open with a REVOKED consent is denied; it was readable before revocation")
    func revokedConsent() throws {
        let h = Harness()
        h.grant(.journal, purpose: "lens", id: "c")
        let env = try h.seal("private line", .journal, purpose: "lens")
        #expect(try h.open(env) == Array("private line".utf8))
        h.authority.revoke(id: "c", atUnixSeconds: t0 + 10)
        h.clock.set(t0 + 10)
        #expect(throws: VaultError.notAuthorized(.consentRequired)) { try h.open(env) }
    }

    @Test("open with an EXPIRED consent is denied at the trusted time")
    func expiredConsent() throws {
        let h = Harness()
        h.grant(.psychometrics, purpose: "self_reflection", expires: t0 + 100)
        let env = try h.seal("answers", .psychometrics, purpose: "self_reflection")
        h.clock.set(t0 + 99)
        #expect(try h.open(env) == Array("answers".utf8))
        h.clock.set(t0 + 100)
        #expect(throws: VaultError.notAuthorized(.consentRequired)) { try h.open(env) }
    }

    @Test("a record is bound to its purpose: a grant or token for another purpose cannot read it")
    func purposeBinding() throws {
        let h = Harness()
        h.grant(.journal, purpose: "lens")
        let env = try h.seal("line", .journal, purpose: "lens")
        h.grant(.journal, purpose: "other")
        #expect(throws: VaultError.authorizationInvalid(.purposeMismatch)) { try h.vault.open(env, authorization: try h.token(.read(recordIDs: nil), purpose: "other")) }
        // Even a correct token cannot help if the grant for the bound purpose is gone.
        for id in ["c1"] { _ = id }
        let h2 = Harness()
        h2.grant(.journal, purpose: "lens", id: "g")
        let env2 = try h2.seal("line", .journal, purpose: "lens")
        h2.authority.revoke(id: "g", atUnixSeconds: t0 + 1); h2.clock.set(t0 + 1)
        h2.grant(.journal, purpose: "other")
        #expect(throws: VaultError.notAuthorized(.consentRequired)) { try h2.vault.open(env2, authorization: try h2.token(.read(recordIDs: nil), purpose: "lens")) }
    }

    @Test("a read token narrowed to other records, a maintenance token, or a write token cannot read")
    func scopeOnRead() throws {
        let h = Harness()
        let env = try h.seal("dob")
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.open(env, authorization: try h.token(.read(recordIDs: [RecordID()]))) }
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.open(env, authorization: try h.token(.maintenance(.integrityCheck))) }
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.open(env, authorization: try h.token(.write(.birthDate))) }
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.open(env, authorization: try h.token(.exportBackup)) }
    }

    @Test("maintenance verify/rewrap never return plaintext and do not need consent; a read token cannot be used for maintenance")
    func maintenanceSeparation() throws {
        let h = Harness()
        h.grant(.journal, purpose: "lens", id: "c")
        let env = try h.seal("line", .journal, purpose: "lens")
        h.authority.revoke(id: "c", atUnixSeconds: t0 + 1); h.clock.set(t0 + 1)
        try h.vault.verify(env, maintenance: try h.token(.maintenance(.integrityCheck)))
        let re = try h.vault.rewrap(env, maintenance: try h.token(.maintenance(.rewrap)))
        #expect(re.ciphertext == env.ciphertext)
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.verify(env, maintenance: try h.token(.read(recordIDs: nil))) }
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.rewrap(env, maintenance: try h.token(.maintenance(.integrityCheck))) }
    }

    @Test("user rights: export and deletion work without active consent; deletion grant is scoped to the ids")
    func userRights() throws {
        let h = Harness()
        h.grant(.journal, purpose: "lens", id: "c")
        let env = try h.seal("line", .journal, purpose: "lens")
        h.authority.revoke(id: "c", atUnixSeconds: t0 + 1); h.clock.set(t0 + 1)
        let rk = try SecureVault.generateRecoveryKey()
        _ = try h.export([env], rk)
        let grant = try h.vault.authorizeDeletion(of: [env.header.recordID], authorization: try h.token(.delete(recordIDs: [env.header.recordID])))
        #expect(grant.recordIDs == [env.header.recordID] && grant.authorizedAtUnixSeconds == t0 + 1)
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.authorizeDeletion(of: [env.header.recordID, RecordID()], authorization: try h.token(.delete(recordIDs: [env.header.recordID]))) }
    }
}

@Suite("G3 — trusted clock and operation tokens")
struct ClockAndTokenTests {
    @Test("a clock set backwards cannot be used to gain authority: the monotonic guard refuses, and an expired token stays expired")
    func clockRollback() throws {
        let base = ManualClock(t0)
        let guardClock = MonotonicGuardClock(wrapping: base, toleranceSeconds: 5)
        let keys = InMemoryKeyProvider(keyID: "d"); let issuer = AuthorizationIssuer(clock: guardClock)
        let vault = SecureVault(keyProvider: keys, consentAuthority: NoConsentAuthority(), clock: guardClock, authorizations: issuer)
        let tok = try issuer.issue(scope: .write(.birthDate), ttlSeconds: 10)
        base.set(t0 + 20)
        _ = try guardClock.now()
        #expect(throws: VaultError.authorizationInvalid(.expired)) { try vault.seal(plaintext: [1], descriptor: try RecordDescriptor(dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0), authorization: tok) }
        base.set(t0) // rolled back 20 s, beyond the 5 s tolerance
        let tok2 = OperationAuthorization(id: tok.id, scope: tok.scope, purpose: "", issuedAtUnixSeconds: t0, expiresAtUnixSeconds: t0 + 10)
        #expect(throws: VaultError.clockRegressed) { try vault.seal(plaintext: [1], descriptor: try RecordDescriptor(dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0), authorization: tok2) }
        #expect(throws: VaultError.clockRegressed) { try issuer.issue(scope: .write(.birthDate)) }
        base.set(t0 + 17) // within tolerance of the high-water mark 20
        _ = try guardClock.now()
    }

    @Test("forged tokens (unknown id), replayed tokens, expired tokens, not-yet-valid tokens and over-long TTLs are rejected")
    func tokenLifecycle() throws {
        let h = Harness()
        let forged = OperationAuthorization(id: RecordID().hex, scope: .read(recordIDs: nil), purpose: "", issuedAtUnixSeconds: t0, expiresAtUnixSeconds: t0 + 1000)
        let env = try h.seal("x")
        #expect(throws: VaultError.authorizationInvalid(.unknownToken)) { try h.vault.open(env, authorization: forged) }
        let real = try h.token(.read(recordIDs: nil))
        #expect(try h.vault.open(env, authorization: real) == Array("x".utf8))
        #expect(throws: VaultError.authorizationInvalid(.alreadyConsumed)) { try h.vault.open(env, authorization: real) }
        let short = try h.token(.read(recordIDs: nil), ttl: 5)
        h.clock.advance(5)
        #expect(throws: VaultError.authorizationInvalid(.expired)) { try h.vault.open(env, authorization: short) }
        #expect(throws: VaultError.authorizationInvalid(.ttlTooLong)) { try h.token(.read(recordIDs: nil), ttl: OperationAuthorization.maxTTLSeconds + 1) }
        #expect(throws: VaultError.authorizationInvalid(.ttlTooLong)) { try h.token(.read(recordIDs: nil), ttl: 0) }
        // caller tampering with the scope of a real token has no effect: the issuer's copy is used
        let narrow = try h.token(.read(recordIDs: [RecordID()]))
        let widened = OperationAuthorization(id: narrow.id, scope: .read(recordIDs: nil), purpose: "", issuedAtUnixSeconds: narrow.issuedAtUnixSeconds, expiresAtUnixSeconds: narrow.expiresAtUnixSeconds + 1000)
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.open(env, authorization: widened) }
        // a token consumed by a failed attempt is gone (single use even on failure)
        #expect(throws: VaultError.authorizationInvalid(.alreadyConsumed)) { try h.vault.open(env, authorization: widened) }
        // tokens from a different issuer are unknown here
        let other = AuthorizationIssuer(clock: h.clock)
        let foreign = try other.issue(scope: .read(recordIDs: nil))
        #expect(throws: VaultError.authorizationInvalid(.unknownToken)) { try h.vault.open(env, authorization: foreign) }
    }

    @Test("a fake user action: calling export/restore with any non-export token is refused; the flag no longer exists")
    func fakeUserAction() throws {
        let h = Harness()
        let env = try h.seal("x")
        let rk = try SecureVault.generateRecoveryKey()
        for scope in [OperationScope.read(recordIDs: nil), .write(.birthDate), .maintenance(.rewrap), .restoreBackup, .releaseQuarantine] {
            #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.exportBackup([env], recoveryKey: rk, authorization: try h.token(scope)) }
        }
        let bytes = try h.export([env], rk)
        for scope in [OperationScope.read(recordIDs: nil), .exportBackup, .maintenance(.integrityCheck)] {
            #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try h.token(scope)) }
        }
    }
}

@Suite("G4 — integrity before rewrap; quarantine on restore")
struct IntegrityAndQuarantineTests {
    @Test("a corrupted envelope cannot be re-wrapped as if valid")
    func rewrapVerifies() throws {
        let h = Harness()
        let env = try h.seal("x")
        let bad = RecordEnvelope(header: env.header, wrappedDEK: env.wrappedDEK, nonce: env.nonce, ciphertext: flipByte(env.ciphertext, at: 0), tag: env.tag)
        #expect(throws: VaultError.authenticationFailed) { try h.vault.rewrap(bad, maintenance: try h.token(.maintenance(.rewrap))) }
        let mixed = env.replacingWrappedDEK(try h.seal("y").wrappedDEK)
        #expect(throws: VaultError.authenticationFailed) { try h.vault.rewrap(mixed, maintenance: try h.token(.maintenance(.rewrap))) }
        _ = try h.vault.rewrap(env, maintenance: try h.token(.maintenance(.rewrap)))
    }

    @Test("restoring an old backup does not silently re-enable revoked sensitive records: they are quarantined, unreadable, and released only with a fresh grant")
    func quarantine() throws {
        let h = Harness()
        h.grant(.parentsNames, purpose: "family_lens", id: "c")
        let sensitive = try h.seal("parent names", .parentsNames, purpose: "family_lens")
        let plain = try h.seal("dob")
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try h.export([sensitive, plain], rk)
        h.authority.revoke(id: "c", atUnixSeconds: t0 + 1); h.clock.set(t0 + 1)

        let result = try h.restore(bytes, rk)
        #expect(result.active.map(\.header.dataClass) == [.birthDate])
        #expect(result.quarantined.count == 1 && result.quarantined[0].reason == .consentRequired && result.quarantined[0].envelope.header.dataClass == .parentsNames)
        let q = result.quarantined[0]
        #expect(throws: VaultError.notAuthorized(.consentRequired)) { try h.open(q.envelope) }
        #expect(throws: VaultError.quarantined(.consentRequired)) { try h.vault.releaseQuarantine(q, authorization: try h.token(.releaseQuarantine)) }
        #expect(throws: VaultError.authorizationInvalid(.scopeMismatch)) { try h.vault.releaseQuarantine(q, authorization: try h.token(.read(recordIDs: nil))) }
        h.grant(.parentsNames, purpose: "family_lens", id: "c2")
        let released = try h.vault.releaseQuarantine(q, authorization: try h.token(.releaseQuarantine))
        #expect(try h.open(released) == Array("parent names".utf8))
        // a different purpose grant does not release it
        let h3 = Harness()
        h3.grant(.parentsNames, purpose: "other")
        let r3 = try h3.restore(bytes, rk)
        #expect(r3.quarantined.count == 1)
    }
}
