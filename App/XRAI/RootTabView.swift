// Five top-level surfaces (constitution §41/§71): Bugün · Ben · Keşfet · Yolum · XRAI.
// P04-00: Bugün, Ben and Yolum are the living court screens (App/XRAI/Experience); Keşfet and XRAI stay honest empty states.
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayLivingView().tabItem { Label("Bugün", systemImage: "sun.max") }.accessibilityIdentifier("tab.today")
            SelfMapView().tabItem { Label("Ben", systemImage: "person") }.accessibilityIdentifier("tab.self")
            ExploreView().tabItem { Label("Keşfet", systemImage: "book") }.accessibilityIdentifier("tab.explore")
            PathPreviewView().tabItem { Label("Yolum", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.accessibilityIdentifier("tab.path")
            GuideView().tabItem { Label("XRAI", systemImage: "sparkle") }.accessibilityIdentifier("tab.guide")
        }
        .tint(XRColor.accent)
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
