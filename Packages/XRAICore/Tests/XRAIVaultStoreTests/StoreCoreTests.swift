import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultStore
import XRAIVaultTesting

@Suite("Store core: round trip, states, derived graph, directory hygiene", .serialized)
struct StoreCoreTests {
    @Test("put/get round-trips; a fresh vault has generation 1, epoch 1, anchor bound; relaunch keeps data and bumps the epoch")
    func roundTripAndRelaunch() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        #expect(s.mode == .readWrite && s.epoch == 1 && (s.manifestGeneration) == 1)
        let id = try await f.put(s, "1998-06-30")
        #expect(try await f.get(s, id) == "1998-06-30")
        #expect(s.state(of: id) == .active && (s.manifestGeneration) == 2)
        let a = try #require(try f.anchor.readAnchor())
        #expect(a.manifestGeneration == 2 && a.manifestHash == (s.manifestHash) && a.vaultInstanceID == (s.vaultInstanceID))
        try await s.close()
        let s2 = try await f.open()
        #expect(s2.epoch == 2 && (s2.mode) == .readWrite)
        #expect(try await f.get(s2, id) == "1998-06-30")
        try await s2.close()
    }

    @Test("NT-H5-15: directory listing shows only hex names, system/*.v1, journal/*.j; every file is a 4 KiB multiple")
    func directoryHygiene() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        for i in 0..<5 { try await f.put(s, "secret-\(i)") }
        let records = f.names("records")
        #expect(records.count == 5)
        for n in records { #expect(n.count == 36 && n.hasSuffix(".env") && n.dropLast(4).allSatisfy { "0123456789abcdef".contains($0) }) }
        #expect(f.names("system") == ["authz.v1", "ledger.v1", "manifest.v1"])
        #expect(f.names("journal").isEmpty)
        for sub in ["records", "system"] {
            for n in f.names(sub) {
                let size = (try FileManager.default.attributesOfItem(atPath: f.rootURL.appendingPathComponent("\(sub)/\(n)").path)[.size] as? Int) ?? -1
                #expect(size > 0 && size % 4096 == 0, Comment(rawValue: "\(sub)/\(n) size \(size)"))
            }
        }
        // No plaintext leaks: the record bytes never contain the payload, class names or the token id.
        for n in records {
            let bytes = try Data(contentsOf: f.rootURL.appendingPathComponent("records/\(n)"))
            #expect(!bytes.contains("secret".data(using: .utf8)!))
        }
        try await s.close()
    }

    @Test("NT-H5-14: stale / suspended / quarantined / missing / corrupt / orphan are each a distinct typed denial, never plaintext")
    func everyNonActiveStateDenied() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "p", id: "g-p")
        let j = try await f.put(s, "diary", .journal, purpose: "p")
        let d = try await f.put(s, "derived-of-diary", .derivedResult, derivedFrom: [j])
        // suspended source → derived denied as sourceInactive; the suspended record itself denied as suspended
        f.authority.revoke(id: "g-p", atUnixSeconds: try f.base.now())
        let r = try await s.revoke(purpose: "p", mode: .suspend(graceSeconds: 100), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "p")))
        #expect(r.suspended == [j] && r.deleted == [d], "derived records of a suspended source are deleted now")
        await expectVaultError(.recordNotActive(state: "suspended")) { try await f.get(s, j, purpose: "p") }
        await expectVaultError(.recordMissing) { try await f.get(s, d) }
        // missing file
        let m = try await f.put(s, "will-vanish")
        try FileManager.default.removeItem(at: f.rootURL.appendingPathComponent("records/\(m.hex).env"))
        await expectVaultError(.recordMissing) { try await f.get(s, m) }
        // corrupt file (NT-H5-10)
        let c = try await f.put(s, "will-corrupt")
        let p = f.rootURL.appendingPathComponent("records/\(c.hex).env")
        var bytes = Array(try Data(contentsOf: p)); bytes[200] ^= 0x01; try Data(bytes).write(to: p)
        await expectVaultError(.recordNotActive(state: "corrupt")) { try await f.get(s, c) }
        // unknown id
        await expectVaultError(.recordMissing) { try await f.get(s, RecordID()) }
        try await s.close()
    }

    @Test("NT-H5-08/09: an extra file is moved to orphans/ and never opened; a manifest entry without a file reports missing")
    func orphansAndMissing() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.put(s, "kept")
        let gone = try await f.put(s, "gone")
        try await s.close()
        // foreign file dropped into records/
        let stray = f.rootURL.appendingPathComponent("records/\(RecordID().hex).env")
        try Data(repeating: 7, count: 4096).write(to: stray)
        try FileManager.default.removeItem(at: f.rootURL.appendingPathComponent("records/\(gone.hex).env"))
        let s2 = try await f.open()
        let rep = s2.integrityReport()
        #expect(rep.orphansQuarantined == 1 && rep.missingFiles == [gone] && rep.mode == .readWrite)
        #expect(f.names("orphans").count == 1 && f.names("records").count == 1)
        #expect(try await f.get(s2, id) == "kept")
        await expectVaultError(.recordMissing) { try await f.get(s2, gone) }
        try await s2.close()
    }

    @Test("NT-H5-11/12: symlinks and malformed ids are refused before any file is touched")
    func pathSafety() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "x")
        try await s.close()
        // symlink inside records/ pointing outside the vault
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("xrai-outside-" + RecordID().hex)
        try Data(repeating: 1, count: 4096).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = f.rootURL.appendingPathComponent("records/\(RecordID().hex).env")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await expectVaultError(.storeIntegrityFailed(reason: "non-regular entry in records/")) { try await f.open() }
        try FileManager.default.removeItem(at: link)
        // ids: RecordID itself rejects traversal / uppercase / wrong length before any path is built
        for bad in ["../../etc/passwd", "ABCDEF0123456789ABCDEF0123456789", "0123456789abcdef0123456789abcde", "0123456789abcdef0123456789abcdef/x"] {
            #expect(throws: VaultError.invalidRecordID) { try RecordID(hex: bad) }
        }
        // a symlinked vault root is refused
        let rootLink = FileManager.default.temporaryDirectory.appendingPathComponent("xrai-rootlink-" + RecordID().hex)
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: f.rootURL)
        defer { try? FileManager.default.removeItem(at: rootLink) }
        await expectVaultError(.storeIntegrityFailed(reason: "vault root is not a directory")) {
            try await FileVaultStore.open(root: rootLink, keyProvider: f.keys, anchor: f.anchor, composition: f.composition, fileSystem: f.fs)
        }
    }

    @Test("NT-H5-13: a second instance on the same root is refused while the first holds the lock; a dead-pid lock is reclaimed")
    func singleWriterLock() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        await expectVaultError(.storeLocked) { try await f.open() }
        try await s.close()
        // stale lock from a dead process
        try "999999999:1".write(to: f.rootURL.appendingPathComponent("vault.lock"), atomically: true, encoding: .utf8)
        let s2 = try await f.open()
        #expect(s2.mode == .readWrite)
        try await s2.close()
    }

    @Test("NT-DG-01/02/03: cascade deletes dependents first; back-edges and unknown sources are rejected; revoking a source blocks the derived record")
    func derivedGraph() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.psychometrics, purpose: "q", id: "g-q")
        let src = try await f.put(s, "answers", .psychometrics, purpose: "q")
        f.base.advance(1)
        let d1 = try await f.put(s, "score", .derivedResult, derivedFrom: [src])
        f.base.advance(1)
        let d2 = try await f.put(s, "interpretation", .derivedResult, derivedFrom: [d1])
        // back-edge: a source created later than the new record
        await expectVaultError(.unknownDependency) {
            try await s.put(plaintext: [1], descriptor: try f.descriptor(.derivedResult, derivedFrom: [d2], at: storeT0), authorization: try s.issuer.issue(scope: .write(.derivedResult)))
        }
        await expectVaultError(.unknownDependency) {
            try await s.put(plaintext: [1], descriptor: try f.descriptor(.derivedResult, derivedFrom: [RecordID()]), authorization: try s.issuer.issue(scope: .write(.derivedResult)))
        }
        #expect(throws: VaultError.unknownDependency) { let id = RecordID(); _ = try RecordDescriptor(recordID: id, dataClass: .derivedResult, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0, derivedFrom: [id]) }
        // NT-DG-03: revoke the source's purpose → derived unreadable immediately (consent inherited at read time)
        #expect(try await f.get(s, d2) == "interpretation")
        f.authority.revoke(id: "g-q", atUnixSeconds: try f.base.now())
        await expectVaultError(.notAuthorized(.consentRequired)) { try await f.get(s, d1) }
        f.grant(.psychometrics, purpose: "q", id: "g-q2")
        #expect(try await f.get(s, d1) == "score")
        // NT-DG-01: cascade order dependents-first, all ledgered
        try await f.delete(s, [src])
        for id in [src, d1, d2] {
            #expect(s.state(of: id) == nil && !f.fileExists(id))
            #expect(s.deletionLookup(id) == .deleted)
        }
        #expect(s.deletionCount == 3)
        try await s.close()
    }

    #if os(iOS)
    @Test("NT-H5-16 (iOS host): every vault file carries NSFileProtectionComplete (physical device; the Simulator does not implement file protection) and the root is excluded from backup")
    func protectionAttributes() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "x")
        var classes: [String: String?] = [:]
        for sub in ["records", "system"] {
            for n in f.names(sub) {
                classes["\(sub)/\(n)"] = try RealFileSystem().protectionClass(f.rootURL.appendingPathComponent("\(sub)/\(n)").path)
            }
        }
        #expect(classes.count == 4)
        #if targetEnvironment(simulator)
        // KNOWN_LIMITATION: the iOS Simulator reports no Data Protection class (no SEP-backed file keys);
        // this assertion is DEVICE evidence only. Recorded, not faked.
        #expect(classes.values.allSatisfy { $0 == nil || $0 == FileProtectionType.complete.rawValue }, Comment(rawValue: "\(classes)"))
        #else
        for (path, cls) in classes { #expect(cls == FileProtectionType.complete.rawValue, Comment(rawValue: "\(path): \(cls ?? "nil")")) }
        #endif
        let values = try f.rootURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        try await s.close()
    }
    #endif
}

