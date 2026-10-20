// P04-00 screen A — Bugün, the living home: an opening (the day, no personal data), ONE discovery,
// ONE optional action (or rest), the living court, and the rhythm card that says honestly what is
// not built. The first minute never needs a model, a network or a stored record.
import SwiftUI

struct TodayLivingView: View {
    @Environment(SessionState.self) private var session
    @State private var pushed: Int?

    private var states: [Int: StationState] { ExperienceDerivation.states(session: session) }

    var body: some View {
        NavigationStack {
            XRPage {
                opening
                discovery
                XRCard {
                    Text("Yaşam haritan").font(XRFont.heading).foregroundStyle(XRColor.text)
                    HopscotchMapView(states: states, selected: nil, compact: true) { pushed = $0 }
                    Text("On bir taş, her biri bir soru; soldan sağa 0'dan 10'a. Düz çizgiler bu sürümde gerçekten çalışan bağlantılardır. Dokun: taşı aç.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                }
                action
                rhythm
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(XRColor.background, for: .navigationBar)
            .navigationDestination(item: $pushed) { id in
                XRPage { StationPanel(station: LivingGrammar.station(id), state: states[id] ?? .pending(phase: "?")) }
                    .navigationTitle(LivingGrammar.station(id).titleTR)
            }
        }
    }

    private var opening: some View {
        HStack(spacing: XRSpace.m) {
            XRLogo(size: 48)
            VStack(alignment: .leading) {
                Text("Bugün").font(XRFont.display).foregroundStyle(XRColor.text).accessibilityAddTraits(.isHeader)
                Text(ExperienceDerivation.todayName()).font(XRFont.secondary).foregroundStyle(XRColor.textSecondary).accessibilityIdentifier("today.date")
            }
        }
    }

    @ViewBuilder private var discovery: some View {
        let d = ExperienceDerivation.discovery(session: session)
        XRCard(tint: XRColor.accent.opacity(0.4)) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bugünün keşfi").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                    .accessibilityIdentifier(session.trace == nil ? "today.empty" : "today.discovery")
                Spacer()
                XREpistemicBadge(kind: d.kind)
            }
            if let t = session.trace {
                HStack(alignment: .firstTextBaseline, spacing: XRSpace.m) {
                    Text(String(t.root)).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(XRColor.accent)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: true)
                        .accessibilityLabel("Kök sayı \(t.root)").accessibilityIdentifier("lifepath.root")
                    Text(d.title).font(XRFont.heading).foregroundStyle(XRColor.text).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(d.title).font(XRFont.heading).foregroundStyle(XRColor.text)
            }
            Text(d.body).font(XRFont.body).foregroundStyle(XRColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            if session.trace == nil {
                Button("Köken taşını doldur") { pushed = 1 }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("today.fillOrigin")
            } else {
                Button("Hesabın izini gör") { pushed = 1 }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("today.seeTrace")
            }
        }
    }

    @ViewBuilder private var action: some View {
        XRCard {
            HStack { Text("Bugünün daveti").font(XRFont.heading).foregroundStyle(XRColor.text); Spacer(); XREpistemicBadge(kind: .systemInvitation) }
            switch session.journey.intention {
            case .rest:
                Text("Bugün dinleniyorsun. Bu da bir seçimdir.").font(XRFont.body).foregroundStyle(XRColor.text)
                HStack { XREpistemicBadge(kind: .userReport); Button("Değiştir") { pushed = 5 }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("today.changeIntention") }
            case .step(let i):
                Text(JourneyOptions.todaySteps[i]).font(XRFont.body).foregroundStyle(XRColor.text)
                HStack { XREpistemicBadge(kind: .userReport); Button("Değiştir") { pushed = 5 }.buttonStyle(XRQuietButtonStyle()).accessibilityIdentifier("today.changeIntention") }
            case nil:
                Text("Tek küçük bir şey ya da dinlenme. Seçmek zorunda değilsin; hiçbir şey kaydedilmez.").font(XRFont.body).foregroundStyle(XRColor.textSecondary)
                Button("Bir niyet seç") { pushed = 5 }.buttonStyle(XRSecondaryButtonStyle()).accessibilityIdentifier("today.chooseIntention")
            }
            if let p = session.journey.pathStep {
                Divider()
                Text("Bu haftanın adımı: \(JourneyOptions.weeklySteps[p]) · \(session.journey.evidence.code)").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
                    .accessibilityIdentifier("today.weekStep")
            }
        }
    }

    private var rhythm: some View {
        let src = PendingRhythmSource()
        return XRCard {
            HStack { Text("Ritim").font(XRFont.heading).foregroundStyle(XRColor.text).accessibilityIdentifier("today.rhythm"); Spacer(); XREpistemicBadge(kind: .notBuilt) }
            if case .notBuilt(let phase) = src.availability {
                Text("Günlük, haftalık ve aylık döngüler \(phase) ile gelecek. Dört ayrı şerit olacak: kesin aritmetik, geleneğin teması, senin beyanın, isteğe bağlı davet. Hiçbiri ölçülen bir 'enerji' değildir.")
                    .font(XRFont.caption).foregroundStyle(XRColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
