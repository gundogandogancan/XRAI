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
    private var issuer: AuthorizationIssuer?
    private var observer: NSObjectProtocol?

    func bootstrap() {
        guard provider == nil else { return }
        secureEnclaveAvailable = SecureEnclaveAvailability.isAvailable
        let clock = MonotonicGuardClock(wrapping: SystemClock())
        let cache = KeyCachePolicy(ttlSeconds: cacheTTLSeconds)
        do {
            let p = try KeychainKeyProvider(keyID: SecurityStatus.keyID, configuration: .production(service: SecurityStatus.keychainService), clock: clock, cachePolicy: cache)
            let i = AuthorizationIssuer(clock: clock)
            let v = SecureVault(keyProvider: p, consentAuthority: NoConsentAuthority(), clock: clock, authorizations: i, quarantine: InMemoryAppQuarantineRegistry())
            provider = p; issuer = i; vault = v
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
    func runSelfTest() {
        guard let vault, let issuer else { selfTestResult = "Kasa hazır değil."; return }
        do {
            let plain = Array("xrai-self-test-\(RecordID().hex)".utf8)
            let descriptor = try RecordDescriptor(dataClass: .derivedResult, retention: .sessionOnly, createdAtUnixSeconds: Int64(Date().timeIntervalSince1970))
            let env = try vault.seal(plaintext: plain, descriptor: descriptor, authorization: try issuer.issue(scope: .write(.derivedResult)))
            let back = try vault.open(env, authorization: try issuer.issue(scope: .read(recordIDs: [descriptor.recordID])))
            selfTestResult = back == plain ? "Başarılı: sentetik kayıt mühürlendi ve açıldı, saklanmadı." : "Başarısız: açılan veri farklı."
        } catch let e as VaultError {
            selfTestResult = "Başarısız (fail-closed): \(String(reflecting: e))"
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
