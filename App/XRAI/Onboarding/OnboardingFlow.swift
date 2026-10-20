// Onboarding state machine (testable, no UI) + the SwiftUI flow.
// Steps: welcome → whatItDoes → privacy → birthDate (optional) → preview (only if the user opted in) → done.
// Nothing entered here is written to disk. The form draft lives in SessionState (one copy) and is
// cleared when onboarding finishes, whether or not a date was confirmed (P03-02 G1).
import Observation
import SwiftUI
import XRAIIdentityTime

@MainActor
@Observable
final class OnboardingFlow {
    enum Step: Int, CaseIterable { case welcome, whatItDoes, privacy, birthDate, preview }

    private(set) var step: Step = .welcome
    private(set) var finished = false
    private(set) var previewOptedIn = false
    private(set) var problem: BirthDateInput.Problem?

    let session: SessionState
    init(session: SessionState) { self.session = session }

    var progress: Double { Double(step.rawValue + 1) / Double(Step.allCases.count) }

    func next() {
        switch step {
        case .welcome: step = .whatItDoes
        case .whatItDoes: step = .privacy
        case .privacy: step = .birthDate
        case .birthDate: finish()                 // "continue without a date": unconfirmed text is dropped
        case .preview: finish()
        }
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// Skip everything: usable app, no personal data.
    func skip() { finish() }

    /// Explicit opt-in: validate, store the DATE in memory only, show the preview.
    func computePreview() {
        switch BirthDateInput.parse(session.draft) {
        case .success(let d):
            problem = nil
            session.setBirthDate(d)
            previewOptedIn = true
            step = .preview
        case .failure(let p):
            problem = p
        }
    }

    private func finish() {
        session.clearDraft()                      // form text never outlives onboarding
        problem = nil
        finished = true
        session.completeOnboarding()
    }
}

struct OnboardingView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(\.xrMotion) private var motion