@Suite("H3 — epoch tokens, persisted clock mark", .serialized)
struct StoreAuthzTests {
    @Test("NT-H3-01/02: a token from the previous epoch is rejected after relaunch; 20 000 consumed tokens never evict (replay is still alreadyConsumed)")
    func epochAndNoEviction() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let id = try await f.put(s, "x")
        let old = try s.issuer.issue(scope: .read(recordIDs: [id]))
        try await s.close()
        let s2 = try await f.open()
        #expect(s2.epoch == s.epoch + 1)
        await expectVaultError(.authorizationInvalid(.epochMismatch)) { try await s2.get(id, authorization: old) }
        // same-epoch replay after many tokens
        let first = try s2.issuer.issue(scope: .read(recordIDs: [id]))
        _ = try await s2.get(id, authorization: first)
        for _ in 0..<20_000 { let t = try s2.issuer.issue(scope: .maintenance(.integrityCheck)); _ = try? s2.vault.verify(RecordEnvelope(header: EnvelopeHeader(algorithm: .aes256gcm, descriptor: try f.descriptor()), wrappedDEK: WrappedKey(keyID: "device", keyVersion: 1, boundRecordID: RecordID(), nonce: [], ciphertext: [], tag: []), nonce: [], ciphertext: [], tag: []), maintenance: t) }
        await expectVaultError(.authorizationInvalid(.alreadyConsumed)) { try await s2.get(id, authorization: first) }
        // a forged id with the right epoch but unknown counter/random is unknown
        await expectVaultError(.authorizationInvalid(.unknownToken)) { try await s2.get(id, authorization: OperationAuthorization(id: String(s2.epoch, radix: 16) + ":1:" + RecordID().hex, scope: .read(recordIDs: nil), purpose: "", issuedAtUnixSeconds: storeT0, expiresAtUnixSeconds: storeT0 + 60)) }
        try await s2.close()
    }

    @Test("NT-H3-07: the clock mark survives relaunch — a wall clock set back within tolerance yields the mark; beyond tolerance fails closed; nothing expires or activates")
    func persistedClockMark() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "p", id: "g-p")
        let j = try await f.put(s, "diary", .journal, purpose: "p")
        f.base.set(storeT0 + 10_000)
        f.authority.revoke(id: "g-p", atUnixSeconds: storeT0 + 10_000)
        _ = try await s.revoke(purpose: "p", mode: .suspend(graceSeconds: 1_000), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "p")))
        #expect(try s.clock.now() == storeT0 + 10_000)
        try await s.close()
        f.base.set(storeT0 + 10_000 - 100)                       // rolled back 100 s across relaunch (within tolerance)
        let s2 = try await f.open()
        #expect(try s2.clock.now() == storeT0 + 10_000, "effective time never drops below the persisted mark")
        #expect(s2.state(of: j) == .suspended)
        try await s2.close()
        f.base.set(storeT0 + 10_000 - 86_400)                    // rolled back a day: fail closed
        let s3 = try await f.open()
        #expect(throws: VaultError.clockRegressed) { try s3.clock.now() }
        await expectVaultError(.clockRegressed) { try await f.get(s3, j, purpose: "p") }
        #expect(s3.state(of: j) == .suspended)
        try await s3.close()
        // forward again: the grace expires at the effective time and the record is deleted (NT-H4-05)
        f.base.set(storeT0 + 20_000)
        let s4 = try await f.open()
        #expect(s4.state(of: j) == nil && (s4.deletionLookup(j)) == .deleted)
        try await s4.close()
    }

    @Test("NT-H3-04/05: an older authz.v1 snapshot fails the manifest binding (read-only); store metadata can never be exported in a backup")
    func authzRollbackAndNoExport() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        _ = try await f.put(s, "a")
        let snapshot = try Data(contentsOf: f.systemPath("authz.v1"))
        _ = try await f.put(s, "b")
        try await s.close()
        try snapshot.write(to: f.systemPath("authz.v1"))
        let s2 = try await f.open()
        #expect(s2.mode == .readOnly(reason: "authorization state does not bind to the manifest"))
        await expectVaultError(.storeReadOnly(reason: "authorization state does not bind to the manifest")) { try await f.put(s2, "c") }
        // export path refuses the system class even with a valid export token
        let sys = try s2.vault.sealSystem(plaintext: [1, 2, 3], descriptor: try RecordDescriptor(dataClass: .storeMetadata, retention: .untilUserDeletes, createdAtUnixSeconds: storeT0))
        let rk = try SecureVault.generateRecoveryKey()
        #expect(throws: VaultError.notAuthorized(.notListed)) { try s2.vault.exportBackup([sys], recoveryKey: rk, authorization: try s2.issuer.issue(scope: .exportBackup)) }
        try await s2.close()
    }

    @Test("NT-H3-06: revoke is linearizable with reads — no read that starts after the revoke returns succeeds")
    func revokeLinearizable() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "p", id: "g-p")
        let j = try await f.put(s, "diary", .journal, purpose: "p")
        var tokens: [OperationAuthorization] = []
        for _ in 0..<100 { tokens.append(try s.issuer.issue(scope: .read(recordIDs: [j]), purpose: "p")) }
        f.authority.revoke(id: "g-p", atUnixSeconds: try f.base.now())
        _ = try await s.revoke(purpose: "p", mode: .suspend(graceSeconds: 100), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "p")))
        let results = await withTaskGroup(of: Bool.self) { group in
            for t in tokens { group.addTask { (try? await s.get(j, authorization: t)) != nil } }
            var ok = 0; for await r in group where r { ok += 1 }; return ok
        }
        #expect(results == 0)
        try await s.close()
    }
}

