import Testing
import XRAIIdentityTime
import XRAINumerology

// Expected values: docs/status/BOOT_01_HAND_DERIVED_FIXTURES.md (hand-derived before the code existed).

private func date(_ y: Int, _ m: Int, _ d: Int) throws -> CivilDate { try CivilDate(year: y, month: m, day: d) }

@Suite("Life Path — num.life_path.digits.v1 golden fixtures")
struct LifePathDigitsGoldenTests {

    @Test("F1 1998-06-30 → compound 36 → root 9")
    func f1() throws {
        let t = try NumerologyLifePath.calculate(try date(1998, 6, 30), method: .lifePathDigitsV1)
        #expect(t.rawDigits == [1, 9, 9, 8, 0, 6, 3, 0])
        #expect(t.compound == 36)
        #expect(t.reductions == [9])
        #expect(t.root == 9)
        #expect(t.masterNumber == nil)
        #expect(t.componentTraces == nil)
        #expect(t.methodID == .lifePathDigitsV1)
        #expect(t.masterPolicy == .preserve11_22_33)
        let all = try NumerologyLifePath.calculate(try date(1998, 6, 30), method: .lifePathDigitsV1, masterPolicy: .reduceAll)
        #expect(all.compound == 36 && all.reductions == [9] && all.root == 9 && all.masterNumber == nil)
    }

    @Test("F2 2000-02-29 (valid leap day) → compound 15 → root 6")
    func f2() throws {
        let t = try NumerologyLifePath.calculate(try date(2000, 2, 29), method: .lifePathDigitsV1)
        #expect(t.rawDigits == [2, 0, 0, 0, 0, 2, 2, 9])
        #expect(t.compound == 15)
        #expect(t.reductions == [6])
        #expect(t.root == 6)
        #expect(t.masterNumber == nil)
    }

    @Test("F4 2000-01-08 → compound 11: preserved as master 11 / reduced to 2")
    func f4() throws {
        let p = try NumerologyLifePath.calculate(try date(2000, 1, 8), method: .lifePathDigitsV1, masterPolicy: .preserve11_22_33)
        #expect(p.compound == 11 && p.reductions == [] && p.root == 11 && p.masterNumber == 11)
        let r = try NumerologyLifePath.calculate(try date(2000, 1, 8), method: .lifePathDigitsV1, masterPolicy: .reduceAll)
        #expect(r.compound == 11 && r.reductions == [2] && r.root == 2 && r.masterNumber == nil)
    }

    @Test("F5 1955-01-01 → compound 22: preserved as master 22 / reduced to 4")
    func f5() throws {
        let p = try NumerologyLifePath.calculate(try date(1955, 1, 1), method: .lifePathDigitsV1)
        #expect(p.compound == 22 && p.reductions == [] && p.root == 22 && p.masterNumber == 22)
        let r = try NumerologyLifePath.calculate(try date(1955, 1, 1), method: .lifePathDigitsV1, masterPolicy: .reduceAll)
        #expect(r.compound == 22 && r.reductions == [4] && r.root == 4 && r.masterNumber == nil)
    }

    @Test("F6 1969-05-21 → compound 33: preserved as master 33 / reduced to 6")
    func f6() throws {
        let p = try NumerologyLifePath.calculate(try date(1969, 5, 21), method: .lifePathDigitsV1)
        #expect(p.compound == 33 && p.reductions == [] && p.root == 33 && p.masterNumber == 33)
        let r = try NumerologyLifePath.calculate(try date(1969, 5, 21), method: .lifePathDigitsV1, masterPolicy: .reduceAll)
        #expect(r.compound == 33 && r.reductions == [6] && r.root == 6 && r.masterNumber == nil)
    }

    @Test("F7 1999-07-03 → compound 38 → 11 reached at a reduction step (preserved) / → 2")
    func f7() throws {
        let p = try NumerologyLifePath.calculate(try date(1999, 7, 3), method: .lifePathDigitsV1)
        #expect(p.compound == 38 && p.reductions == [11] && p.root == 11 && p.masterNumber == 11)
        let r = try NumerologyLifePath.calculate(try date(1999, 7, 3), method: .lifePathDigitsV1, masterPolicy: .reduceAll)
        #expect(r.compound == 38 && r.reductions == [11, 2] && r.root == 2 && r.masterNumber == nil)
    }

