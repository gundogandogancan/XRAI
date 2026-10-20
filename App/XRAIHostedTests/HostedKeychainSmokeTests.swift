import CryptoKit
import Foundation
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultKeychain
@testable import XRAI

// Runs INSIDE the signed XRAI app process (TEST_HOST). Proves that the production keychain
// configuration works here, and states the Secure Enclave truth for this runtime.

@Suite("Hosted: production keychain configuration inside the app")
struct HostedKeychainSmokeTests {
    @Test("production config opens the data-protection keychain; protection is device-bound, SE-wrapped only where hardware exists")
    func productionConfigWorksInHost() throws {
        let service = "com.xrai.app.vault.hostedtest." + RecordID().hex
        let p = try KeychainKeyProvider(keyID: "host", configuration: .production(service: service))
        defer { try? p.wipeAllKeys(confirmation: WipeConfirmation(keyID: "host", acknowledgesIrreversibleLoss: true)) }
        #expect(p.protection.isProductionGrade)
        // Truth about the enclave in this runtime. On an Apple-silicon Mac the Simulator proxies the
        // HOST MAC's Secure Enclave, so `isAvailable` can be true there; that is not iPhone hardware
        // evidence. The provider must simply be consistent with what CryptoKit reports.
        let acc = KeychainAccessibility.whenUnlockedThisDeviceOnly.rawValue
        if SecureEnclave.isAvailable {
            #expect(p.protection == .secureEnclaveWrapped(accessibility: acc))
        } else {
            #expect(p.protection == .keychainDeviceBound(accessibility: acc))
        }
        #if targetEnvironment(simulator)
        let runtime = "iOS Simulator (enclave, if any, is the host Mac's)"
        #else
        let runtime = "physical device"
        #endif
        #expect(!runtime.isEmpty)
        let clock = MonotonicGuardClock(wrapping: SystemClock())
        let issuer = AuthorizationIssuer(clock: clock)
        let vault = SecureVault(keyProvider: p, consentAuthority: NoConsentAuthority(), clock: clock, authorizations: issuer, quarantine: InMemoryAppQuarantineRegistry())
        let plain = Array("hosted synthetic".utf8)
        let env = try vault.seal(plaintext: plain, descriptor: try RecordDescriptor(dataClass: .derivedResult, retention: .sessionOnly, createdAtUnixSeconds: try clock.now()), authorization: try issuer.issue(scope: .write(.derivedResult)))
        #expect(try vault.open(env, authorization: try issuer.issue(scope: .read(recordIDs: nil))) == plain)
        // relaunch simulation inside the host: a second instance over the same keychain
        let p2 = try KeychainKeyProvider(keyID: "host", configuration: .production(service: service))
        #expect(p2.currentKey == p.currentKey)
        _ = try p2.unwrapDataKey(env.wrappedDEK)
    }

    @Test("SecurityStatus bootstrap reports a ready, production-grade key state and the self-test passes without persisting anything")
    @MainActor
    func appStatusBootstrap() {
        let s = SecurityStatus()
        s.bootstrap()
        guard case .ready(let protection, _) = s.keyState else {
            Issue.record("key state: \(s.keyState)")
            return
        }
        #expect(protection.isProductionGrade)
        // P03-05A: the self-test goes through the InteractionGate — refused while the scene is inactive, allowed when active.
        s.sceneActivity.set(false)
        s.runSelfTest()
        #expect(s.selfTestResult?.hasPrefix("Reddedildi (etkileşim kapısı): SCENE_INACTIVE") == true, Comment(rawValue: s.selfTestResult ?? "nil"))
        s.sceneActivity.set(true)
        s.runSelfTest()
        #expect(s.selfTestResult?.hasPrefix("Başarılı") == true, Comment(rawValue: s.selfTestResult ?? "nil"))
        #expect(!s.persistenceImplemented && !s.deviceVerified && !s.securityReviewed)
        s.purgeKeyCache()
        #expect(s.cachedKeyVersions.isEmpty)
    }
}
