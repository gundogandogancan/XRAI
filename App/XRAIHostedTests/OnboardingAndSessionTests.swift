import Foundation
import Testing
import XRAIIdentityTime
import XRAINumerology
@testable import XRAI

// P03-01 §6: start, skip, invalid date, valid date, background/relaunch semantics — on the models,
// without UI. Uses an isolated UserDefaults suite so the real app flag is untouched.

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
        #expect(f.finished && s.onboardingCompleted && s.birthDate == nil && s.trace == nil)
    }

    @Test("continue without a date finishes without setting a date")
    func continueWithoutDate() {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.next(); f.next(); f.next()
        f.year = "1998"; f.month = "6"; f.day = "30"   // typed but NOT confirmed
        f.next()
        #expect(f.finished && s.birthDate == nil, "typing is not consent; only 'compute' sets the date")
    }

    @Test("invalid date: typed problem, no date set, stays on the date step")
    func invalidDate() {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.next(); f.next(); f.next()
        f.year = "1900"; f.month = "2"; f.day = "29"
        f.computePreview()
        #expect(f.problem == .invalid(.invalidDay(year: 1900, month: 2, day: 29, daysInMonth: 28)))
        #expect(f.step == .birthDate && s.birthDate == nil && !f.previewOptedIn)
        f.year = "abc"; f.computePreview()
        #expect(f.problem == .notNumbers)
        f.year = ""; f.month = ""; f.day = ""; f.computePreview()
        #expect(f.problem == .empty)
    }

    @Test("valid date: explicit opt-in sets the in-memory date, shows the preview, trace matches the engine")
    func validDate() throws {
        let s = freshSession(); let f = OnboardingFlow(session: s)
        f.next(); f.next(); f.next()
        f.year = "1998"; f.month = "06"; f.day = "30"
        f.computePreview()
        #expect(f.problem == nil && f.step == .preview && f.previewOptedIn)
        let d = try #require(s.birthDate)
        #expect(d.isoString == "1998-06-30")
        let t = try #require(s.trace)
        let expected = try NumerologyLifePath.calculate(d, method: .lifePathDigitsV1)
        #expect(t == expected && t.root == 9 && t.compound == 36)
        f.next()
        #expect(f.finished && s.onboardingCompleted)
    }
}

@Suite("Session state: memory only, non-personal flag only")
@MainActor
struct SessionStateTests {
    @Test("method and policy changes recompute the trace; forgetting clears it")
    func settings() throws {
        let s = freshSession()
        s.setBirthDate(try CivilDate(year: 1955, month: 1, day: 1))
        #expect(s.trace?.root == 22)
        s.method = .lifePathComponentsV1
        #expect(s.trace?.root == 4)
        s.method = .lifePathDigitsV1; s.masterPolicy = .reduceAll
        #expect(s.trace?.root == 4)
        s.forgetBirthDate()
        #expect(s.birthDate == nil && s.trace == nil)
    }

    @Test("relaunch semantics: the onboarding flag persists, the birth date does not (no personal persistence)")
    func relaunch() throws {
        let suite = "xrai.tests." + UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let first = SessionState(defaults: d)
        first.setBirthDate(try CivilDate(year: 1998, month: 6, day: 30))
        first.completeOnboarding()
        let second = SessionState(defaults: d)          // "relaunch"
        #expect(second.onboardingCompleted && second.birthDate == nil)
        // the defaults suite contains ONLY the boolean flag, never a date
        let keys = d.persistentDomain(forName: suite)?.keys.map { String($0) } ?? []
        #expect(keys == [SessionState.onboardingKey])
        #expect(!keys.contains { $0.lowercased().contains("birth") || $0.contains("1998") })
        second.resetOnboarding()
        #expect(!second.onboardingCompleted && d.persistentDomain(forName: suite)?[SessionState.onboardingKey] == nil)
    }

    @Test("background → foreground inside one process keeps the in-memory date (documented) while the key cache is purged by the app")
    func backgroundKeepsSessionButPurgesKeys() throws {
        let s = freshSession()
        s.setBirthDate(try CivilDate(year: 2000, month: 2, day: 29))
        let sec = SecurityStatus(); sec.bootstrap()
        sec.runSelfTest()
        sec.purgeKeyCache()                               // what XRAIApp does on scenePhase != .active
        #expect(sec.cachedKeyVersions.isEmpty)
        #expect(s.trace?.root == 6, "session memory survives backgrounding within the process")
    }

    @Test("date parsing messages cover every typed problem")
    func messages() {
        for p in [BirthDateInput.Problem.empty, .notNumbers, .invalid(.invalidMonth(month: 13)), .invalid(.invalidDay(year: 2023, month: 4, day: 31, daysInMonth: 30)), .invalid(.yearOutOfSupportedRange(year: 1, supported: 1583...9999))] {
            _ = BirthDateInput.message(for: p)
        }
        #expect(BirthDateInput.parse(year: " 2024 ", month: "2", day: "29").map(\.isoString) == .success("2024-02-29"))
    }
}
