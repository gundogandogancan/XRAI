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

## Amendment Q — P03-02 privacy & UX quality gate (2026-10-20)

1. **One draft, one forget.** The free-text date draft moved from the onboarding view model into `SessionState.draft` (shared with the Ben feature). `SessionState.forgetAll()` is the single privacy operation: it clears the confirmed date and every draft field; onboarding `finish()` always clears the draft (confirmed date kept only if the user computed it); abandoning the date step drops unconfirmed text. Swift gives no memory-zeroing guarantee; the operation drops references.
2. **Three lifecycles, three sentences.** Background: the date stays in memory for this process and the app says so. Termination: gone. "Tarihi unut": gone now. Copy in onboarding, Ben and the forget button reflects this. A `PrivacyShieldView` covers the UI whenever the scene is inactive **and** personal data is held (`PrivacyShieldPolicy`), so the app-switcher snapshot shows the brand, not the date. Visual verification of the actual switcher snapshot is not automated (MANUAL_PENDING); the policy is unit-tested.
3. **Five epistemic classes.** `systemInvitation` ("Sistem daveti") added for prompts XRAI offers; "Senin beyanın" is reserved for things the user actually said. Badges carry identifiers for UI assertions.
4. **UX defects.** F-UX-1: onboarding actions are pinned in a bottom `safeAreaInset`, "Şimdilik atla" is a visible secondary button at every size (asserted hittable at AccessibilityL). F-UX-2: relative bottom content margin plus a hard bottom scroll edge on iOS 26; the last control on Ben is asserted hittable after scrolling. F-UX-3: trace date and digits are stacked label/value rows on their own lines.
5. **Measured contrast.** `ContrastTests` resolves every token pair in light and dark and asserts AA; two real defects were found and fixed: dark primary-button text (white on lavender 2.70:1 → new `onAccent` token, 7.19:1) and dark border on surface (1.29 → 1.56:1). Full table in `docs/status/evidence/p03_02_contrast_ratios_measured.txt`.
6. **Automated accessibility audit** (`XCUIApplication.performAccessibilityAudit`) on welcome, birthdate, preview, today, ben. Findings fixed: progress bar flagged as a tiny control (now decorative, step count exposed as text); preview contrast/clipping flagged mid-animation (audit now waits for the UI to settle; root number pinned). **Known limitation:** on tab screens the `.contrast` audit type is excluded because iOS 26's translucent floating tab bar blends scrolled content and the audit measures that blend; the colours themselves pass the measured gate and all other audit types run on those screens.
7. **Not claimed:** VoiceOver by a human (checklist with MANUAL_PENDING items), SE-class screens (no simulator installed), landscape (portrait-only by design), native-English review (agent-proofread only).
