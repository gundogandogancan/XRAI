import CryptoKit
import Foundation
import Security
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
@testable import XRAIVaultKeychain
import XRAIVaultTesting

// P02-02 GATE 3. These tests use the REAL Keychain of the test host:
//   - macOS `swift test` (unsigned CLI): the data-protection keychain is unavailable
//     (errSecMissingEntitlement), so the provider must FAIL CLOSED in production configuration and
//     may use the login keychain only with the explicit test flag (reported as legacy/test-only).
//   - iOS Simulator (xcodebuild): data-protection keychain works; Secure Enclave is absent.
//   - Physical iPhone: NOT run here. Nothing below is DEVICE_VERIFIED.
// Every test uses a unique service name and deletes its items afterwards.

private let t0: Int64 = 1_760_000_000

private func testService() -> String { "com.xrai.vault.test." + RecordID().hex }

private func testConfig(_ service: String, se: SecureEnclavePolicy = .preferred, accessibility: KeychainAccessibility = .whenUnlockedThisDeviceOnly) -> KeychainConfiguration {
    KeychainConfiguration(service: service, accessibility: accessibility, secureEnclave: se, useDataProtectionKeychain: true, allowLegacyMacOSKeychainForTesting: true)
}

/// Deletes every keychain item of a test service when the enclosing scope exits.
/// (An earlier `~Copyable` helper was consumed too early and leaked items; `defer` is explicit.)
private func cleanup(_ service: String) { try? KeychainKeyProvider.debugDeleteService(service) }

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

@Suite("Keychain mode selection and fail-closed behaviour", .serialized)
struct KeychainModeTests {
    @Test("production configuration never falls back: on an unsigned macOS test host it fails closed; on iOS it uses the data-protection keychain")
    func productionConfigIsFailClosed() throws {
        let service = testService(); defer { cleanup(service) }
        let prod = KeychainConfiguration.production(service: service)
        #expect(prod.allowLegacyMacOSKeychainForTesting == false && prod.useDataProtectionKeychain == true)
        do {
            let p = try KeychainKeyProvider(keyID: "prod", configuration: prod)
            // Reached only where the data-protection keychain is usable (iOS simulator / entitled host).
            #expect(p.protection.isProductionGrade)
            #expect(p.debugStore().mode == "dataProtection")
        } catch VaultError.keychainUnavailable(let status) {
            // Unsigned macOS CLI and host-less iOS Simulator logic bundles both lack the keychain
            // entitlement: the only acceptable outcome is this typed, closed failure. Functional
            // keychain tests on iOS need a signed host app (SIM_HOST_APP blocker) or a device.
            #expect(status == errSecMissingEntitlement || status == errSecAuthFailed || status == errSecParam || status == errSecNotAvailable, "status \(status)")
        }
    }

