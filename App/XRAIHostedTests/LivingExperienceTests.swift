// P04-00 — hosted tests for the living grammar: structural invariants of the court, honest state
// derivation from the session, the forbidden-copy lexicon, the court's own contrast pairs, the
// rhythm contract's refusal to calculate, and the privacy rule (forgetAll clears the journey).
import Foundation
import SwiftUI
import Testing
import XRAIIdentityTime
@testable import XRAI

@MainActor
@Suite("GATE P04-00 — living grammar court.v1: structure")
struct LivingGrammarStructureTests {
    @Test("NT-LX-01: eleven stones 0…10 with unique ids and keys; the rows cover every stone exactly once; pairs are two stones, singles one")
    func stones() {
        let ids = LivingGrammar.stations.map(\.id)
        #expect(ids == Array(0...10))
        #expect(Set(LivingGrammar.stations.map(\.key)).count == 11)
        let rowIDs = LivingGrammar.rows.flatMap { $0 }
        #expect(rowIDs.sorted() == Array(0...10) && rowIDs.count == 11)
        #expect(LivingGrammar.rows.allSatisfy { $0.count == 1 || $0.count == 2 })
        #expect(LivingGrammar.version == "court.v1")
    }

    @Test("NT-LX-02: every connector joins two existing, distinct stones, has a relation and a note; ids are unique; a live-capable connector (no phase) joins only stones that can run in this build")
    func connectors() {
        let cs = LivingGrammar.connectors
        #expect(Set(cs.map(\.id)).count == cs.count)
        for c in cs {
            #expect((0...10).contains(c.from) && (0...10).contains(c.to) && c.from != c.to, "\(c.id)")
            #expect(!c.note.isEmpty)
            if c.phase == nil {
                #expect(LivingGrammar.station(c.from).phase == nil && LivingGrammar.station(c.to).phase == nil, "\(c.id) claims to run but an end is planned")
            }
        }
        // every planned stone has at least one planned connector explaining where it will attach
        for st in LivingGrammar.stations where st.phase != nil {
            #expect(cs.contains { $0.from == st.id || $0.to == st.id }, "stone \(st.id) is an island")
        }
    }

