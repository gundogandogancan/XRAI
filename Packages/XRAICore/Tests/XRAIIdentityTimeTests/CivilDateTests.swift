import Testing
import XRAIIdentityTime

// Expected values come from docs/status/BOOT_01_HAND_DERIVED_FIXTURES.md (written before the code).

@Suite("CivilDate validity — hand-derived fixtures")
struct CivilDateValidityTests {

    @Test("2000-02-29 is valid (divisible by 400)")
    func leap2000() throws {
        let d = try CivilDate(year: 2000, month: 2, day: 29)
        #expect(d.isoString == "2000-02-29")
    }

    @Test("1900-02-29 is invalid (century, not divisible by 400)")
    func notLeap1900() {
        #expect(throws: CivilDateError.invalidDay(year: 1900, month: 2, day: 29, daysInMonth: 28)) {
            try CivilDate(year: 1900, month: 2, day: 29)
        }
    }

    @Test("2024-02-29 valid, 2023-02-29 invalid")
    func ordinaryLeapRule() throws {
        _ = try CivilDate(year: 2024, month: 2, day: 29)
        #expect(throws: CivilDateError.invalidDay(year: 2023, month: 2, day: 29, daysInMonth: 28)) {
            try CivilDate(year: 2023, month: 2, day: 29)
        }
    }

    @Test("April 31 is invalid")
    func april31() {
        #expect(throws: CivilDateError.invalidDay(year: 2023, month: 4, day: 31, daysInMonth: 30)) {
            try CivilDate(year: 2023, month: 4, day: 31)
        }
    }

    @Test("month 13 and month 0 are invalid")
    func invalidMonths() {
        #expect(throws: CivilDateError.invalidMonth(month: 13)) { try CivilDate(year: 2023, month: 13, day: 1) }
        #expect(throws: CivilDateError.invalidMonth(month: 0)) { try CivilDate(year: 2023, month: 0, day: 10) }
    }

    @Test("day 0 and day 32 are invalid")
    func invalidDays() {
        #expect(throws: CivilDateError.invalidDay(year: 2023, month: 1, day: 0, daysInMonth: 31)) {
            try CivilDate(year: 2023, month: 1, day: 0)
        }
        #expect(throws: CivilDateError.invalidDay(year: 2023, month: 1, day: 32, daysInMonth: 31)) {
            try CivilDate(year: 2023, month: 1, day: 32)
        }
    }

    @Test("supported year window is 1583...9999 inclusive")
    func yearWindow() throws {
        _ = try CivilDate(year: 1583, month: 1, day: 1)
        _ = try CivilDate(year: 9999, month: 12, day: 31)
        #expect(throws: CivilDateError.yearOutOfSupportedRange(year: 1582, supported: 1583...9999)) {
            try CivilDate(year: 1582, month: 10, day: 4)
        }
        #expect(throws: CivilDateError.yearOutOfSupportedRange(year: 10000, supported: 1583...9999)) {
            try CivilDate(year: 10000, month: 1, day: 1)
        }
    }

    @Test("leap-year table")
    func leapTable() {
        #expect(CivilDate.isLeapYear(2000))
        #expect(!CivilDate.isLeapYear(1900))
        #expect(CivilDate.isLeapYear(2024))
        #expect(!CivilDate.isLeapYear(2023))
        #expect(!CivilDate.isLeapYear(2100))
        #expect(CivilDate.isLeapYear(2400))
        #expect(CivilDate.daysInMonth(year: 2000, month: 2) == 29)
        #expect(CivilDate.daysInMonth(year: 1900, month: 2) == 28)
        #expect(CivilDate.daysInMonth(year: 2023, month: 13) == nil)
    }
}

@Suite("CivilDate digits, ordering and redaction")
struct CivilDateRepresentationTests {

    @Test("literal YYYYMMDD digits preserve order and zero padding")
    func literalDigits() throws {
        let d = try CivilDate(year: 1998, month: 6, day: 30)
        #expect(d.decimalDigitsYYYYMMDD == [1, 9, 9, 8, 0, 6, 3, 0])
        let e = try CivilDate(year: 2000, month: 2, day: 29)
        #expect(e.decimalDigitsYYYYMMDD == [2, 0, 0, 0, 0, 2, 2, 9])
        let f = try CivilDate(year: 1583, month: 1, day: 1)
        #expect(f.decimalDigitsYYYYMMDD == [1, 5, 8, 3, 0, 1, 0, 1])
    }

    @Test("Comparable orders by year, month, day")
    func ordering() throws {
        let a = try CivilDate(year: 1998, month: 6, day: 30)
        let b = try CivilDate(year: 1998, month: 7, day: 1)
        let c = try CivilDate(year: 1999, month: 1, day: 1)
        #expect(a < b && b < c)
        #expect(!(b < a))
        #expect(a == (try CivilDate(year: 1998, month: 6, day: 30)))
    }

    @Test("description never contains the birth date (privacy negative test)")
    func redactedDescription() throws {
        let d = try CivilDate(year: 1998, month: 6, day: 30)
        let printed = "\(d)"
        #expect(printed == "CivilDate(redacted)")
        #expect(!printed.contains("1998"))
        #expect(!printed.contains("30"))
        #expect(String(reflecting: d) == "CivilDate(redacted)")
        #expect(d.isoString == "1998-06-30")
    }

    @Test("CivilDate is not Codable in this module (persistence belongs to the vault layer)")
    func notCodable() {
        #expect((CivilDate.self as Any) is Encodable.Type == false)
        #expect((CivilDate.self as Any) is Decodable.Type == false)
    }

    @Test("date-only type has exactly three stored properties and no time or zone")
    func noTimeFields() throws {
        let d = try CivilDate(year: 2000, month: 1, day: 1)
        let labels = Mirror(reflecting: d).children.compactMap { $0.label }
        #expect(labels == ["year", "month", "day"])
    }
}
