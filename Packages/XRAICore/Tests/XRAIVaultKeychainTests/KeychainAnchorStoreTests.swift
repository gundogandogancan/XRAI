import Foundation
import Testing
import XRAIVaultContracts
@testable import XRAIVaultKeychain

// P03-04 H5: the anchor in the REAL keychain of the test host (macOS legacy keychain under the explicit
// test flag; data-protection keychain inside the signed app on Simulator/device). Unique service, cleaned up.

@Suite("Keychain anchor store (real keychain)")
struct KeychainAnchorStoreTests {
    @Test("write → read → update → clear round-trips; a second instance sees the same anchor; decoding rejects a foreign blob")
    func anchorRoundTrip() throws {
        let service = "com.xrai.vault.test." + RecordID().hex
        defer { for mode in [KeychainStore.Mode.dataProtection, .legacyMacOS] { try? KeychainStore(service: service, accessibility: .whenUnlockedThisDeviceOnly, mode: mode).deleteAll() } }
        let cfg = KeychainConfiguration(service: service, accessibility: .whenUnlockedThisDeviceOnly, secureEnclave: .preferred, useDataProtectionKeychain: true, allowLegacyMacOSKeychainForTesting: true)
        let a = try KeychainAnchorStore(keyID: "k", configuration: cfg)
        #expect(try a.readAnchor() == nil)
        let id = [UInt8](repeating: 4, count: 16)
        let h1 = [UInt8](repeating: 1, count: 32), h2 = [UInt8](repeating: 2, count: 32)
        try a.writeAnchor(try VaultAnchor(vaultInstanceID: id, manifestGeneration: 1, manifestHash: h1))
        #expect(try a.readAnchor() == (try VaultAnchor(vaultInstanceID: id, manifestGeneration: 1, manifestHash: h1)))
        try a.writeAnchor(try VaultAnchor(vaultInstanceID: id, manifestGeneration: 2, manifestHash: h2))
        let b = try KeychainAnchorStore(keyID: "k", configuration: cfg)
        #expect(try b.readAnchor()?.manifestGeneration == 2 && (try b.readAnchor()?.manifestHash) == h2)
        try b.clearAnchor()
        #expect(try a.readAnchor() == nil)
        #expect(throws: VaultError.self) { try VaultAnchor.decode([1, 2, 3]) }
        #expect(throws: VaultError.self) { try VaultAnchor(vaultInstanceID: [1], manifestGeneration: 1, manifestHash: h1) }
    }
}
