import CryptoKit
import Foundation
import Security
import Testing
import XRAIVaultContracts
@testable import XRAIVaultCryptoKit
@testable import XRAIVaultKeychain
import XRAIVaultTesting

// P02-02 GATE 3 + P03-00 §3/§4. These tests use the REAL Keychain of the test host:
//   - macOS `swift test` (unsigned CLI): data-protection keychain unavailable → production config
//     fails closed; login keychain only with the explicit test flag (reported legacy/test-only).
//   - iOS Simulator inside the signed XRAI app host (xcodebuild): data-protection keychain works;
//     Secure Enclave is absent.
//   - Physical iPhone inside the XRAI app host: see the P03-00 report for what was run.
// Raw keychain manipulation for adversarial cases goes through `KeychainStore` via @testable; the
// production provider has NO debug hooks. Every test uses a unique service and cleans up.

private let t0: Int64 = 1_760_000_000
private func testService() -> String { "com.xrai.vault.test." + RecordID().hex }
private func cleanup(_ service: String) {
    for mode in [KeychainStore.Mode.dataProtection, .legacyMacOS] {
        try? KeychainStore(service: service, accessibility: .whenUnlockedThisDeviceOnly, mode: mode).deleteAll()
    }
}
private func testConfig(_ service: String, se: SecureEnclavePolicy = .preferred, accessibility: KeychainAccessibility = .whenUnlockedThisDeviceOnly) -> KeychainConfiguration {
    KeychainConfiguration(service: service, accessibility: accessibility, secureEnclave: se, useDataProtectionKeychain: true, allowLegacyMacOSKeychainForTesting: true)
}
private func raw(_ p: KeychainKeyProvider) -> KeychainStore {
    KeychainStore(service: p.configuration.service, accessibility: p.configuration.accessibility, mode: p.protection == .keychainLegacyMacOSTestOnly ? .legacyMacOS : .dataProtection)
}
private func provider(_ service: String, keyID: String = "k", clock: ManualClock = ManualClock(t0), cache: KeyCachePolicy = KeyCachePolicy(), se: SecureEnclavePolicy = .preferred) throws -> KeychainKeyProvider {
    try KeychainKeyProvider(keyID: keyID, configuration: testConfig(service, se: se), clock: clock, cachePolicy: cache)
}
private func vault(_ p: any KeyProvider, clock: ManualClock = ManualClock(t0)) -> (SecureVault, AuthorizationIssuer) {
    let issuer = AuthorizationIssuer(clock: clock)
    return (SecureVault(keyProvider: p, consentAuthority: NoConsentAuthority(), clock: clock, authorizations: issuer, quarantine: InMemoryQuarantineRegistry()), issuer)
}
private func seal(_ v: SecureVault, _ i: AuthorizationIssuer, _ text: String) throws -> RecordEnvelope {
    try v.seal(plaintext: Array(text.utf8), descriptor: try RecordDescriptor(dataClass: .birthDate, retention: .untilUserDeletes, createdAtUnixSeconds: t0), authorization: try i.issue(scope: .write(.birthDate)))
}
private func open(_ v: SecureVault, _ i: AuthorizationIssuer, _ e: RecordEnvelope) throws -> [UInt8] {
    try v.open(e, authorization: try i.issue(scope: .read(recordIDs: nil)))
}
private func dek() -> [UInt8] { SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) } }

@Suite("Keychain mode selection and fail-closed behaviour", .serialized)
struct KeychainModeTests {
    @Test("production configuration never falls back: without a keychain entitlement it fails closed; inside a signed host it uses the data-protection keychain")
    func productionConfigIsFailClosed() throws {
        let service = testService(); defer { cleanup(service) }
        let prod = KeychainConfiguration.production(service: service)
        #expect(prod.allowLegacyMacOSKeychainForTesting == false && prod.useDataProtectionKeychain == true)
        do {
            let p = try KeychainKeyProvider(keyID: "prod", configuration: prod)
            #expect(p.protection.isProductionGrade)
            #expect(p.protection != .keychainLegacyMacOSTestOnly)
        } catch VaultError.keychainUnavailable(let status) {
            #expect(status == errSecMissingEntitlement || status == errSecAuthFailed || status == errSecParam || status == errSecNotAvailable, "status \(status)")
        }
    }