@Suite("H4 — revoke vs delete, suspension, grace", .serialized)
struct StoreRevokeTests {
    @Test("NT-H4-01: 'Kalıcı sil' deletes now with a ledger entry and never produces a suspended state")
    func permanentDeleteHasNoGrace() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "p", id: "g-p")
        let j = try await f.put(s, "diary", .journal, purpose: "p")
        try await f.delete(s, [j])
        #expect(s.state(of: j) == nil && (s.deletionLookup(j)) == .deleted && !f.fileExists(j))
        // reusing the grant is refused
        await expectVaultError(.deletionGrantInvalid) { try await s.delete([j], grant: DeletionGrant(recordIDs: [j], authorizedAtUnixSeconds: storeT0)) }
        try await s.close()
    }

    @Test("NT-H4-02/03: suspension blocks reads, deletes derived data now, excludes from export, and re-granting does not reactivate; restoreSuspended needs a token + active grant")
    func suspendThenRegrant() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.journal, purpose: "p", id: "g-p")
        let j = try await f.put(s, "diary", .journal, purpose: "p")
        let d = try await f.put(s, "mood", .derivedResult, derivedFrom: [j])
        f.authority.revoke(id: "g-p", atUnixSeconds: try f.base.now())
        let r = try await s.revoke(purpose: "p", mode: .suspend(graceSeconds: 7 * 86_400), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "p")))
        #expect(r.suspended == [j] && r.deleted == [d])
        #expect(s.state(of: j) == .suspended && (s.state(of: d)) == nil)
        await expectVaultError(.recordNotActive(state: "suspended")) { try await f.get(s, j, purpose: "p") }
        // re-grant alone changes nothing
        f.grant(.journal, purpose: "p", id: "g-p2")
        #expect(s.state(of: j) == .suspended)
        await expectVaultError(.recordNotActive(state: "suspended")) { try await f.get(s, j, purpose: "p") }
        // explicit restore with the right scope and an active grant
        await expectVaultError(.authorizationInvalid(.scopeMismatch)) { try await s.restoreSuspended([j], authorization: try s.issuer.issue(scope: .read(recordIDs: nil))) }
        try await s.restoreSuspended([j], authorization: try s.issuer.issue(scope: .restoreSuspended(recordIDs: [j])))
        #expect(try await f.get(s, j, purpose: "p") == "diary")
        // without an active grant the restore is refused
        f.authority.revoke(id: "g-p2", atUnixSeconds: try f.base.now())
        _ = try await s.revoke(purpose: "p", mode: .suspend(graceSeconds: 100), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "p")))
        await expectVaultError(.notAuthorized(.consentRequired)) { try await s.restoreSuspended([j], authorization: try s.issuer.issue(scope: .restoreSuspended(recordIDs: [j]))) }
        try await s.close()
    }

    @Test("NT-H4-04: third-party classes cannot be suspended — revoke must delete immediately")
    func thirdPartyNotGraceEligible() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        f.grant(.parentsNames, purpose: "fam", id: "g-fam")
        let p = try await f.put(s, "names", .parentsNames, purpose: "fam")
        await expectVaultError(.notEligible(reason: "class not grace-eligible: parents_names")) {
            try await s.revoke(purpose: "fam", mode: .suspend(graceSeconds: 100), authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "fam")))
        }
        #expect(s.state(of: p) == .active)
        let r = try await s.revoke(purpose: "fam", mode: .deleteNow, authorization: try s.issuer.issue(scope: .revokeConsent(purpose: "fam")))
        #expect(r.deleted == [p] && (s.deletionLookup(p)) == .deleted)
        try await s.close()
    }
}

