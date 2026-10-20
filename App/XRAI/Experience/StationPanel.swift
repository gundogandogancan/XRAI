// P04-00 — the panel for one stone: progressive disclosure (short insight → why → method → source →
// technical trace, constitution §60). Stone 1 hosts the real Life Path feature; stones 5, 9 and 10
// host the session-only choices; planned stones say which phase and why.
import SwiftUI

struct StationPanel: View {
    @Environment(SessionState.self) private var session
    let station: Station
    let state: StationState
    @State private var showContract = false

    var body: some View {
        VStack(alignment: .leading, spacing: XRSpace.l) {
            XRCard(tint: state.isActive ? XRColor.accent.opacity(0.4) : nil) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(station.id) · \(station.titleTR)").font(XRFont.heading).foregroundStyle(XRColor.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("station.panel.\(station.id)")
                    Spacer()
                    XREpistemicBadge(kind: station.contract.epistemic)
                }
                Text(station.question).font(XRFont.title).foregroundStyle(XRColor.text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("station.question")
                Text(station.meaning).font(XRFont.body).foregroundStyle(XRColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                stateLine
            }

            switch station.id {
            case 1: LifePathFeatureView()
            case 5: IntentionChooser()
            case 9: PathStepChooser()
            case 10: EvidenceLadderCard()
            default: EmptyView()
            }

            DisclosureGroup(isExpanded: $showContract) {
                VStack(alignment: .leading, spacing: XRSpace.s) {
                    ForEach(station.contract.rows, id: \.0) { row in
                        XRStackedValue(label: LocalizedStringKey(row.0), value: row.1, mono: false)
                    }
                    relations
                }
                .padding(.top, XRSpace.s)
            } label: {
                Text("Nasıl çalışır (girdi, yöntem, kaynak, sınıf, amaç, çıktı, düzeltme, eylem)")
                    .font(XRFont.secondary.weight(.medium)).foregroundStyle(XRColor.accent)
            }
            .tint(XRColor.accent)
            .accessibilityIdentifier("station.contract.toggle")
        }
    }

    @ViewBuilder private var stateLine: some View {
        switch state {
        case .active(let s): XRLabeledValue(label: "Durum", value: "Etkin · \(s)")
        case .available(let p): XRLabeledValue(label: "Durum", value: "Hazır · \(p)")
        case .pending(let ph): HStack(spacing: XRSpace.s) { XREpistemicBadge(kind: .notBuilt); Text("Planlanan faz: \(ph)").font(XRFont.caption).foregroundStyle(XRColor.textSecondary) }
        case .lockedByConsent(let p): XRLabeledValue(label: "Durum", value: "İzin bekliyor · \(p)")
        case .error(let m): Text(m).font(XRFont.caption).foregroundStyle(XRColor.danger)
        }
    }