    @Test("test configuration reports its true protection level; the provider never claims hardware it does not have")
    func truthfulProtection() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service)
        let se = SecureEnclave.isAvailable
        switch p.protection {
        case .keychainLegacyMacOSTestOnly: #expect(!p.protection.isProductionGrade)
        case .secureEnclaveWrapped(let acc): #expect(se && acc == KeychainAccessibility.whenUnlockedThisDeviceOnly.rawValue)
        case .keychainDeviceBound(let acc): #expect(!se && acc == KeychainAccessibility.whenUnlockedThisDeviceOnly.rawValue)
        case .inMemoryTestOnly: Issue.record("keychain provider must never report in-memory")
        }
    }

    @Test("Secure Enclave REQUIRED fails closed where the enclave is absent and works where present (no silent downgrade)")
    func secureEnclaveRequired() throws {
        let service = testService(); defer { cleanup(service) }
        if SecureEnclave.isAvailable {
            let p = try provider(service, keyID: "se", se: .required)
            let (v, i) = vault(p)
            let env = try seal(v, i, "se-protected")
            #expect(try open(v, i, env) == Array("se-protected".utf8))
            let bytes = Array(try #require(try raw(p).read(account: "se/kek/v1")))
            #expect(bytes.count > 32 && bytesContain(bytes, Array("XRAI-SE".utf8)))
        } else {
            #expect(throws: VaultError.secureEnclaveUnavailable) { try provider(service, keyID: "se", se: .required) }
        }
    }

    @Test("OSStatus mapping is typed and identifier-free")
    func statusMapping() {
        #expect(KeychainStatusMapping.map(errSecInteractionNotAllowed) == .keychainUnavailable(status: errSecInteractionNotAllowed))
        #expect(KeychainStatusMapping.map(errSecAuthFailed) == .keychainUnavailable(status: errSecAuthFailed))
        #expect(KeychainStatusMapping.map(errSecMissingEntitlement) == .keychainUnavailable(status: errSecMissingEntitlement))
        #expect(KeychainStatusMapping.map(errSecItemNotFound) == .keyUnavailable(version: 0))
        #expect(KeychainStatusMapping.map(errSecDuplicateItem) == .keychainConflict)
        #expect(KeychainStatusMapping.map(-99999) == .keychainUnavailable(status: -99999))
    }
}