    @Test("F10 permutation: 1998-03-06 shares compound 36 with F1 but trace and hash differ")
    func f10PermutationNotAllowed() throws {
        let a = try NumerologyLifePath.calculate(try date(1998, 6, 30), method: .lifePathDigitsV1)
        let b = try NumerologyLifePath.calculate(try date(1998, 3, 6), method: .lifePathDigitsV1)
        #expect(b.rawDigits == [1, 9, 9, 8, 0, 3, 0, 6])
        #expect(a.compound == b.compound && a.root == b.root)
        #expect(a.rawDigits != b.rawDigits)
        #expect(a.formulaTraceHash != b.formulaTraceHash)
        #expect(a != b)
    }

    @Test("determinism: same inputs give identical trace and hash")
    func deterministic() throws {
        let a = try NumerologyLifePath.calculate(try date(1998, 6, 30), method: .lifePathDigitsV1)
        let b = try NumerologyLifePath.calculate(try date(1998, 6, 30), method: .lifePathDigitsV1)
        #expect(a == b)
        #expect(a.formulaTraceHash == b.formulaTraceHash)
    }
}

@Suite("Life Path — num.life_path.components.v1 golden fixtures")
struct LifePathComponentsGoldenTests {

    @Test("F8 1955-01-01 → year 20→2, month 1, day 1 → compound 4 → root 4 (differs from digits method 22)")
    func f8() throws {
        let t = try NumerologyLifePath.calculate(try date(1955, 1, 1), method: .lifePathComponentsV1)
        let cts = try #require(t.componentTraces)
        #expect(cts.count == 3)
        // Component reduction starts from the numeric value: 1955 → 20 → 2.
        #expect(cts[0].component == .year && cts[0].digits == [1, 9, 5, 5])
        #expect(cts[0].reduction.compound == 1955 && cts[0].reduction.steps == [20, 2] && cts[0].reduction.root == 2)
        #expect(cts[1].component == .month && cts[1].digits == [0, 1] && cts[1].reduction.compound == 1 && cts[1].reduction.root == 1)
        #expect(cts[2].component == .day && cts[2].digits == [0, 1] && cts[2].reduction.compound == 1 && cts[2].reduction.root == 1)
        #expect(t.compound == 4 && t.reductions == [] && t.root == 4 && t.masterNumber == nil)
        // Same date, different method, different root: methods are never conflated.
        let digits = try NumerologyLifePath.calculate(try date(1955, 1, 1), method: .lifePathDigitsV1)
        #expect(digits.root == 22 && t.root == 4)
        #expect(digits.methodID != t.methodID)
    }

    @Test("F9 2000-02-29 → 2 + 2 + 11(preserved) = 15 → 6; reduce_all: 2 + 2 + 2 = 6")
    func f9() throws {
        let p = try NumerologyLifePath.calculate(try date(2000, 2, 29), method: .lifePathComponentsV1)
        let cts = try #require(p.componentTraces)
        // day 29 → 11, preserved as a master component.
        #expect(cts[2].reduction.compound == 29 && cts[2].reduction.steps == [11] && cts[2].reduction.root == 11 && cts[2].reduction.masterNumber == 11)
        #expect(cts[0].reduction.compound == 2000 && cts[0].reduction.root == 2 && cts[1].reduction.compound == 2 && cts[1].reduction.root == 2)
        #expect(p.compound == 15 && p.reductions == [6] && p.root == 6 && p.masterNumber == nil)
        let r = try NumerologyLifePath.calculate(try date(2000, 2, 29), method: .lifePathComponentsV1, masterPolicy: .reduceAll)
        let rts = try #require(r.componentTraces)
        #expect(rts[2].reduction.steps == [11, 2] && rts[2].reduction.root == 2)
        #expect(r.compound == 6 && r.reductions == [] && r.root == 6)
    }

    @Test("F11 1984-11-22 → 22 + 11 + 22 = 55 → 10 → 1; reduce_all: 4 + 2 + 4 = 10 → 1")
    func f11() throws {
        let p = try NumerologyLifePath.calculate(try date(1984, 11, 22), method: .lifePathComponentsV1)
        let cts = try #require(p.componentTraces)
        // year 1984 → 22 (preserved); month 11 is already a master value; day 22 likewise.
        #expect(cts[0].reduction.compound == 1984 && cts[0].reduction.steps == [22] && cts[0].reduction.root == 22 && cts[0].reduction.masterNumber == 22)
        #expect(cts[1].reduction.compound == 11 && cts[1].reduction.steps == [] && cts[1].reduction.root == 11 && cts[1].reduction.masterNumber == 11)
        #expect(cts[2].reduction.compound == 22 && cts[2].reduction.steps == [] && cts[2].reduction.root == 22 && cts[2].reduction.masterNumber == 22)
        #expect(p.compound == 55 && p.reductions == [10, 1] && p.root == 1 && p.masterNumber == nil)
        let r = try NumerologyLifePath.calculate(try date(1984, 11, 22), method: .lifePathComponentsV1, masterPolicy: .reduceAll)
        let rts = try #require(r.componentTraces)
        #expect(rts[0].reduction.root == 4 && rts[1].reduction.root == 2 && rts[2].reduction.root == 4)
        #expect(r.compound == 10 && r.reductions == [1] && r.root == 1)
    }
}

