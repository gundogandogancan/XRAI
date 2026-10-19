// In-memory session state (P03-01). NOTHING personal is written to disk in this phase:
// the birth date lives only in this object and is gone when the process ends.
// The single persisted value is the non-personal boolean "onboarding completed", kept in
// UserDefaults so the user is not forced through onboarding on every launch (temporary demo
// solution until a real preferences layer exists). It can be reset from the Ben tab.
import Foundation
import Observation
import SwiftUI
import XRAIIdentityTime
import XRAINumerology

@MainActor
@Observable
final class SessionState {
    static let onboardingKey = "xrai.onboarding.completed.v1"

    /// Optional, user-entered, never persisted.
    private(set) var birthDate: CivilDate?
    var method: NumerologyMethodID = .lifePathDigitsV1
    var masterPolicy: MasterNumberPolicy = .preserve11_22_33
    private(set) var onboardingCompleted: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.onboardingCompleted = defaults.bool(forKey: SessionState.onboardingKey)
    }

    func setBirthDate(_ d: CivilDate?) { birthDate = d }
    func forgetBirthDate() { birthDate = nil }

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