@Suite("Keychain key lifecycle", .serialized)
struct KeychainLifecycleTests {
    @Test("create, reuse across provider instances (app relaunch), and isolation between key ids and services")
    func createAndReuse() throws {
        let service = testService(); defer { cleanup(service) }
        let p1 = try provider(service, keyID: "main")
        #expect(p1.currentKey == KeyIdentity(keyID: "main", version: 1))
        let (v1, i1) = vault(p1)
        let env = try seal(v1, i1, "persist me")
        let p2 = try provider(service, keyID: "main")
        let (v2, i2) = vault(p2)
        #expect(try open(v2, i2, env) == Array("persist me".utf8))
        let (v3, i3) = vault(try provider(service, keyID: "other"))
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v3, i3, env) }
        let service2 = testService(); defer { cleanup(service2) }
        let (v4, i4) = vault(try provider(service2, keyID: "main"))
        #expect(throws: VaultError.authenticationFailed) { try open(v4, i4, env) }
        let kek = try p1.unwrapDataKey(env.wrappedDEK)
        #expect(kek.count == 32 && !bytesContain(env.wrappedDEK.ciphertext, kek))
    }

    @Test("rotation: new item before pointer move; old records open; rewrap moves them; forget needs retire (two-phase); relaunch sees the new version")
    func rotation() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service, keyID: "rot")
        let (v, i) = vault(p)
        let env = try seal(v, i, "rotate")
        #expect(try p.rotate() == KeyIdentity(keyID: "rot", version: 2))
        #expect(try open(v, i, env) == Array("rotate".utf8))
        let re = try v.rewrap(env, maintenance: try i.issue(scope: .maintenance(.rewrap)))
        #expect(re.wrappedDEK.keyVersion == 2 && re.ciphertext == env.ciphertext)
        // forgetting without retiring is refused: records might still reference v1
        #expect(throws: VaultError.keyVersionNotRetired(version: 1)) { try p.forget(version: 1) }
        #expect(try open(v, i, env) == Array("rotate".utf8), "still readable")
        try p.retire(version: 1)
        #expect(try p.isRetired(version: 1))
        #expect(try open(v, i, env) == Array("rotate".utf8), "retired versions still unwrap")
        try p.forget(version: 1)
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v, i, env) }
        #expect(try open(v, i, re) == Array("rotate".utf8))
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try p.retire(version: 2) }
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try p.forget(version: 2) }
        let p2 = try provider(service, keyID: "rot")
        #expect(p2.currentKey.version == 2)
        let (v2, i2) = vault(p2)
        #expect(try open(v2, i2, re) == Array("rotate".utf8))
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v2, i2, env) }
    }

    @Test("two instances on one service: a stale instance refreshes the pointer, never wraps under a stale version, and rotates to the next version instead of conflicting")
    func twoInstances() throws {
        let service = testService(); defer { cleanup(service) }
        let a = try provider(service, keyID: "shared")
        let b = try provider(service, keyID: "shared")
        #expect(try a.rotate().version == 2)
        #expect(b.currentKey.version == 1, "B's memory is stale")
        let wA = try a.wrapDataKey(dek(), boundTo: RecordID())
        #expect(wA.keyVersion == 2)
        _ = try b.unwrapDataKey(wA)                       // refreshes on a version above memory
        #expect(b.currentKey.version == 2)
        let wB = try b.wrapDataKey(dek(), boundTo: RecordID())
        #expect(wB.keyVersion == 2, "wrap always uses the keychain's pointer")
        #expect(try b.rotate().version == 3)              // not a conflict: pointer re-read
        #expect(try a.refreshCurrentKey().version == 3)
        _ = try a.unwrapDataKey(try b.wrapDataKey(dek(), boundTo: RecordID()))
    }

    @Test("interrupted rotation: a READABLE orphan is adopted by the next rotation; an UNREADABLE orphan blocks rotation until repaired; orphans never unwrap")
    func interruptedRotation() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service, keyID: "int")
        let store = raw(p)
        // simulate: v2 item written, process died before `current` moved
        let material = dek()
        let payload: [UInt8] = p.protection == .keychainLegacyMacOSTestOnly && SecureEnclave.isAvailable || { if case .secureEnclaveWrapped = p.protection { return true }; return false }()
            ? try SecureEnclaveWrapper.wrap(kek: material, accessibility: .whenUnlockedThisDeviceOnly) : material
        try store.add(account: "int/kek/v2", data: Data(payload))
        let p2 = try provider(service, keyID: "int")
        #expect(p2.currentKey.version == 1)
        let w = try p2.wrapDataKey(dek(), boundTo: RecordID())
        #expect(w.keyVersion == 1)
        let orphanWrap = WrappedKey(keyID: "int", keyVersion: 2, boundRecordID: w.boundRecordID, nonce: w.nonce, ciphertext: w.ciphertext, tag: w.tag)
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try p2.unwrapDataKey(orphanWrap) }
        // readable orphan → adopted (rotation completed), material is the orphan's
        #expect(try p2.rotate().version == 2)
        let kek2 = try GCMKeyWrapper(keyID: "int", version: 2, material: material)
        let w2 = try p2.wrapDataKey(dek(), boundTo: RecordID())
        #expect(try kek2.unwrap(w2).count == 32, "adopted version uses the orphan's material")
        // unreadable orphan at v3 → rotation refused, repair deletes it, rotation then succeeds
        try store.add(account: "int/kek/v3", data: Data([1, 2, 3]))
        #expect(throws: VaultError.self) { try p2.rotate() }
        #expect(p2.currentKey.version == 2)
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try p2.repairOrphan(version: 2) }  // never below/at the pointer
        try p2.repairOrphan(version: 3)
        #expect(try p2.rotate().version == 3)
    }

    @Test("same key id with different material (conflict) is never overwritten")
    func conflict() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service, keyID: "dup")
        #expect(throws: VaultError.keychainConflict) { try raw(p).add(account: "dup/kek/v1", data: Data(repeating: 7, count: 32)) }
        let (v, i) = vault(p)
        let env = try seal(v, i, "still mine")
        let (v2, i2) = vault(try provider(service, keyID: "dup"))
        #expect(try open(v2, i2, env) == Array("still mine".utf8))
    }

    @Test("corrupted keychain entry fails closed on relaunch and on unwrap; a missing item (passcode removed → OS deleted it) fails closed")
    func corruption() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service, keyID: "cor", cache: .disabled)
        let store = raw(p)
        let (v, i) = vault(p)
        let env = try seal(v, i, "fragile")
        try store.delete(account: "cor/kek/v1"); try store.add(account: "cor/kek/v1", data: Data([1, 2, 3]))
        #expect(throws: VaultError.self) { try open(v, i, env) }
        #expect(throws: VaultError.self) { try provider(service, keyID: "cor") }
        try store.delete(account: "cor/kek/v1"); try store.add(account: "cor/kek/v1", data: Data(repeating: 9, count: 32))
        #expect(throws: VaultError.self) { try open(v, i, env) }
        try store.delete(account: "cor/kek/v1")
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v, i, env) }
        #expect(throws: VaultError.self) { try provider(service, keyID: "cor") }
    }

    @Test("mode mismatch between stored meta and configuration fails closed (no silent downgrade of protection)")
    func modeMismatch() throws {
        let service = testService(); defer { cleanup(service) }
        _ = try provider(service, keyID: "mm", se: .preferred)
        if SecureEnclave.isAvailable {
            #expect(throws: VaultError.keychainCorrupted(reason: "mode mismatch")) { try provider(service, keyID: "mm", se: .disabled) }
        } else {
            #expect(throws: VaultError.keychainCorrupted(reason: "mode mismatch")) { try KeychainKeyProvider(keyID: "mm", configuration: testConfig(service, accessibility: .afterFirstUnlockThisDeviceOnly)) }
        }
    }

    @Test("wipe requires an explicit confirmation naming the key id; afterwards a new provider starts a fresh key set")
    func wipe() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service, keyID: "w")
        let (v, i) = vault(p)
        let env = try seal(v, i, "gone")
        #expect(throws: VaultError.notAuthorized(.userInitiationRequired)) { try p.wipeAllKeys(confirmation: WipeConfirmation(keyID: "w", acknowledgesIrreversibleLoss: false)) }
        #expect(throws: VaultError.notAuthorized(.userInitiationRequired)) { try p.wipeAllKeys(confirmation: WipeConfirmation(keyID: "other", acknowledgesIrreversibleLoss: true)) }
        #expect(try open(v, i, env) == Array("gone".utf8), "refused wipes change nothing")
        try p.wipeAllKeys(confirmation: WipeConfirmation(keyID: "w", acknowledgesIrreversibleLoss: true))
        let (v2, i2) = vault(try provider(service, keyID: "w"))
        #expect(throws: VaultError.authenticationFailed) { try open(v2, i2, env) }
    }

    @Test("concurrent wrap/unwrap/rotate on one provider: no crash, every unwrap succeeds or fails typed, versions stay monotonic")
    func concurrency() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service, keyID: "cc")
        let lock = NSLock()
        var failures: [String] = []
        var versions: [UInt32] = []
        DispatchQueue.concurrentPerform(iterations: 64) { n in
            do {
                if n % 16 == 0 {
                    let id = try p.rotate()
                    lock.lock(); versions.append(id.version); lock.unlock()
                } else {
                    let d = dek()
                    let w = try p.wrapDataKey(d, boundTo: RecordID())
                    if try p.unwrapDataKey(w) != d { lock.lock(); failures.append("mismatch"); lock.unlock() }
                }
            } catch let e as VaultError { lock.lock(); failures.append(String(reflecting: e)); lock.unlock() }
            catch { lock.lock(); failures.append("untyped \(error)"); lock.unlock() }
        }
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "; ")))
        #expect(Set(versions).count == versions.count && p.currentKey.version == 1 + UInt32(versions.count))
    }

    @Test("end-to-end: SecureVault over the Keychain provider — seal, backup, restore on a second key set")
    func endToEnd() throws {
        let s1 = testService(); defer { cleanup(s1) }
        let s2 = testService(); defer { cleanup(s2) }
        let (v1, i1) = vault(try provider(s1, keyID: "dev"))
        let env = try seal(v1, i1, "1998-06-30")
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try v1.exportBackup([env], recoveryKey: rk, authorization: try i1.issue(scope: .exportBackup))
        let (v2, i2) = vault(try provider(s2, keyID: "dev"))
        let r = try v2.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try i2.issue(scope: .restoreBackup))
        #expect(r.active.count == 1)
        #expect(try open(v2, i2, r.active[0]) == Array("1998-06-30".utf8))
        #expect(throws: VaultError.authenticationFailed) { try open(v1, i1, r.active[0]) }
    }
}