@Suite("H1 — permanent deletion ledger and fail-closed restore admission", .serialized)
struct StoreLedgerTests {
    /// P03-04b: v3 backup of every active record through the store, restored through the facade.
    private func backup(of f: StoreFixture, _ s: FileVaultStore, ids: [RecordID]) async throws -> (RestoreResult, RecoveryKey, [UInt8]) {
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try await s.exportBackup(recoveryKey: rk, authorization: try s.issuer.issue(scope: .exportBackup))
        let result = try s.vault.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try s.issuer.issue(scope: .restoreBackup))
        #expect(Set(result.active.map(\.header.recordID)).isSuperset(of: ids))
        return (result, rk, bytes)
    }

    @Test("NT-H1-01/04: a deleted id in a backup is skipped, never reactivated — not even through release; reimport creates a NEW id with provenance")
    func deletedNeverReturns() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let a = try await f.put(s, "A"), b = try await f.put(s, "B")
        let (result, _, _) = try await backup(of: f, s, ids: [a, b])
        try await f.delete(s, [a])
        let rep = try await s.admitRestored(result, authorization: try s.issuer.issue(scope: .admitRestored))
        #expect(rep.skippedDeleted == [a] && rep.skippedExisting == [b] && rep.staged.isEmpty)
        #expect(s.state(of: a) == nil && !f.fileExists(a))
        // P03-04bH2: `releaseQuarantined` no longer exists (compile-negative); activation of a deleted id is refused by `activateRestored`
        await expectVaultError(.recordMissing) { try await s.activateRestored([a], acknowledging: [], authorization: try s.issuer.issue(scope: .activateRestored(recordIDs: [a]))) }
        // explicit re-import = a new record under a new id
        let env = result.active.first { $0.header.recordID == a }!
        let newID = try await s.put(plaintext: try s.vault.open(env, authorization: try s.issuer.issue(scope: .read(recordIDs: [a]))), descriptor: try f.descriptor(), authorization: try s.issuer.issue(scope: .write(.birthDate)), provenance: .reimportedAfterDeletion)
        #expect(newID != a && (s.state(of: newID)) == .active && s.entry(of: newID)?.provenance == .reimportedAfterDeletion)
        #expect(s.deletionLookup(a) == .deleted, "the old id stays deleted forever")
        try await s.close()
    }

    @Test("NT-H1-02/03: a corrupted ledger quarantines every restored record; a missing ledger makes the vault read-only with restore refused")
    func untrustedLedger() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let a = try await f.put(s, "A")
        let (_, rk, bytes) = try await backup(of: f, s, ids: [a])
        try await f.delete(s, [a])
        try await s.close()
        let lp = f.systemPath("ledger.v1")
        let good = try Data(contentsOf: lp)
        var bad = Array(good); bad[100] ^= 0x01; try Data(bad).write(to: lp)
        let s2 = try await f.open()
        #expect(s2.deletionHistoryTrusted == false && (s2.mode) == .readWrite)
        // P03-04bH: a result is verified only by the facade instance that restored it → restore again in this session
        let result = try s2.vault.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try s2.issuer.issue(scope: .restoreBackup))
        let rep = try await s2.admitRestored(result, authorization: try s2.issuer.issue(scope: .admitRestored))
        #expect(rep.staged == [a] && rep.risks[a]?.contains(.untrustedLocalHistory) == true, "with no trustworthy history, nothing becomes active without acknowledging it")
        #expect(s2.state(of: a) == .quarantined)
        await expectVaultError(.recordNotActive(state: "quarantined")) { try await f.get(s2, a) }
        try await s2.close()
        try FileManager.default.removeItem(at: lp)
        let s3 = try await f.open()
        #expect(s3.deletionHistoryTrusted == false && s3.mode == .readOnly(reason: "deletion ledger missing"))
        await expectVaultError(.storeReadOnly(reason: "deletion ledger missing")) { try await s3.admitRestored(result, authorization: try s3.issuer.issue(scope: .admitRestored)) }
        await expectVaultError(.storeReadOnly(reason: "deletion ledger missing")) { try await f.put(s3, "no writes either") }
        try await s3.close()
    }

    @Test("NT-H1-05: a backup from another (or unknown) vault instance is staged whole with a foreign/legacy risk while this vault holds data; activated per record only with acknowledgment + consent, never through releaseQuarantined")
    func foreignBackupQuarantined() async throws {
        let f = StoreFixture(); defer { f.cleanup() }
        let s = try await f.open()
        let a = try await f.put(s, "A")
        let (result, _, _) = try await backup(of: f, s, ids: [a])
        try await f.delete(s, [a])
        _ = try await f.put(s, "local")
        let rep1 = try await s.admitRestored(result, authorization: try s.issuer.issue(scope: .admitRestored))
        #expect(rep1.skippedDeleted == [a] && rep1.staged.isEmpty, "the local ledger wins")
        // a GENUINE foreign backup: exported by another vault instance, restored through this facade (verified)
        let g = StoreFixture(); defer { g.cleanup() }
        let sg = try await g.open()
        let fid = try await g.put(sg, "foreign")
        let rk = try SecureVault.generateRecoveryKey()
        let foreignBytes = try await sg.exportBackup(recoveryKey: rk, authorization: try sg.issuer.issue(scope: .exportBackup))
        try await sg.close()
        let rep2 = try await s.admitRestored(try s.vault.restoreBackup(bytes: foreignBytes, recoveryKey: rk, authorization: try s.issuer.issue(scope: .restoreBackup)), authorization: try s.issuer.issue(scope: .admitRestored))
        #expect(rep2.staged == [fid] && rep2.risks[fid] == [.foreignInstance] && s.state(of: fid) == .quarantined)
        #expect(f.quarantine.isQuarantined(fid))
        await expectVaultError(.recordNotActive(state: "quarantined")) { try await f.get(s, fid) }
        await expectVaultError(.notEligible(reason: "restore risks must be acknowledged exactly: need 1 got ")) { try await s.activateRestored([fid], acknowledging: [], authorization: try s.issuer.issue(scope: .activateRestored(recordIDs: [fid]))) }
        #expect(s.state(of: fid) == .quarantined)
        try await s.activateRestored([fid], acknowledging: [.foreignInstance], authorization: try s.issuer.issue(scope: .activateRestored(recordIDs: [fid])))
        #expect(try await f.get(s, fid) == "foreign" && s.entry(of: fid)?.restoreRisks == 0 && !f.quarantine.isQuarantined(fid))
        // P03-04bH: a caller-built result (unknown origin) is not verified and is refused outright
        let fresh2 = try s.vault.seal(plaintext: Array("legacy".utf8), descriptor: try f.descriptor(), authorization: try s.issuer.issue(scope: .write(.birthDate)))
        await expectVaultError(.restoreUnverified) { try await s.admitRestored(RestoreResult(active: [fresh2], quarantined: []), authorization: try s.issuer.issue(scope: .admitRestored)) }
        #expect(s.state(of: fresh2.header.recordID) == nil)
        try await s.close()
    }

    @Test("NT-H1-07: digest compaction keeps deletions fail-closed (possiblyDeleted → quarantine) and the Bloom false-positive rate stays ≤ 1e-6 at 250 000 entries")
    func compaction() async throws {
        // pure ledger: 250 000 entries folded into the digest, 2 000 000 non-member probes
        var l = DeletionLedger()
        var members: [RecordID] = []
        for _ in 0..<250_000 { let id = RecordID(); members.append(id); l.append(DeletionLedger.Entry(recordID: id, deletedAtUnixSeconds: storeT0, manifestGeneration: 1)) }
        l.compactIfNeeded(threshold: 200_000, keepRecent: 100_000, digestCapacity: 1_000_000)
        #expect(l.entries.count == 100_000 && l.digestedCount == 150_000 && l.totalCount == 250_000)
        for id in members.prefix(1000) { #expect(l.lookup(id) == .possiblyDeleted) }
        for id in members.suffix(1000) { #expect(l.lookup(id) == .deleted) }
        var fp = 0
        for _ in 0..<2_000_000 where l.lookup(RecordID()) != .notDeleted { fp += 1 }
        print("NT-H1-07 bloom false positives: \(fp) of 2000000 probes against 150000 digested ids (bits/entry ≈ 28.8, k = 20)")
        #expect(fp <= 4, Comment(rawValue: "false positives: \(fp) of 2 000 000"))
        let decoded = try DeletionLedger.decode(l.encode())
        #expect(decoded == l)
        // store level with a tiny threshold: compacted ids quarantine on restore
        let f = StoreFixture(limits: StoreLimits(ledgerCompactionThreshold: 4, ledgerRecentKept: 2, ledgerDigestCapacity: 1_000)); defer { f.cleanup() }
        let s = try await f.open()
        var ids: [RecordID] = []
        for i in 0..<6 { ids.append(try await f.put(s, "r\(i)")) }
        let (result, _, _) = try await backup(of: f, s, ids: ids)
        try await f.delete(s, Set(ids))
        let byHex = ids.sorted { $0.hex < $1.hex }   // the cascade orders roots by id, so the two newest ledger entries are the two highest ids
        #expect(s.deletionLookup(byHex[0]) == .possiblyDeleted && s.deletionLookup(byHex[5]) == .deleted)
        let rep = try await s.admitRestored(result, authorization: try s.issuer.issue(scope: .admitRestored))
        #expect(Set(rep.staged).union(rep.skippedDeleted) == Set(ids) && rep.staged.allSatisfy { rep.risks[$0]?.contains(.possiblyDeleted) == true })
        try await s.close()
        let s2 = try await f.open()   // survives relaunch
        #expect(s2.deletionLookup(byHex[0]) == .possiblyDeleted && (s2.deletionCount) == 6)
        try await s2.close()
    }
}
