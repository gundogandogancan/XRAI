// P03-05A — consent user-experience model (GATE 4) on SYNTHETIC state.
// The vault store is NOT wired in this phase: grants, revocations, deletions and suspensions act on an
// in-memory `ConsentLedger` and a synthetic record table, through the real `PurposeRegistry` and the
// real `InteractionGate` (every action needs a proof minted inside the control's action closure).
// Nothing here is persisted; the screen says so.
import Foundation
import Observation
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultInteraction

/// Scene activity for the gate, written by the app on every scene-phase change (main actor) and read
/// by the gate from any thread.
final class AppSceneActivity: SceneActivity, @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func set(_ a: Bool) { lock.lock(); active = a; lock.unlock() }
}

/// What the user can do with a purpose, as DISTINCT actions (GATE 4).
enum ConsentAction: String, CaseIterable, Identifiable {
    case grant, revokeDeleteNow, revokeSuspend, deleteRecords, restoreSuspended
    var id: String { rawValue }
}

/// Synthetic record state per purpose (what the real store would hold).
enum SyntheticRecordState: String, Equatable {
    case none, active, suspended, deleted
}

@MainActor
@Observable
final class ConsentFlow {
    enum Status: Equatable {
        case notGranted
        case granted(eventID: String, version: UInt32, at: Int64)
        case revoked(at: Int64)
    }

    let registry: PurposeRegistry
    private let gate: InteractionGate
    private let clock: any VaultClock
    private(set) var ledger = ConsentLedger()
    private(set) var records: [String: SyntheticRecordState] = [:]
    private(set) var lastRefusal: String?

    init(registry: PurposeRegistry, gate: InteractionGate, clock: any VaultClock) {
        self.registry = registry; self.gate = gate; self.clock = clock
    }

    var purposes: [PurposeDefinition] { registry.purposeIDs.compactMap { registry.latest($0) } }
    var history: [ConsentEvent] { ledger.events }
    func recordState(_ purposeID: String) -> SyntheticRecordState { records[purposeID] ?? .none }

    func status(_ purposeID: String) -> Status {
        let now = (try? clock.now()) ?? 0
        if let g = ledger.activeGrants(atUnixSeconds: now).last(where: { $0.purposeID == purposeID }) { return .granted(eventID: g.id, version: g.purposeVersion, at: g.atUnixSeconds) }
        if let r = ledger.events.last(where: { $0.purposeID == purposeID && $0.kind == .revoked }) { return .revoked(at: r.atUnixSeconds) }
        return .notGranted
    }

    /// Whether a grant for the shown version exists (the version shown is always `registry.latest`).
    func isCovered(_ def: PurposeDefinition) -> Bool {
        let now = (try? clock.now()) ?? 0
        return def.allowedDataClasses.allSatisfy { ledger.activeGrant(for: $0, purpose: def.id, destination: .deviceVault, atUnixSeconds: now, registry: registry) != nil }
    }

    /// Grant: `.confirmDialog` proof → `.grantConsent` token → consumed → immutable event for THIS version.
    func grant(_ def: PurposeDefinition, proof: InteractionProof) {
        do {
            let token = try gate.authorize(scope: .grantConsent(purpose: def.id), proof: proof)
            _ = try gate.validator.consume(tokenID: token.id, atUnixSeconds: try clock.now())
            let now = try clock.now()
            try ledger.append(ConsentEvent(id: RecordID().hex, kind: .granted, purposeID: def.id, purposeVersion: def.version, dataClasses: def.allowedDataClasses, destination: .deviceVault, atUnixSeconds: now, authorizationID: token.id, revokesEventID: nil, previousChain: ledger.lastChain))
            if records[def.id] == nil { records[def.id] = .none }
            lastRefusal = nil
            // a re-grant NEVER reactivates deleted or suspended data (H4): the record state is untouched
        } catch { lastRefusal = Self.describe(error) }
    }

    /// Synthetic "write a record" after a grant (what a feature would do). Refused without a covering grant.
    func createSyntheticRecord(_ def: PurposeDefinition) {
        guard isCovered(def) else { lastRefusal = "İzin yok: kayıt oluşturulamaz."; return }
        guard recordState(def.id) != .deleted else { lastRefusal = "Silinmiş kimlik yeniden oluşturulmaz; yeni bir kayıt gerekir."; return }
        records[def.id] = .active
        lastRefusal = nil
    }

    /// Revoke: stops reads NOW and either deletes now or suspends (grace-eligible classes only). Third-party
    /// classes have no suspension (`stopReadsAndDeleteNow`). A new `revoked` event is appended; nothing is edited.
    func revoke(_ def: ConsentDefinitionRef, suspend: Bool, proof: InteractionProof) {
        guard let d = registry.latest(def.id) else { return }
        if suspend && d.revocation == .stopReadsAndDeleteNow { lastRefusal = "Bu veri sınıfı askıya alınamaz; geri çekince hemen silinir."; return }
        do {
            let token = try gate.authorize(scope: .revokeConsent(purpose: d.id), proof: proof)
            _ = try gate.validator.consume(tokenID: token.id, atUnixSeconds: try clock.now())
            let now = try clock.now()
            for g in ledger.activeGrants(atUnixSeconds: now) where g.purposeID == d.id {
                try ledger.append(ConsentEvent(id: RecordID().hex, kind: .revoked, purposeID: d.id, purposeVersion: g.purposeVersion, dataClasses: g.dataClasses, destination: g.destination, atUnixSeconds: now, authorizationID: token.id, revokesEventID: g.id, previousChain: ledger.lastChain))
            }
            if recordState(d.id) == .active { records[d.id] = suspend ? .suspended : .deleted }
            lastRefusal = nil
        } catch { lastRefusal = Self.describe(error) }
    }

