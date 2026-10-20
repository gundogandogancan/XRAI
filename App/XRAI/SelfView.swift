// "Ben": the person's own surface — session data (never persisted), the first feature, the truthful
// security status of this build, and privacy controls that exist today.
import SwiftUI
import XRAIVaultContracts

struct SelfView: View {
    @Environment(SecurityStatus.self) private var security
    @Environment(SessionState.self) private var session

    var body: some View {
        NavigationStack {
            XRPage {
                XRSectionTitle(text: "Ben")
                Text("Burada yalnızca sen varsın. Bu sürümde hiçbir şey diske kaydedilmez; tarih yalnızca uygulama açıkken bellekte durur.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)

                LifePathFeatureView()

                if security.consentFlow != nil {
                    NavigationLink("Gizlilik ve izinler") { ConsentView() }
                        .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("self.consent")
                    NavigationLink("Yedekten geri yükleme (örnek)") { RestoreRiskView() }
                        .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("self.restore")
                }

                XRCard {
                    Text("Güvenlik durumu (bu derleme)").font(XRFont.heading).foregroundStyle(XRColor.text)
                    keyRows
                    XRLabeledValue(label: "Secure Enclave", value: security.secureEnclaveAvailable ? "Var" : "Yok")
                    XRLabeledValue(label: "Anahtar önbelleği", value: "\(security.cacheTTLSeconds) sn, arka planda temizlenir")
                    XRLabeledValue(label: "Kalıcı kişisel veri", value: security.persistenceImplemented ? "Var" : "Yok")
                    XRLabeledValue(label: "İzin kaydı", value: security.consentRegistryImplemented ? "Var" : "Yok")
                    XRLabeledValue(label: "Yedekleme / kurtarma anahtarı", value: "Henüz çalışmıyor")
                    XRLabeledValue(label: "Cihazda doğrulandı", value: security.deviceVerified ? "Evet" : "Kısmen")
                    XRLabeledValue(label: "Bağımsız güvenlik denetimi", value: security.securityReviewed ? "Evet" : "Hayır")
                    XRLabeledValue(label: "Derleme", value: security.buildIsDebug ? "Debug (test/demo)" : "Release")
                    Text("Anahtar zincirinde yalnızca şifreleme anahtarları durur; kişisel kayıt yok. Arka planda tarih bellekte kalır ve uygulama değiştiricide gizlilik perdesi gösterilir; uygulamayı kapatınca tarih silinir; 'Tarihi unut' hemen siler. Kayıt saklama, izin kaydı ve yedek daha sonra, açık izninle gelir.")
                        .font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                }

                XRCard {
                    Text("Kendi kendini sına").font(XRFont.heading).foregroundStyle(XRColor.text)
                    Text("Gerçek kasa ile sentetik veri şifrelenir, açılır ve atılır. Hiçbir şey saklanmaz.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                    Button("Sentetik kaydı mühürle ve aç") { security.runSelfTest() }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("security.selftest")
                    if let r = security.selfTestResult { Text(r).font(XRFont.caption).foregroundStyle(XRColor.text).accessibilityIdentifier("security.selftest.result") }
                    Button("Anahtar önbelleğini temizle") { security.purgeKeyCache() }.buttonStyle(XRQuietButtonStyle())
                    XRLabeledValue(label: "Bellekteki anahtar sürümleri", value: security.cachedKeyVersions.isEmpty ? "yok" : security.cachedKeyVersions.map(String.init).joined(separator: ", "))
                }

                XRCard {
                    Text("Tercihler").font(XRFont.heading).foregroundStyle(XRColor.text)
                    Button("Tanıtımı yeniden göster") { session.resetOnboarding() }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("prefs.resetOnboarding")
                    Text("Kaydedilen tek şey, tanıtımın tamamlandığını belirten kişisel olmayan bir işarettir.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                }
            }
        }
    }

    @ViewBuilder private var keyRows: some View {
        switch security.keyState {
        case .notStarted:
            XRLabeledValue(label: "Anahtar koruması", value: "Başlatılıyor…")
        case .ready(let protection, let key):
            XRLabeledValue(label: "Anahtar koruması", value: Self.describe(protection))
            XRLabeledValue(label: "Anahtar sürümü", value: "\(key.keyID) #\(key.version)", mono: true)
        case .failedClosed(let reason):
            XRLabeledValue(label: "Anahtar koruması", value: "Kapalı (fail-closed)")
            Text(reason).font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
        }
    }

    static func describe(_ p: KeyProtection) -> String {
        switch p {
        case .inMemoryTestOnly: return "Bellek içi (yalnız test)"
        case .keychainLegacyMacOSTestOnly: return "macOS eski keychain (yalnız test)"
        case .keychainDeviceBound: return "Keychain, cihaza bağlı"
        case .secureEnclaveWrapped: return "Secure Enclave ile sarılı Keychain"
        }
    }
}
