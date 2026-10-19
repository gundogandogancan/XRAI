// Reusable components built on the tokens. Every component: Dynamic Type, VoiceOver labels,
// 44pt targets, light/dark, no emoji, no decorative noise.
import SwiftUI

struct XRPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XRFont.heading)
            .foregroundStyle(XRColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: XRHit.min + 6)
            .background(XRColor.accent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: XRRadius.control, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct XRSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XRFont.heading)
            .foregroundStyle(XRColor.accent)
            .frame(maxWidth: .infinity, minHeight: XRHit.min + 6)
            .background(XRColor.accentSoft.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: XRRadius.control, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct XRQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XRFont.secondary)
            .foregroundStyle(XRColor.textSecondary)
            .frame(minHeight: XRHit.min)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Content card on the page background.
struct XRCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: XRSpace.m) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(XRSpace.l)
            .background(XRColor.surface)
            .overlay(RoundedRectangle(cornerRadius: XRRadius.card, style: .continuous).strokeBorder(tint ?? XRColor.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: XRRadius.card, style: .continuous))
    }
}

/// Epistemic class label (constitution §73): every result says what kind of knowledge it is.
struct XREpistemicBadge: View {
    /// Five classes that must never blend (constitution §73, P03-02 G3):
    /// exact math · symbolic tradition · the user's own report · a system-offered invitation · not built.
    enum Kind: CaseIterable, Equatable {
        case exactMath, symbolic, userReport, systemInvitation, notBuilt
        var text: LocalizedStringKey {
            switch self {
            case .exactMath: return "Kesin matematik"
            case .symbolic: return "Sembolik gelenek"
            case .userReport: return "Senin beyanın"
            case .systemInvitation: return "Sistem daveti"
            case .notBuilt: return "Henüz yok"
            }
        }
        /// Plain string for tests and VoiceOver composition.
        var rawLabel: String {
            switch self {
            case .exactMath: return "Kesin matematik"
            case .symbolic: return "Sembolik gelenek"
            case .userReport: return "Senin beyanın"
            case .systemInvitation: return "Sistem daveti"
            case .notBuilt: return "Henüz yok"
            }
        }
    }
    let kind: Kind
    private var text: LocalizedStringKey { kind.text }
    private var color: Color {
        switch kind {
        case .exactMath: return XRColor.sage
        case .symbolic: return XRColor.gold
        case .userReport: return XRColor.accent
        case .systemInvitation: return XRColor.textSecondary
        case .notBuilt: return XRColor.textSecondary
        }
    }
    var body: some View {
        Text(text)
            .font(XRFont.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, XRSpace.m).padding(.vertical, XRSpace.xs + 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(Text("Bilgi sınıfı: ") + Text(text))
            .accessibilityIdentifier("badge." + String(describing: kind))
    }
}

struct XRSectionTitle: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(XRFont.title).foregroundStyle(XRColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Honest empty state: what will be here, which phase, and one real action if any.
struct XREmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let phase: String
    var systemImage: String = "circle.dashed"
    var body: some View {
        XRCard {
            HStack(spacing: XRSpace.m) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(XRColor.accent).accessibilityHidden(true)
                Text(title).font(XRFont.heading).foregroundStyle(XRColor.text)
            }
            Text(message).font(XRFont.body).foregroundStyle(XRColor.textSecondary)
            HStack(spacing: XRSpace.s) {
                XREpistemicBadge(kind: .notBuilt)
                Text("Planlanan faz: \(phase)").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            }
        }
    }
}

/// Logo mark with the brand's rounded-square clip.
struct XRLogo: View {
    var size: CGFloat = 88
    var body: some View {
        Image("XRAILogo")
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityLabel("XRAI logosu")
    }
}

/// Page scaffold: background, padding, scroll.
struct XRPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        scroll
            .background(XRColor.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            // F-UX-2: breathing room under the last card so the floating tab bar never covers it; a
            // relative content margin, not a device-specific number.
            .contentMargins(.bottom, XRSpace.xxl, for: .scrollContent)
    }

    /// iOS 26 glass bars let content show through them, which lowers the measured contrast of text
    /// passing underneath (caught by the accessibility audit on Bugün). A hard bottom edge keeps the
    /// bar region opaque so text is either fully visible or fully hidden, never mixed.
    @ViewBuilder private var scroll: some View {
        if #available(iOS 26.0, *) {
            baseScroll.scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            baseScroll
        }
    }

    private var baseScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XRSpace.l) { content }
                .padding(.horizontal, XRSpace.page)
                .padding(.vertical, XRSpace.l)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
    }
}


/// Label above a value, for values that must stay on their own readable line (F-UX-3).
struct XRStackedValue: View {
    let label: LocalizedStringKey
    let value: String
    var mono = true
    var body: some View {
        VStack(alignment: .leading, spacing: XRSpace.xs) {
            Text(label).font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            Text(value).font(mono ? XRFont.mono : XRFont.body).foregroundStyle(XRColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Covers personal content while the scene is inactive so the app-switcher snapshot shows the brand, not the date (G2).
struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            XRColor.background.ignoresSafeArea()
            VStack(spacing: XRSpace.m) {
                XRLogo(size: 96)
                Text("XRAI").font(XRFont.title).foregroundStyle(XRColor.text)
                Text("Gizlilik perdesi: içerik uygulama etkinken görünür.").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
            }
        }
        .accessibilityIdentifier("privacy.shield")
        .accessibilityLabel("Gizlilik perdesi")
    }
}

struct XRLabeledValue: View {
    let label: LocalizedStringKey
    let value: String
    var mono = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(XRFont.secondary).foregroundStyle(XRColor.textSecondary)
            Spacer(minLength: XRSpace.m)
            Text(value).font(mono ? XRFont.mono : XRFont.body).foregroundStyle(XRColor.text).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
