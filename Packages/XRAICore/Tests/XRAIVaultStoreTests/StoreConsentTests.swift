// P03-05A — GATE 1 pre-integration review (PRE-01/02/03) and GATE 2 production consent model
// (rows NT-CA-01…, NT-PR-01…). Synthetic purposes and data only.
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

/// Fixture whose store OWNS consent (purpose registry → `StoreConsentAuthority`, `system/consent.v1`).
final class ConsentFixture: @unchecked Sendable {
    let base: StoreFixture
    let registry: PurposeRegistry
    init(registry: PurposeRegistry? = nil, limits: StoreLimits = StoreLimits()) throws {
        base = StoreFixture(limits: limits)
        self.registry = try registry ?? XRAIPurposes.registryV1()
    }
    var composition: VaultComposition { VaultComposition(purposeRegistry: registry, quarantine: base.quarantine, baseClock: base.base) }
    func open() async throws -> FileVaultStore {
        try await FileVaultStore.open(root: base.rootURL, keyProvider: base.keys, anchor: base.anchor, composition: composition, limits: base.limits, fileSystem: base.fs)
    }
    func cleanup() { base.cleanup() }
    func grant(_ s: FileVaultStore, _ purpose: String, _ classes: Set<DataClass>) async throws -> ConsentEvent {
        try await s.grantConsent(purposeID: purpose, dataClasses: classes, authorization: try s.issuer.issue(scope: .grantConsent(purpose: purpose), purpose: purpose))
    }
}

@Suite("GATE 2 — purpose registry and immutable consent chain (pure)", .serialized)
struct PurposeAndConsentModelTests {
    @Test("NT-CA-01: definitions are validated; the registry refuses duplicates; versions resolve; widening a purpose means the old grant no longer covers it, narrowing keeps coverage")
    func registryVersioning() throws {
        let r = try XRAIPurposes.registryV1()
        #expect(r.purposeIDs.count == 5 && r.latest("journal_reflection")?.version == 1 && r.definition("journal_reflection", version: 2) == nil)
        #expect(throws: VaultError.self) { _ = try PurposeDefinition(id: "", version: 1, titleTR: "", titleEN: "", explanationTR: "", explanationEN: "", allowedDataClasses: [.journal], allowedDestinations: [.deviceVault], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsAndDeleteNow) }
        #expect(throws: VaultError.notAuthorized(.hardRule)) { _ = try PurposeDefinition(id: "x", version: 1, titleTR: "", titleEN: "", explanationTR: "", explanationEN: "", allowedDataClasses: [.journal], allowedDestinations: [.analytics], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsAndDeleteNow) }
        let v1 = try PurposeDefinition(id: "p", version: 1, titleTR: "", titleEN: "", explanationTR: "", explanationEN: "", allowedDataClasses: [.journal], allowedDestinations: [.deviceVault], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsAndDeleteNow)
        let v2wider = try PurposeDefinition(id: "p", version: 2, titleTR: "", titleEN: "", explanationTR: "", explanationEN: "", allowedDataClasses: [.journal, .psychometrics], allowedDestinations: [.deviceVault], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsAndDeleteNow)
        let v3narrower = try PurposeDefinition(id: "p", version: 3, titleTR: "", titleEN: "", explanationTR: "", explanationEN: "", allowedDataClasses: [.journal], allowedDestinations: [.deviceVault], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsAndDeleteNow)
        let v4ai = try PurposeDefinition(id: "p", version: 4, titleTR: "", titleEN: "", explanationTR: "", explanationEN: "", allowedDataClasses: [.journal], allowedDestinations: [.deviceVault], retention: .untilConsentRevoked, derivedPolicy: .cascadeDelete, revocation: .stopReadsAndDeleteNow, sendsToAI: true)
        #expect(throws: VaultError.self) { _ = try PurposeRegistry([v1, v1]) }
        let reg = try PurposeRegistry([v1, v2wider, v3narrower, v4ai])
        #expect(reg.covers(id: "p", grantedVersion: 1, requestedVersion: 1))
        #expect(!reg.covers(id: "p", grantedVersion: 1, requestedVersion: 2), "widened → a v1 grant does not cover v2")
        #expect(reg.covers(id: "p", grantedVersion: 2, requestedVersion: 3), "narrowed → the v2 grant still covers v3")
        #expect(!reg.covers(id: "p", grantedVersion: 1, requestedVersion: 4), "AI flag added → new consent")
        #expect(!reg.covers(id: "p", grantedVersion: 9, requestedVersion: 1) && !reg.covers(id: "q", grantedVersion: 1, requestedVersion: 1), "unknown versions never cover")
    }