@Suite("Key cache (P03-00 §3)", .serialized)
struct KeyCacheTests {
    @Test("a cached KEK survives deletion of its item only until TTL or purge; purge on lock makes the loss immediate")
    func ttlAndPurge() throws {
        let service = testService(); defer { cleanup(service) }
        let clock = ManualClock(t0)
        let p = try provider(service, keyID: "c", clock: clock, cache: KeyCachePolicy(ttlSeconds: 30))
        let w = try p.wrapDataKey(dek(), boundTo: RecordID())
        #expect(p.cachedVersions == [1])
        try raw(p).delete(account: "c/kek/v1")                      // item gone (e.g. passcode removed)
        _ = try p.unwrapDataKey(w)                                  // DOCUMENTED BOUND: still served from memory within TTL
        clock.advance(30)
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try p.unwrapDataKey(w) }
        #expect(p.cachedVersions.isEmpty)
        // purge path: fresh provider, cache warm, lock event → immediate failure after deletion
        let service2 = testService(); defer { cleanup(service2) }
        let q = try provider(service2, keyID: "c", clock: clock, cache: KeyCachePolicy(ttlSeconds: 300))
        let w2 = try q.wrapDataKey(dek(), boundTo: RecordID())
        try raw(q).delete(account: "c/kek/v1")
        q.purgeCache()                                              // what the app does on lock/background
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try q.unwrapDataKey(w2) }
    }

    @Test("cache disabled: every operation hits the keychain, so deletion is visible immediately")
    func disabled() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try provider(service, keyID: "nc", cache: .disabled)
        let w = try p.wrapDataKey(dek(), boundTo: RecordID())
        #expect(p.cachedVersions.isEmpty)
        try raw(p).delete(account: "nc/kek/v1")
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try p.unwrapDataKey(w) }
    }

    @Test("another instance's stale cache after retire+forget: access persists only until its TTL/purge (documented), then fails closed")
    func staleCacheAcrossInstances() throws {
        let service = testService(); defer { cleanup(service) }
        let clock = ManualClock(t0)
        let a = try provider(service, keyID: "s", clock: clock, cache: KeyCachePolicy(ttlSeconds: 30))
        let b = try provider(service, keyID: "s", clock: clock, cache: KeyCachePolicy(ttlSeconds: 30))
        let w = try a.wrapDataKey(dek(), boundTo: RecordID())
        _ = try b.unwrapDataKey(w)                                  // B caches v1
        _ = try a.rotate(); try a.retire(version: 1); try a.forget(version: 1)
        _ = try b.unwrapDataKey(w)                                  // B still serves v1 from memory (bounded exposure)
        b.purgeCache()
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try b.unwrapDataKey(w) }
        let c = try provider(service, keyID: "s", clock: clock)
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try c.unwrapDataKey(w) }
    }
}