    var body: some View {
        VStack(spacing: 0) {
            // Decorative for assistive tech (the audit flags it as a tiny control); the step count is
            // exposed on the page as text instead.
            ProgressView(value: flow.progress)
                .tint(XRColor.accent)
                .padding(.horizontal, XRSpace.page)
                .padding(.top, XRSpace.s)
                .accessibilityHidden(true)
            Text("Adım \(flow.step.rawValue + 1) / \(OnboardingFlow.Step.allCases.count)")
                .font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, XRSpace.page)
                .accessibilityLabel("Tanıtım adımı \(flow.step.rawValue + 1), toplam \(OnboardingFlow.Step.allCases.count)")
            XRPage {
                switch flow.step {
                case .welcome: welcome
                case .whatItDoes: whatItDoes
                case .privacy: privacy
                case .birthDate: birthDate
                case .preview: preview
                }
            }
            .animation(motion.standard, value: flow.step)
            // Actions pinned above the home indicator at every Dynamic Type size (F-UX-1):
            // "Şimdilik atla" is always visible next to "Başla", never below the fold.
            .safeAreaInset(edge: .bottom) { actions }
        }
        .background(XRColor.background.ignoresSafeArea())
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: XRSpace.s) {
            switch flow.step {
            case .welcome:
                Button("Başla") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.start")
                Button("Şimdilik atla") { flow.skip() }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("onboarding.skip")
            case .whatItDoes:
                Button("Devam") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.next.whatItDoes")
                Button("Geri") { flow.back() }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("onboarding.back.whatItDoes")
            case .privacy:
                Button("Anladım, devam") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.next.privacy")
                Button("Geri") { flow.back() }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("onboarding.back.privacy")
            case .birthDate:
                Button("Önizlemeyi hesapla") { flow.computePreview() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.compute")
                Button("Tarih girmeden devam et") { flow.next() }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("onboarding.continueWithoutDate")
                Button("Geri") { flow.back() }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("onboarding.back.birthDate")
            case .preview:
                Button("Uygulamaya geç") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.finish")
            }
        }
        .padding(.horizontal, XRSpace.page)
        .padding(.top, XRSpace.m)
        .padding(.bottom, XRSpace.s)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(XRColor.background.opacity(0.96))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: XRSpace.xl) {
            HStack { Spacer(); XRLogo(size: 112); Spacer() }.padding(.top, XRSpace.xl)
            VStack(alignment: .leading, spacing: XRSpace.s) {
                Text("XRAI").font(XRFont.display).foregroundStyle(XRColor.text).accessibilityAddTraits(.isHeader)
                Text("Kendini keşfet. Kendi hızında, kendi cihazında.").font(XRFont.title).foregroundStyle(XRColor.text)
                Text("Kim olduğunu, seni neyin harekete geçirdiğini ve bugün atabileceğin tek anlamlı adımı birlikte araştırırız. Yorumlar pencere açar; kararı sen verirsin.")
                    .font(XRFont.body).foregroundStyle(XRColor.textSecondary)
            }
        }
    }

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: XRSpace.l) {
            XRSectionTitle(text: "XRAI ne yapar, ne yapmaz")
            XRCard(tint: XRColor.sage.opacity(0.5)) {
                Text("Bu sürümde yapar").font(XRFont.heading).foregroundStyle(XRColor.text)
                bullet("Doğum tarihinden Yaşam Yolu sayısını çevrimdışı, adım adım hesaplar.")
                bullet("Hangi bilginin matematik, hangisinin gelenek, hangisinin senin beyanın, hangisinin sistemin daveti olduğunu her zaman ayırır.")
                bullet("Hiçbir kişisel veriyi diske yazmaz.")
            }
            XRCard {
                Text("Henüz yapmaz").font(XRFont.heading).foregroundStyle(XRColor.text)
                bullet("Kişisel kasa, günlük, hedefler, Gelecek Benlik (planlı).")
                bullet("Astroloji, Human Design, isim analizi, psikoloji keşfi (planlı; kaynak ve hak incelemesi sürüyor).")
                bullet("Rehber sohbeti ve yorum üretimi (planlı; hiçbir model bağlı değil).")
                Text("Planlanan hiçbir şey tamamlanmış gibi gösterilmez.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: XRSpace.l) {
            XRSectionTitle(text: "Verilerin senin kontrolünde")
            XRCard {
                bullet("Her şey cihazında çalışır. Bulut, analitik veya dış yapay zekâ bağlantısı yok.")
                bullet("Bu sürümde kişisel veri diske kaydedilmez. Girdiğin tarih yalnızca uygulama açıkken bellekte durur.")
                bullet("Uygulamayı arka plana alırsan tarih bellekte kalmaya devam eder; ekran görüntüsü yerine bir gizlilik perdesi gösterilir. Uygulamayı tamamen kapatınca tarih silinir. 'Tarihi unut' ise hemen siler.")
                bullet("Cihazın anahtar zincirinde yalnızca şifreleme anahtarları durur; kişisel kayıt değil. Kalıcı şifreli kasa daha sonra, senin açık izninle gelecek.")
                bullet("Yedekleme ve kurtarma anahtarı henüz çalışmıyor. Geldiğinde kural şu olacak: kurtarma anahtarını kaybedersen yedeğini kimse açamaz, XRAI dahil.")
                bullet("İstediğin an vazgeçebilir, veriyi unutturabilir veya uygulamayı kullanmayı bırakabilirsin.")
            }
        }
    }

    private var birthDate: some View {
        @Bindable var session = flow.session
        return VStack(alignment: .leading, spacing: XRSpace.l) {
            XRSectionTitle(text: "Doğum tarihin (isteğe bağlı)")
            Text("İstersen Yaşam Yolu sayını hemen görebilirsin. Bu yalnızca rakam aritmetiğidir; kişilik, sağlık ya da kader anlamı taşımaz. Tarih diske kaydedilmez; onaylamadan çıkarsan yazdıkların da silinir.")
                .font(XRFont.body).foregroundStyle(XRColor.textSecondary)
            DateFields(year: $session.draft.year, month: $session.draft.month, day: $session.draft.day, problem: flow.problem)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: XRSpace.l) {
            XRSectionTitle(text: "İlk önizlemen")
            if let t = flow.session.trace {
                LifePathCard(trace: t)
            }
            Text("Bu bir başlangıç noktası, bir hüküm değil. Ben sekmesinden yöntemi değiştirebilir, izi inceleyebilir veya tarihi unutturabilirsin.")
                .font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
        }
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: XRSpace.s) {
            Circle().fill(XRColor.accent).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
            Text(text).font(XRFont.body).foregroundStyle(XRColor.text)
        }
    }
}

/// Three numeric fields with validation message. Labels for VoiceOver; identifiers for UI tests.
struct DateFields: View {
    @Binding var year: String
    @Binding var month: String
    @Binding var day: String
    let problem: BirthDateInput.Problem?

    var body: some View {
        VStack(alignment: .leading, spacing: XRSpace.s) {
            HStack(spacing: XRSpace.s) {
                field("Yıl", text: $year, id: "date.year")
                field("Ay", text: $month, id: "date.month")
                field("Gün", text: $day, id: "date.day")
            }
            if let problem {
                Text(BirthDateInput.message(for: problem))
                    .font(XRFont.caption).foregroundStyle(problem == .empty ? XRColor.textSecondary : XRColor.danger)
                    .accessibilityIdentifier("date.problem")
                    .accessibilityLabel(Text("Tarih hatası: ") + Text(BirthDateInput.message(for: problem)))
            }
        }
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, id: String) -> some View {
        TextField(label, text: text)
            .keyboardType(.numberPad)
            .font(XRFont.body)
            .padding(XRSpace.m)
            .frame(minHeight: XRHit.min)
            .background(XRColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: XRRadius.control, style: .continuous))
            // F-UX-5: a 1.5pt boundary at ≥ 3:1 against the card so the input is identifiable without its placeholder.
            .overlay(RoundedRectangle(cornerRadius: XRRadius.control, style: .continuous).strokeBorder(XRColor.inputBorder, lineWidth: 1.5))
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }
}
