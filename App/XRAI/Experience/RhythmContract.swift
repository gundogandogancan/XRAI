// P04-00 §4 — the CONTRACT for the future rhythm engine (P07). Nothing is calculated here: the only
// implementation is `PendingRhythmSource`, which reports "not built". The four strands below must
// never be blended on a screen:
//   1. exact arithmetic        (e.g. a reduced calendar number — a method id, a version, a trace)
//   2. symbolic interpretation (a named tradition's reading of that number — "bu geleneğe göre")
//   3. the person's own report (how the day felt — chosen by the person, never inferred)
//   4. an optional invitation  (one small option or rest — never a prescription)
// "Enerji" on an XRAI screen is never a measured personal frequency; it is a word a person may use
// for their own report. The engine must not infer mood, sleep or health from any cycle (LF-04).
import Foundation
import XRAIIdentityTime

enum RhythmSpan: String, CaseIterable, Sendable { case day, week, month }

/// What a rhythm engine may return for one span. Each strand is optional and separately labelled.
struct RhythmReading: Sendable, Equatable {
    let span: RhythmSpan
    /// Strand 1: the exact number with its method and version (nil until a registered method exists).
    let arithmetic: (number: Int, methodID: String, traceSummary: String)?
    /// Strand 2: a symbolic theme with its tradition and source id (nil until rights-clean content exists).
    let symbolicTheme: (tradition: String, sourceID: String, text: String)?
    /// Strand 3: the person's own report for this span (nil unless the person chose to say).
    let userReport: String?
    /// Strand 4: one optional invitation (nil is a valid answer: silence and rest).
    let invitation: String?

    static func == (a: Self, b: Self) -> Bool {
        a.span == b.span && a.arithmetic?.number == b.arithmetic?.number && a.arithmetic?.methodID == b.arithmetic?.methodID
            && a.symbolicTheme?.sourceID == b.symbolicTheme?.sourceID && a.userReport == b.userReport && a.invitation == b.invitation
    }
}

enum RhythmAvailability: Sendable, Equatable {
    case notBuilt(phase: String)
    case available
}

/// The port the P07 engine will implement. Deterministic: the same inputs give the same reading.
protocol RhythmSource: Sendable {
    var availability: RhythmAvailability { get }
    /// `birthDate` may be nil: a reading without strand 1 is still a valid reading (strands 3–4).
    func reading(span: RhythmSpan, birthDate: CivilDate?, calendarDay: CivilDate) -> RhythmReading
}

/// The only implementation in this build: it never calculates.
struct PendingRhythmSource: RhythmSource {
    let availability: RhythmAvailability = .notBuilt(phase: "P07")
    func reading(span: RhythmSpan, birthDate: CivilDate?, calendarDay: CivilDate) -> RhythmReading {
        RhythmReading(span: span, arithmetic: nil, symbolicTheme: nil, userReport: nil, invitation: nil)
    }
}