    /// Delete records of a purpose WITHOUT touching the consent (distinct user right).
    func deleteRecords(_ def: PurposeDefinition, proof: InteractionProof) {
        do {
            let token = try gate.authorize(scope: .delete(recordIDs: []), proof: proof)
            _ = try gate.validator.consume(tokenID: token.id, atUnixSeconds: try clock.now())
            if recordState(def.id) != .none { records[def.id] = .deleted }
            lastRefusal = nil
        } catch { lastRefusal = Self.describe(error) }
    }

    /// Bring suspended records back: needs an ACTIVE grant again AND this explicit action (never automatic).
    func restoreSuspended(_ def: PurposeDefinition, proof: InteractionProof) {
        guard recordState(def.id) == .suspended else { lastRefusal = "Askıda kayıt yok."; return }
        guard isCovered(def) else { lastRefusal = "Önce yeniden izin vermen gerekir; izin tek başına geri getirmez."; return }
        do {
            let token = try gate.authorize(scope: .restoreSuspended(recordIDs: []), proof: proof)
            _ = try gate.validator.consume(tokenID: token.id, atUnixSeconds: try clock.now())
            records[def.id] = .active
            lastRefusal = nil
        } catch { lastRefusal = Self.describe(error) }
    }

    /// Proof minting is delegated so views mint ONLY inside action closures.
    func mint(_ kind: InteractionKind, purpose: String = "") throws -> InteractionProof { try gate.mint(kind, purpose: purpose) }

    static func describe(_ e: Error) -> String {
        if let i = e as? InteractionError {
            switch i.failure {
            case .sceneInactive: return "Uygulama etkin değilken izin işlemi yapılmaz."
            case .proofExpired: return "Dokunuş 5 saniyeden eski; yeniden dokun."
            case .proofConsumed: return "Bu dokunuş zaten kullanıldı."
            case .proofUnknown, .notFromAction: return "Eylem bir kontrolden gelmedi."
            case .kindNotAllowed: return "Bu işlem açık bir onay gerektirir."
            case .purposeMismatch: return "Onay başka bir amaç içindi."
            }
        }
        if let v = e as? VaultError { return "Reddedildi: \(String(reflecting: v))" }
        return "Reddedildi."
    }

    /// The eight questions every purpose must answer (GATE 4), in Turkish with English in the catalog.
    func answers(for def: PurposeDefinition) -> [(question: String, answer: String)] {
        let classes = def.allowedDataClasses.map(Self.className).sorted().joined(separator: ", ")
        let dests = def.allowedDestinations.map(Self.destinationName).sorted().joined(separator: ", ")
        let retention: String = {
            switch def.retention {
            case .untilUserDeletes: return "Sen silene kadar."
            case .untilConsentRevoked: return "İznini geri çekene kadar."
            case .derivedInvalidatable: return "Kaynağı değişene kadar."
            case .sessionOnly: return "Yalnız bu oturum; diske yazılmaz."
            }
        }()
        let revoke: String = def.revocation == .stopReadsAndDeleteNow
            ? "Okumalar hemen durur ve kayıtlar hemen silinir (üçüncü kişi verisi: askıya alma yok)."
            : "Okumalar hemen durur; 'hemen sil' veya 'askıda tut' seçersin. Türetilmiş sonuçlar da silinir."
        return [
            ("Hangi verime izin veriyorum?", classes),
            ("Bu veri neden gerekli?", def.explanationTR),
            ("Nerede saklanacak?", dests),
            ("Kim erişebilecek?", "Yalnız sen, bu cihazda. XRAI'nın sunucusu yok."),
            ("Yapay zekâya gönderilecek mi?", def.sendsToAI ? "Evet, yalnız her seferinde ayrı onayla." : "Hayır. Hiçbir modele gönderilmez."),
            ("Ne kadar tutulacak?", retention),
            ("İznimi geri çekince ne olacak?", revoke),
            ("Tamamen nasıl sileceğim?", "'Kayıtları sil' ile bu amacın kayıtları silinir; silinen kimlik bir daha geri gelmez. İzin ayrı bir eylemdir."),
        ]
    }

    static func className(_ c: DataClass) -> String {
        switch c {
        case .birthDate: return "doğum tarihi"
        case .birthPlace: return "doğum yeri"
        case .birthTime: return "doğum saati"
        case .parentsNames: return "ebeveyn isimleri"
        case .siblingOrder: return "kardeş sırası"
        case .spiritualPractices: return "uygulamalar"
        case .psychometrics: return "anket cevapları"
        case .journal: return "günlük"
        case .goalRoadmap: return "hedefler"
        case .evidenceFiles: return "kanıt dosyaları"
        case .consentReceipts: return "izin kayıtları"
        case .derivedResult: return "türetilmiş sonuçlar"
        case .storeMetadata: return "sistem verisi"
        }
    }
    static func destinationName(_ d: Destination) -> String {
        switch d {
        case .deviceVault: return "cihazındaki şifreli kasa"
        case .userEncryptedBackup: return "senin tuttuğun şifreli yedek"
        case .perCallConsentedProvider: return "her seferinde onaylı sağlayıcı"
        case .appleStoreKit: return "Apple StoreKit"
        case .crashLogs, .analytics, .modelTraining, .cloudSync, .advertising: return "asla"
        }
    }
}

/// Small reference so views pass only an id into revoke (keeps the call site readable).
struct ConsentDefinitionRef { let id: String }
