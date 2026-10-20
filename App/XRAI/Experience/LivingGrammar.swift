// P04-00 — XRAI living grammar v1: the "court" (seksek / hopscotch 0→10).
//
// WHAT THIS IS: an ORIGINAL XRAI presentation grammar for the constitution's claim graph (§73): every
// stone is one question a person can explore, every connector is one defensible relationship between
// two stones (derives / reports / interprets / evidences / invites). The number on a stone is an ORDINAL
// POSITION in the journey, nothing else.
//
// WHAT THIS IS NOT: not the Kabbalistic Sefirot (ten emanations, twenty-two lettered paths, theological
// attributes), not a Human Design bodygraph, not a scoring system. No stone carries a divine attribute,
// no connector carries a Hebrew letter, no number is "higher" than another. The grammar must never be
// marketed as Kabbalah or Human Design (constitution C:303 "do not collapse mutually incompatible
// cosmologies"; recon doc §3: "a presentation grammar, the math behind each square is a separately
// tested engine"). Versioned: a changed meaning or connector is a new grammar version, never a silent edit.
//
// Everything here is synthetic or session-only. No persistence. No model. No network.
import Foundation
import Observation
import XRAIIdentityTime
import XRAINumerology

/// The relationship a connector asserts. Each has an epistemic class it can carry.
enum Relation: String, CaseIterable, Sendable {
    /// Exact arithmetic turns the source stone's input into the target stone's output.
    case derives
    /// The person's own statement flows from one stone to another.
    case reports
    /// A named tradition reads a result (always symbolic, never blended with the math).
    case interprets
    /// Real-world evidence supports a chosen direction (P0 → P1 → P2 ladder).
    case evidences
    /// The system offers (never pushes) one small option.
    case invites

    var verbTR: String {
        switch self {
        case .derives: return "hesaplar"
        case .reports: return "beyan eder"
        case .interprets: return "yorumlar"
        case .evidences: return "kanıtlar"
        case .invites: return "davet eder"
        }
    }
    var epistemic: XREpistemicBadge.Kind {
        switch self {
        case .derives: return .exactMath
        case .reports: return .userReport
        case .interprets: return .symbolic
        case .evidences: return .userReport
        case .invites: return .systemInvitation
        }
    }
}

/// The eight questions every visible stone or card must answer (directive §5, "Octopus-to-Screen").
struct ScreenContract: Sendable, Equatable {
    let input: String
    let method: String
    let knowledgeSource: String
    let epistemic: XREpistemicBadge.Kind
    let privacyPurpose: String
    let output: String
    let userCorrection: String
    let optionalAction: String

    var rows: [(String, String)] {
        [("Girdi", input), ("Yöntem", method), ("Bilgi kaynağı", knowledgeSource),
         ("Bilgi sınıfı", epistemic.rawLabel), ("Gizlilik amacı", privacyPurpose),
         ("Çıktı", output), ("Düzeltme", userCorrection), ("İsteğe bağlı eylem", optionalAction)]
    }
}

/// One stone of the court.
struct Station: Identifiable, Sendable, Equatable {
    let id: Int                 // ordinal position 0…10
    let key: String             // stable machine key (never shown)
    let titleTR: String
    let titleEN: String
    let question: String        // the single question this stone explores
    let meaning: String         // why this stone exists, in plain language
    let phase: String?          // nil = something real runs here in this build
    let contract: ScreenContract
}

/// One connector of the court.
struct Connector: Identifiable, Sendable, Equatable {
    var id: String { "\(from)-\(to)" }
    let from: Int
    let to: Int
    let relation: Relation
    let phase: String?          // nil = this relationship runs in this build (when both ends are active)
    let note: String
}

/// Honest state of a stone in THIS build and THIS session.
enum StationState: Equatable, Sendable {
    /// Real data or a real choice is present (session-only).
    case active(summary: String)
    /// The person can act here now; nothing is present yet.
    case available(prompt: String)
    /// Planned for a later phase; nothing runs here (phase shown).
    case pending(phase: String)
    /// Would need a consent that does not exist in this build.
    case lockedByConsent(purpose: String)
    /// Something went wrong (e.g. a calculation could not run).
    case error(message: String)

