# P03_01_FIRST_EXPERIENCE_REVIEW_REPORT — design system, onboarding, first working feature

**Date:** 2026-10-20 · **Agent:** Claude Fable 5.1 · **Basis:** founder message "XRAI — P03-01 FIRST EXPERIENCE & ONBOARDING" (P03-00F accepted at `4715552`). **Scope executed:** §1 design system, §2 onboarding, §3 first feature, §4 five tabs + launch/icon, §5 security limits kept, §6 quality/tests with screenshots, §7 this report. **Gate:** STOP for ChatGPT code and screen review.

Türkçe özet: SwiftUI üzerinde semantik token tabanlı tasarım sistemi (mor/lavanta vurgu, sıcak nötr zemin, tek altın vurgu, dark/light, Dynamic Type, Reduce Motion, 44pt hedefler, emoji yok) ve yeniden kullanılabilir bileşenler kuruldu. Gerçek onboarding: karşılama → XRAI ne yapar/yapmaz (dürüst) → gizlilik → isteğe bağlı doğum tarihi → yalnız açık tercihle önizleme; ilk ekrandan atlanabiliyor. Hiçbir kişisel veri diske yazılmıyor; tek kalıcı değer kişisel olmayan "tanıtım tamamlandı" bayrağı (testle doğrulandı). İlk özellik: `NumerologyLifePath` ile tarih doğrulama, yöntem/ana sayı seçimi, rakam-bileşik-indirgeme-kök izi; sembolik yorum ayrı kartta ve "Henüz yok" etiketli. Beş sekme aynı sistemde; Bugün ve Ben ilk akışa bağlı; diğerleri dürüst, tasarlanmış boş durumlar. Logo: AppIcon, launch screen ve uygulama içi. Testler: macOS 108/108; iPhone 17 simülatörü 38/38 (33 host + 5 UI) açık ve koyu modda; fiziksel iPhone 14 Pro Max 38/38; 54 ekran görüntüsü kanıt klasöründe. Cihazda iki UI hatası yaşandı ve kök nedenleri belgelendi (animasyon sırasında yutulan dokunma; tekrar-dokunma sezgisi + iki adımda aynı erişilebilirlik kimliği → iki adım ilerleme). Güvenlik sınırları korundu. İngilizce metinler anadil denetiminden geçmedi; otomatik kontrast/a11y kapısı yok.

## 1. Screens actually completed

| screen | state | notes |
|---|---|---|
| Onboarding 1/5 Karşılama | DONE | logo, value proposition, "Başla", "Şimdilik atla" |
| Onboarding 2/5 Ne yapar / ne yapmaz | DONE | two cards: this version does / not yet (vault, journal, astrology/HD/names/psychology, guide) |
| Onboarding 3/5 Gizlilik | DONE | device-only, no cloud/analytics/AI, nothing on disk this version, keychain holds keys not records, backup/recovery not yet + lost-key rule, you can stop any time |
| Onboarding 4/5 Doğum tarihi (isteğe bağlı) | DONE | validated fields with typed messages; "Önizlemeyi hesapla" (explicit opt-in) / "Tarih girmeden devam et" |
| Onboarding 5/5 İlk önizleme | DONE | Life Path card with method, compound, reduction, master rule, epistemic badge |
| Bugün | DONE (first flow) | session Life Path card + one reflective invitation marked "Senin beyanın"; honest empty state otherwise; "Günlük içerik" planned-state card |
| Ben | DONE (first flow) | Life Path feature (trace, method picker, master toggle, "Tarihi unut"), "Sembolik yorum — Henüz yok", truthful security status, self-test, preferences (reset onboarding) |
| Keşfet · Yolum · XRAI | DONE as honest empty states | real navigation, designed cards with planned phases; no fake features |
| Launch screen, AppIcon, in-app logo | DONE | `LaunchLogo` on `LaunchBackground` (light/dark), AppIcon 1024 from the founder's mark |

## 2. Screenshot evidence
`docs/status/evidence/screenshots/` — `simulator-light/` (18), `simulator-dark/` (18), `device/` (18, iPhone 14 Pro Max, iOS 26.6). Sequence: 01-welcome, 02-what-it-does, 03-privacy, 04-birthdate, 05-preview, 06-today-with-lifepath, 07-ben-trace, 08-skipped-today-empty, 09-tab-0…4, 10-invalid-date, 11-after-foreground, 12-after-relaunch, 13-welcome-accessibilityL, 14-ben-accessibilityL. All captured by the UI tests (XCTAttachment, exported from the xcresults), not hand-staged.

