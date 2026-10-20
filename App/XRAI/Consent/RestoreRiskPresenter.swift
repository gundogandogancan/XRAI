// P03-05A GATE 5 — restore risk experience, bound 1:1 to the `RestoreRisk` contract.
// Pure presenter (unit-tested) + synthetic staged records for the screen. No store is wired.
import Foundation
import XRAIVaultContracts

struct RiskExplanation: Identifiable, Equatable {
    let risk: RestoreRisk
    let titleTR: String
    let bodyTR: String
    /// False for risks that can NEVER be acknowledged away under the same identity.
    let activatable: Bool
    var id: UInt16 { risk.rawValue }
}

enum RestoreRiskPresenter {
    static func explain(_ r: RestoreRisk) -> RiskExplanation {
        switch r {
        case .foreignInstance:
            return RiskExplanation(risk: r, titleTR: "Başka bir cihazın yedeği", bodyTR: "Bu yedek başka bir XRAI kasasından geliyor; bu cihazda zaten veri var. Kayıtlar önce karantinada tutulur; sen onaylayınca etkinleşir.", activatable: true)
        case .legacyFormat:
            return RiskExplanation(risk: r, titleTR: "Eski biçimli yedek", bodyTR: "Yedek eski biçimde: hangi cihazdan geldiği ve silme geçmişi bilinmiyor. Kayıtlar onayına kadar karantinada kalır.", activatable: true)
        case .untrustedLocalHistory:
            return RiskExplanation(risk: r, titleTR: "Bu cihazın silme geçmişi doğrulanamıyor", bodyTR: "Bu kasa daha önce hangi kayıtları sildiğini kanıtlayamıyor. Bu kayıtlar aynı kimlikle asla etkinleşmez; istersen yeni bir kimlikle, bilinçli olarak yeniden içe aktarabilirsin.", activatable: false)
        case .possiblyDeleted:
            return RiskExplanation(risk: r, titleTR: "Daha önce silinmiş olabilir", bodyTR: "Bu kaydın kimliği silme özetinde işaretli. Silinmiş bir kimlik geri gelmez. İstersen içeriği yeni bir kimlikle yeniden içe aktarabilirsin.", activatable: false)
        case .olderBackupGeneration:
            return RiskExplanation(risk: r, titleTR: "Daha eski bir yedek", bodyTR: "Bu yedek, bu cihazın daha sonra aldığı bir yedekten eski. Yeni verinin üzerine yazılmaz; yalnız eksik kayıtlar karantinaya alınır.", activatable: true)
        case .consentInactiveAtRestore:
            return RiskExplanation(risk: r, titleTR: "İzin şu anda etkin değil", bodyTR: "Bu kaydın amacı için şu anda izin yok. Önce izin vermen gerekir; izin vermek tek başına kaydı etkinleştirmez.", activatable: true)
        case .unmergedBackupHistory:
            return RiskExplanation(risk: r, titleTR: "Yedeğin silme geçmişi birleştirilemedi", bodyTR: "Yedekteki silme geçmişi bu cihazınkiyle birleştirilemedi. Kayıtlar karantinada; onaylarsan etkinleşir.", activatable: true)
        case .attachmentsMissing:
            return RiskExplanation(risk: r, titleTR: "Ekler bu yedekte yok", bodyTR: "Yedek alınırken ekler vardı ama yedeğe dahil değildi. Bu eksik bir kurtarmadır; kayıtlar eksiz gelir.", activatable: true)
        }
    }

    static func explanations(_ risks: Set<RestoreRisk>) -> [RiskExplanation] { risks.map(explain).sorted { $0.risk.rawValue < $1.risk.rawValue } }

    /// Activation under the same id is possible only when every risk is activatable.
    static func canActivate(_ risks: Set<RestoreRisk>) -> Bool { risks.allSatisfy { explain($0).activatable } }

    /// Re-import under a NEW id is offered exactly for the non-activatable risks.
    static func offersReimport(_ risks: Set<RestoreRisk>) -> Bool { !canActivate(risks) }

    /// The acknowledged set must equal the recorded set — not a subset, not a superset (store contract).
    static func acknowledgmentMatches(selected: Set<RestoreRisk>, required: Set<RestoreRisk>) -> Bool { selected == required }

    /// Synthetic staged records for the screen (one per documented situation).
    struct StagedRecord: Identifiable, Equatable {
        let id: String
        let label: String
        let risks: Set<RestoreRisk>
    }
    static let syntheticStaged: [StagedRecord] = [
        StagedRecord(id: "r-foreign", label: "Günlük girdisi (başka cihaz)", risks: [.foreignInstance]),
        StagedRecord(id: "r-legacy", label: "Doğum tarihi (eski yedek)", risks: [.legacyFormat]),
        StagedRecord(id: "r-older", label: "Hedef yol haritası", risks: [.olderBackupGeneration, .attachmentsMissing]),
        StagedRecord(id: "r-untrusted", label: "Anket cevapları", risks: [.untrustedLocalHistory]),
        StagedRecord(id: "r-possibly", label: "Uygulama kaydı", risks: [.possiblyDeleted]),
        StagedRecord(id: "r-consent", label: "Günlük girdisi (izin yok)", risks: [.consentInactiveAtRestore]),
        StagedRecord(id: "r-unmerged", label: "Kanıt dosyası", risks: [.unmergedBackupHistory]),
    ]
}
