# ADR-BOOT-008 — Design system, onboarding and the first user flow (P03-01)

**Status:** ACCEPTED (2026-10-20) · Simulator 38/38 · iPhone 14 Pro Max 38/38 · macOS package 108/108 · **Refines:** constitution §41, §71, §73, §88, §89 (first vertical slice); ADR-BOOT-001 (no new product direction), ADR-BOOT-005/007 (security limits unchanged)

## Decisions

### D1 — Tokens, not colours
`App/XRAI/DesignSystem/Theme.swift` defines semantic tokens only: `background`, `surface`, `surfaceSecondary`, `border`, `text`, `textSecondary`, `accent` (violet), `accentSoft`, `gold` (one meaningful highlight per screen), `sage` (positive), `warning`, `danger`; every token has a light and a dark value (`UIColor` dynamic provider). Spacing is a 4-pt rhythm (`XRSpace`), radii are fixed (`XRRadius`), typography uses system text styles only (`XRFont`) so Dynamic Type always applies, and `XRMotion` returns no animation when Reduce Motion is on. Minimum touch target 44 pt. No emoji, no gradients beyond the logo itself.

### D2 — Components
`XRPrimaryButtonStyle`, `XRSecondaryButtonStyle`, `XRQuietButtonStyle`, `XRCard`, `XRPage`, `XRSectionTitle`, `XRLabeledValue`, `XRLogo`, `XREmptyState` (title, honest message, planned phase, "Henüz yok" badge), and `XREpistemicBadge` with four kinds: **Kesin matematik / Sembolik gelenek / Senin beyanın / Henüz yok**. Every result on screen carries one of these (constitution §73).

### D3 — Onboarding is honest and optional
Steps: welcome → what XRAI does and does not do (this version) → privacy → optional birth date → preview (only after the explicit "Önizlemeyi hesapla") → done. "Şimdilik atla" on the first screen reaches the full app with zero personal data. Typing a date is not consent; only computing is. Copy states plainly: no personal data is written to disk in this version; the Keychain holds encryption keys, not records; backup and recovery key do not work yet, and when they do, a lost recovery key means nobody can open the backup, XRAI included.

### D4 — Persistence boundary (temporary demo solution)
`SessionState` keeps the birth date, method and master policy **in memory only**; it vanishes with the process. The one persisted value is the non-personal boolean `xrai.onboarding.completed.v1` in `UserDefaults`, so the user is not pushed through onboarding on every launch; it is resettable from Ben › Tercihler. A test asserts the defaults suite contains nothing but that key. When the vault store exists this flag moves to a proper preferences layer.

### D5 — First feature
`LifePathCard` / `LifePathFeatureView` use `NumerologyLifePath` unchanged: validated `CivilDate`, selectable method (`digits.v1`, `components.v1`), master-number policy toggle, literal digits, compound, reductions, root; "Sembolik yorum" is a separate card marked **Henüz yok** with the planned phase. No personality/fate wording anywhere.

### D6 — Tabs
Bugün shows the session Life Path (if any) with a single reflective invitation marked as the user's own report, and honest empty states; Ben hosts the feature, the truthful security status, self-test and preferences; Keşfet, Yolum and XRAI are designed empty states with planned phases. Launch screen: `LaunchLogo` on `LaunchBackground` (light/dark). AppIcon: the founder's mark.

### D7 — Localisation
Source language Turkish; `Localizable.xcstrings` carries 63 English translations; `CFBundleLocalizations = [tr, en]`. English copy has not been proofread by a native reviewer (open item).

### D8 — Testing contract for UI
Every onboarding step has a **unique** accessibility identifier; UI tests wait for hittability and tap once. (A re-tap heuristic combined with a duplicated identifier advanced two steps on the device and was removed — recorded in the P03-01 report.)

## Consequences
The first vertical slice of §89 (free DOB → exact Life Path → honest labelling) exists on a real device with no persistence. Open: automated contrast/a11y gates, English proofreading, launch-screen polish, and everything behind the security blockers.
