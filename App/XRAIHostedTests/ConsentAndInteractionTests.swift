// P03-05A GATE 3/4/5/6 hosted tests on synthetic state: consent flow model, restore risk presenter,
// F-UX-5 input boundary contrast, and the token-source scan (no direct issuer use in app code).
import Foundation
import SwiftUI
import Testing
import XRAIVaultContracts
import XRAIVaultCryptoKit
import XRAIVaultInteraction
import XRAIVaultTesting
@testable import XRAI

@MainActor
private func flowFixture(active: Bool = true) throws -> (ConsentFlow, AppSceneActivity, ManualClock) {
    let clock = ManualClock(1_760_000_000)
    let scene = AppSceneActivity(); scene.set(active)
    let gate = InteractionGate(issuer: AuthorizationIssuer(clock: clock, epoch: 1), clock: clock, scene: scene)
    return (ConsentFlow(registry: try XRAIPurposes.registryV1(), gate: gate, clock: clock), scene, clock)
}

@Suite("GATE 4 — consent flow (synthetic state): distinct actions, no automatic reactivation, typing is not consent")
@MainActor
struct ConsentFlowTests {
    @Test("NT-UX-01: grant needs a dialog proof minted in the action; status/version recorded; a re-grant after revoke+delete never reactivates; delete keeps the consent; suspend + re-grant + explicit restore")
    func lifecycle() throws {
        let (flow, _, _) = try flowFixture()
        let journal = try #require(flow.registry.latest("journal_reflection"))
        #expect(flow.status(journal.id) == .notGranted && !flow.isCovered(journal))
        flow.createSyntheticRecord(journal)
        #expect(flow.recordState(journal.id) == .none && flow.lastRefusal != nil, "no record without a grant")
        flow.grant(journal, proof: try flow.mint(.confirmDialog, purpose: journal.id))
        #expect(flow.isCovered(journal) && flow.history.count == 1)
        if case .granted(_, let v, _) = flow.status(journal.id) { #expect(v == 1) } else { Issue.record("not granted") }
        flow.createSyntheticRecord(journal)
        #expect(flow.recordState(journal.id) == .active)
        // delete records: consent stays
        flow.deleteRecords(journal, proof: try flow.mint(.confirmDialog))
        #expect(flow.recordState(journal.id) == .deleted && flow.isCovered(journal))
        flow.createSyntheticRecord(journal)
        #expect(flow.recordState(journal.id) == .deleted && flow.lastRefusal != nil, "a deleted identity is never re-created")
        // revoke + suspend path on a fresh purpose
        let psy = try #require(flow.registry.latest("psychometric_exploration"))
        flow.grant(psy, proof: try flow.mint(.confirmDialog, purpose: psy.id)); flow.createSyntheticRecord(psy)
        flow.revoke(ConsentDefinitionRef(id: psy.id), suspend: true, proof: try flow.mint(.confirmDialog, purpose: psy.id))
        #expect(flow.recordState(psy.id) == .suspended && !flow.isCovered(psy) && flow.history.count == 3)
        flow.restoreSuspended(psy, proof: try flow.mint(.confirmDialog))
        #expect(flow.recordState(psy.id) == .suspended, "no grant → no restore")
        flow.grant(psy, proof: try flow.mint(.confirmDialog, purpose: psy.id))
        #expect(flow.recordState(psy.id) == .suspended, "re-granting alone never reactivates")
        flow.restoreSuspended(psy, proof: try flow.mint(.confirmDialog))
        #expect(flow.recordState(psy.id) == .active)
        // third-party class: no suspension
        let fam = try #require(flow.registry.latest("symbolic_family_lens"))
        flow.grant(fam, proof: try flow.mint(.confirmDialog, purpose: fam.id)); flow.createSyntheticRecord(fam)
        flow.revoke(ConsentDefinitionRef(id: fam.id), suspend: true, proof: try flow.mint(.confirmDialog, purpose: fam.id))
        #expect(flow.recordState(fam.id) == .active && flow.isCovered(fam) && flow.lastRefusal != nil, "refused: third-party data cannot be suspended")
        flow.revoke(ConsentDefinitionRef(id: fam.id), suspend: false, proof: try flow.mint(.confirmDialog, purpose: fam.id))
        #expect(flow.recordState(fam.id) == .deleted && !flow.isCovered(fam))
        // the history is append-only and payload-free
        #expect(flow.history.allSatisfy { $0.authorizationID.contains(":") && $0.id.count == 32 })
    }

    @Test("NT-UX-02: a proof of the wrong kind, a reused proof, a proof for another purpose, and an inactive scene all refuse — and the ledger stays unchanged")
    func refusals() throws {
        let (flow, scene, clock) = try flowFixture()
        let journal = try #require(flow.registry.latest("journal_reflection"))
        flow.grant(journal, proof: try flow.mint(.tap, purpose: journal.id))
        #expect(flow.history.isEmpty && flow.lastRefusal?.contains("açık bir onay") == true)
        let p = try flow.mint(.confirmDialog, purpose: "symbolic_family_lens")
        flow.grant(journal, proof: p)
        #expect(flow.history.isEmpty && flow.lastRefusal?.contains("başka bir amaç") == true)
        let good = try flow.mint(.confirmDialog, purpose: journal.id)
        clock.advance(6)
        flow.grant(journal, proof: good)
        #expect(flow.history.isEmpty && flow.lastRefusal?.contains("5 saniye") == true)
        let ok = try flow.mint(.confirmDialog, purpose: journal.id)
        flow.grant(journal, proof: ok); #expect(flow.history.count == 1)
        flow.revoke(ConsentDefinitionRef(id: journal.id), suspend: false, proof: ok)
        #expect(flow.history.count == 1 && flow.lastRefusal?.contains("zaten kullanıldı") == true)
        scene.set(false)
        #expect(throws: InteractionError(.sceneInactive)) { _ = try flow.mint(.confirmDialog, purpose: journal.id) }
        #expect(flow.history.count == 1)
    }

    @Test("NT-UX-03: every purpose answers the eight questions with non-empty, specific text; AI is 'Hayır' for all shipped purposes")
    func eightQuestions() throws {
        let (flow, _, _) = try flowFixture()
        for def in flow.purposes {
            let qa = flow.answers(for: def)
            #expect(qa.count == 8 && qa.allSatisfy { !$0.answer.isEmpty && !$0.question.isEmpty })
            #expect(qa[4].answer.hasPrefix("Hayır"))
            #expect(qa[0].answer.contains(ConsentFlow.className(def.allowedDataClasses.first!)))
        }
    }
}

@Suite("GATE 5 — restore risk presenter: 1:1 with the RestoreRisk contract, exact acknowledgment, no activation of (possibly) deleted identities")
struct RestoreRiskPresenterTests {
    @Test("NT-UX-04: every RestoreRisk case has a distinct explanation; possiblyDeleted and untrustedLocalHistory are never activatable and offer re-import; acknowledgment must be exact")
    func mapping() {
        let all = Set(RestoreRisk.allCases)
        let ex = RestoreRiskPresenter.explanations(all)
        #expect(ex.count == RestoreRisk.allCases.count && Set(ex.map(\.titleTR)).count == ex.count && ex.allSatisfy { !$0.bodyTR.isEmpty })
        #expect(!RestoreRiskPresenter.canActivate([.possiblyDeleted]) && !RestoreRiskPresenter.canActivate([.untrustedLocalHistory]) && !RestoreRiskPresenter.canActivate([.foreignInstance, .possiblyDeleted]))
        #expect(RestoreRiskPresenter.canActivate([.foreignInstance, .legacyFormat, .olderBackupGeneration, .consentInactiveAtRestore, .unmergedBackupHistory, .attachmentsMissing]))
        #expect(RestoreRiskPresenter.offersReimport([.possiblyDeleted]) && !RestoreRiskPresenter.offersReimport([.foreignInstance]))
        #expect(RestoreRiskPresenter.acknowledgmentMatches(selected: [.foreignInstance], required: [.foreignInstance]))
        #expect(!RestoreRiskPresenter.acknowledgmentMatches(selected: [], required: [.foreignInstance]))
        #expect(!RestoreRiskPresenter.acknowledgmentMatches(selected: [.foreignInstance, .legacyFormat], required: [.foreignInstance]), "a superset is not an acknowledgment")
        #expect(RestoreRiskPresenter.syntheticStaged.count == 7 && Set(RestoreRiskPresenter.syntheticStaged.flatMap { $0.risks }) == all)
    }
}

@Suite("GATE 6 — F-UX-5 input boundary contrast (WCAG 2.2 SC 1.4.11)")
struct InputBoundaryContrastTests {
    @Test("the input border reaches ≥ 3:1 against the input fill AND against the card surface in both appearances; ratios recorded")
    func inputBorder() {
        var report: [String] = []
        for (name, bg) in [("surfaceSecondary (input fill)", XRColor.surfaceSecondary), ("surface (card)", XRColor.surface), ("background", XRColor.background)] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let r = ContrastTests.ratio(XRColor.inputBorder, bg, style)
                report.append("inputBorder/\(name) [\(style == .light ? "light" : "dark")] = \(String(format: "%.2f", r))")
                #expect(r >= 3.0, Comment(rawValue: report.last!))
            }
        }
        Attachment.record(report.joined(separator: "\n"), named: "input-boundary-contrast.txt")
    }
}

