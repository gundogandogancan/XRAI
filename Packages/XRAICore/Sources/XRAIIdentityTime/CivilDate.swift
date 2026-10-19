// XRAIIdentityTime — identity, time and calendar canonicalization kernel (constitution §75).
//
// This file deliberately imports NOTHING. It uses only the Swift standard library, so the
// module has no way to touch the network, the file system, logs or user defaults.
// Locale-dependent formatters are never used as calculators (constitution §57A).

/// Typed errors for civil date construction. Every case carries the offending input so a
/// caller can explain the problem without re-deriving it.
public enum CivilDateError: Error, Equatable, Sendable {
    /// The year is outside the supported proleptic Gregorian window.
    case yearOutOfSupportedRange(year: Int, supported: ClosedRange<Int>)
    /// Month is not 1...12.
    case invalidMonth(month: Int)
    /// Day is not 1...daysInMonth for that year and month (leap rules applied).
    case invalidDay(year: Int, month: Int, day: Int, daysInMonth: Int)
}

/// An immutable, validated calendar date in the proleptic Gregorian calendar.
///
/// Design decisions (ADR-BOOT01-CivilDate):
/// - Date-only. There is no time, time zone or instant here, so date-only arithmetic is
///   time-zone independent by construction. Birth time and precision are separate types
///   (future `CivilTime`, `TimePrecision`) and are never inferred from a date.
/// - Supported years are 1583...9999: 1583 is the first full year after the Gregorian reform
///   and 9999 keeps the eight-digit `YYYYMMDD` contract exact. Earlier historical dates need an
///   explicit calendar type and are rejected, never silently converted.
/// - Not `Codable` on purpose: persistence of a date of birth belongs to the consented,
///   encrypted vault layer (P02), not to this pure module.
/// - `description` is redacted. The date is only exposed through `isoString` and the
///   component accessors, so accidental interpolation into a log never prints a DOB.
public struct CivilDate: Hashable, Sendable, Comparable {
    /// First fully Gregorian year through the largest four-digit year.
    public static let supportedYears: ClosedRange<Int> = 1583...9999

    public let year: Int
    public let month: Int
    public let day: Int

    /// Validates and constructs a date. Throws a typed `CivilDateError` otherwise.
    public init(year: Int, month: Int, day: Int) throws {
        guard CivilDate.supportedYears.contains(year) else {
            throw CivilDateError.yearOutOfSupportedRange(year: year, supported: CivilDate.supportedYears)
        }
        guard let dim = CivilDate.daysInMonth(year: year, month: month) else {
            throw CivilDateError.invalidMonth(month: month)
        }
        guard (1...dim).contains(day) else {
            throw CivilDateError.invalidDay(year: year, month: month, day: day, daysInMonth: dim)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Gregorian leap rule: divisible by 4, except centuries, except those divisible by 400.
    public static func isLeapYear(_ year: Int) -> Bool {
        if year % 400 == 0 { return true }
        if year % 100 == 0 { return false }
        return year % 4 == 0
    }

    /// Days in a month, or `nil` when `month` is not 1...12.
    public static func daysInMonth(year: Int, month: Int) -> Int? {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return nil
        }
    }

    /// The eight decimal digits of `YYYYMMDD` in literal order (zero-padded).
    /// This is the only numerology input the calendar kernel provides; it preserves digit
    /// order so that permuted dates remain distinguishable in a calculation trace.
    public var decimalDigitsYYYYMMDD: [UInt8] {
        CivilDate.digits(of: year, width: 4)
            + CivilDate.digits(of: month, width: 2)
            + CivilDate.digits(of: day, width: 2)
    }

    /// Decimal digits of a single component, zero-padded to `width`.
    public static func digits(of value: Int, width: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width)
        var v = value
        var i = width - 1
        while i >= 0 {
            out[i] = UInt8(v % 10)
            v /= 10
            i -= 1
        }
        return out
    }

    /// Explicit ISO-8601 calendar date `YYYY-MM-DD`. Use only where the date is meant to be shown.
    public var isoString: String {
        func pad(_ v: Int, _ w: Int) -> String {
            var s = String(v)
            while s.count < w { s = "0" + s }
            return s
        }
        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2)
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

extension CivilDate: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted on purpose: a date of birth must not leak through string interpolation or logs.
    public var description: String { "CivilDate(redacted)" }
    public var debugDescription: String { "CivilDate(redacted)" }
}
