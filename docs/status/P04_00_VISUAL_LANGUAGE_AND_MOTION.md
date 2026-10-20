# P04_00_VISUAL_LANGUAGE_AND_MOTION — how the court looks, moves and speaks (v1)

**Date:** 2026-10-20 · **Branch:** `p04-00-living-experience` · **Baseline:** `4c5235f1c6e0442a1b68fad90e4594873fe46630` · **Code:** `App/XRAI/Experience/HopscotchMapView.swift`, existing tokens in `App/XRAI/DesignSystem/Theme.swift` (no new colour tokens were added; every pair used by the court is measured in `CourtContrastTests` NT-LX-11).

Türkçe özet: Taşlar var olan jetonlarla çizilir; durumlar renkle değil çizgi, kilit simgesi ve sözle ayrılır. Hareket yalnız iki yerde: 0 taşındaki nefes halkası (5 saniyede bir, aciliyet yok) ve bu sürümde gerçekten çalışan bağlantılarda yavaş akış. Planlı bağlantılar hareket etmez ve yalnız seçili taşta görünür. Hareketi Azalt açıkken her şey durur. Dinamik Tip, VoiceOver, karanlık/aydınlık ve küçük ekran kuralları aşağıda; ölçülenler ve elle bekleyenler ayrı yazıldı.

## 1. Colour (tokens only, §88 quiet discovery)

| element | token | note |
|---|---|---|
| active stone fill / ring / number | `accentSoft` / `accent` / `accent` | measured number-on-fill ≥ 4.5:1 both modes |
| available stone fill / ring / number | `surface` / `inputBorder` (dashed) / `textSecondary` | the dashed ring is the F-UX-5 input-boundary colour: "you can write here" |
| pending stone fill / ring / number | `surfaceSecondary` / `border` / `textSecondary` + lock glyph | the glyph carries the state, not the colour |
| error | `danger` ring and number | message in the panel |
| current stone ring | `gold` | the one gold highlight per screen |
| live connector | `accent` (35 % base + full dash) | |
| planned connector | `inputBorder` 70 %, dashed 3/7 | still, selection-only |
| page / card | `background` / `surface` | unchanged |

No spectral gradient, no glow, no "scanner" imagery (brand README). Dark mode uses the same tokens; nothing is hard-coded.

## 2. Shape and typography

- Stone: rounded square, `XRRadius.control` (12 pt), 60 pt in the full court, 76 pt at accessibility Dynamic Type sizes, 40 pt in the compact court; 2 pt ring, 3 pt when selected.
- Number: `XRFont.title` (full) / `XRFont.heading` (compact), Dynamic Type text styles only.
- Title: `XRFont.caption` **under** the square in the full court with `fixedSize()` (the first run clipped titles inside the square at normal size — fixed; the audit's "text clipped" check is part of the UI test).
- Compact court: numbers only; titles are read by VoiceOver and shown in the panel.
- Symbol language: exactly one glyph, `lock` on pending stones. No emoji. No icons on connectors; relationships are words in the panel and in VoiceOver labels.

## 3. Two layouts, one grammar

- **Full court (Ben):** rows climb from the bottom, start at the bottom (0), pairs at 27 % / 73 % of the width, singles centred. Height = 8 × (stone + caption + gap).
- **Compact court (Bugün):** the same rows become columns, left to right, pairs stacked. Height = 2 × stone + gap (88 pt), so the court is visible in the first screen together with the discovery and the invitation.
- Long connectors (span > 1 row) bow outward with a quadratic curve so they never pass through a stone they do not join; neighbours are straight.

## 4. Motion (constitution C:351: no animation that implies certainty)

| what | how | why |
|---|---|---|
| current ring on stone 0 | scale 1 ± 4 %, period ≈ 5 s (`sin(t·1.2)`) | "the court is alive" without urgency |
| live connectors | dash 6/18 moving at 18 pt/s | "this path runs now" — and nothing else moves |
| planned connectors | none | a planned relationship must not look alive |
| selection change | `XRMotion.standard` (0.28 s ease) on the panel swap | continuity |
| Reduce Motion | `TimelineView(.animation(paused: true))`, static gold ring, no dash flow, no ease | OS setting honoured by construction (`accessibilityReduceMotion`) |

No parallax, no particles, no haptics in this version. Nothing moves on a timer to attract attention.

## 5. Gestures

Tap only. A tap on a stone selects it (Ben) or pushes its panel (Bugün). No long-press, no drag, no swipe meaning. Nothing on the court grants anything: consent and vault operations still happen only through explicit controls inside their own screens (P03-05A `InteractionGate` contract unchanged).

## 6. Dynamic Type

- All text uses text styles; the stone grows at accessibility sizes; the compact court scales stones down to fit eight columns on narrow widths.
- The UI test `testAccessibilitySizeAudit` launches at `UICTContentSizeCategoryAccessibilityL` and runs the audit on all three screens (dynamicType, textClipped included).
- Known limit: at the largest accessibility sizes the compact court's numbers stay at `heading` size inside 40 pt stones; the panel carries the full text. A horizontal-scroll compact court is a v2 option if a manual pass finds it necessary.

## 7. VoiceOver

- Each stone is one button: "Taş N, <title>, <state>: <summary>. Bağlantılar: <other> <verb> (<phase>)…" — the relationships are spoken, so the hidden canvas loses nothing.
- The connectors canvas is `accessibilityHidden`; the legend is one combined element; the court container is labelled "Yaşam haritası, on bir taş".
- Every badge reads "Bilgi sınıfı: …". The selected stone carries the `isSelected` trait.
- MANUAL_PENDING: a human VoiceOver pass (reading order of the panel, the DisclosureGroup label).

## 8. Small screens and widths

The court is width-driven (`GeometryReader`); the page is capped at 640 pt. On an SE-class width the compact stones shrink to ≈ 36 pt. MANUAL_PENDING: SE-class device run (no such device available).

## 9. Empty, locked, pending and error states

- Empty session: stone 0 active (today), stone 1 available with "Tarihini gir", choice stones available, the rest pending with their phase. The discovery card shows a worked example computed by the real engine on `2000-01-01` (never a typed claim).
- Locked by consent: defined in the state machine, not reachable in this build (no consent authority is wired); the visual equals pending with the purpose named.
- Error: the engine refusing a date is shown on stone 1 as "Hesap çalışmadı" in `danger`; the panel keeps the input editable.
- Nothing is ever shown as "completed".

## 10. Epistemic labels without clutter

One badge per card, placed in the card header; the court itself carries none (the state ring is not an epistemic claim). The panel header carries the stone's class. Rule: no sentence about the person appears without a badge within the same card.

## 11. Measured vs manual

| check | status |
|---|---|
| contrast of every court pair, both modes | TESTED (NT-LX-11, attachment `court-contrast.txt`) |
| text clipped / dynamic type / hit region / labels / traits on Bugün, Ben (+ panel, + contract), Yolum, incl. accessibility size | TESTED (XCUI audit, Simulator and device) |
| Reduce Motion returns no animation | TESTED (existing `XRMotion` test); court paused by the same environment value — visual confirmation MANUAL_PENDING |
| human VoiceOver pass, SE-class layout, native English | MANUAL_PENDING |
