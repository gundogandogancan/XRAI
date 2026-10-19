// First working feature: exact Life Path with a readable trace. Math and symbolism are separate;
// symbolism does not exist yet and says so. Offline; the date is never stored.
import SwiftUI
import XRAIIdentityTime
import XRAINumerology

struct LifePathCard: View {
    let trace: NumerologyTrace

    var body: some View {
        XRCard(tint: XRColor.accent.opacity(0.4)) {
            HStack {
                Text("Yaşam Yolu").font(XRFont.heading).foregroundStyle(XRColor.text)
                Spacer()
                XREpistemicBadge(kind: .exactMath)
            }
            HStack(alignment: .firstTextBaseline, spacing: XRSpace.m) {
                Text(String(trace.root))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(XRColor.accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityLabel("Kök sayı \(trace.root)")
                    .accessibilityIdentifier("lifepath.root")
                if let m = trace.masterNumber {
                    Text("Ana sayı \(m) korundu").font(XRFont.caption).foregroundStyle(XRColor.gold)
                }
            }
            XRLabeledValue(label: "Yöntem", value: trace.methodID.rawValue, mono: true)
            XRLabeledValue(label: "Bileşik", value: String(trace.compound))
            XRLabeledValue(label: "İndirgeme", value: trace.reductions.isEmpty ? "—" : trace.reductions.map(String.init).joined(separator: " → "))
            XRLabeledValue(label: "Ana sayı kuralı", value: trace.masterPolicy == .preserve11_22_33 ? "11/22/33 korunur" : "Hepsi tek haneye iner")
            Text("Bu bir hesaptır, bir yorum değil. Sembolik anlam henüz eklenmedi.")
                .font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
        }
    }
}

/// Full feature view (Ben tab): date entry, method/policy, trace, symbolic section honestly absent.
struct LifePathFeatureView: View {
    @Environment(SessionState.self) private var session
    @State private var problem: BirthDateInput.Problem?

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: XRSpace.l) {
            if let t = session.trace, let d = session.birthDate {
                LifePathCard(trace: t)
                XRCard {
                    Text("Hesaplama izi").font(XRFont.heading).foregroundStyle(XRColor.text)
                    XRStackedValue(label: "Tarih (yalnız bellekte, diske yazılmaz)", value: d.isoString)
                    XRStackedValue(label: "Rakamlar", value: t.rawDigits.map(String.init).joined(separator: " "))
                    if let cts = t.componentTraces {
                        ForEach(cts, id: \.component) { c in
                            Text("\(c.component.rawValue): \(c.reduction.compound) → \(c.reduction.root)").font(XRFont.mono).foregroundStyle(XRColor.text)
                        }
                    }
                    Text("Toplam \(t.compound)" + (t.reductions.isEmpty ? "" : " → " + t.reductions.map(String.init).joined(separator: " → ")) + " = kök \(t.root)")
                        .font(XRFont.mono).foregroundStyle(XRColor.text)
                        .accessibilityIdentifier("lifepath.trace")
                    Picker("Yöntem", selection: $session.method) {
                        Text("Tüm rakamlar (digits.v1)").tag(NumerologyMethodID.lifePathDigitsV1)
                        Text("Yıl/Ay/Gün ayrı (components.v1)").tag(NumerologyMethodID.lifePathComponentsV1)
                    }
                    .pickerStyle(.menu).tint(XRColor.accent)
                    Toggle("11/22/33 ana sayılarını koru", isOn: Binding(
                        get: { session.masterPolicy == .preserve11_22_33 },
                        set: { session.masterPolicy = $0 ? .preserve11_22_33 : .reduceAll }
                    )).tint(XRColor.accent)
                    Button("Tarihi unut") { session.forgetAll(); problem = nil }
                        .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("lifepath.forget")
                    Text("Unutmak, tarihi ve yazdığın taslağı hemen bellekten çıkarır. Arka planda beklerken ise tarih bellekte kalır; uygulamayı kapatınca silinir.")
                        .font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                }
                XRCard {
                    HStack {
                        Text("Sembolik yorum").font(XRFont.heading).foregroundStyle(XRColor.text)
                        Spacer()
                        XREpistemicBadge(kind: .notBuilt)
                    }
                    Text("Pisagorcu gelenekte bu sayıya atfedilen temalar, kaynağı gösterilerek ve 'bu geleneğe göre' diye işaretlenerek daha sonra eklenecek (P04/P07). Matematik ile yorum hiçbir zaman karıştırılmayacak.")
                        .font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                }
            } else {
                XRCard {
                    Text("Yaşam Yolu hesabı").font(XRFont.heading).foregroundStyle(XRColor.text)
                    Text("İsteğe bağlı. Tarih yalnızca uygulama açıkken bellekte tutulur, diske yazılmaz.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                    DateFields(year: $session.draft.year, month: $session.draft.month, day: $session.draft.day, problem: problem)
                    Button("Hesapla") {
                        switch BirthDateInput.parse(session.draft) {
                        case .success(let d): problem = nil; session.setBirthDate(d)
                        case .failure(let p): problem = p
                        }
                    }
                    .buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("lifepath.compute")
                }
            }
        }
    }
}
