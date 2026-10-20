// P04-00 screen B — Ben, the personal map: the full court, one selected stone's panel inline (no
// modal, VoiceOver-friendly), the real Life Path feature on stone 1, and the security/privacy
// surfaces one level down so the screen is a map, not an encyclopedia.
import SwiftUI

struct SelfMapView: View {
    @Environment(SessionState.self) private var session
    @Environment(SecurityStatus.self) private var security
    @Environment(\.xrMotion) private var motion
    @State private var selected = 1          // the one real engine is the natural first stop

    private var states: [Int: StationState] { ExperienceDerivation.states(session: session) }

    var body: some View {
        NavigationStack {
            XRPage {
                XRSectionTitle(text: "Ben")
                Text("Senin haritan. Bir taşa dokun; altında ne olduğunu, nasıl hesaplandığını ve nasıl düzelteceğini gör. Bu sürümde hiçbir şey diske yazılmaz.")
                    .font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                XRCard {
                    HopscotchMapView(states: states, selected: selected, compact: false) { id in
                        withAnimation(motion.standard) { selected = id }
                    }
                    CourtLegend()
                }
                .accessibilityIdentifier("ben.map")

                StationPanel(station: LivingGrammar.station(selected), state: states[selected] ?? .pending(phase: "?"))
                    .id(selected)

                XRCard {
                    Text("Güvenlik ve gizlilik").font(XRFont.heading).foregroundStyle(XRColor.text)
                    Text("Bu derlemenin gerçek durumu, izinler ve geri yükleme örnekleri.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                    NavigationLink("Güvenlik durumu") { SecurityPrivacyView() }
                        .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("self.security")
                    if security.consentFlow != nil {
                        NavigationLink("Gizlilik ve izinler") { ConsentView() }
                            .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("self.consent")
                        NavigationLink("Yedekten geri yükleme (örnek)") { RestoreRiskView() }
                            .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("self.restore")
                    }
                }
            }
        }
    }
}

/// The former Ben content: truthful security status, self-test, preferences. Unchanged semantics.
struct SecurityPrivacyView: View {
    @Environment(SecurityStatus.self) private var security
    @Environment(SessionState.self) private var session

    var body: some View {
        XRPage {
            XRSectionTitle(text: "Güvenlik durumu")
            XRCard {
                Text("Bu derleme").font(XRFont.heading).foregroundStyle(XRColor.text)
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
        .navigationTitle("Güvenlik")
    }

    @ViewBuilder private var keyRows: some View {
        switch security.keyState {
        case .notStarted:
            XRLabeledValue(label: "Anahtar koruması", value: "Başlatılıyor…")
        case .ready(let protection, let key):
            XRLabeledValue(label: "Anahtar koruması", value: SelfView.describe(protection))
            XRLabeledValue(label: "Anahtar sürümü", value: "\(key.keyID) #\(key.version)", mono: true)
        case .failedClosed(let reason):
            XRLabeledValue(label: "Anahtar koruması", value: "Kapalı (fail-closed)")
            Text(reason).font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
        }
    }
}