    private var relations: some View {
        let rel = LivingGrammar.connectors.filter { $0.from == station.id || $0.to == station.id }
        return VStack(alignment: .leading, spacing: XRSpace.xs) {
            Text("Bağlantılar").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            ForEach(rel) { c in
                HStack(spacing: XRSpace.s) {
                    Text("\(LivingGrammar.station(c.from).titleTR) → \(LivingGrammar.station(c.to).titleTR)").font(XRFont.secondary).foregroundStyle(XRColor.text)
                    Text(c.relation.verbTR).font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                    Spacer()
                    Text(c.phase ?? "çalışıyor").font(XRFont.caption).foregroundStyle(c.phase == nil ? XRColor.sage : XRColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Stone 5: today's intention — rest or one small step (LLE-04: "one short task + alternative / rest").
struct IntentionChooser: View {
    @Environment(SessionState.self) private var session
    var body: some View {
        XRCard {
            HStack { Text("Bugün için").font(XRFont.heading).foregroundStyle(XRColor.text); Spacer(); XREpistemicBadge(kind: .systemInvitation) }
            Text("Bir seçenek, bir alternatif, dinlenme. Hiçbiri kaydedilmez; uygulamayı kapatınca silinir.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            ForEach(Array(JourneyOptions.todaySteps.enumerated()), id: \.offset) { i, s in
                Button(s) { session.journey.intention = .step(i) }
                    .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("intention.step.\(i)")
                    .overlay(alignment: .trailing) { if session.journey.intention == .step(i) { Image(systemName: "checkmark").foregroundStyle(XRColor.accent).padding(.trailing, XRSpace.l).accessibilityHidden(true) } }
                    .accessibilityValue(session.journey.intention == .step(i) ? "seçili" : "")
            }
            Button("Bugün dinleniyorum") { session.journey.intention = .rest }
                .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("intention.rest")
                .accessibilityValue(session.journey.intention == .rest ? "seçili" : "")
            if session.journey.intention != nil {
                HStack { XREpistemicBadge(kind: .userReport); Text("Senin seçimin").font(XRFont.caption).foregroundStyle(XRColor.textSecondary) }
                Button("Seçimi sil") { session.journey.intention = nil }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("intention.clear")
            }
        }
    }
}

/// Stone 9: this week's one step toward a chosen direction (session-only).
struct PathStepChooser: View {
    @Environment(SessionState.self) private var session
    var body: some View {
        XRCard {
            HStack { Text("Bu hafta bir adım").font(XRFont.heading).foregroundStyle(XRColor.text); Spacer(); XREpistemicBadge(kind: .systemInvitation) }
            ForEach(Array(JourneyOptions.weeklySteps.enumerated()), id: \.offset) { i, s in
                Button(s) { session.journey.pathStep = i; session.journey.evidence = .planned }
                    .buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("path.step.\(i)")
                    .accessibilityValue(session.journey.pathStep == i ? "seçili" : "")
            }
            if session.journey.pathStep != nil {
                HStack { XREpistemicBadge(kind: .userReport); Text("Senin seçimin · P0 planlandı").font(XRFont.caption).foregroundStyle(XRColor.textSecondary) }
                Button("Vazgeç") { session.journey.pathStep = nil; session.journey.evidence = .planned }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("path.clear")
            }
        }
    }
}

/// Stone 10: the honest evidence ladder for the chosen step. P2 cannot be reached in this build.
struct EvidenceLadderCard: View {
    @Environment(SessionState.self) private var session
    var body: some View {
        XRCard {
            HStack { Text("Kanıt basamağı").font(XRFont.heading).foregroundStyle(XRColor.text); Spacer(); XREpistemicBadge(kind: .userReport) }
            if session.journey.pathStep == nil {
                Text("Önce Yön taşında bir adım seç.").font(XRFont.body).foregroundStyle(XRColor.textSecondary).accessibilityIdentifier("evidence.noStep")
            } else {
                ForEach(EvidenceTier.allCases, id: \.rawValue) { tier in
                    HStack(alignment: .firstTextBaseline, spacing: XRSpace.s) {
                        Image(systemName: session.journey.evidence >= tier ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(session.journey.evidence >= tier ? XRColor.sage : XRColor.textSecondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tier.code) · \(tier.titleTR)").font(XRFont.secondary.weight(.medium)).foregroundStyle(XRColor.text)
                            Text(tier.explanationTR).font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(session.journey.evidence >= tier ? "ulaşıldı" : "ulaşılmadı")
                    .accessibilityIdentifier("evidence.tier.\(tier.rawValue)")
                }
                if session.journey.evidence == .planned {
                    Button("Yaptım (öz bildirim)") { session.journey.evidence = .actionRecorded }
                        .buttonStyle(XRPrimaryButtonStyle()).accessibilityIdentifier("evidence.didIt")
                } else {
                    Button("Beyanı geri al") { session.journey.evidence = .planned }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("evidence.undo")
                }
                Text("P2 için bir eser gerekir; bu sürümde eser eklenemez (P05).").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            }
        }
    }
}