@Suite("GATE 3 — token source scan: production app code never calls the issuer directly")
struct TokenSourceScanTests {
    // The app source tree exists only on the Mac (macOS and Simulator hosts). On a physical iPhone this scan is reported
    // as SKIPPED — never as passed — and the same rule is enforced statically by validation/check_p03_03_docs.py.
    #if os(iOS) && !targetEnvironment(simulator)
    static let sourceScanTrait: any TestTrait = .disabled("source scan not applicable on a physical device (no source tree); runs on Simulator")
    #else
    static let sourceScanTrait: any TestTrait = .enabled(if: true)
    #endif

    @Test("NT-UX-05: in App/XRAI no file calls `.issue(` and `AuthorizationIssuer(` appears only inline inside the InteractionGate construction in SecurityStatus", Self.sourceScanTrait)
    func scan() throws {
        var u = URL(fileURLWithPath: #filePath); u.deleteLastPathComponent(); u.deleteLastPathComponent()
        let dir = u.appendingPathComponent("XRAI")
        let e = try #require(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil))
        var files = 0
        for case let f as URL in e where f.pathExtension == "swift" {
            files += 1
            let t = try String(contentsOf: f, encoding: .utf8)
            #expect(!t.contains(".issue("), Comment(rawValue: "\(f.lastPathComponent) calls the issuer directly"))
            let occurrences = t.components(separatedBy: "AuthorizationIssuer(").count - 1
            if f.lastPathComponent == "SecurityStatus.swift" {
                #expect(occurrences == 1 && t.contains("InteractionGate(issuer: AuthorizationIssuer("), "the issuer exists only inline inside the gate construction")
            } else {
                #expect(occurrences == 0, Comment(rawValue: "\(f.lastPathComponent) constructs an issuer"))
            }
        }
        #expect(files >= 12)
    }
}