    var isActive: Bool { if case .active = self { return true }; return false }
    var labelTR: String {
        switch self {
        case .active: return "etkin"
        case .available: return "hazır"
        case .pending(let p): return "planlı, \(p)"
        case .lockedByConsent: return "izin bekliyor"
        case .error: return "hata"
        }
    }
}

/// Evidence ladder P0–P2 (constitution RWIP-01, C:3741–3749). P3–P5 are not representable in this build.
enum EvidenceTier: Int, CaseIterable, Sendable, Comparable {
    case planned = 0            // P0 PLANNED — no realised progress evidence yet
    case actionRecorded = 1     // P1 ACTION_RECORDED — action / self-report only
    case artifactProduced = 2   // P2 ARTIFACT_PRODUCED — an artefact exists; skill still uncertain
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var code: String { "P\(rawValue)" }
    var titleTR: String {
        switch self {
        case .planned: return "Planlandı"
        case .actionRecorded: return "Eylem kaydedildi (öz bildirim)"
        case .artifactProduced: return "Eser üretildi"
        }
    }
    var explanationTR: String {
        switch self {
        case .planned: return "Henüz gerçekleşmiş bir ilerleme kanıtı yok."
        case .actionRecorded: return "Yalnız senin beyanın var; beceri kanıtı değildir."
        case .artifactProduced: return "Bir eser var; becerinin özgünlüğü hâlâ belirsiz olabilir."
        }
    }
}

/// The grammar, version 1. Changing a meaning, a stone or a connector = version 2.
enum LivingGrammar {
    static let version = "court.v1"

    /// Rows of the court from the BOTTOM (start) to the TOP: single stones are turning points where
    /// only one thing is possible; paired stones are two sides of one question.
    static let rows: [[Int]] = [[0], [1], [2, 3], [4], [5, 6], [7], [8, 9], [10]]

