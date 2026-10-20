// "Ben" helpers. The tab itself moved to Experience/SelfMapView.swift in P04-00.
import SwiftUI
import XRAIVaultContracts

/// P04-00: the Ben tab is `SelfMapView`; this type keeps the protection description used by the security screen.
enum SelfView {
    static func describe(_ p: KeyProtection) -> String {
        switch p {
        case .inMemoryTestOnly: return "Bellek içi (yalnız test)"
        case .keychainLegacyMacOSTestOnly: return "macOS eski keychain (yalnız test)"
        case .keychainDeviceBound: return "Keychain, cihaza bağlı"
        case .secureEnclaveWrapped: return "Secure Enclave ile sarılı Keychain"
        }
    }
}
