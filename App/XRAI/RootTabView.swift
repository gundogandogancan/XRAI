// Five top-level surfaces (constitution §41/§71): Bugün · Ben · Keşfet · Yolum · XRAI.
// Bugün and Ben carry the first real flow (session Life Path); the rest are honest, designed empty states.
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Bugün", systemImage: "sun.max") }.accessibilityIdentifier("tab.today")
            SelfView().tabItem { Label("Ben", systemImage: "person") }.accessibilityIdentifier("tab.self")
            ExploreView().tabItem { Label("Keşfet", systemImage: "book") }.accessibilityIdentifier("tab.explore")
            PathView().tabItem { Label("Yolum", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.accessibilityIdentifier("tab.path")
            GuideView().tabItem { Label("XRAI", systemImage: "sparkle") }.accessibilityIdentifier("tab.guide")
        }
        .tint(XRColor.accent)
    }
}

struct TodayView: View {
    @Environment(SessionState.self) private var session

    var body: some View {
        NavigationStack {
            XRPage {
                HStack(spacing: XRSpace.m) {
                    XRLogo(size: 48)
                    VStack(alignment: .leading) {
                        Text("Bugün").font(XRFont.display).foregroundStyle(XRColor.text).accessibilityAddTraits(.isHeader)
                        Text("Tek bir anlamlı adım yeter.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                    }
                }
                if let t = session.trace {
                    LifePathCard(trace: t)
                    XRCard {
                        Text("Bugünün daveti").font(XRFont.heading).foregroundStyle(XRColor.text)
                        Text("Bu sayıyı bir cevap gibi değil, bir soru gibi tut: bugün hangi küçük şeyi gerçekten yapmak istersin? Cevabı yazmana gerek yok; bu sürümde hiçbir şey kaydedilmez.")
                            .font(XRFont.body).foregroundStyle(XRColor.textSecondary)
                        XREpistemicBadge(kind: .userReport)
                    }
                } else {
                    XRCard {
                        Text("Henüz bir başlangıç noktası yok").font(XRFont.heading).foregroundStyle(XRColor.text)
                        Text("İstersen Ben sekmesinden doğum tarihini girip çevrimdışı Yaşam Yolu hesabını görebilirsin. Tarih kaydedilmez.")
                            .font(XRFont.body).foregroundStyle(XRColor.textSecondary)
                    }
                    .accessibilityIdentifier("today.empty")
                }
                XREmptyState(title: "Günlük içerik", message: "Kısa yansıma, isteğe bağlı günlük ve gerçek mini dersler buraya gelecek. Kalıcı kasa olmadan hiçbir günlük tutulmaz.", phase: "P03–P05", systemImage: "sun.horizon")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(XRColor.background, for: .navigationBar)
        }
    }
}

struct ExploreView: View {
    var body: some View {
        NavigationStack {
            XRPage {
                XRSectionTitle(text: "Keşfet")
                Text("Kaynaklı bilgi, gerçek dersler, matematik ve gök haritaları.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                XREmptyState(title: "Bilgelik Atlası", message: "Gelenekler, filozoflar ve bilim; her iddia kaynağı ve bilgi sınıfıyla. Hakları temiz özgün içerik olmadan yayınlanmaz.", phase: "P04/P10", systemImage: "books.vertical")
                XREmptyState(title: "Mini dersler ve deneyler", message: "Gerçek, çevrimdışı çalışan kısa dersler ve küçük projeler.", phase: "P04", systemImage: "flask")
                XREmptyState(title: "Astroloji, Human Design, isim analizi", message: "Bağımsız hesap motorları ve kaynak/hak incelemesi tamamlanmadan sunulmaz.", phase: "P07–P09", systemImage: "moon.stars")
            }
        }
    }
}

struct PathView: View {
    var body: some View {
        NavigationStack {
            XRPage {
                XRSectionTitle(text: "Yolum")
                Text("Seçtiğin yön, kendi hızında.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                XREmptyState(title: "Gelecek Benlik ve hedefler", message: "Uzun vadeli yön → yıllık sonuçlar → 90 günlük kilometre taşları → haftalık adımlar. Gelecek Benlik bir varsayımdır, kehanet değil.", phase: "P05", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                XREmptyState(title: "Kanıt cüzdanı", message: "Yaptıkların, P0'dan P5'e dürüst kanıt basamaklarıyla. 'Video izledim' öğrenmiş saymaz.", phase: "P05", systemImage: "checkmark.seal")
            }
        }
    }
}

struct GuideView: View {
    var body: some View {
        NavigationStack {
            XRPage {
                HStack(spacing: XRSpace.m) { XRLogo(size: 40); XRSectionTitle(text: "XRAI") }
                Text("Kaynaklarını gösteren, cihazında çalışan rehber.").font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
                XREmptyState(title: "Rehber henüz etkin değil", message: "Hiçbir model bağlı değil; bu ekran hiçbir soruya yanıt üretmez. Geldiğinde her cümle 'hesap', 'gelenek', 'senin beyanın' veya 'varsayım' olarak işaretlenecek.", phase: "P06", systemImage: "sparkle")
            }
        }
    }
}