    static let stations: [Station] = [
        Station(id: 0, key: "now", titleTR: "Şimdi", titleEN: "Now",
                question: "Bugün neredeyim?",
                meaning: "Her yolculuk bugünden başlar ve bugüne döner. Bu taşta kişisel veri gerekmez; yalnız takvim günü vardır.",
                phase: nil,
                contract: ScreenContract(input: "Cihaz saati (takvim günü)", method: "Yok (gösterim)", knowledgeSource: "—", epistemic: .systemInvitation, privacyPurpose: "Gerekmez", output: "Günün adı ve tek bir davet", userCorrection: "Daveti görmezden gelebilirsin; dinlenmek bir seçenektir", optionalAction: "Bir niyet seç ya da dinlen")),
        Station(id: 1, key: "origin", titleTR: "Köken", titleEN: "Origin",
                question: "Nereden başladım?",
                meaning: "Doğum tarihinden kesin bir hesap: Yaşam Yolu. Bu bir toplama ve indirgemedir; yorum değildir.",
                phase: nil,
                contract: ScreenContract(input: "Doğum tarihi (yalnız bellekte)", method: "NumerologyLifePath (digits.v1 / components.v1)", knowledgeSource: "Pisagorcu indirgeme aritmetiği; yöntem kayıtlı ve sürümlü", epistemic: .exactMath, privacyPurpose: "life_path_calculation (bu sürümde kayıt yok)", output: "Kök sayı ve tam hesap izi", userCorrection: "Tarihi değiştir ya da unut; yöntem ve kuralı seç", optionalAction: "Tarihi gir / unut")),
        Station(id: 2, key: "name", titleTR: "Ad", titleEN: "Name",
                question: "Bana ne deniyor?",
                meaning: "İsim analizleri (Pisagor, gematria, ebced) ayrı ayrı, kaynağı gösterilerek gelecek. Geleneklerin aritmetiği kesin, anlamları semboliktir.",
                phase: "P07",
                contract: ScreenContract(input: "Ad (henüz alınmıyor)", method: "Henüz yok", knowledgeSource: "Hak denetimi bekliyor", epistemic: .notBuilt, privacyPurpose: "Tanımlanacak", output: "—", userCorrection: "—", optionalAction: "—")),
        Station(id: 3, key: "place", titleTR: "Yer", titleEN: "Place",
                question: "Nereye aitim?",
                meaning: "Doğum yeri ve şehirler; gök haritası ve yer eşlemesi. Konum hesapları kesin, yer yorumları semboliktir.",
                phase: "P08",
                contract: ScreenContract(input: "Doğum yeri (henüz alınmıyor)", method: "Henüz yok", knowledgeSource: "Efemeris lisansı bekliyor", epistemic: .notBuilt, privacyPurpose: "Tanımlanacak", output: "—", userCorrection: "—", optionalAction: "—")),
        Station(id: 4, key: "rhythm", titleTR: "Ritim", titleEN: "Rhythm",
                question: "Günün, haftanın, ayın düzeni ne?",
                meaning: "Günlük, haftalık ve aylık döngüler. Aritmetik kesin, gün teması sembolik, nasıl hissettiğin senin beyanındır. 'Enerji' ölçülen bir şey değildir.",
                phase: "P07",
                contract: ScreenContract(input: "Doğum tarihi + takvim günü", method: "RhythmContract (sözleşme yazıldı, motor yok)", knowledgeSource: "Sürümlü yöntem kaydı bekliyor", epistemic: .notBuilt, privacyPurpose: "Tanımlanacak", output: "—", userCorrection: "—", optionalAction: "—")),
        Station(id: 5, key: "state", titleTR: "Durum", titleEN: "State",
                question: "Bugün nasılım?",
                meaning: "Yalnız senin söylediğin. Sistem hiçbir ruh halini tahmin etmez, ölçmez, çıkarmaz.",
                phase: nil,
                contract: ScreenContract(input: "Senin seçimin (dinlenme ya da küçük bir adım)", method: "Yok (kayıt değil, oturum içi seçim)", knowledgeSource: "—", epistemic: .userReport, privacyPurpose: "Gerekmez (bellekte, kapanınca silinir)", output: "Bugünkü niyetin", userCorrection: "Değiştir ya da sil", optionalAction: "Seçimi değiştir")),
        Station(id: 6, key: "bond", titleTR: "Bağ", titleEN: "Bond",
                question: "Kimlerle bağlıyım?",
                meaning: "Başka bir kişinin verisi üçüncü taraf verisidir: ayrı izin, askıya alma yok, hemen silme. Bu yüzden en son gelir.",
                phase: "P07–P09",
                contract: ScreenContract(input: "Üçüncü taraf verisi (alınmıyor)", method: "Henüz yok", knowledgeSource: "—", epistemic: .notBuilt, privacyPurpose: "Üçüncü taraf kuralları", output: "—", userCorrection: "—", optionalAction: "—")),
        Station(id: 7, key: "pattern", titleTR: "Desen", titleEN: "Pattern",
                question: "Hangi desenlerle anlatılıyorum?",
                meaning: "Human Design ve benzeri sistemler: bağımsız hesap motoru ve yöntem hakları olmadan sunulmaz. Desen bir mercektir; tıbbi ya da kesin bir sonuç değildir.",
                phase: "P09",
                contract: ScreenContract(input: "Tarih + saat + yer (alınmıyor)", method: "Henüz yok", knowledgeSource: "Yöntem hakları bekliyor", epistemic: .notBuilt, privacyPurpose: "Tanımlanacak", output: "—", userCorrection: "—", optionalAction: "—")),
        Station(id: 8, key: "meaning", titleTR: "Anlam", titleEN: "Meaning",
                question: "Gelenekler bu sayıya ne demiş?",
                meaning: "Bilgelik Atlası: her cümle kaynağı ve 'bu geleneğe göre' etiketiyle. Matematikle hiçbir zaman karışmaz.",
                phase: "P04/P10",
                contract: ScreenContract(input: "Köken taşının çıktısı", method: "Henüz yok", knowledgeSource: "Hakları temiz özgün içerik bekliyor", epistemic: .notBuilt, privacyPurpose: "symbolic_family_lens (ileride)", output: "—", userCorrection: "—", optionalAction: "—")),
        Station(id: 9, key: "direction", titleTR: "Yön", titleEN: "Direction",
                question: "Nereye gitmek istiyorum?",
                meaning: "Gelecek Benlik bir senaryodur, tahmin değil. Sen seçersin, sen değiştirirsin.",
                phase: nil,
                contract: ScreenContract(input: "Senin seçtiğin haftalık adım", method: "Yok (oturum içi seçim)", knowledgeSource: "—", epistemic: .userReport, privacyPurpose: "Gerekmez (bellekte)", output: "Bu haftanın bir adımı", userCorrection: "Vazgeç ya da değiştir", optionalAction: "Adım seç")),
        Station(id: 10, key: "evidence", titleTR: "Kanıt", titleEN: "Evidence",
                question: "Gerçekten ne yaptım?",
                meaning: "P0 plan, P1 beyan, P2 eser. 'Video izledim' öğrenmiş saymaz. Sonra yeniden Şimdi'ye dönülür.",
                phase: nil,
                contract: ScreenContract(input: "Senin beyanın (bu sürümde eser yok)", method: "Kanıt basamağı P0–P2", knowledgeSource: "Anayasa RWIP-01", epistemic: .userReport, privacyPurpose: "Gerekmez (bellekte)", output: "Dürüst basamak", userCorrection: "Beyanı geri al", optionalAction: "Yaptım de")),
    ]

