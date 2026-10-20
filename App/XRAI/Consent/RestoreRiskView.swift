// P03-05A GATE 5 — restore risk screen (synthetic staged records). The acknowledged set must equal the
// recorded set; possibly-deleted / untrusted identities can only be re-imported under a new id; there is
// no "reset deletion history" button because that operation does not exist.
import SwiftUI
import XRAIVaultContracts

struct RestoreRiskView: View {
    @State private var selected: [String: Set<RestoreRisk>] = [:]
    @State private var outcome: [String: String] = [:]

    var body: some View {
        XRPage {
            XRSectionTitle(text: "Yedekten geri yükleme")
            Text("Örnek durum: bu sürümde gerçek yedek yok. Her kayıt önce karantinaya alınır; yalnız gösterilen riskleri tam olarak onaylarsan etkinleşir.")
                .font(XRFont.secondary).foregroundStyle(XRColor.textSecondary).accessibilityIdentifier("restore.intro")
            ForEach(RestoreRiskPresenter.syntheticStaged) { rec in
                XRCard(tint: RestoreRiskPresenter.canActivate(rec.risks) ? nil : XRColor.warning.opacity(0.6)) {
                    Text(rec.label).font(XRFont.heading).foregroundStyle(XRColor.text)
                    ForEach(RestoreRiskPresenter.explanations(rec.risks)) { ex in
                        VStack(alignment: .leading, spacing: XRSpace.xs) {
                            Toggle(isOn: Binding(get: { selected[rec.id, default: []].contains(ex.risk) }, set: { on in var s = selected[rec.id, default: []]; if on { s.insert(ex.risk) } else { s.remove(ex.risk) }; selected[rec.id] = s })) {
                                Text(ex.titleTR).font(XRFont.body.weight(.semibold)).foregroundStyle(XRColor.text)
                            }
                            .tint(XRColor.accent)
                            .accessibilityIdentifier("restore.ack.\(rec.id).\(ex.risk.rawValue)")
                            Text(ex.bodyTR).font(XRFont.caption).foregroundStyle(XRColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if RestoreRiskPresenter.canActivate(rec.risks) {
                        Button("Etkinleştir") { activate(rec) }
                            .buttonStyle(XRPrimaryButtonStyle())
                            .disabled(!RestoreRiskPresenter.acknowledgmentMatches(selected: selected[rec.id, default: []], required: rec.risks))
                            .accessibilityIdentifier("restore.activate.\(rec.id)")
                        Text("Düğme yalnız tüm riskler işaretliyken etkindir.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                    } else {
                        Text("Bu kayıt aynı kimlikle etkinleşemez.").font(XRFont.caption).foregroundStyle(XRColor.warning).accessibilityIdentifier("restore.noactivate.\(rec.id)")
                        Button("Yeni kimlikle yeniden içe aktar") { outcome[rec.id] = "Örnek: içerik yeni bir kimlikle içe aktarıldı; eski kimlik silinmiş kaldı." }
                            .buttonStyle(XRSecondaryButtonStyle())
                            .accessibilityIdentifier("restore.reimport.\(rec.id)")
                    }
                    if let o = outcome[rec.id] { Text(o).font(XRFont.caption).foregroundStyle(XRColor.sage).accessibilityIdentifier("restore.outcome.\(rec.id)") }
                }
            }
            XRCard {
                Text("Silme geçmişi sıfırlama").font(XRFont.heading).foregroundStyle(XRColor.text)
                Text("Bu işlem henüz yok. Olmayan bir seçenek gösterilmez; doğrulanamayan geçmişle çalışan bir kasa yeni kayıt oluşturmaz.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                XREpistemicBadge(kind: .notBuilt)
            }
            .accessibilityIdentifier("restore.noreset")
        }
        .navigationTitle("Geri yükleme")
    }

    private func activate(_ rec: RestoreRiskPresenter.StagedRecord) {
        let sel = selected[rec.id, default: []]
        guard RestoreRiskPresenter.canActivate(rec.risks), RestoreRiskPresenter.acknowledgmentMatches(selected: sel, required: rec.risks) else { outcome[rec.id] = "Reddedildi: onaylanan riskler gösterilenlerle birebir eşleşmeli."; return }
        outcome[rec.id] = "Örnek: kayıt etkinleştirildi (riskler tam olarak onaylandı)."
    }
}