    @Test("NT-LX-03: every stone answers the eight contract questions; planned stones are labelled not built; running stones never claim a knowledge source they do not have")
    func contracts() {
        for st in LivingGrammar.stations {
            #expect(st.contract.rows.count == 8 && st.contract.rows.allSatisfy { !$0.1.isEmpty }, "stone \(st.id)")
            #expect(!st.question.isEmpty && !st.meaning.isEmpty && !st.titleTR.isEmpty && !st.titleEN.isEmpty)
            if st.phase != nil { #expect(st.contract.epistemic == .notBuilt, "stone \(st.id)") }
            else { #expect(st.contract.epistemic != .notBuilt, "stone \(st.id)") }
        }
        // the only exact-math stone in this build is Köken (the BOOT-01 engine)
        #expect(LivingGrammar.stations.filter { $0.contract.epistemic == .exactMath }.map(\.id) == [1])
    }

    @Test("NT-LX-04: no forbidden copy anywhere in the grammar, the options or the scenario (destiny, diagnosis, scan, frequency, aura, soulmate, certainty)")
    func lexicon() {
        var texts: [String] = []
        for st in LivingGrammar.stations { texts += [st.titleTR, st.question, st.meaning] + st.contract.rows.map(\.1) }
        texts += LivingGrammar.connectors.map(\.note)
        texts += JourneyOptions.todaySteps + JourneyOptions.weeklySteps + [JourneyOptions.futureSelfScenario]
        texts += EvidenceTier.allCases.flatMap { [$0.titleTR, $0.explanationTR] }
        for t in texts { #expect(CopyLexicon.violations(in: t).isEmpty, Comment(rawValue: "\(t) → \(CopyLexicon.violations(in: t))")) }
        #expect(CopyLexicon.violations(in: "Senin kaderin bu frekansta") == ["kader", "frekans"])
    }

    @Test("NT-LX-05: the grammar is not Sefirot — no stone mentions a divine attribute, a Hebrew letter or a 'crown'; stone numbers are ordinal only")
    func notKabbalah() {
        let banned = ["keter", "sefira", "sefirot", "taç", "ilahi", "tanrısal", "yüksek bilinç", "kabala"]
        for st in LivingGrammar.stations {
            let all = (st.titleTR + st.question + st.meaning).lowercased(with: Locale(identifier: "tr"))
            for b in banned { #expect(!all.contains(b), Comment(rawValue: "stone \(st.id) mentions \(b)")) }
        }
    }
}

@MainActor
@Suite("GATE P04-00 — honest state derivation from the session")
struct ExperienceDerivationTests {
    private func fresh() -> SessionState {
        let d = UserDefaults(suiteName: "xrai.test.experience.\(UUID().uuidString)")!
        return SessionState(defaults: d)
    }

    @Test("NT-LX-06: with nothing set, stone 0 is active (today), stone 1 is available, planned stones are pending with their phase, choice stones are available; no connector is live")
    func empty() {
        let s = fresh()
        let st = ExperienceDerivation.states(session: s)
        #expect(st[0]?.isActive == true)
        #expect(st[1] == .available(prompt: "Tarihini gir"))
        for id in [2, 3, 4, 6, 7, 8] { #expect(st[id] == .pending(phase: LivingGrammar.station(id).phase!)) }
        #expect(st[5] == .available(prompt: "Bir niyet seç") && st[9] == .available(prompt: "Bir adım seç") && st[10] == .available(prompt: "Önce bir yön seç"))
        #expect(LivingGrammar.connectors.allSatisfy { !ExperienceDerivation.isLive($0, states: st) })
    }

    @Test("NT-LX-07: a birth date makes stone 1 active with the engine's root and exactly the connector 1→0 live; the discovery is the person's exact result")
    func origin() throws {
        let s = fresh()
        s.setBirthDate(try CivilDate(year: 1998, month: 6, day: 30))
        let st = ExperienceDerivation.states(session: s)
        #expect(st[1] == .active(summary: "Kök sayı 9"))
        let live = LivingGrammar.connectors.filter { ExperienceDerivation.isLive($0, states: st) }.map(\.id)
        #expect(live == ["1-0"])
        let d = ExperienceDerivation.discovery(session: s)
        #expect(d.kind == .exactMath && d.title.contains("9"))
    }

    @Test("NT-LX-08: without a date the discovery is a worked example computed by the engine (2000-01-01 → 4), labelled exact math, never a typed claim")
    func workedExample() {
        let d = ExperienceDerivation.discovery(session: fresh())
        #expect(d.kind == .exactMath && d.body.contains("2000-01-01") && d.body.contains("= 4"))
    }

    @Test("NT-LX-09: choices light stones 5, 9, 10 and their connectors; evidence P1 needs a step; P2 is unreachable; forgetAll clears all of it")
    func journey() throws {
        let s = fresh()
        s.journey.intention = .rest
        var st = ExperienceDerivation.states(session: s)
        #expect(st[5] == .active(summary: "Bugün dinleniyorum"))
        #expect(ExperienceDerivation.isLive(LivingGrammar.connectors.first { $0.id == "0-5" }!, states: st))
        s.journey.pathStep = 2
        st = ExperienceDerivation.states(session: s)
        #expect(st[9] == .active(summary: JourneyOptions.weeklySteps[2]) && st[10] == .available(prompt: "Yaptığında söyle"))
        #expect(ExperienceDerivation.isLive(LivingGrammar.connectors.first { $0.id == "9-0" }!, states: st))
        #expect(!ExperienceDerivation.isLive(LivingGrammar.connectors.first { $0.id == "9-10" }!, states: st))
        s.journey.evidence = .actionRecorded
        st = ExperienceDerivation.states(session: s)
        #expect(st[10] == .active(summary: "P1"))
        #expect(ExperienceDerivation.isLive(LivingGrammar.connectors.first { $0.id == "9-10" }!, states: st))
        #expect(EvidenceTier.allCases.map(\.code) == ["P0", "P1", "P2"], "P3–P5 are not representable here")
        #expect(s.holdsPersonalData, "a choice is the person's report: the shield covers it")
        s.forgetAll()
        #expect(s.journey == .empty && !s.holdsPersonalData)
    }

    @Test("NT-LX-10: the rhythm contract's only implementation refuses to calculate: not built (P07), every strand nil, deterministic")
    func rhythm() throws {
        let src = PendingRhythmSource()
        #expect(src.availability == .notBuilt(phase: "P07"))
        let day = try CivilDate(year: 2026, month: 10, day: 20)
        for span in RhythmSpan.allCases {
            let r = src.reading(span: span, birthDate: try CivilDate(year: 1998, month: 6, day: 30), calendarDay: day)
            #expect(r.arithmetic == nil && r.symbolicTheme == nil && r.userReport == nil && r.invitation == nil)
            #expect(r == src.reading(span: span, birthDate: try CivilDate(year: 1998, month: 6, day: 30), calendarDay: day))
        }
    }
}

@MainActor
@Suite("GATE P04-00 — the court's own contrast pairs")
struct CourtContrastTests {
    @Test("NT-LX-11: stone number on its fill ≥ 4.5:1 (active, available, pending) and every ring ≥ 3:1 against its fill and the page, in BOTH appearances; ratios recorded")
    func pairs() {
        var report: [String] = []
        let textPairs: [(String, Color, Color)] = [
            ("active number / accentSoft", XRColor.accent, XRColor.accentSoft),
            ("available number / surface", XRColor.textSecondary, XRColor.surface),
            ("pending number / surfaceSecondary", XRColor.textSecondary, XRColor.surfaceSecondary),
            ("error number / surface", XRColor.danger, XRColor.surface),
        ]
        let ringPairs: [(String, Color, Color)] = [
            ("active ring / accentSoft", XRColor.accent, XRColor.accentSoft),
            ("active ring / background", XRColor.accent, XRColor.background),
            ("available ring / surface", XRColor.inputBorder, XRColor.surface),
            ("available ring / background", XRColor.inputBorder, XRColor.background),
            ("current ring (gold) / background", XRColor.gold, XRColor.background),
            ("live connector / background", XRColor.accent, XRColor.background),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (n, fg, bg) in textPairs {
                let r = ContrastTests.ratio(fg, bg, style); report.append("\(style == .dark ? "dark" : "light") \(n): \(String(format: "%.2f", r))")
                #expect(r >= 4.5, Comment(rawValue: "\(n) \(style == .dark ? "dark" : "light") = \(r)"))
            }
            for (n, fg, bg) in ringPairs {
                let r = ContrastTests.ratio(fg, bg, style); report.append("\(style == .dark ? "dark" : "light") \(n): \(String(format: "%.2f", r))")
                #expect(r >= 3.0, Comment(rawValue: "\(n) \(style == .dark ? "dark" : "light") = \(r)"))
            }
        }
        Attachment.record(report.joined(separator: "\n"), named: "court-contrast.txt")
    }
}
