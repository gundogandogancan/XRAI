// P04-00 screen C — Yolum, Future Self preview: ONE voluntary scenario (synthetic, labelled), ONE
// action for this week, and the honest evidence state. Future Self is a scenario, never a prediction
// (constitution §07, F:126). Session-only; nothing is stored.
import SwiftUI

struct PathPreviewView: View {
    @Environment(SessionState.self) private var session

    var body: some View {
        NavigationStack {
            XRPage {
                XRSectionTitle(text: "Yolum")
                Text("Seçtiğin yön, kendi hızında. Gelecek Benlik bir senaryodur; tahmin değildir.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)

                XRCard(tint: XRColor.gold.opacity(0.5)) {
                    HStack { Text("Örnek senaryo").font(XRFont.caption).foregroundStyle(XRColor.textSecondary).accessibilityIdentifier("path.scenario"); Spacer(); XREpistemicBadge(kind: .systemInvitation) }
                    Text("Gelecek Benlik, 90 gün").font(XRFont.heading).foregroundStyle(XRColor.text)
                    Text(JourneyOptions.futureSelfScenario).font(XRFont.body).foregroundStyle(XRColor.text).fixedSize(horizontal: false, vertical: true)
                    Text("Bu sürümde senaryo sabit bir örnektir; kendi vizyonunu yazmak P05 ile, şifreli ve izinli gelir.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                }

                PathStepChooser()
                EvidenceLadderCard()

                XRCard {
                    Text("Nasıl ilerler").font(XRFont.heading).foregroundStyle(XRColor.text)
                    Text("Uzun yön → yıllık sonuç → 90 günlük kilometre taşı → haftalık adım → bugünün niyeti. Seri bozulunca ceza yok; dinlenmek bir seçenektir.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: XRSpace.s) { XREpistemicBadge(kind: .notBuilt); Text("Vizyon, hedef ağacı ve kanıt cüzdanı: P05").font(XRFont.caption).foregroundStyle(XRColor.textSecondary) }
                }
            }
        }
    }
}