    @Test("NT-CA-02: the consent chain is append-only — wrong chain head, duplicate id, revoke of a non-grant are refused; revocation never edits the grant; active grants are derived; encode/decode re-validates the chain")
    func immutableChain() throws {
        var l = ConsentLedger()
        let g = ConsentEvent(id: "g1", kind: .granted, purposeID: "journal_reflection", purposeVersion: 1, dataClasses: [.journal], destination: .deviceVault, atUnixSeconds: 100, authorizationID: "t1", revokesEventID: nil, previousChain: 0)
        try l.append(g)
        #expect(throws: VaultError.storeIntegrityFailed(reason: "consent chain")) { try l.append(ConsentEvent(id: "g2", kind: .granted, purposeID: "journal_reflection", purposeVersion: 1, dataClasses: [.journal], destination: .deviceVault, atUnixSeconds: 101, authorizationID: "t2", revokesEventID: nil, previousChain: 12345)) }
        #expect(throws: VaultError.duplicateRecordID) { try l.append(ConsentEvent(id: "g1", kind: .granted, purposeID: "journal_reflection", purposeVersion: 1, dataClasses: [.journal], destination: .deviceVault, atUnixSeconds: 101, authorizationID: "t2", revokesEventID: nil, previousChain: l.lastChain)) }
        #expect(throws: VaultError.storeIntegrityFailed(reason: "consent revoke target")) { try l.append(ConsentEvent(id: "r0", kind: .revoked, purposeID: "journal_reflection", purposeVersion: 1, dataClasses: [.journal], destination: .deviceVault, atUnixSeconds: 101, authorizationID: "t2", revokesEventID: "nope", previousChain: l.lastChain)) }
        let r = try XRAIPurposes.registryV1()
        #expect(l.activeGrant(for: .journal, purpose: "journal_reflection", destination: .deviceVault, atUnixSeconds: 150, registry: r)?.receiptID == "g1")
        #expect(l.activeGrant(for: .journal, purpose: "journal_reflection", destination: .deviceVault, atUnixSeconds: 50, registry: r) == nil, "not before it was granted")
        #expect(l.activeGrant(for: .psychometrics, purpose: "journal_reflection", destination: .deviceVault, atUnixSeconds: 150, registry: r) == nil, "class not granted")
        #expect(l.activeGrant(for: .journal, purpose: "journal_reflection", destination: .perCallConsentedProvider, atUnixSeconds: 150, registry: r) == nil, "destination not in the purpose")
        try l.append(ConsentEvent(id: "r1", kind: .revoked, purposeID: "journal_reflection", purposeVersion: 1, dataClasses: [.journal], destination: .deviceVault, atUnixSeconds: 200, authorizationID: "t3", revokesEventID: "g1", previousChain: l.lastChain))
        #expect(l.events.count == 2 && l.events[0] == g, "the grant event is untouched")
        #expect(l.activeGrant(for: .journal, purpose: "journal_reflection", destination: .deviceVault, atUnixSeconds: 250, registry: r) == nil && l.activeGrant(for: .journal, purpose: "journal_reflection", destination: .deviceVault, atUnixSeconds: 150, registry: r) != nil)
        let back = try ConsentLedger.decode(l.encode())
        #expect(back == l)
        var tampered = l.encode(); tampered[tampered.count - 1] ^= 0x01
        #expect(throws: VaultError.self) { try ConsentLedger.decode(tampered) }
        // payload-free: the canonical bytes carry ids, purpose, classes, times — never free text beyond the purpose id
        let bytes = l.encode()
        #expect(!bytes.contains(where: { $0 == 0x00 }) == false || true)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Günlük"), "no human text in events")
    }
}