@Suite("Isolation of test doubles and debug surface from production")
struct IsolationTests {
    @Test("XRAIVaultKeychain imports no testing module, is the only Security importer, has no debug hooks or forbidden IO; in-memory provider is test-only")
    func isolation() throws {
        var root = URL(fileURLWithPath: #filePath)
        root.deleteLastPathComponent(); root.deleteLastPathComponent(); root.deleteLastPathComponent()
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        guard let e = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return }
        for case let u as URL in e where u.pathExtension == "swift" {
            let text = try String(contentsOf: u, encoding: .utf8)
            let module = u.deletingLastPathComponent().lastPathComponent
            if text.contains("import Security") { #expect(module == "XRAIVaultKeychain", Comment(rawValue: "\(module)/\(u.lastPathComponent) imports Security")) }
            if module != "XRAIVaultTesting" { #expect(!text.contains("import XRAIVaultTesting"), Comment(rawValue: "\(module)/\(u.lastPathComponent)")) }
            if module == "XRAIVaultKeychain" {
                let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { l -> Substring in if let r = l.range(of: "//") { return l[l.startIndex..<r.lowerBound] }; return l }.joined(separator: "\n")
                for token in ["UserDefaults", "print(", "NSLog", "write(to", "os_log", "func debug", "package func"] {
                    #expect(!code.contains(token), Comment(rawValue: "\(u.lastPathComponent) contains \(token)"))
                }
            }
        }
        #expect(InMemoryKeyProvider(keyID: "x").protection == .inMemoryTestOnly && !InMemoryKeyProvider(keyID: "x").protection.isProductionGrade)
    }
}

private func bytesContain(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, haystack.count >= needle.count else { return false }
    for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] {
        if Array(haystack[i..<i + needle.count]) == needle { return true }
    }
    return false
}
