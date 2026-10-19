// "Ben": the only tab with working content in P03-00 — the truthful security status of this build
// and a free, on-device Life Path calculation that stores nothing and claims no meaning.
import SwiftUI
import XRAIIdentityTime
import XRAINumerology
import XRAIVaultContracts

struct SelfView: View {
    @Environment(SecurityStatus.self) private var security

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LifePathPreview()
                } header: {
                    Text("Ücretsiz hesap: Yaşam Yolu")
                } footer: {
                    Text("Yalnızca rakam aritmetiği (EXACT_MATH). Kişilik, sağlık veya kader anlamı taşımaz. Girdiğin tarih cihazda saklanmaz.")
                }

                Section("Güvenlik durumu (bu derleme)") {
                    keyRow
                    LabeledContent("Secure Enclave", value: security.secureEnclaveAvailable ? "Var" : "Yok (simülatör veya desteklemeyen cihaz)")
                    LabeledContent("Anahtar önbelleği", value: "\(security.cacheTTLSeconds) sn, arka planda temizlenir")
                    LabeledContent("Kalıcı kişisel veri", value: security.persistenceImplemented ? "Var" : "Yok — hiçbir kayıt saklanmıyor")
                    LabeledContent("İzin kaydı", value: security.consentRegistryImplemented ? "Var" : "Yok — izin gerektiren sınıflar reddedilir")
                    LabeledContent("Karantina kaydı", value: security.quarantineRegistryPersisted ? "Kalıcı" : "Bellek içi, kalıcı değil")
                    LabeledContent("Cihazda doğrulandı", value: security.deviceVerified ? "Evet" : "Hayır")
                    LabeledContent("Bağımsız güvenlik denetimi", value: security.securityReviewed ? "Evet" : "Hayır")
                    LabeledContent("Derleme", value: security.buildIsDebug ? "Debug (test/demo)" : "Release")
                }

                Section("Kendi kendini sına") {
                    Button("Sentetik kaydı mühürle ve aç") { security.runSelfTest() }
                        .accessibilityHint("Gerçek kasa ile sentetik veri şifrelenir, açılır ve atılır. Hiçbir şey saklanmaz.")
                    if let r = security.selfTestResult {
                        Text(r).font(.footnote)
                    }
                    Button("Anahtar önbelleğini temizle") { security.purgeKeyCache() }
                    LabeledContent("Bellekteki anahtar sürümleri", value: security.cachedKeyVersions.isEmpty ? "yok" : security.cachedKeyVersions.map(String.init).joined(separator: ", "))
                }
            }
            .navigationTitle("Ben")
        }
    }

    @ViewBuilder private var keyRow: some View {
        switch security.keyState {
        case .notStarted:
            LabeledContent("Anahtar koruması", value: "Başlatılıyor…")
        case .ready(let protection, let key):
            LabeledContent("Anahtar koruması", value: Self.describe(protection))
            LabeledContent("Anahtar sürümü", value: "\(key.keyID) #\(key.version)")
        case .failedClosed(let reason):
            LabeledContent("Anahtar koruması", value: "Kapalı (fail-closed)")
            Text(reason).font(.footnote).foregroundStyle(.secondary)
        }
    }

    static func describe(_ p: KeyProtection) -> String {
        switch p {
        case .inMemoryTestOnly: return "Bellek içi (yalnız test)"
        case .keychainLegacyMacOSTestOnly: return "macOS eski keychain (yalnız test)"
        case .keychainDeviceBound(let a): return "Keychain, cihaza bağlı (\(a))"
        case .secureEnclaveWrapped(let a): return "Secure Enclave ile sarılı Keychain (\(a))"
        }
    }
}

/// Free Life Path: validated civil date → exact trace. Nothing is stored; the date lives in view state only.
struct LifePathPreview: View {
    @State private var year = ""
    @State private var month = ""
    @State private var day = ""
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Yıl", text: $year).keyboardType(.numberPad).accessibilityLabel("Doğum yılı")
                TextField("Ay", text: $month).keyboardType(.numberPad).accessibilityLabel("Doğum ayı")
                TextField("Gün", text: $day).keyboardType(.numberPad).accessibilityLabel("Doğum günü")
            }
            .textFieldStyle(.roundedBorder)
            Button("Hesapla") { compute() }
            if let result { Text(result).font(.footnote) }
        }
    }

    private func compute() {
        guard let y = Int(year), let m = Int(month), let d = Int(day) else { result = "Üç alanı da sayı olarak gir."; return }
        do {
            let date = try CivilDate(year: y, month: m, day: d)
            let t = try NumerologyLifePath.calculate(date, method: .lifePathDigitsV1)
            let master = t.masterNumber.map { " (ana sayı \($0) korundu)" } ?? ""
            result = "num.life_path.digits.v1 · bileşik \(t.compound) → kök \(t.root)\(master). Yorum yok; yalnızca aritmetik."
        } catch let e as CivilDateError {
            result = "Geçersiz tarih: \(String(reflecting: e))"
        } catch {
            result = "Hesaplanamadı."
        }
    }
}