    static let connectors: [Connector] = [
        Connector(from: 1, to: 0, relation: .derives, phase: nil, note: "Kökenin hesabı bugün görünür."),
        Connector(from: 0, to: 5, relation: .reports, phase: nil, note: "Bugünün niyeti senin beyanındır."),
        Connector(from: 9, to: 0, relation: .invites, phase: nil, note: "Haftanın adımı bugüne iner (tek davet)."),
        Connector(from: 9, to: 10, relation: .evidences, phase: nil, note: "Yön, kanıtla sınanır."),
        Connector(from: 1, to: 4, relation: .derives, phase: "P07", note: "Döngüler doğum tarihinden hesaplanacak."),
        Connector(from: 4, to: 0, relation: .invites, phase: "P07", note: "Gün teması bugüne davet olarak gelecek."),
        Connector(from: 1, to: 8, relation: .interprets, phase: "P04/P10", note: "Gelenekler kök sayıyı yorumlayacak."),
        Connector(from: 1, to: 7, relation: .derives, phase: "P09", note: "Desen hesabı tarih, saat ve yer ister."),
        Connector(from: 3, to: 7, relation: .derives, phase: "P09", note: "Yer, desen hesabının girdisidir."),
        Connector(from: 2, to: 8, relation: .interprets, phase: "P07/P10", note: "Ad analizleri geleneklerle okunacak."),
        Connector(from: 1, to: 6, relation: .derives, phase: "P07–P09", note: "Bağ analizi iki kökenden hesaplanacak."),
    ]

    static func station(_ id: Int) -> Station { stations[id] }
}

/// Copy that must never appear on an XRAI screen (constitution C:24327, F:303–305, GAP-053).
enum CopyLexicon {
    static let forbidden: [String] = [
        "kader", "teşhis", "tarama", "tarar", "frekans", "aura", "ruh eşi", "ruhunun gerçek amacı",
        "geleceğin kesin", "enerji frekansı", "titreşim", "bilimsel olarak kanıtlanmış", "garanti",
    ]
    /// Returns the forbidden terms found in the text (case-insensitive, Turkish-aware lowercasing).
    static func violations(in text: String) -> [String] {
        let lower = text.lowercased(with: Locale(identifier: "tr"))
        return forbidden.filter { lower.contains($0) }
    }
}

/// The session-only journey draft: today's intention and this week's chosen step (constitution LLE-04:
/// "one short main task + an optional alternative / rest"). Nothing here is written anywhere.
struct JourneyDraft: Equatable, Sendable {
    enum Intention: Equatable, Sendable { case rest, step(Int) }
    var intention: Intention?
    var pathStep: Int?
    var evidence: EvidenceTier = .planned
    var isEmpty: Bool { intention == nil && pathStep == nil && evidence == .planned }
    static let empty = JourneyDraft()
}

