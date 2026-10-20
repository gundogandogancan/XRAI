// P03-05A GATE 4 — consent screens (synthetic state). Every action mints its proof INSIDE the control's
// action closure; typing never grants; the screen answers the eight questions before any grant.
import SwiftUI
import XRAIVaultContracts
import XRAIVaultInteraction

struct ConsentView: View {
    @Environment(ConsentFlow.self) private var flow

    var body: some View {
        XRPage {
            XRSectionTitle(text: "Gizlilik ve izinler")
            Text("Her amaç için önce sekiz soruyu görür, sonra karar verirsin. Bu sürümde gerçek kayıt yok: izinler yalnız bu oturumda, bellekte tutulur.")
                .font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                .accessibilityIdentifier("consent.intro")
            ForEach(flow.purposes, id: \.id) { def in
                NavigationLink {
                    PurposeDetailView(def: def)
                } label: {
                    PurposeRow(def: def, status: flow.status(def.id), covered: flow.isCovered(def))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("consent.purpose.\(def.id)")
            }
            NavigationLink {
                ConsentHistoryView()
            } label: {
                XRCard {
                    HStack { Text("İzin geçmişi").font(XRFont.heading).foregroundStyle(XRColor.text); Spacer(); Image(systemName: "chevron.right").foregroundStyle(XRColor.textSecondary).accessibilityHidden(true) }
                    Text("\(flow.history.count) olay · yalnız kimlik, amaç ve zaman; içerik yok").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("consent.history")
        }
        .navigationTitle("İzinler")
    }
}

private struct PurposeRow: View {
    let def: PurposeDefinition
    let status: ConsentFlow.Status
    let covered: Bool
    var body: some View {
        XRCard(tint: covered ? XRColor.sage.opacity(0.6) : nil) {
            HStack(alignment: .firstTextBaseline) {
                Text(def.titleTR).font(XRFont.heading).foregroundStyle(XRColor.text)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(XRColor.textSecondary).accessibilityHidden(true)
            }
            Text(statusText).font(XRFont.caption).foregroundStyle(covered ? XRColor.sage : XRColor.textSecondary)
                .accessibilityIdentifier("consent.status.\(def.id)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(def.titleTR). \(statusText)")
    }
    private var statusText: String {
        switch status {
        case .notGranted: return "İzin verilmedi"
        case .granted(_, let v, _): return "İzin verildi (sürüm \(v))"
        case .revoked: return "İzin geri çekildi"
        }
    }
}

struct PurposeDetailView: View {
    @Environment(ConsentFlow.self) private var flow
    let def: PurposeDefinition
    @State private var confirming: ConsentAction?

    var body: some View {
        XRPage {
            XRSectionTitle(text: LocalizedStringKey(def.titleTR))
            HStack(spacing: XRSpace.s) {
                XREpistemicBadge(kind: .userReport)
                Text("Sürüm \(def.version)").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            }
            XRCard {
                ForEach(Array(flow.answers(for: def).enumerated()), id: \.offset) { i, qa in
                    VStack(alignment: .leading, spacing: XRSpace.xs) {
                        Text(qa.question).font(XRFont.heading).foregroundStyle(XRColor.text)
                        Text(qa.answer).font(XRFont.body).foregroundStyle(XRColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("consent.qa.\(i)")
                    if i < 7 { Divider() }
                }
            }
            XRCard {
                Text("Durum").font(XRFont.heading).foregroundStyle(XRColor.text)
                XRLabeledValue(label: "İzin", value: statusText)
                XRLabeledValue(label: "Kayıtlar (örnek)", value: recordText)
                if let r = flow.lastRefusal { Text(r).font(XRFont.caption).foregroundStyle(XRColor.danger).accessibilityIdentifier("consent.refusal") }
            }
            actions
        }
        .navigationTitle(def.titleTR)
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            if let a = confirming {
                Button(dialogButton(a), role: a == .grant ? nil : .destructive) {
                    // The proof is minted HERE, inside the affirmative dialog action — the one tap that counts.
                    perform(a)
                    confirming = nil
                }
                .accessibilityIdentifier("consent.confirm.\(a.rawValue)")
                Button("Vazgeç", role: .cancel) { confirming = nil }
            }
        } message: { Text(dialogMessage) }
    }

    private var statusText: String {
        switch flow.status(def.id) {
        case .notGranted: return "Verilmedi"
        case .granted(_, let v, _): return "Verildi · sürüm \(v)"
        case .revoked: return "Geri çekildi"
        }
    }
    private var recordText: String {
        switch flow.recordState(def.id) {
        case .none: return "Yok"
        case .active: return "Etkin"
        case .suspended: return "Askıda (okunamaz)"
        case .deleted: return "Silindi (kimlik geri gelmez)"
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: XRSpace.s) {
            if !flow.isCovered(def) {
                Button("İzin veriyorum") { confirming = .grant }.buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("consent.action.grant")
            } else {
                Button("Örnek kayıt oluştur") { flow.createSyntheticRecord(def) }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("consent.action.createRecord")
                Button("İzni geri çek ve hemen sil") { confirming = .revokeDeleteNow }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("consent.action.revokeDeleteNow")
                if def.revocation == .stopReadsThenUserChoosesDeleteOrSuspend {
                    Button("İzni geri çek, askıda tut") { confirming = .revokeSuspend }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("consent.action.revokeSuspend")
                }
            }
            if flow.recordState(def.id) == .active || flow.recordState(def.id) == .suspended {
                Button("Kayıtları sil (izin kalır)") { confirming = .deleteRecords }.buttonStyle(XRQuietButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("consent.action.deleteRecords")
            }
            if flow.recordState(def.id) == .suspended {
                Button("Askıdaki kayıtları geri getir") { confirming = .restoreSuspended }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("consent.action.restoreSuspended")
            }
            Text("Yazmak izin değildir; yalnız bu düğmeler ve onay penceresi izin verir.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
        }
    }

    private var dialogTitle: String {
        switch confirming {
        case .grant: return "\(def.titleTR) için izin veriyor musun?"
        case .revokeDeleteNow: return "İzni geri çek ve kayıtları hemen sil?"
        case .revokeSuspend: return "İzni geri çek, kayıtları askıda tut?"
        case .deleteRecords: return "Bu amacın kayıtlarını sil?"
        case .restoreSuspended: return "Askıdaki kayıtları geri getir?"
        case nil: return ""
        }
    }
    private var dialogMessage: String {
        switch confirming {
        case .grant: return "Yalnız \(def.allowedDataClasses.map(ConsentFlow.className).sorted().joined(separator: ", ")) · sürüm \(def.version). Dışarıya gönderilmez."
        case .revokeDeleteNow: return "Okumalar hemen durur. Silinen kimlik bir daha geri gelmez."
        case .revokeSuspend: return "Okumalar hemen durur. Kayıtlar askıda kalır; yeniden izin vermek tek başına geri getirmez."
        case .deleteRecords: return "İzin kalır, kayıtlar silinir. Silinen kimlik geri gelmez."
        case .restoreSuspended: return "Bu açık eylemle ve etkin bir izinle geri gelir."
        case nil: return ""
        }
    }
    private func dialogButton(_ a: ConsentAction) -> String {
        switch a {
        case .grant: return "İzin veriyorum"
        case .revokeDeleteNow: return "Geri çek ve sil"
        case .revokeSuspend: return "Geri çek, askıda tut"
        case .deleteRecords: return "Sil"
        case .restoreSuspended: return "Geri getir"
        }
    }

    private func perform(_ a: ConsentAction) {
        do {
            switch a {
            case .grant: flow.grant(def, proof: try flow.mint(.confirmDialog, purpose: def.id))
            case .revokeDeleteNow: flow.revoke(ConsentDefinitionRef(id: def.id), suspend: false, proof: try flow.mint(.confirmDialog, purpose: def.id))
            case .revokeSuspend: flow.revoke(ConsentDefinitionRef(id: def.id), suspend: true, proof: try flow.mint(.confirmDialog, purpose: def.id))
            case .deleteRecords: flow.deleteRecords(def, proof: try flow.mint(.confirmDialog))
            case .restoreSuspended: flow.restoreSuspended(def, proof: try flow.mint(.confirmDialog))
            }
        } catch { /* mint refused (scene inactive): the flow records nothing */ }
    }
}

struct ConsentHistoryView: View {
    @Environment(ConsentFlow.self) private var flow
    var body: some View {
        XRPage {
            XRSectionTitle(text: "İzin geçmişi")
            Text("Her satır bir olaydır; içerik yoktur. Geri çekme eski kaydı değiştirmez, yeni bir olay ekler.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
            if flow.history.isEmpty {
                XRCard { Text("Henüz olay yok.").font(XRFont.body).foregroundStyle(XRColor.textSecondary) }.accessibilityIdentifier("consent.history.empty")
            }
            ForEach(flow.history, id: \.id) { e in
                XRCard {
                    HStack { Text(e.kind == .granted ? "Verildi" : "Geri çekildi").font(XRFont.heading).foregroundStyle(e.kind == .granted ? XRColor.sage : XRColor.warning); Spacer(); Text("sürüm \(e.purposeVersion)").font(XRFont.caption).foregroundStyle(XRColor.textSecondary) }
                    XRLabeledValue(label: "Amaç", value: flow.registry.latest(e.purposeID)?.titleTR ?? e.purposeID)
                    XRLabeledValue(label: "Veri", value: e.dataClasses.map(ConsentFlow.className).sorted().joined(separator: ", "))
                    XRLabeledValue(label: "Zaman", value: Self.format(e.atUnixSeconds))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Geçmiş")
    }
    static func format(_ t: Int64) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
    }
}
