// Composition root + truthful security status for the host skeleton.
// Wires the PRODUCTION ports: KeychainKeyProvider (data-protection keychain, SE where present),
// SystemClock behind MonotonicGuardClock, AuthorizationIssuer. Consent registry and quarantine
// registry are NOT implemented yet: an empty consent authority (consent-gated classes cannot be
// stored) and an in-memory quarantine registry (not persisted) are used and shown as such.
// Nothing is persisted: the self-test seals and opens synthetic bytes and discards them.
import Foundation
import Observation
import UIKit
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultInteraction
import XRAIVaultKeychain

/// In-memory quarantine registry for the host skeleton. NOT persisted; replaced in a later phase.
final class InMemoryAppQuarantineRegistry: QuarantineAuthority, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String> = []
    func isQuarantined(_ recordID: RecordID) -> Bool { lock.lock(); defer { lock.unlock() }; return ids.contains(recordID.hex) }
    func quarantine(_ recordID: RecordID, reason: DenialReason) { lock.lock(); ids.insert(recordID.hex); lock.unlock() }
    func release(_ recordID: RecordID) { lock.lock(); ids.remove(recordID.hex); lock.unlock() }
}

@MainActor
@Observable
final class SecurityStatus {
    enum KeyState: Equatable {
        case notStarted
        case ready(protection: KeyProtection, key: KeyIdentity)
        case failedClosed(reason: String)
    }

    static let keychainService = "com.xrai.app.vault"
    static let keyID = "device-main"

    private(set) var keyState: KeyState = .notStarted
    private(set) var selfTestResult: String?
    private(set) var cacheTTLSeconds: Int64 = 30
    private(set) var secureEnclaveAvailable: Bool = false

    // Honest, hard-coded facts about THIS build (changed only by code review when they change).
    let persistenceImplemented = false
    let consentRegistryImplemented = false
    let quarantineRegistryPersisted = false
    let deviceVerified = false
    let securityReviewed = false
    let buildIsDebug: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private var provider: KeychainKeyProvider?
    private var vault: SecureVault?
    /// P03-05A: the ONLY token source in the app. The issuer is created inline and handed over; no other
    /// code holds it (source-scan test `TokenSourceScanTests`).
    let sceneActivity = AppSceneActivity()
    private(set) var gate: InteractionGate?
    private(set) var consentFlow: ConsentFlow?
    private var observer: NSObjectProtocol?

    func bootstrap() {
        guard provider == nil else { return }
        secureEnclaveAvailable = SecureEnclaveAvailability.isAvailable
        let clock = MonotonicGuardClock(wrapping: SystemClock())
        let cache = KeyCachePolicy(ttlSeconds: cacheTTLSeconds)
        do {
            let p = try KeychainKeyProvider(keyID: SecurityStatus.keyID, configuration: .production(service: SecurityStatus.keychainService), uptime: SystemUptime(), cachePolicy: cache)
            let g = InteractionGate(issuer: AuthorizationIssuer(clock: clock), clock: clock, scene: sceneActivity)
            let v = SecureVault(keyProvider: p, consentAuthority: NoConsentAuthority(), clock: clock, authorizations: g.validator, quarantine: InMemoryAppQuarantineRegistry())
            provider = p; gate = g; vault = v
            consentFlow = ConsentFlow(registry: try XRAIPurposes.registryV1(), gate: g, clock: clock)
            keyState = .ready(protection: p.protection, key: p.currentKey)
        } catch let e as VaultError {
            keyState = .failedClosed(reason: String(reflecting: e))
        } catch {
            keyState = .failedClosed(reason: "unexpected")
        }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeKeyCache() }
        }
    }

    /// Seals and opens SYNTHETIC bytes through the real vault, then discards them. Nothing is stored.
    /// P03-05A: called from the button's action closure; the two proofs (seal, open) are minted there and
    /// each becomes exactly one token through the gate — no code path can call the issuer directly.
    func runSelfTest() {
        guard let vault, let gate else { selfTestResult = "Kasa hazır değil."; return }
        do {
            let plain = Array("xrai-self-test-\(RecordID().hex)".utf8)
            let descriptor = try RecordDescriptor(dataClass: .derivedResult, retention: .sessionOnly, createdAtUnixSeconds: Int64(Date().timeIntervalSince1970))
            let env = try vault.seal(plaintext: plain, descriptor: descriptor, authorization: try gate.authorize(scope: .write(.derivedResult), proof: try gate.mint(.tap)))
            let back = try vault.open(env, authorization: try gate.authorize(scope: .read(recordIDs: [descriptor.recordID]), proof: try gate.mint(.tap)))
            selfTestResult = back == plain ? "Başarılı: sentetik kayıt mühürlendi ve açıldı, saklanmadı." : "Başarısız: açılan veri farklı."
        } catch let e as VaultError {
            selfTestResult = "Başarısız (fail-closed): \(String(reflecting: e))"
        } catch let e as InteractionError {
            selfTestResult = "Reddedildi (etkileşim kapısı): \(e.failure.rawValue)"
        } catch {
            selfTestResult = "Başarısız: beklenmeyen hata."
        }
    }

    func purgeKeyCache() { provider?.purgeCache() }

    var cachedKeyVersions: [UInt32] { provider?.cachedVersions ?? [] }
}

enum SecureEnclaveAvailability {
    static var isAvailable: Bool {
        // CryptoKit's flag; on Simulator this is false and the provider reports keychainDeviceBound.
        CryptoKitSE.isAvailable
    }
}

import CryptoKit
private enum CryptoKitSE { static var isAvailable: Bool { SecureEnclave.isAvailable } }