@Suite("Life Path — typed errors and registry")
struct LifePathErrorTests {

    @Test("valid date but unregistered method → methodUnavailable")
    func unknownMethod() throws {
        let unknown = NumerologyMethodID(rawValue: "num.life_path.chaldean.v9")
        #expect(throws: NumerologyError.methodUnavailable(unknown)) {
            try NumerologyLifePath.calculate(try date(1998, 6, 30), method: unknown)
        }
    }

    @Test("registry v1 exposes exactly the two BOOT-01 methods")
    func registryContents() {
        #expect(NumerologyMethodRegistry.v1.registeredIDs == [.lifePathComponentsV1, .lifePathDigitsV1])
        #expect(NumerologyTrace.epistemicClass == "EXACT_MATH")
    }

    @Test("an empty registry makes every method unavailable")
    func emptyRegistry() throws {
        let empty = NumerologyMethodRegistry(methods: [])
        #expect(throws: NumerologyError.methodUnavailable(.lifePathDigitsV1)) {
            try NumerologyLifePath.calculate(try date(1998, 6, 30), method: .lifePathDigitsV1, registry: empty)
        }
    }
}

@Suite("Life Path — arithmetic properties over the whole supported domain sample")
struct LifePathPropertyTests {

    /// Digital root identity: for n > 0, repeated digit-sum equals 1 + (n - 1) mod 9.
    private func digitalRoot(_ n: Int) -> Int { n == 0 ? 0 : 1 + (n - 1) % 9 }

    @Test("reduce_all root equals the digital root of the compound, and both methods agree")
    func digitalRootInvariant() throws {
        var checked = 0
        var year = 1583
        while year <= 9999 {
            for month in 1...12 {
                let dim = CivilDate.daysInMonth(year: year, month: month)!
                for day in stride(from: 1, through: dim, by: 7) {
                    let d = try CivilDate(year: year, month: month, day: day)
                    let a = try NumerologyLifePath.calculate(d, method: .lifePathDigitsV1, masterPolicy: .reduceAll)
                    let b = try NumerologyLifePath.calculate(d, method: .lifePathComponentsV1, masterPolicy: .reduceAll)
                    #expect(a.root == digitalRoot(a.compound))
                    #expect((1...9).contains(a.root))
                    #expect(a.root == b.root)
                    #expect(a.compound == DigitReduction.sum(d.decimalDigitsYYYYMMDD))
                    checked += 1
                }
            }
            year += 37
        }
        #expect(checked > 1000)
    }

    @Test("preserve policy roots are in 1...9 or {11,22,33} and master is set iff root is master")
    func preservePolicyDomain() throws {
        var year = 1583
        while year <= 9999 {
            for month in [1, 2, 11, 12] {
                let dim = CivilDate.daysInMonth(year: year, month: month)!
                for day in [1, 11, 22, dim] {
                    let d = try CivilDate(year: year, month: month, day: day)
                    for method in [NumerologyMethodID.lifePathDigitsV1, .lifePathComponentsV1] {
                        let t = try NumerologyLifePath.calculate(d, method: method, masterPolicy: .preserve11_22_33)
                        #expect((1...9).contains(t.root) || [11, 22, 33].contains(t.root))
                        #expect((t.masterNumber != nil) == [11, 22, 33].contains(t.root))
                        if let m = t.masterNumber { #expect(m == t.root) }
                    }
                }
            }
            year += 23
        }
    }

    @Test("every reduction step strictly decreases and ends at the root")
    func monotoneReduction() throws {
        for (y, m, d) in [(1998, 6, 30), (1999, 7, 3), (9999, 12, 31), (1583, 1, 1), (1984, 11, 22)] {
            let t = try NumerologyLifePath.calculate(try date(y, m, d), method: .lifePathDigitsV1, masterPolicy: .reduceAll)
            var prev = t.compound
            for step in t.reductions {
                #expect(step < prev)
                prev = step
            }
            #expect(t.reductions.last ?? t.compound == t.root)
        }
    }
}