## 3. UX and accessibility findings (from the screenshots)
- Light and dark both read cleanly; the violet accent stays legible on both backgrounds; cards have visible borders in dark mode.
- Dynamic Type at AccessibilityL: the welcome headline wraps to three lines and the "Şimdilik atla" link moves below the fold (the page scrolls, so it stays reachable, but a first-time user with large text sees "Başla" and may not notice "atla"). **Finding F-UX-1:** on accessibility sizes place "Şimdilik atla" above the primary button or pin both buttons. Deferred to P03-02.
- The iOS 26 floating tab bar overlaps the last card on Ben when scrolled to the bottom (visible in `device/07-ben-trace.png`); content remains scrollable. **F-UX-2:** add bottom safe-area padding for the tab bar.
- Monospace trace lines wrap on narrow widths ("Tarih (yalnız bellekte): 1998-06-30" wraps); acceptable, but **F-UX-3:** show the date on its own line.
- VoiceOver: every control has a label; epistemic badges read as "Bilgi sınıfı: …"; headers carry the header trait. Not yet run with VoiceOver on device by a human (**not tested**).
- No automated contrast gate exists; token values were chosen for AA on their backgrounds but not measured in CI (**open**).
- Reduce Motion: step transitions drop their animation when the setting is on (code path), **not exercised by a test**.

## 4. Test results

| host | command | exit | result | evidence |
|---|---|---|---|---|
| macOS | `swift test --package-path Packages/XRAICore` | 0 | 108/108 (package untouched this phase) | `p03_01_swift_test_macos.log` |
| iPhone 17 Simulator | `xcodebuild build-for-testing` | 0 | app + hosted + UI bundles | `p03_01_xcodebuild_sim_build_for_testing.log` |
| iPhone 17 Simulator (light) | `xcodebuild test` (final code) | 0 | **38/38** (33 hosted: 24 keychain/smoke + 9 onboarding/session; 5 UI) | `p03_01_xcodebuild_sim_tests_run2.log`, `p03_01_sim_xcresult_summary.json` |
| iPhone 17 Simulator (dark) | `-only-testing:XRAIUITests` | 0 | 5/5, 18 dark screenshots (captured before the identifier fix; same screens) | `p03_01_xcodebuild_sim_dark_ui_tests.log` |
| iPhone 14 Pro Max, run 1 | `xcodebuild test` | 65 | 37/38 — `testBackgroundAndForegroundKeepsSession` missed "onboarding.next" (tap swallowed during the transition) | `p03_01_xcodebuild_device_tests_run1_1_UI_FAIL.log` |
| iPhone 14 Pro Max, run 2 (re-tap helper) | `-only-testing:XRAIUITests` | 65 | 2/5 — the re-tap heuristic plus a duplicated identifier (`onboarding.next` on two steps) advanced two steps; the exported UI hierarchy showed the app already on the birth-date step | `p03_01_xcodebuild_device_ui_run2_3_FAIL_double_tap.log` |
| iPhone 14 Pro Max, run 3 (unique identifiers, wait-for-hittable, single tap) | `xcodebuild test` | **0** | **38/38** | `p03_01_xcodebuild_device_tests_run3.log`, `p03_01_device_xcresult_summary.json` |

Scenario coverage (§6): start ✓ (`start`, `testStartThroughAllStepsWithValidDate`), skip ✓ (`skip`, `testSkipFromWelcome`), invalid date ✓ (`invalidDate`, `testInvalidDateShowsProblemAndDoesNotAdvance`: 1900-02-29, non-numbers, empty), valid date ✓ (`validDate` matches the engine: 1998-06-30 → 36 → 9), background → foreground ✓ (`testBackgroundAndForegroundKeepsSession`: in-memory date survives within the process; `backgroundKeepsSessionButPurgesKeys`: key cache purged), relaunch ✓ (same UI test: date gone, onboarding not repeated; `relaunch`: defaults suite holds only the boolean flag), Dynamic Type ✓ (AccessibilityL layout test + screenshots), tab navigation ✓ (all five tabs tapped and captured). **Not tested:** VoiceOver by a human, Reduce Motion, English locale run, iPad/small-screen (iPhone SE) layouts, landscape (portrait only by Info.plist).

## 5. Security limits kept
No personal persistence (test-asserted: only `xrai.onboarding.completed.v1` in defaults); no production consent registry (consent-gated classes still refuse, stated on screen); cross-process rotation unsupported (unchanged); forget still lacks store proof (unchanged); recovery-key loss explained in onboarding copy and backup shown as "Henüz çalışmıyor"; keychain-keys-vs-records difference explained in two places; no analytics/cloud/AI. Package `XRAICore` unchanged in this phase (`git diff` empty); key cache still purged on scene inactive/background.

## 6. Next smallest implementable task (proposal)
**P03-02 — UX polish and gates:** fix F-UX-1/2/3; add an automated contrast check over the token table and an accessibility audit test (labels, traits, hit sizes); run VoiceOver and Reduce Motion manually on the device with a checklist; proofread the English catalog; add iPhone SE-class and landscape layout screenshots. No new product features before ChatGPT review.

**STOP — awaiting ChatGPT code and screen review.**