    @Test("test configuration reports its true protection level; the provider never claims hardware it does not have")
    func truthfulProtection() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try KeychainKeyProvider(keyID: "k", configuration: testConfig(service))
        let se = SecureEnclave.isAvailable
        switch p.protection {
        case .keychainLegacyMacOSTestOnly:
            #expect(p.debugStore().mode == "legacyMacOS")
            #expect(!p.protection.isProductionGrade)
        case .secureEnclaveWrapped(let acc):
            #expect(se && acc == KeychainAccessibility.whenUnlockedThisDeviceOnly.rawValue)
        case .keychainDeviceBound(let acc):
            #expect(!se && acc == KeychainAccessibility.whenUnlockedThisDeviceOnly.rawValue)
        case .inMemoryTestOnly:
            Issue.record("keychain provider must never report in-memory")
        }
    }

    @Test("Secure Enclave REQUIRED fails closed where the enclave is absent and works where present (no silent downgrade)")
    func secureEnclaveRequired() throws {
        let service = testService(); defer { cleanup(service) }
        if SecureEnclave.isAvailable {
            let p = try KeychainKeyProvider(keyID: "se", configuration: testConfig(service, se: .required))
            let (v, i) = vault(p)
            let env = try seal(v, i, "se-protected")
            #expect(try open(v, i, env) == Array("se-protected".utf8))
            // the stored KEK item is an SE blob, not raw key bytes
            let raw = try KeychainStore(service: service, accessibility: .whenUnlockedThisDeviceOnly, mode: p.debugStore().mode == "dataProtection" ? .dataProtection : .legacyMacOS).read(account: "se/kek/v1")
            let bytes = Array(try #require(raw))
            #expect(bytes.count > 32 && bytesContain(bytes, Array("XRAI-SE".utf8)))
        } else {
            #expect(throws: VaultError.secureEnclaveUnavailable) { try KeychainKeyProvider(keyID: "se", configuration: testConfig(service, se: .required)) }
        }
    }

    @Test("OSStatus mapping is typed and identifier-free (locked device, access denied, missing entitlement, not found, duplicate)")
    func statusMapping() {
        #expect(KeychainStatusMapping.map(errSecInteractionNotAllowed) == .keychainUnavailable(status: errSecInteractionNotAllowed))
        #expect(KeychainStatusMapping.map(errSecAuthFailed) == .keychainUnavailable(status: errSecAuthFailed))
        #expect(KeychainStatusMapping.map(errSecMissingEntitlement) == .keychainUnavailable(status: errSecMissingEntitlement))
        #expect(KeychainStatusMapping.map(errSecItemNotFound) == .keyUnavailable(version: 0))
        #expect(KeychainStatusMapping.map(errSecDuplicateItem) == .keychainConflict)
        #expect(KeychainStatusMapping.map(errSecDecode) == .keychainCorrupted(reason: "decode"))
        #expect(KeychainStatusMapping.map(-99999) == .keychainUnavailable(status: -99999))
    }
}

