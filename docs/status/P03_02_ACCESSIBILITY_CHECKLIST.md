# P03-02 — Accessibility checklist (VoiceOver, Reduce Motion, layout)

Status vocabulary: `AUTOMATED` (an XCUITest or hosted test asserts it), `AUDIT` (XCUI accessibility audit ran; findings attached), `MANUAL_PENDING` (needs a human with VoiceOver on a device — **not** done, never marked MANUAL_VERIFIED by the agent), `DESIGN_DECISION`.

## VoiceOver
| item | status | evidence / note |
|---|---|---|
| Every button and field has a label (not an icon name) | AUTOMATED (audit, labels in code) | `testAccessibilityAuditOnKeyScreens`; identifiers + labels in `OnboardingFlow.swift`, `SelfView.swift` |
| Headers carry the header trait (XRAI, Bugün, Ben, section titles) | AUTOMATED (code) · MANUAL_PENDING (rotor order) | `.accessibilityAddTraits(.isHeader)` |
| Date fields announce "Yıl / Ay / Gün" and the error is announced as "Tarih hatası: …" | AUTOMATED (labels) · MANUAL_PENDING (announcement timing) | `DateFields` |
| Epistemic badges read "Bilgi sınıfı: …" | AUTOMATED (label) | `XREpistemicBadge` |
| Tab bar items named Bugün/Ben/Keşfet/Yolum/XRAI | AUTOMATED (UI test taps by index; labels from `Label`) | `RootTabView` |
| Focus order: progress → title → text → actions (actions pinned at bottom) | MANUAL_PENDING | design intent; verify with VoiceOver swipe order |
| Privacy shield announced when returning from background | MANUAL_PENDING | `PrivacyShieldView` label "Gizlilik perdesi" |
| Logo images decorative except where labelled "XRAI logosu" | AUTOMATED (code) | `XRLogo` |

## Reduce Motion
| item | status |
|---|---|
| Design-system motion returns nil animation when Reduce Motion is on | AUTOMATED (`MotionTests`) |
| Onboarding step transition without animation; no parallax/auto-play anywhere | AUTOMATED (code path) · simulator run with Reduce Motion enabled, see report |

## Dynamic Type / layout
| item | status |
|---|---|
| AccessibilityL: skip visible without scrolling; last Ben control reachable | AUTOMATED (`testDynamicTypeLargeSkipIsVisibleAndLastCardReachable`) |
| AccessibilityXXXL | NOT_RUN |
| Narrow / SE-class screens | NOT_RUN — no SE simulator installed on this Mac (smallest available: iPhone 17e); record as open |
| Landscape | DESIGN_DECISION — portrait only (`UISupportedInterfaceOrientations`); not tested, not claimed |
| Light / dark | AUTOMATED screenshots in both appearances |

## Contrast
Measured by `ContrastTests` on the resolved light and dark token pairs; thresholds AA 4.5:1 for text, 3:1 for accents/large UI; the measured ratios are attached to the test run (`contrast-ratios.txt`) and copied into the report.

## English catalog
Reviewed by the agent for meaning, grammar and length (not a native reviewer); English-locale screenshots not captured in this phase.
