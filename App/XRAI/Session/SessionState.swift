// In-memory session state (P03-01, hardened P03-02 G1/G2). NOTHING personal is written to disk in
// this phase: the birth date and the form draft live only in this object.
//   - Background: the process keeps running, so the date stays in memory (the UI says so).
//   - Termination: the process ends, the date is gone.
//   - "Tarihi unut" / forgetAll(): every copy under our control is cleared NOW (date + draft fields).
// Swift does not zero freed memory; forgetAll() drops references, it does not scrub RAM.
// The single persisted value is the non-personal boolean "onboarding completed" in UserDefaults
// (temporary demo solution until a preferences layer exists); resettable from the Ben tab.
import Foundation
import Observation
import SwiftUI
import XRAIIdentityTime
import XRAINumerology

/// Free-text date draft shared by onboarding and the Ben feature (one copy, one place to clear).
struct DateDraft: Equatable {
    var year = ""
    var month = ""
    var day = ""
    var isEmpty: Bool { year.isEmpty && month.isEmpty && day.isEmpty }
    static let empty = DateDraft()
}

@MainActor
@Observable
final class SessionState {
    static let onboardingKey = "xrai.onboarding.completed.v1"

    /// Optional, user-entered, never persisted.
    private(set) var birthDate: CivilDate?
    /// Unconfirmed form text. Cleared on forgetAll(), on onboarding completion, and on unconfirmed exit.
    var draft = DateDraft.empty
    /// P04-00: today's intention, this week's step and its evidence tier — session-only, cleared by forgetAll().
    var journey = JourneyDraft.empty
    var method: NumerologyMethodID = .lifePathDigitsV1
    var masterPolicy: MasterNumberPolicy = .preserve11_22_33
    private(set) var onboardingCompleted: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.onboardingCompleted = defaults.bool(forKey: SessionState.onboardingKey)
    }

    func setBirthDate(_ d: CivilDate?) { birthDate = d }

    /// The one central privacy operation: forgets the confirmed date AND every draft field.
    /// Method/policy preferences are not personal and are kept.
    func forgetAll() {
        birthDate = nil
        draft = .empty
        journey = .empty
    }

    /// Drops unconfirmed text only (used when a form is abandoned).
    func clearDraft() { draft = .empty }

    /// True when any personal value is held in memory.
    var holdsPersonalData: Bool { birthDate != nil || !draft.isEmpty || !journey.isEmpty }

    func completeOnboarding() {
        onboardingCompleted = true
        defaults.set(true, forKey: SessionState.onboardingKey)   // non-personal flag only
    }

    func resetOnboarding() {
        onboardingCompleted = false
        defaults.removeObject(forKey: SessionState.onboardingKey)
    }

    /// Exact trace for the current date and settings, or nil when no date is set.
    var trace: NumerologyTrace? {
        guard let birthDate else { return nil }
        return try? NumerologyLifePath.calculate(birthDate, method: method, masterPolicy: masterPolicy)
    }
}

/// Validation of free-text date fields into a CivilDate. Pure, testable, no persistence.
enum BirthDateInput {
    enum Problem: Error, Equatable {
        case empty
        case notNumbers
        case invalid(CivilDateError)
    }

    static func parse(_ d: DateDraft) -> Result<CivilDate, Problem> { parse(year: d.year, month: d.month, day: d.day) }

    static func parse(year: String, month: String, day: String) -> Result<CivilDate, Problem> {
        let y = year.trimmingCharacters(in: .whitespaces), m = month.trimmingCharacters(in: .whitespaces), d = day.trimmingCharacters(in: .whitespaces)
        if y.isEmpty && m.isEmpty && d.isEmpty { return .failure(.empty) }
        guard let yi = Int(y), let mi = Int(m), let di = Int(d) else { return .failure(.notNumbers) }
        do { return .success(try CivilDate(year: yi, month: mi, day: di)) }
        catch let e as CivilDateError { return .failure(.invalid(e)) }
        catch { return .failure(.notNumbers) }
    }

    static func message(for p: Problem) -> LocalizedStringKey {
        switch p {
        case .empty: return "Tarih girmek isteğe bağlı. Boş bırakabilirsin."
        case .notNumbers: return "Yıl, ay ve günü sayı olarak gir."
        case .invalid(let e):
            switch e {
            case .invalidMonth: return "Ay 1 ile 12 arasında olmalı."
            case .invalidDay(_, _, _, let dim): return "Bu ayda en fazla \(dim) gün var."
            case .yearOutOfSupportedRange: return "Yıl 1583 ile 9999 arasında olmalı."
            }
        }
    }
}

/// App-switcher privacy (G2): while the scene is not active, personal content is covered so the
/// system snapshot shows the shield, not the date. Pure policy, unit-tested.
enum PrivacyShieldPolicy {
    static func shouldShield(phase: ScenePhase, holdsPersonalData: Bool) -> Bool {
        phase != .active && holdsPersonalData
    }
}
