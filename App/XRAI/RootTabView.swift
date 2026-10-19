// Five top-level surfaces (constitution §41/§71): Bugün · Ben · Keşfet · Yolum · XRAI.
// Skeleton only: every screen states plainly what exists and what does not. No fake analysis.
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Bugün", systemImage: "sun.max") }
            SelfView().tabItem { Label("Ben", systemImage: "person") }
            ExploreView().tabItem { Label("Keşfet", systemImage: "book") }
            PathView().tabItem { Label("Yolum", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            GuideView().tabItem { Label("XRAI", systemImage: "sparkle") }
        }
    }
}

/// Shared empty-state card. Honest copy, no placeholder "insights".
struct NotYetView: View {
    let title: String
    let what: String
    let phase: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(what).font(.body)
                Label("Bu bölüm henüz geliştirilmedi. Planlanan faz: \(phase).", systemImage: "hammer")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel("Bu bölüm henüz geliştirilmedi. Planlanan faz \(phase).")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

struct TodayView: View {
    var body: some View {
        NavigationStack {
            NotYetView(title: "Bugün",
                       what: "Günün tek anlamlı daveti, isteğe bağlı kısa bir yansıma ve bir adım burada görünecek. Şu an hiçbir kişisel veri saklanmıyor ve hiçbir yorum üretilmiyor.",
                       phase: "P03 (ücretsiz ilk deneyim)")
        }
    }
}

struct ExploreView: View {
    var body: some View {
        NavigationStack {
            NotYetView(title: "Keşfet",
                       what: "Kaynaklı Bilgelik Atlası, kısa dersler, matematik ve gök haritaları burada olacak. İçerik, hakları temiz ve kaynağı gösterilen özgün materyal olmadan yayınlanmayacak.",
                       phase: "P04")
        }
    }
}

struct PathView: View {
    var body: some View {
        NavigationStack {
            NotYetView(title: "Yolum",
                       what: "Kendi seçtiğin uzun vadeli yön, yıllık sonuçlar, 90 günlük kilometre taşları ve haftalık adımlar burada olacak. Gelecek Benlik bir varsayımdır, kehanet değil.",
                       phase: "P05")
        }
    }
}

struct GuideView: View {
    var body: some View {
        NavigationStack {
            NotYetView(title: "XRAI",
                       what: "Kaynaklarını gösteren, cihaz içinde çalışan rehber burada olacak. Henüz hiçbir model bağlı değil; bu ekran hiçbir soruya yanıt üretmez.",
                       phase: "P06")
        }
    }
}
