// Onboarding state machine (testable, no UI) + the SwiftUI flow.
// Steps: welcome → whatItDoes → privacy → birthDate (optional) → preview (only if the user opted in) → done.
// Nothing entered here is written to disk.
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
    var year = ""
    var month = ""
    var day = ""
    private(set) var problem: BirthDateInput.Problem?

    let session: SessionState
    init(session: SessionState) { self.session = session }

    var progress: Double { Double(step.rawValue + 1) / Double(Step.allCases.count) }

    func next() {
        switch step {
        case .welcome: step = .whatItDoes
        case .whatItDoes: step = .privacy
        case .privacy: step = .birthDate
        case .birthDate: finish()                 // "continue without a date"
        case .preview: finish()
        }
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// Skip everything: usable app, no personal data.
    func skip() { finish() }

    /// Explicit opt-in: validate, store in memory only, show the preview.
    func computePreview() {
        switch BirthDateInput.parse(year: year, month: month, day: day) {
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
        finished = true
        session.completeOnboarding()
    }
}

struct OnboardingView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(\.xrMotion) private var motion

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: flow.progress)
                .tint(XRColor.accent)
                .padding(.horizontal, XRSpace.page)
                .padding(.top, XRSpace.s)
                .accessibilityLabel("Onboarding ilerlemesi")
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
        }
        .background(XRColor.background.ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: XRSpace.xl) {
            HStack { Spacer(); XRLogo(size: 112); Spacer() }.padding(.top, XRSpace.xxl)
            VStack(alignment: .leading, spacing: XRSpace.s) {
                Text("XRAI").font(XRFont.display).foregroundStyle(XRColor.text).accessibilityAddTraits(.isHeader)
                Text("Kendini keşfet. Kendi hızında, kendi cihazında.").font(XRFont.title).foregroundStyle(XRColor.text)
                Text("Kim olduğunu, seni neyin harekete geçirdiğini ve bugün atabileceğin tek anlamlı adımı birlikte araştırırız. Yorumlar pencere açar; kararı sen verirsin.")
                    .font(XRFont.body).foregroundStyle(XRColor.textSecondary)
            }
            Button("Başla") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.start")
            Button("Şimdilik atla") { flow.skip() }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("onboarding.skip")
        }
    }

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: XRSpace.l) {
            XRSectionTitle(text: "XRAI ne yapar, ne yapmaz")
            XRCard(tint: XRColor.sage.opacity(0.5)) {
                Text("Bu sürümde yapar").font(XRFont.heading).foregroundStyle(XRColor.text)
                bullet("Doğum tarihinden Yaşam Yolu sayısını çevrimdışı, adım adım hesaplar.")
                bullet("Hangi bilginin matematik, hangisinin gelenek, hangisinin senin beyanın olduğunu her zaman ayırır.")
                bullet("Hiçbir kişisel veriyi diske yazmaz; tarih yalnızca bu oturumda bellekte kalır.")
            }
            XRCard {
                Text("Henüz yapmaz").font(XRFont.heading).foregroundStyle(XRColor.text)
                bullet("Kişisel kasa, günlük, hedefler, Gelecek Benlik (planlı).")
                bullet("Astroloji, Human Design, isim analizi, psikoloji keşfi (planlı; kaynak ve hak incelemesi sürüyor).")
                bullet("Rehber sohbeti ve yorum üretimi (planlı; hiçbir model bağlı değil).")
                Text("Planlanan hiçbir şey tamamlanmış gibi gösterilmez.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            }
            Button("Devam") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.next.whatItDoes")
            Button("Geri") { flow.back() }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: XRSpace.l) {
            XRSectionTitle(text: "Verilerin senin kontrolünde")
            XRCard {
                bullet("Her şey cihazında çalışır. Bulut, analitik veya dış yapay zekâ bağlantısı yok.")
                bullet("Bu sürümde kişisel veri diske kaydedilmez. Uygulamayı kapatınca girdiğin tarih silinir.")
                bullet("Cihazın anahtar zincirinde yalnızca şifreleme anahtarları durur; kişisel kayıt değil. Kalıcı şifreli kasa daha sonra, senin açık izninle gelecek.")
                bullet("Yedekleme ve kurtarma anahtarı henüz çalışmıyor. Geldiğinde kural şu olacak: kurtarma anahtarını kaybedersen yedeğini kimse açamaz, XRAI dahil.")
                bullet("İstediğin an vazgeçebilir, veriyi unutturabilir veya uygulamayı kullanmayı bırakabilirsin.")
            }
            Button("Anladım, devam") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.next.privacy")
            Button("Geri") { flow.back() }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity)
        }
    }

    private var birthDate: some View {
        VStack(alignment: .leading, spacing: XRSpace.l) {
            XRSectionTitle(text: "Doğum tarihin (isteğe bağlı)")
            Text("İstersen Yaşam Yolu sayını hemen görebilirsin. Bu yalnızca rakam aritmetiğidir; kişilik, sağlık ya da kader anlamı taşımaz. Tarih kaydedilmez.")
                .font(XRFont.body).foregroundStyle(XRColor.textSecondary)
            DateFields(year: $flow.year, month: $flow.month, day: $flow.day, problem: flow.problem)
            Button("Önizlemeyi hesapla") { flow.computePreview() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.compute")
            Button("Tarih girmeden devam et") { flow.next() }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("onboarding.continueWithoutDate")
            Button("Geri") { flow.back() }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity)
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
            Button("Uygulamaya geç") { flow.next() }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("onboarding.finish")
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
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }
}
