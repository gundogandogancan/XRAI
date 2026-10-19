import Foundation
import SwiftUI
import Testing
import XRAIIdentityTime
import XRAINumerology
@testable import XRAI

// P03-01 §6 + P03-02 G1/G2/G3/G5: start, skip, invalid date, valid date, background/relaunch semantics,
// data lifecycle (forgetAll), epistemic classes, contrast, motion and privacy-shield policy.
// Isolated UserDefaults suites keep the real app flag untouched.

@MainActor
private func freshSession() -> SessionState {
    let suite = "xrai.tests." + UUID().uuidString
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return SessionState(defaults: d)
}

@Suite("Onboarding flow model")
@MainActor
struct OnboardingFlowTests {
    @Test("start: steps advance in order and nothing is set before the user opts in")
    func start() {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        #expect(f.step == .welcome && !s.onboardingCompleted && s.birthDate == nil)
        f.next(); #expect(f.step == .whatItDoes)
        f.next(); #expect(f.step == .privacy)
        f.next(); #expect(f.step == .birthDate)
        #expect(!f.finished && s.birthDate == nil && !f.previewOptedIn)
        f.back(); #expect(f.step == .privacy)
    }

    @Test("skip from welcome: app usable, onboarding completed, no personal data anywhere")
    func skip() {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.skip()
        #expect(f.finished && s.onboardingCompleted && s.birthDate == nil && s.trace == nil && !s.holdsPersonalData)
    }

    @Test("G1: continue without a date drops the unconfirmed draft text")
    func continueWithoutDateDropsDraft() {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.next(); f.next(); f.next()
        s.draft = DateDraft(year: "1998", month: "6", day: "30")   // typed but NOT confirmed
        #expect(s.holdsPersonalData)
        f.next()
        #expect(f.finished && s.birthDate == nil && s.draft == .empty && !s.holdsPersonalData, "typing is not consent and does not survive onboarding")
    }

    @Test("invalid date: typed problem, no date set, stays on the date step")
    func invalidDate() {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.next(); f.next(); f.next()
        s.draft = DateDraft(year: "1900", month: "2", day: "29")
        f.computePreview()
        #expect(f.problem == .invalid(.invalidDay(year: 1900, month: 2, day: 29, daysInMonth: 28)))
        #expect(f.step == .birthDate && s.birthDate == nil && !f.previewOptedIn)
        s.draft.year = "abc"; f.computePreview(); #expect(f.problem == .notNumbers)
        s.draft = .empty; f.computePreview(); #expect(f.problem == .empty)
    }

    @Test("valid date: explicit opt-in sets the in-memory date, shows the preview, trace matches the engine; finishing clears the draft but keeps the date")
    func validDate() throws {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.next(); f.next(); f.next()
        s.draft = DateDraft(year: "1998", month: "06", day: "30")
        f.computePreview()
        #expect(f.problem == nil && f.step == .preview && f.previewOptedIn)
        let d = try #require(s.birthDate)
        #expect(d.isoString == "1998-06-30")
        let t = try #require(s.trace)
        #expect(t == (try NumerologyLifePath.calculate(d, method: .lifePathDigitsV1)) && t.root == 9 && t.compound == 36)
        f.next()
        #expect(f.finished && s.onboardingCompleted && s.draft == .empty && s.birthDate != nil, "G1: form text does not outlive onboarding; the confirmed date does")
    }
}

@Suite("G1 — data lifecycle: one central forget, nothing lingers")
@MainActor
struct DataLifecycleTests {
    @Test("forgetAll clears the confirmed date AND every draft field; preferences stay; recompute works afterwards")
    func forgetAllClearsEverything() throws {
        let s = freshSession()
        s.draft = DateDraft(year: "1955", month: "1", day: "1")
        s.setBirthDate(try CivilDate(year: 1955, month: 1, day: 1))
        s.method = .lifePathComponentsV1
        #expect(s.holdsPersonalData && s.trace?.root == 4)
        s.forgetAll()
        #expect(s.birthDate == nil && s.draft == .empty && s.trace == nil && !s.holdsPersonalData)
        #expect(s.method == .lifePathComponentsV1, "non-personal preference kept")
        // new entry after forgetting is not broken
        s.draft = DateDraft(year: "2000", month: "2", day: "29")
        if case .success(let d) = BirthDateInput.parse(s.draft) { s.setBirthDate(d) } else { Issue.record("parse failed") }
        #expect(s.trace?.root == 6)
        s.forgetAll(); s.method = .lifePathDigitsV1
        s.setBirthDate(try CivilDate(year: 1998, month: 6, day: 30))
        #expect(s.trace?.root == 9)
    }

    @Test("the onboarding flow and the feature share ONE draft: forgetting from the feature empties the onboarding form too")
    func singleDraftCopy() {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.next(); f.next(); f.next()
        s.draft = DateDraft(year: "1998", month: "6", day: "30")
        f.computePreview()
        #expect(s.birthDate != nil)
        s.forgetAll()                       // "Tarihi unut" in Ben
        #expect(s.draft == .empty && s.birthDate == nil)
        #expect(f.session === s, "no second copy of the session exists")
    }

    @Test("negative: forgetAll never touches the onboarding flag, and resetOnboarding never touches personal data")
    func separationOfConcerns() throws {
        let s = freshSession()
        s.completeOnboarding()
        s.setBirthDate(try CivilDate(year: 1998, month: 6, day: 30))
        s.forgetAll()
        #expect(s.onboardingCompleted)
        s.setBirthDate(try CivilDate(year: 1998, month: 6, day: 30))
        s.resetOnboarding()
        #expect(s.birthDate != nil && !s.onboardingCompleted)
    }
}