/// Static, non-personal option lists (system invitations). No model generates these.
enum JourneyOptions {
    static let todaySteps = ["On dakika yürü", "Birine teşekkür et", "Yarım kalan bir şeyi bitir"]
    static let weeklySteps = ["İki kez 20 dakika yaz", "Bir kişiyle gerçek bir sohbet", "Bir şeyi baştan sona öğren"]
    static let futureSelfScenario = "Doksan gün sonra, haftada iki kez yirmi dakika yazan biri. Bu bir senaryodur; sen seçtin diye gerçek olmaz, yaptığın için olur."
}

/// Derives the honest state of every stone and connector from the session (never from disk).
@MainActor
enum ExperienceDerivation {
    static func states(session: SessionState) -> [Int: StationState] {
        var s: [Int: StationState] = [:]
        s[0] = .active(summary: todayName())
        if let t = session.trace {
            s[1] = .active(summary: "Kök sayı \(t.root)")
        } else if session.birthDate != nil {
            s[1] = .error(message: "Hesap çalışmadı")
        } else {
            s[1] = .available(prompt: "Tarihini gir")
        }
        for st in LivingGrammar.stations where st.phase != nil { s[st.id] = .pending(phase: st.phase!) }
        switch session.journey.intention {
        case .rest: s[5] = .active(summary: "Bugün dinleniyorum")
        case .step(let i): s[5] = .active(summary: JourneyOptions.todaySteps[i])
        case nil: s[5] = .available(prompt: "Bir niyet seç")
        }
        if let p = session.journey.pathStep {
            s[9] = .active(summary: JourneyOptions.weeklySteps[p])
            s[10] = session.journey.evidence >= .actionRecorded ? .active(summary: session.journey.evidence.code) : .available(prompt: "Yaptığında söyle")
        } else {
            s[9] = .available(prompt: "Bir adım seç")
            s[10] = .available(prompt: "Önce bir yön seç")
        }
        return s
    }

    /// A connector is live only when it has no phase AND both ends are active in this session.
    static func isLive(_ c: Connector, states: [Int: StationState]) -> Bool {
        c.phase == nil && (states[c.from]?.isActive ?? false) && (states[c.to]?.isActive ?? false)
    }

    static func todayName(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM, EEEE"
        return f.string(from: date)
    }

    /// One discovery for today: from the person's own trace when present, otherwise a worked example
    /// computed by the real engine on a fixed synthetic date (true by construction, never typed by hand).
    static func discovery(session: SessionState) -> (title: String, body: String, kind: XREpistemicBadge.Kind) {
        if let t = session.trace {
            let steps = t.reductions.count <= 1 ? "tek adımda" : "\(t.reductions.count) adımda"
            let master = t.masterNumber.map { " \($0) ana sayı olarak korundu." } ?? ""
            return ("Kökenin \(steps) \(t.root)'a iner", "Rakamların toplamı \(t.compound)." + (t.reductions.isEmpty ? "" : " Sonra " + t.reductions.map(String.init).joined(separator: " → ") + ".") + master + " Bu bir hesaptır; anlamı henüz eklenmedi.", .exactMath)
        }
        if let d = try? CivilDate(year: 2000, month: 1, day: 1), let t = try? NumerologyLifePath.calculate(d, method: .lifePathDigitsV1, masterPolicy: .preserve11_22_33) {
            return ("Yaşam Yolu bir toplamadır", "Örnek: 2000-01-01 → rakamlar " + t.rawDigits.map(String.init).joined(separator: "+") + " = \(t.compound)" + (t.reductions.isEmpty ? "" : " → " + t.reductions.map(String.init).joined(separator: " → ")) + ". XRAI her adımı gösterir; kendi tarihin yalnız bellekte kalır.", .exactMath)
        }
        return ("Yaşam Yolu bir toplamadır", "Örnek hesap şu an üretilemedi.", .systemInvitation)
    }
}
