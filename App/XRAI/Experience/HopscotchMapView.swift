// P04-00 — the court: eleven stones (0→10) drawn as a hopscotch. Every stone is a button; every
// connector is a labelled relationship. Two layouts of the SAME grammar: the full court (Ben) climbs
// from the bottom; the compact court (Bugün) is the same court seen from the side, left to right.
// Connectors: LIVE ones are always drawn and flow slowly; PLANNED ones appear only for the selected
// stone, dashed and still — so the court never looks busier than what actually runs (constitution
// C:351: no animation implies certainty). Long connectors bow outward so they never cross a stone
// they do not belong to. With Reduce Motion the court is still and the current ring is static.
import SwiftUI

struct HopscotchMapView: View {
    let states: [Int: StationState]
    var selected: Int?
    var compact = false
    var onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var gap: CGFloat { compact ? XRSpace.s : XRSpace.m }
    private var captionHeight: CGFloat { compact ? 0 : UIFont.preferredFont(forTextStyle: .footnote).lineHeight + 4 }
    private var stoneEstimate: CGFloat { compact ? 40 : (typeSize.isAccessibilitySize ? 76 : 60) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let stone = stoneSize(width: w)
            let centers = centers(width: w, stone: stone)
            ZStack {
                connectorsLayer(centers: centers, width: w, height: geo.size.height)
                stones(centers: centers, stone: stone)
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Yaşam haritası, on bir taş")
        .accessibilityIdentifier(compact ? "map.compact" : "map.full")
    }

    private func stones(centers: [Int: CGPoint], stone: CGFloat) -> some View {
        ForEach(LivingGrammar.stations) { st in
            StoneView(station: st, state: states[st.id] ?? .pending(phase: "?"), isSelected: selected == st.id,
                      isCurrent: st.id == 0, size: stone, compact: compact, reduceMotion: reduceMotion) { onSelect(st.id) }
                .position(centers[st.id] ?? .zero)
        }
    }

    // MARK: geometry

    private var totalHeight: CGFloat {
        compact ? 2 * stoneEstimate + gap : CGFloat(LivingGrammar.rows.count) * (stoneEstimate + captionHeight + gap)
    }
    private func stoneSize(width: CGFloat) -> CGFloat {
        compact ? min(stoneEstimate, width / CGFloat(LivingGrammar.rows.count) - gap) : min(stoneEstimate, (width - 3 * gap) / 2)
    }

    /// Full: rows climb from the bottom (row 0 at the bottom). Compact: rows become columns, left to right.
    private func centers(width w: CGFloat, stone: CGFloat) -> [Int: CGPoint] {
        var out: [Int: CGPoint] = [:]
        let rows = LivingGrammar.rows
        if compact {
            let colW = w / CGFloat(rows.count)
            let h = 2 * stone + gap
            for (r, row) in rows.enumerated() {
                let x = colW * (CGFloat(r) + 0.5)
                if row.count == 1 { out[row[0]] = CGPoint(x: x, y: h / 2) }
                else { out[row[0]] = CGPoint(x: x, y: stone / 2); out[row[1]] = CGPoint(x: x, y: h - stone / 2) }
            }
        } else {
            let rowH = stone + captionHeight + gap
            for (r, row) in rows.enumerated() {
                let y = rowH * (CGFloat(rows.count - 1 - r) + 0.5) - captionHeight / 2
                if row.count == 1 { out[row[0]] = CGPoint(x: w / 2, y: y) }
                else { out[row[0]] = CGPoint(x: w * 0.27, y: y); out[row[1]] = CGPoint(x: w * 0.73, y: y) }
            }
        }
        return out
    }

    private static func rowIndex(_ id: Int) -> Int { LivingGrammar.rows.firstIndex { $0.contains(id) } ?? 0 }

    /// A connector spanning more than one row bows outward (away from the court's axis) so it never
    /// passes through a stone in between; neighbours are joined by a straight line.
    private func path(from a: CGPoint, to b: CGPoint, span: Int, width: CGFloat, height: CGFloat) -> Path {
        var p = Path(); p.move(to: a)
        guard span > 1 else { p.addLine(to: b); return p }
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let bow = CGFloat(span) * (compact ? 14 : 26)
        let control: CGPoint
        if compact {
            let axis = height / 2
            let dir: CGFloat = (mid.y < axis || (mid.y == axis && a.x < b.x)) ? -1 : 1
            control = CGPoint(x: mid.x, y: mid.y + dir * bow)
        } else {
            let axis = width / 2
            let dir: CGFloat = (mid.x < axis || (mid.x == axis && a.y > b.y)) ? -1 : 1
            control = CGPoint(x: mid.x + dir * bow, y: mid.y)
        }
        p.addQuadCurve(to: b, control: control)
        return p
    }

    private var visibleConnectors: [Connector] {
        LivingGrammar.connectors.filter { c in
            ExperienceDerivation.isLive(c, states: states) || (selected != nil && (c.from == selected || c.to == selected))
        }
    }

    @ViewBuilder private func connectorsLayer(centers: [Int: CGPoint], width: CGFloat, height: CGFloat) -> some View {
        let visible = visibleConnectors
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, _ in
                for c in visible {
                    guard let a = centers[c.from], let b = centers[c.to] else { continue }
                    let span = abs(Self.rowIndex(c.from) - Self.rowIndex(c.to))
                    let p = path(from: a, to: b, span: span, width: width, height: height)
                    if ExperienceDerivation.isLive(c, states: states) {
                        g.stroke(p, with: .color(XRColor.accent.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        let phase = CGFloat((t * 18).truncatingRemainder(dividingBy: 24))
                        g.stroke(p, with: .color(XRColor.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 18], dashPhase: -phase))
                    } else {
                        g.stroke(p, with: .color(XRColor.inputBorder.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 7]))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the relationships are read on each stone instead
    }
}

/// One stone. Fill, ring and glyph change by state; text never relies on colour alone.
/// The title sits UNDER the square in the full court (never clipped); the compact court shows numbers only.
struct StoneView: View {
    let station: Station
    let state: StationState
    let isSelected: Bool
    let isCurrent: Bool
    let size: CGFloat
    let compact: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: XRRadius.control, style: .continuous).fill(fill)
                    RoundedRectangle(cornerRadius: XRRadius.control, style: .continuous)
                        .strokeBorder(ring, style: StrokeStyle(lineWidth: isSelected ? 3 : 2, dash: dash))
                    if isCurrent { breathingRing }
                    HStack(spacing: 2) {
                        Text(String(station.id)).font(compact ? XRFont.heading : XRFont.title).foregroundStyle(number)
                        if case .pending = state { Image(systemName: "lock").font(.caption2).foregroundStyle(XRColor.textSecondary) }
                    }
                }
                .frame(width: size, height: size)
                if !compact {
                    Text(station.titleTR).font(XRFont.caption).foregroundStyle(number).fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Taşı açar")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("map.station.\(station.id)")
    }

    private var label: String {
        var s = "Taş \(station.id), \(station.titleTR), \(state.labelTR)"
        switch state {
        case .active(let sum): s += ": \(sum)"
        case .available(let p): s += ": \(p)"
        case .error(let m): s += ": \(m)"
        default: break
        }
        let rel = LivingGrammar.connectors.filter { $0.from == station.id || $0.to == station.id }
        if !rel.isEmpty {
            s += ". Bağlantılar: " + rel.map { c in
                let other = c.from == station.id ? c.to : c.from
                return "\(LivingGrammar.station(other).titleTR) \(c.relation.verbTR)" + (c.phase.map { " (\($0))" } ?? "")
            }.joined(separator: "; ")
        }
        return s
    }

    private var fill: Color {
        switch state {
        case .active: return XRColor.accentSoft
        case .available: return XRColor.surface
        case .pending, .lockedByConsent: return XRColor.surfaceSecondary
        case .error: return XRColor.surface
        }
    }
    private var ring: Color {
        switch state {
        case .active: return XRColor.accent
        case .available: return XRColor.inputBorder
        case .pending, .lockedByConsent: return XRColor.border
        case .error: return XRColor.danger
        }
    }
    private var dash: [CGFloat] { if case .available = state { return [4, 4] }; return [] }
    private var number: Color {
        switch state {
        case .active: return XRColor.accent
        case .error: return XRColor.danger
        default: return XRColor.textSecondary
        }
    }

    @ViewBuilder private var breathingRing: some View {
        if reduceMotion {
            RoundedRectangle(cornerRadius: XRRadius.control + 4, style: .continuous).strokeBorder(XRColor.gold, lineWidth: 2).padding(-5)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let s = 1 + 0.04 * sin(t * 1.2)          // a breath every ~5 s, never a pulse of urgency
                RoundedRectangle(cornerRadius: XRRadius.control + 4, style: .continuous).strokeBorder(XRColor.gold.opacity(0.9), lineWidth: 2).padding(-5).scaleEffect(s)
            }
        }
    }
}

/// Legend: the three states and the two kinds of connector, in words (never colour-only).
struct CourtLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: XRSpace.xs) {
            HStack(spacing: XRSpace.m) {
                item(fill: XRColor.accentSoft, ring: XRColor.accent, text: "etkin")
                item(fill: XRColor.surface, ring: XRColor.inputBorder, text: "hazır", dashed: true)
                item(fill: XRColor.surfaceSecondary, ring: XRColor.border, text: "planlı")
            }
            Text("Düz çizgi: bu sürümde çalışıyor · kesik çizgi: planlı, seçili taşta görünür").font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
    private func item(fill: Color, ring: Color, text: String, dashed: Bool = false) -> some View {
        HStack(spacing: XRSpace.xs) {
            RoundedRectangle(cornerRadius: 4).fill(fill).frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ring, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [2, 2] : [])))
            Text(text).font(XRFont.caption).foregroundStyle(XRColor.textSecondary)
        }
    }
}