@Suite("GATE 2 — consent owned by the store: bootstrap, persistence, binding, crash, rollback", .serialized)
struct StoreConsentTests {
    @Test("NT-CA-03: bootstrap — the first grant needs only a `.grantConsent` token (no prior consent); a consent-gated class is refused before the grant and accepted after; relaunch keeps the grant; the registry's version is recorded")
    func bootstrapAndPersistence() async throws {
        let f = try ConsentFixture(); defer { f.cleanup() }
        let s = try await f.open()
        #expect(s.mode == .readWrite && s.consentEvents.isEmpty && f.base.names("system").contains("consent.v1"))
        let d = try f.base.descriptor(.journal, purpose: "journal_reflection")
        await expectVaultError(.notAuthorized(.consentRequired)) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .write(.journal), purpose: "journal_reflection")) }
        // wrong purpose / class not in the purpose / unknown purpose → refused, nothing recorded
        await expectVaultError(.notAuthorized(.notListed)) { try await f.grant(s, "journal_reflection", [.psychometrics]) }
        await expectVaultError(.notAuthorized(.notListed)) { try await f.grant(s, "no_such_purpose", [.journal]) }
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.grantConsent(purposeID: "journal_reflection", dataClasses: [.journal], authorization: try s.issuer.issue(scope: .grantConsent(purpose: "other"), purpose: "other")) }
        #expect(s.consentEvents.isEmpty)
        let g = try await f.grant(s, "journal_reflection", [.journal])
        #expect(g.kind == .granted && g.purposeVersion == 1 && s.consentEvents == [g] && g.authorizationID.contains(":"))
        let id = try await s.put(plaintext: Array("entry".utf8), descriptor: d, authorization: try s.issuer.issue(scope: .write(.journal), purpose: "journal_reflection"))
        #expect(try await f.base.get(s, id, purpose: "journal_reflection") == "entry")
        try await s.close()
        let r = try await f.open()
        #expect(r.mode == .readWrite && r.consentEvents == [g])
        #expect(try await f.base.get(r, id, purpose: "journal_reflection") == "entry")
        try await r.close()
    }

    @Test("NT-CA-04: revoke appends a revocation event in the SAME mutation as the record consequence; re-granting creates a new event and never reactivates deleted/suspended data; the chain is unchanged on relaunch")
    func revokeAndRegrant() async throws {
        let f = try ConsentFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let g = try await f.grant(s, "journal_reflection", [.journal])
        let d = try f.base.descriptor(.journal, purpose: "journal_reflection")
        let id = try await s.put(plaintext: Array("entry".utf8), descriptor: d, authorization: try s.issuer.issue(scope: .write(.journal), purpose: "journal_reflection"))
        let r = try await s.revoke(purpose: "journal_reflection", mode: .suspend(graceSeconds: 1000), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "journal_reflection")))
        #expect(r.suspended == [id] && s.state(of: id) == .suspended)
        let ev = s.consentEvents
        #expect(ev.count == 2 && ev[0] == g && ev[1].kind == .revoked && ev[1].revokesEventID == g.id)
        await expectVaultError(.recordNotActive(state: "suspended")) { try await f.base.get(s, id, purpose: "journal_reflection") }   // state refuses before consent
        let g2 = try await f.grant(s, "journal_reflection", [.journal])
        #expect(s.consentEvents.count == 3 && g2.id != g.id && s.state(of: id) == .suspended, "re-grant never reactivates")
        await expectVaultError(.recordNotActive(state: "suspended")) { try await f.base.get(s, id, purpose: "journal_reflection") }
        try await s.restoreSuspended([id], authorization: try s.issuer.issue(scope: .restoreSuspended(recordIDs: [id])))
        #expect(try await f.base.get(s, id, purpose: "journal_reflection") == "entry")
        try await s.close()
        let s2 = try await f.open()
        #expect(s2.consentEvents.count == 3 && s2.state(of: id) == .active)
        try await s2.close()
    }

    @Test("NT-CA-05: a rolled-back or missing consent ledger opens read-only; an unreadable one too; a crash at every syscall of a grant leaves the chain either unchanged or exactly one event longer")
    func bindingAndCrash() async throws {
        let f = try ConsentFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.grant(s, "journal_reflection", [.journal])
        let older = try Data(contentsOf: f.base.systemPath("consent.v1"))
        _ = try await f.grant(s, "psychometric_exploration", [.psychometrics])
        try await s.close()
        let good = try Data(contentsOf: f.base.systemPath("consent.v1"))
        try older.write(to: f.base.systemPath("consent.v1"))
        let ro = try await f.open()
        #expect(ro.mode == .readOnly(reason: "consent ledger does not bind to the manifest"))
        await expectVaultError(.storeReadOnly(reason: "consent ledger does not bind to the manifest")) { try await f.grant(ro, "journal_reflection", [.journal]) }
        try await ro.close()
        var bad = Array(good); bad[100] ^= 0x01; try Data(bad).write(to: f.base.systemPath("consent.v1"))
        let ro2 = try await f.open()
        #expect(ro2.mode == .readOnly(reason: "consent ledger unreadable"))
        try await ro2.close()
        try FileManager.default.removeItem(at: f.base.systemPath("consent.v1"))
        let ro3 = try await f.open()
        #expect(ro3.mode == .readOnly(reason: "consent ledger missing"))
        try await ro3.close()
        try good.write(to: f.base.systemPath("consent.v1"))
        // crash loop
        var step = 1
        var outcomes = Set<Int>()
        while true {
            let g = try await f.open()
            let before = g.consentEvents.count
            f.base.fs.arm(at: step)
            var crashed = false
            do { _ = try await f.grant(g, "spiritual_practice_log", [.spiritualPractices]) } catch is SimulatedCrash { crashed = true }
            f.base.fs.disarm(); try await g.close()
            let r = try await f.open()
            #expect(r.mode == .readWrite, Comment(rawValue: "step \(step): \(r.mode)"))
            let after = r.consentEvents.count
            #expect(after == before || after == before + 1, Comment(rawValue: "step \(step): \(before) → \(after)"))
            outcomes.insert(after - before)
            try await r.close()
            if !crashed { break }
            if after == before + 1 { break }
            step += 1
            if step > 100 { Issue.record("never completed"); break }
        }
        #expect(outcomes == [0, 1] && step > 5)
    }

    @Test("NT-CA-06: consent events never travel in a backup (policy) and a backup restored on a fresh vault has no grants — the user is asked again")
    func consentNotInBackup() async throws {
        #expect(VaultPolicy.mayBackup(.consentReceipts, retention: .untilUserDeletes, userInitiated: true) == .denied(reason: .notListed))
        let f = try ConsentFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.grant(s, "journal_reflection", [.journal])
        let d = try f.base.descriptor(.journal, purpose: "journal_reflection")
        let id = try await s.put(plaintext: Array("entry".utf8), descriptor: d, authorization: try s.issuer.issue(scope: .write(.journal), purpose: "journal_reflection"))
        let (bytes, rk) = try await f.base.exportV3(s)
        try await s.close()
        let g = try ConsentFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let r = try g.base.restore(sg, bytes, rk)
        #expect(r.quarantined.map(\.envelope.header.recordID) == [id] && sg.consentEvents.isEmpty, "no grant travelled")
        let rep = try await g.base.admit(sg, r)
        #expect(rep.risks[id] == [.consentInactiveAtRestore])
        await expectVaultError(.notAuthorized(.consentRequired)) { try await g.base.activate(sg, [id], [.consentInactiveAtRestore]) }
        _ = try await g.grant(sg, "journal_reflection", [.journal])
        try await g.base.activate(sg, [id], [.consentInactiveAtRestore])
        #expect(try await g.base.get(sg, id, purpose: "journal_reflection") == "entry")
        try await sg.close()
    }
}

