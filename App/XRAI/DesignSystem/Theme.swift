// XRAI design system — tokens (constitution §88, ADR-014): quiet discovery, violet/lavender accent,
// calm warm neutrals, restrained gold, deep contrast. Semantic tokens only; screens never pick raw
// colours. Dark and light are both first-class. All type uses Dynamic Type text styles.
import SwiftUI
import UIKit

enum XRColor {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light })
    }
    private static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    /// Page background. Light: warm beige. Dark: violet-tinted near-black (matches the logo field).
    static let background = dynamic(light: hex(0xFAF8F4), dark: hex(0x0E0C14))
    /// Cards and grouped content.
    static let surface = dynamic(light: hex(0xFFFFFF), dark: hex(0x181526))
    /// Subtle separators / inset fields.
    static let surfaceSecondary = dynamic(light: hex(0xF1EDE6), dark: hex(0x221E33))
    static let border = dynamic(light: hex(0xE3DED5), dark: hex(0x2E2942))
    /// Primary text (AA+ on background and surface).
    static let text = dynamic(light: hex(0x1A1724), dark: hex(0xF3F0FA))
    static let textSecondary = dynamic(light: hex(0x5E586E), dark: hex(0xB5AFC6))
    /// Violet accent: the brand's lens colour.
    static let accent = dynamic(light: hex(0x6A48D7), dark: hex(0xA78BFF))
    static let accentSoft = dynamic(light: hex(0xEDE7FF), dark: hex(0x2A2345))
    /// Restrained gold for the one meaningful highlight per screen.
    static let gold = dynamic(light: hex(0x8F6F1F), dark: hex(0xD9BC72))
    /// Calm green-beige for positive states.
    static let sage = dynamic(light: hex(0x4F7A5A), dark: hex(0x9CC9A6))
    static let warning = dynamic(light: hex(0xA2641B), dark: hex(0xE7B169))
    static let danger = dynamic(light: hex(0xB23B3B), dark: hex(0xF08A8A))
}

/// 4-pt rhythm.
enum XRSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let page: CGFloat = 20
}

enum XRRadius {
    static let card: CGFloat = 16
    static let control: CGFloat = 12
    static let pill: CGFloat = 999
}

/// Typography: system text styles (Dynamic Type) with the house weights. Never hard-coded sizes.
enum XRFont {
    static let display = Font.largeTitle.weight(.semibold)
    static let title = Font.title2.weight(.semibold)
    static let heading = Font.headline
    static let body = Font.body
    static let secondary = Font.subheadline
    static let caption = Font.footnote
    static let mono = Font.system(.body, design: .monospaced)
}

/// Motion that respects Reduce Motion: returns nil animation when the user asked for less motion.
struct XRMotion {
    let reduce: Bool
    var standard: Animation? { reduce ? nil : .easeInOut(duration: 0.28) }
    var gentle: Animation? { reduce ? nil : .easeOut(duration: 0.4) }
}

extension EnvironmentValues {
    var xrMotion: XRMotion { XRMotion(reduce: accessibilityReduceMotion) }
}

/// Minimum touch target per HIG.
enum XRHit { static let min: CGFloat = 44 }