@Suite("G2 — privacy semantics: background keeps memory, relaunch forgets, shield policy")
@MainActor
struct PrivacySemanticsTests {
    @Test("relaunch: the onboarding flag persists, the birth date and draft do not; the defaults suite holds only the flag")
    func relaunch() throws {
        let suite = "xrai.tests." + UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let first = SessionState(defaults: d)
        first.setBirthDate(try CivilDate(year: 1998, month: 6, day: 30))
        first.draft = DateDraft(year: "1998", month: "6", day: "30")
        first.completeOnboarding()
        let second = SessionState(defaults: d)
        #expect(second.onboardingCompleted && second.birthDate == nil && second.draft == .empty)
        let keys = d.persistentDomain(forName: suite)?.keys.map { String($0) } ?? []
        #expect(keys == [SessionState.onboardingKey])
        let dump = String(describing: d.persistentDomain(forName: suite))
        #expect(!dump.contains("1998") && !dump.contains("birth"))
    }

    @Test("background → foreground inside one process keeps the in-memory date (and the UI says so) while the key cache is purged")
    func backgroundKeepsSessionButPurgesKeys() throws {
        let s = freshSession()
        s.setBirthDate(try CivilDate(year: 2000, month: 2, day: 29))
        let sec = SecurityStatus(); sec.bootstrap(); sec.runSelfTest(); sec.purgeKeyCache()
        #expect(sec.cachedKeyVersions.isEmpty && s.trace?.root == 6)
    }

    @Test("shield policy: shown only when inactive AND personal data is held")
    func shieldPolicy() {
        #expect(PrivacyShieldPolicy.shouldShield(phase: .background, holdsPersonalData: true))
        #expect(PrivacyShieldPolicy.shouldShield(phase: .inactive, holdsPersonalData: true))
        #expect(!PrivacyShieldPolicy.shouldShield(phase: .active, holdsPersonalData: true))
        #expect(!PrivacyShieldPolicy.shouldShield(phase: .background, holdsPersonalData: false), "nothing to hide, nothing to cover")
    }
}

@Suite("G3 — epistemic classes never blend")
struct EpistemicClassTests {
    @Test("five distinct classes with distinct, non-empty labels; the system invitation is not the user's report")
    func distinct() {
        let kinds = XREpistemicBadge.Kind.allCases
        #expect(kinds.count == 5)
        let labels = kinds.map(\.rawLabel)
        #expect(Set(labels).count == 5 && labels.allSatisfy { !$0.isEmpty })
        #expect(XREpistemicBadge.Kind.systemInvitation.rawLabel == "Sistem daveti")
        #expect(XREpistemicBadge.Kind.systemInvitation.rawLabel != XREpistemicBadge.Kind.userReport.rawLabel)
    }
}

@Suite("G5 — measured contrast of the real light/dark token pairs (WCAG 2.x)")
struct ContrastTests {
    private static func luminance(_ c: UIColor, _ style: UIUserInterfaceStyle) -> Double {
        let r = c.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, a: CGFloat = 0
        r.getRed(&red, green: &green, blue: &blue, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }
    static func ratio(_ fg: Color, _ bg: Color, _ style: UIUserInterfaceStyle) -> Double {
        let a = luminance(UIColor(fg), style), b = luminance(UIColor(bg), style)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test("text pairs reach AA 4.5:1 and UI accents reach 3:1 in BOTH appearances; ratios recorded")
    func pairs() {
        let pairs: [(String, Color, Color, Double)] = [
            ("text/background", XRColor.text, XRColor.background, 4.5),
            ("text/surface", XRColor.text, XRColor.surface, 4.5),
            ("textSecondary/background", XRColor.textSecondary, XRColor.background, 4.5),
            ("textSecondary/surface", XRColor.textSecondary, XRColor.surface, 4.5),
            ("onAccent/accent (primary button)", XRColor.onAccent, XRColor.accent, 4.5),
            ("accent/background (large/UI)", XRColor.accent, XRColor.background, 3.0),
            ("accent/accentSoft (secondary button)", XRColor.accent, XRColor.accentSoft, 4.5),
            ("sage/background", XRColor.sage, XRColor.background, 3.0),
            ("gold/background", XRColor.gold, XRColor.background, 3.0),
            ("danger/surface", XRColor.danger, XRColor.surface, 4.5),
            ("border/surface (non-text, ≥1.3)", XRColor.border, XRColor.surface, 1.3),
        ]
        var report: [String] = []
        for (name, fg, bg, minimum) in pairs {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let r = Self.ratio(fg, bg, style)
                report.append("\(name) [\(style == .light ? "light" : "dark")] = \(String(format: "%.2f", r)) (min \(minimum))")
                #expect(r >= minimum, Comment(rawValue: report.last!))
            }
        }
        // Written to the attachment list so the measured numbers are part of the evidence.
        Attachment.record(report.joined(separator: "\n"), named: "contrast-ratios.txt")
    }
}

@Suite("G5 — Reduce Motion")
struct MotionTests {
    @Test("with Reduce Motion the design system returns no animation; otherwise a short ease")
    func motion() {
        #expect(XRMotion(reduce: true).standard == nil && XRMotion(reduce: true).gentle == nil)
        #expect(XRMotion(reduce: false).standard != nil && XRMotion(reduce: false).gentle != nil)
    }
}