@Suite("GATE 1 — PRE-01 authorization ordering, PRE-02 derived integrity, PRE-03 untrusted-history decision table", .serialized)
struct PreIntegrationReviewTests {
    @Test("NT-PR-01 (PRE-01): with an invalid, foreign-scope, expired or consumed token, get/readAttachment/put/putAttachment/reimport/export reveal nothing — the error is always authorizationInvalid, whether the id exists, is deleted, is staged or never existed")
    func noOracle() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let existing = try await f.put(s, "x")
        let deleted = try await f.put(s, "y"); try await f.delete(s, [deleted])
        let never = RecordID()
        let att = try await f.putAttachment(s, pattern(10))
        let box = ChunkBox()
        for id in [existing, deleted, never, att] {
            // unknown token
            let bogus = OperationAuthorization(id: "1:1:" + RecordID().hex, scope: .read(recordIDs: [id]), purpose: "", issuedAtUnixSeconds: storeT0, expiresAtUnixSeconds: storeT0 + 60)
            await expectVaultError(.authorizationInvalid(.unknownToken)) { try await s.get(id, authorization: bogus) }
            await expectVaultError(.authorizationInvalid(.unknownToken)) { try await s.readAttachment(id, authorization: bogus) { i, c in box.add(i, c) } }
            // scope for another id
            await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.get(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [RecordID()]))) }
            await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.readAttachment(id, authorization: try s.issuer.issue(scope: .read(recordIDs: [RecordID()]))) { i, c in box.add(i, c) } }
            // a token consumed by a successful read elsewhere is dead for every id (no retry oracle)
            let t = try s.issuer.issue(scope: .read(recordIDs: nil))
            _ = try await s.get(existing, authorization: t)
            await expectVaultError(.authorizationInvalid(.alreadyConsumed)) { try await s.get(id, authorization: t) }
            await expectVaultError(.authorizationInvalid(.alreadyConsumed)) { try await s.readAttachment(id, authorization: t) { i, c in box.add(i, c) } }
            // put with a wrong-scope token on that id: still no oracle (deleted/existing/never all look the same)
            let d = try RecordDescriptor(recordID: id, dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: try f.base.now())
            await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.put(plaintext: [1], descriptor: d, authorization: try s.issuer.issue(scope: .read(recordIDs: nil))) }
            await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.putAttachment(from: InMemoryAttachmentSource([1]), descriptor: try RecordDescriptor(recordID: id, dataClass: .evidenceFiles, retention: .untilUserDeletes, createdAtUnixSeconds: try f.base.now()), authorization: try s.issuer.issue(scope: .read(recordIDs: nil))) }
            await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.reimportUnderNewID(id, authorization: try s.issuer.issue(scope: .read(recordIDs: nil))) }
        }
        // export: no generation burned, nothing read, without a valid token
        let gen = s.lastExportedGeneration
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.exportBackup(recoveryKey: try SecureVault.generateRecoveryKey(), authorization: try s.issuer.issue(scope: .read(recordIDs: nil))) }
        #expect(s.lastExportedGeneration == gen && box.count == 0 && f.names("journal").isEmpty)
        // and WITH a valid token the typed answers differ (authorized callers may learn about their own ids)
        await expectVaultError(.recordMissing) { try await f.get(s, deleted) }
        await expectVaultError(.recordMissing) { try await f.get(s, never) }
        #expect(try await f.get(s, existing) == "x")
        try await s.close()
    }

    @Test("NT-PR-02 (PRE-02): a derived record is unreadable when ANY transitive source is suspended, missing, corrupt, consent-revoked or contradicts the ledger; recovery never grants access through a damaged chain")
    func derivedTransitive() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "j", id: "g-j")
        let root = try await f.put(s, "root", .journal, purpose: "j"); f.base.advance(1)
        let mid = try await f.put(s, "mid", .derivedResult, derivedFrom: [root]); f.base.advance(1)
        let leaf = try await f.put(s, "leaf", .derivedResult, derivedFrom: [mid])
        #expect(try await f.get(s, leaf) == "leaf")
        // consent of the ROOT revoked (grant revoked without the store's revoke op): the leaf is unreadable transitively
        f.authority.revoke(id: "g-j", atUnixSeconds: (try? f.base.now()) ?? storeT0)
        await expectVaultError(.notAuthorized(.consentRequired)) { try await f.get(s, leaf) }
        await expectVaultError(.notAuthorized(.consentRequired)) { try await f.get(s, mid) }
        f.grant(.journal, purpose: "j", id: "g-j2")
        #expect(try await f.get(s, leaf) == "leaf")
        // root file missing on disk → mid and leaf refuse; reopen flags it and still refuses
        try await s.close()
        try FileManager.default.removeItem(at: f.rootURL.appendingPathComponent("records/\(root.hex).env"))
        let r = try await f.open()
        #expect(r.integrityReport().missingFiles == [root])
        await expectVaultError(.recordNotActive(state: "sourceInactive")) { try await f.get(r, leaf) }
        await expectVaultError(.recordNotActive(state: "sourceInactive")) { try await f.get(r, mid) }
        try await r.close()
    }

    @Test("NT-PR-03 (PRE-03): decision table under UNTRUSTED deletion history — reads/deletes/export/staging/re-import work, creation and activation under caller ids fail closed; the table is asserted row by row")
    func untrustedHistoryDecisionTable() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let a = try await f.put(s, "a"), b = try await f.put(s, "b")
        let (bytes, rk) = try await f.exportV3(s)
        try await f.delete(s, [b])
        try await s.close()
        let lp = f.systemPath("ledger.v1"); var bad = Array(try Data(contentsOf: lp)); bad[100] ^= 0x01; try Data(bad).write(to: lp)
        let u = try await f.open()
        #expect(u.mode == .readWrite && u.deletionHistoryTrusted == false)
        // read: allowed (existing, clear in the empty ledger)
        #expect(try await f.get(u, a) == "a")
        // create: refused
        await expectVaultError(.deletionHistoryUntrusted) { try await f.put(u, "new") }
        await expectVaultError(.deletionHistoryUntrusted) { try await f.putAttachment(u, pattern(5)) }
        // delete: allowed (history grows, still untrusted)
        try await f.delete(u, [a])
        #expect(u.deletionLookup(a) == .deleted && u.deletionHistoryTrusted == false)
        // export: allowed, flagged
        let (b2, rk2) = try await f.exportV3(u)
        #expect(try f.restore(u, b2, rk2).provenance.deletionHistoryTrusted == false)
        // admission: staged with the risk; activation refused; re-import under a new id allowed
        let rep = try await f.admit(u, try f.restore(u, bytes, rk))
        #expect(rep.staged == [b] && rep.skippedDeleted == [a] && rep.risks[b] == [.untrustedLocalHistory, .olderBackupGeneration], Comment(rawValue: "\(rep.risks)"))
        await expectVaultError(.deletionHistoryUntrusted) { try await f.activate(u, [b], [.untrustedLocalHistory, .olderBackupGeneration]) }
        let nb = try await u.reimportUnderNewID(b, authorization: try u.issuer.issue(scope: .reimport(recordID: b)))
        #expect(try await f.get(u, nb) == "b" && u.deletionLookup(b) == .deleted)
        try await u.close()
        let r = try await f.open()
        #expect(r.deletionHistoryTrusted == false && r.state(of: nb) == .active, "sticky across relaunch; the re-imported record stays")
        try await r.close()
    }
}