@Suite("Keychain key lifecycle", .serialized)
struct KeychainLifecycleTests {
    @Test("create, reuse across provider instances (app relaunch), and isolation between key ids and services")
    func createAndReuse() throws {
        let service = testService(); defer { cleanup(service) }
        let p1 = try KeychainKeyProvider(keyID: "main", configuration: testConfig(service))
        #expect(p1.currentKey == KeyIdentity(keyID: "main", version: 1))
        let (v1, i1) = vault(p1)
        let env = try seal(v1, i1, "persist me")
        // "relaunch": a fresh instance over the same keychain, no in-process cache
        let p2 = try KeychainKeyProvider(keyID: "main", configuration: testConfig(service))
        #expect(p2.currentKey.version == 1)
        let (v2, i2) = vault(p2)
        #expect(try open(v2, i2, env) == Array("persist me".utf8))
        // another key id in the same service cannot open it
        let other = try KeychainKeyProvider(keyID: "other", configuration: testConfig(service))
        let (v3, i3) = vault(other)
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v3, i3, env) }
        // same key id in a different service (another "device"/app) has different material
        let service2 = testService(); defer { cleanup(service2) }
        let foreign = try KeychainKeyProvider(keyID: "main", configuration: testConfig(service2))
        let (v4, i4) = vault(foreign)
        #expect(throws: VaultError.authenticationFailed) { try open(v4, i4, env) }
        // key material never appears in the wrapped key or envelope
        let kek = try p1.unwrapDataKey(env.wrappedDEK)
        #expect(kek.count == 32 && !bytesContain(env.wrappedDEK.ciphertext, kek))
    }

    @Test("rotation: new version item written before the pointer moves; old records still open; rewrap moves them; forget deletes the old item")
    func rotation() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try KeychainKeyProvider(keyID: "rot", configuration: testConfig(service))
        let (v, i) = vault(p)
        let env = try seal(v, i, "rotate")
        #expect(try p.rotate() == KeyIdentity(keyID: "rot", version: 2))
        #expect(try open(v, i, env) == Array("rotate".utf8))
        let re = try v.rewrap(env, maintenance: try i.issue(scope: .maintenance(.rewrap)))
        #expect(re.wrappedDEK.keyVersion == 2 && re.ciphertext == env.ciphertext)
        try p.forget(version: 1)
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v, i, env) }
        #expect(try open(v, i, re) == Array("rotate".utf8))
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try p.forget(version: 2) }
        // relaunch after rotation sees version 2 and cannot read the forgotten version
        let p2 = try KeychainKeyProvider(keyID: "rot", configuration: testConfig(service))
        #expect(p2.currentKey.version == 2)
        let (v2, i2) = vault(p2)
        #expect(try open(v2, i2, re) == Array("rotate".utf8))
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v2, i2, env) }
    }

    @Test("interrupted rotation: an orphan newer item without a pointer update is ignored; the pointer wins; the next rotation does not reuse it")
    func interruptedRotation() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try KeychainKeyProvider(keyID: "int", configuration: testConfig(service))
        try p.debugWriteOrphan(version: 2)   // simulates a crash after writing v2 but before updating `current`
        let p2 = try KeychainKeyProvider(keyID: "int", configuration: testConfig(service))
        #expect(p2.currentKey.version == 1)
        let (v, i) = vault(p2)
        let env = try seal(v, i, "x")
        #expect(env.wrappedDEK.keyVersion == 1)
        let orphanWrap = WrappedKey(keyID: "int", keyVersion: 2, boundRecordID: env.wrappedDEK.boundRecordID, nonce: env.wrappedDEK.nonce, ciphertext: env.wrappedDEK.ciphertext, tag: env.wrappedDEK.tag)
        #expect(throws: VaultError.keyUnavailable(version: 2)) { try p2.unwrapDataKey(orphanWrap) }
        // completing a rotation now must not silently adopt the orphan: it conflicts, fail closed
        #expect(throws: VaultError.keychainConflict) { try p2.rotate() }
        #expect(p2.currentKey.version == 1, "pointer unchanged after the failed rotation")
    }

    @Test("same key id with different material (conflict) is never overwritten")
    func conflict() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try KeychainKeyProvider(keyID: "dup", configuration: testConfig(service))
        #expect(throws: VaultError.keychainConflict) { try p.debugAddConflicting(version: 1) }
        let (v, i) = vault(p)
        let env = try seal(v, i, "still mine")
        let p2 = try KeychainKeyProvider(keyID: "dup", configuration: testConfig(service))
        let (v2, i2) = vault(p2)
        #expect(try open(v2, i2, env) == Array("still mine".utf8))
    }

    @Test("corrupted keychain entry (wrong length / garbage) fails closed on relaunch and on unwrap; a missing item (passcode removed → OS deleted it) fails closed")
    func corruption() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try KeychainKeyProvider(keyID: "cor", configuration: testConfig(service))
        let (v, i) = vault(p)
        let env = try seal(v, i, "fragile")
        try p.debugCorrupt(version: 1, with: [1, 2, 3])
        #expect(throws: VaultError.self) { try open(v, i, env) }
        #expect(throws: VaultError.self) { try KeychainKeyProvider(keyID: "cor", configuration: testConfig(service)) }
        // garbage of the right length under SE mode is also rejected (blob magic), under keychain-only it is just a different key
        try p.debugCorrupt(version: 1, with: [UInt8](repeating: 9, count: 32))
        #expect(throws: VaultError.self) { try open(v, i, env) }
        // item deleted behind our back (what the OS does for WhenPasscodeSetThisDeviceOnly on passcode removal)
        try p.debugDeleteItem(version: 1)
        #expect(throws: VaultError.keyUnavailable(version: 1)) { try open(v, i, env) }
        #expect(throws: VaultError.self) { try KeychainKeyProvider(keyID: "cor", configuration: testConfig(service)) }
    }

    @Test("mode mismatch between stored meta and configuration fails closed (no silent downgrade of protection)")
    func modeMismatch() throws {
        let service = testService(); defer { cleanup(service) }
        _ = try KeychainKeyProvider(keyID: "mm", configuration: testConfig(service, se: .preferred))
        if SecureEnclave.isAvailable {
            #expect(throws: VaultError.keychainCorrupted(reason: "mode mismatch")) { try KeychainKeyProvider(keyID: "mm", configuration: testConfig(service, se: .disabled)) }
        } else {
            #expect(throws: VaultError.keychainCorrupted(reason: "mode mismatch")) { try KeychainKeyProvider(keyID: "mm", configuration: testConfig(service, accessibility: .afterFirstUnlockThisDeviceOnly)) }
        }
    }

    @Test("explicit wipe removes every item; a new provider starts a fresh key set and cannot open old records")
    func wipe() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try KeychainKeyProvider(keyID: "w", configuration: testConfig(service))
        let (v, i) = vault(p)
        let env = try seal(v, i, "gone")
        try p.wipeAllKeys()
        let p2 = try KeychainKeyProvider(keyID: "w", configuration: testConfig(service))
        let (v2, i2) = vault(p2)
        #expect(throws: VaultError.authenticationFailed) { try open(v2, i2, env) }
    }

    @Test("concurrent wrap/unwrap/rotate on one provider: no crash, every unwrap succeeds or fails typed, versions stay monotonic")
    func concurrency() throws {
        let service = testService(); defer { cleanup(service) }
        let p = try KeychainKeyProvider(keyID: "cc", configuration: testConfig(service))
        let lock = NSLock()
        var failures: [String] = []
        var versions: [UInt32] = []
        DispatchQueue.concurrentPerform(iterations: 64) { n in
            do {
                if n % 16 == 0 {
                    let id = try p.rotate()
                    lock.lock(); versions.append(id.version); lock.unlock()
                } else {
                    let dek = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
                    let rid = RecordID()
                    let w = try p.wrapDataKey(dek, boundTo: rid)
                    let back = try p.unwrapDataKey(w)
                    if back != dek { lock.lock(); failures.append("mismatch"); lock.unlock() }
                }
            } catch let e as VaultError {
                lock.lock(); failures.append(String(reflecting: e)); lock.unlock()
            } catch {
                lock.lock(); failures.append("untyped \(error)"); lock.unlock()
            }
        }
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "; ")))
        #expect(versions.sorted() == versions.sorted().map { $0 } && Set(versions).count == versions.count)
        #expect(p.currentKey.version == 1 + UInt32(versions.count))
    }

    @Test("end-to-end: SecureVault over the Keychain provider — seal, backup, restore on a second key set, forget old")
    func endToEnd() throws {
        let s1 = testService(); defer { cleanup(s1) }
        let s2 = testService(); defer { cleanup(s2) }
        let (v1, i1) = vault(try KeychainKeyProvider(keyID: "dev", configuration: testConfig(s1)))
        let env = try seal(v1, i1, "1998-06-30")
        let rk = try SecureVault.generateRecoveryKey()
        let bytes = try v1.exportBackup([env], recoveryKey: rk, authorization: try i1.issue(scope: .exportBackup))
        let (v2, i2) = vault(try KeychainKeyProvider(keyID: "dev", configuration: testConfig(s2)))
        let r = try v2.restoreBackup(bytes: bytes, recoveryKey: rk, authorization: try i2.issue(scope: .restoreBackup))
        #expect(r.active.count == 1)
        #expect(try open(v2, i2, r.active[0]) == Array("1998-06-30".utf8))
        #expect(throws: VaultError.authenticationFailed) { try open(v1, i1, r.active[0]) }
    }
}

@Suite("Isolation of test doubles from production")
struct IsolationTests {
    @Test("XRAIVaultKeychain never imports XRAIVaultTesting; Security is imported only by XRAIVaultKeychain; the in-memory provider reports test-only protection")
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
                // scan code only (comments legitimately mention the forbidden APIs by name)
                let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { l -> Substring in if let r = l.range(of: "//") { return l[l.startIndex..<r.lowerBound] }; return l }.joined(separator: "\n")
                #expect(!code.contains("UserDefaults") && !code.contains("print(") && !code.contains("NSLog") && !code.contains("write(to") && !code.contains("os_log"), Comment(rawValue: u.lastPathComponent))
            }
        }
        #expect(InMemoryKeyProvider(keyID: "x").protection == .inMemoryTestOnly)
        #expect(!InMemoryKeyProvider(keyID: "x").protection.isProductionGrade)
    }
}

private func bytesContain(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, haystack.count >= needle.count else { return false }
    for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] {
        if Array(haystack[i..<i + needle.count]) == needle { return true }
    }
    return false
}
