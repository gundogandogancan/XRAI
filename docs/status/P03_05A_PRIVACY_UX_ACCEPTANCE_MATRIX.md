# P03_05A_PRIVACY_UX_ACCEPTANCE_MATRIX — consent, restore-risk and accessibility acceptance

**Date:** 2026-10-20 · **Baseline:** `1a3a448` · Status words: TESTED (automated, log in the ledger), MANUAL_PENDING (needs a human), OPEN.

Türkçe özet: İzin ekranı sekiz soruyu her amaç için cevaplıyor; beş ayrı eylem; yeniden izin eski veriyi geri getirmiyor; risk ekranı sekiz risk türünü ayrı anlatıyor ve tam onay istiyor; F-UX-5 ölçülerek kapatıldı; VoiceOver ve ana dil İngilizce incelemesi MANUAL_PENDING.

## GATE 4 — consent UX
| requirement | where | evidence | status |
|---|---|---|---|
| "Hangi verime izin veriyorum?" … "Tamamen nasıl sileceğim?" (8 questions) shown before any grant, per purpose | `ConsentFlow.answers`, `PurposeDetailView` ids `consent.qa.0…7` | NT-UX-03, NT-UX-07 (XCUI asserts all eight exist before the grant) | TESTED |
| grant, revoke+delete, revoke+suspend, delete records, restore suspended are distinct actions with distinct confirmations | `ConsentAction`, `PurposeDetailView.actions`, dialog ids `consent.confirm.*` | NT-UX-01, NT-UX-07 | TESTED |
| third-party classes are never suspended | `revocation == .stopReadsAndDeleteNow` → no suspend button; model refuses | NT-UX-01, NT-UX-07 (`symbolic_family_lens`) | TESTED |
| re-granting never reactivates deleted/suspended data; restore is explicit | `ConsentFlow.grant` leaves record state; `restoreSuspended` needs grant + action | NT-UX-01, NT-CA-04 (store) | TESTED |
| typing is not consent; only controls + dialogs mint proofs | proofs minted inside action closures only; `InteractionKind` has no "edit" | NT-UX-02, NT-IG-03 | TESTED |
| synthetic state is labelled as such | intro texts "bu sürümde gerçek kayıt yok" | NT-UX-07 (`consent.intro`) | TESTED |
| consent history shows no payload | `ConsentHistoryView` (purpose, classes, time, version) | NT-CA-02 (no human text in events), NT-UX-07 | TESTED |
| English localisation of the new screens | `Localizable.xcstrings` (en entries for every new string key) | file present; native English review | MANUAL_PENDING |

## GATE 5 — restore risk UX
| requirement | where | evidence | status |
|---|---|---|---|
| each `RestoreRisk` explained differently (8 cases) | `RestoreRiskPresenter.explain` | NT-UX-04 | TESTED |
| exact acknowledgment (= recorded set) | `acknowledgmentMatches`, button enabled only when equal | NT-UX-04, NT-UX-07 (one of two toggles → disabled) | TESTED |
| possibly-deleted / untrusted identity never activate; re-import offered | `canActivate`, `offersReimport`, ids `restore.noactivate.*`, `restore.reimport.*` | NT-UX-04, NT-UX-07; store: NT-BH-01, NT-PR-03 | TESTED |
| no reset button shown as if it existed | `restore.noreset` card with "Henüz yok" badge | NT-UX-07 | TESTED |

## GATE 6 — accessibility
| item | evidence | status |
|---|---|---|
| F-UX-5 input boundary ≥ 3:1 (light/dark, vs fill, card, background) | NT-UX-06 attachment `input-boundary-contrast.txt` | TESTED → **CLOSED** |
| F-UX-4 quiet-button affordance (accent + underline + chevron, 44pt) | `XRQuietButtonStyle`; audits green | TESTED (automated) · human judgement MANUAL_PENDING |
| Dynamic Type | all new text uses `XRFont` styles; XCUI accessibilityL run (P03-02 test) still green | TESTED |
| VoiceOver labels / reading order | identifiers + combined elements; audit `sufficientElementDescription` | automated TESTED · human VoiceOver pass MANUAL_PENDING |
| Reduce Motion | `XRMotion` (no new animations added) | TESTED (MotionTests) |
| small-screen layout | no SE-class simulator available (P03-02 OPEN) | OPEN |
| screen-reader confirmation of destructive actions | confirmation dialogs with explicit destructive buttons (`role: .destructive`) | automated TESTED · human MANUAL_PENDING |
| app-switcher privacy shielding | unchanged (`PrivacyShieldView`); consent screens hold no personal data | TESTED (policy) · visual MANUAL_PENDING |
| Turkish/English | tr source + en catalog entries for new strings | native English review MANUAL_PENDING |
