# P04_00_PROTOTYPE_REVIEW_REPORT — living experience & hopscotch design gate

**Date:** 2026-10-20 · **Decision received:** approve P04-00 design and synthetic SwiftUI prototyping only; P03-05B NOT authorised · **Baseline:** `4c5235f1c6e0442a1b68fad90e4594873fe46630` · **Branch:** `p04-00-living-experience` in worktree `../ProjectXrai-p04` (main untouched, no force push, not merged) · **SECURITY_REVIEWED:** NO (no security surface changed) · **Real personal data persistence:** none; session memory only.

Türkçe özet: Üç çalışan ekran (Bugün, Ben, Yolum) sentetik/oturum verisiyle; "seksek" grameri `court.v1` kodda ve belgede; her taş bir soru, her bağlantı savunulabilir bir ilişki; planlı olan hiçbir şey canlı gibi görünmez. Simulator ve iPhone koşuları, erişilebilirlik denetimleri ve önce/sonra ekran görüntüleri aşağıda. Kasa, izin, keychain ve yetki modüllerine dokunulmadı. Figma kullanılmadı (ADR-BOOT-011 PROPOSED). Birleştirme ve P03-05B kararı incelemecinin.

## §1 Founding vision recovered
Read: constitution §41/§55/§60/§71/§73/§88/§89 (first vertical slice), the philosophy doc (§04 X-ray metaphor, §08 octopus, G1–G16, §13 filter), the founder's first message, P03-01/P03-02 UX reports, the product-vision recon. The canon has no hopscotch; the court is defined as an original presentation grammar over the §73 claim graph (`P04_00_LIVING_EXPERIENCE_GRAMMAR.md` §1, §6). Five tabs kept in order. X-ray = depth, never diagnosis (lexicon enforced). Octopus pipeline mapped step by step to this build (`P04_00_OCTOPUS_TO_SCREEN_CONTRACT.md` §1).

## §2 Living visual grammar
`court.v1`: 11 stones (questions), 11 connectors (relations: derives / reports / interprets / evidences / invites, each with an epistemic class), 5 stone states, the return rule, pairs = two sides of one question, versioning rule, explicit non-equivalence with Sefirot and HD (asserted by `NT-LX-05`). Visual language, motion, gestures, Dynamic Type, VoiceOver, dark/light, small screens, empty/locked/pending/error states and badge placement: `P04_00_VISUAL_LANGUAGE_AND_MOTION.md`.

## §3 Visible screens (running SwiftUI, session/synthetic data)
| screen | file | what runs |
|---|---|---|
| A. Bugün — living home | `Experience/TodayLivingView.swift` | day in words; ONE discovery (the person's exact Life Path or a worked example computed live by the engine); the compact court (live connectors flow, planned ones hidden until selection); ONE invitation (rest or one small step); rhythm card that says "P07" |
| B. Ben — personal map | `Experience/SelfMapView.swift`, `StationPanel.swift` | the full court; inline panel per stone with question → meaning → state → feature → "Nasıl çalışır" (eight-question contract + connectors); stone 1 hosts the unchanged Life Path feature (trace `lifepath.trace`, root `Kök sayı 9` for 1998-06-30); security/consent/restore moved one level down (`SecurityPrivacyView`) |
| C. Yolum — Future Self preview | `Experience/PathPreviewView.swift` | labelled synthetic scenario; one weekly step; P0 → P1 (self-report) ladder with P2 shown unreachable; the step reaches Bugün (connector 9→0) |

Five-tab architecture retained; Keşfet and XRAI unchanged. `XRAIVaultStore` not linked (docs check). No model, no network.

## §4 Personal rhythms
Contract specified in code (`Experience/RhythmContract.swift`: `RhythmSource`, `RhythmReading` with four separately labelled strands, `PendingRhythmSource` refusing to calculate) and in `P04_00_OCTOPUS_TO_SCREEN_CONTRACT.md` §3. `NT-LX-10` asserts nothing calculates and the result is deterministic. No P07/P08 engine implemented.

## §5 Octopus-to-screen contract
Eight fields for all 11 stones in code (`ScreenContract`, shown to the person under "Nasıl çalışır") and for the 9 non-stone cards in the doc. First slice needs no model; offline behaviour identical. `NT-LX-03` asserts completeness.

## §6 Tooling and isolation
Worktree + branch from `4c5235f`. Files changed: `App/XRAI/Experience/*` (new: LivingGrammar, HopscotchMapView, StationPanel, TodayLivingView, SelfMapView, PathPreviewView, RhythmContract), `App/XRAI/RootTabView.swift` (tabs point to the new screens; old Today/Path bodies removed), `App/XRAI/SelfView.swift` (reduced to the protection-description helper), `App/XRAI/Session/SessionState.swift` (`journey` draft, cleared by `forgetAll`, counted by `holdsPersonalData`), `App/XRAI/DesignSystem/Components.swift` (quiet button = one accessibility element), `App/XRAI/Localizable.xcstrings` (en entries), tests (`App/XRAIHostedTests/LivingExperienceTests.swift`, `App/XRAIUITests/LivingExperienceUITests.swift`), `XRAI.xcodeproj` (regenerated), docs (six P04-00 documents, ADR-BOOT-011, matrix addendum NT-LX, NEXT_TASK, OPEN_BLOCKERS, tools ledger, ADR index, CLAUDE.md, validator, evidence ledger). **No file under `Packages/XRAICore` changed.** Figma not used (ADR-BOOT-011 PROPOSED; export deferred, see tools ledger).

## §7 Measured visual acceptance
Screenshots: `docs/status/evidence/p04_00_screens/before_sim/` (baseline), `after_sim/`, `after_device/` — captured by the UI tests, exported from the xcresult bundles. Before/after narrative: `P04_00_FIRST_MINUTE_USER_JOURNEY.md` §2.

| run | command | exit | result | log |
|---|---|---|---|---|
| baseline screenshots | `xcodebuild test … Simulator -only-testing:XRAIUITests/OnboardingUITests` at `4c5235f` | 0 | 7 tests, "before" screenshots exported | `evidence/p04_00_before_sim_ui.log` |
| targeted, run 1 | hosted NT-LX + `LivingExperienceUITests` | 65 | NT-LX-04 caught "teşhis" in stone 7's copy (reworded); audits: stone titles clipped inside the square (titles moved under the stone), a card identifier read as a label (removed) | `evidence/p04_00_sim_targeted_run1.log` |
| targeted, run 2 | same | 65 | hosted 11/11; audits: the on-screen "court.v1" tag flagged (removed from the screen); Ben panel below the fold (test scrolls) | `evidence/p04_00_sim_targeted_run2.log` |
| targeted, run 3 | UI only | 65 | the renamed version label still flagged as clipped (tag removed); `map.full` container not addressable (tests wait on a stone) | `evidence/p04_00_sim_targeted_run3.log` |
| targeted, run 4 | UI only | 65 | audits all clean; two assertion issues: a planned stone's badge below the fold, `today.fillOrigin` missing — root cause found in the whole-scheme run: an `accessibilityIdentifier` on an `XRCard` collapses the card into one StaticText on iOS 26 (children vanish, the audit reports the card as clipped); identifiers moved to inner texts; the quiet-button style now also combines its children for VoiceOver | `evidence/p04_00_sim_targeted_run4.log` |
| UI bundle, run 5 | `-only-testing:XRAIUITests` | 65 | 15 tests, 2 issues: the big root number on Bugün flagged as clipped (same fix as the old card: `lineLimit(1).fixedSize`) | `evidence/p04_00_sim_ui_run5.log` |
| Simulator, whole scheme | `xcodebuild test -project XRAI.xcodeproj -scheme XRAI -destination 'platform=iOS Simulator,name=iPhone 17'` | 65 → 0 | hosted 166 tests in 42 suites + XCUI 15/15 (OnboardingUITests 7, ConsentUITests 4, LivingExperienceUITests 4 incl. accessibility-size audit); run 1 of the whole scheme failed with 7 UI issues (identifier-on-card collapse, root number clipped, preferences moved) — kept as `…sim_all_run1_FAIL_7_ui_issues.log`; the UI-only run 5 fixed all but the root clipping (`…sim_ui_run5.log`); final run exit 0 | `evidence/p04_00_xcodebuild_sim_all.log` |
| iPhone 14 Pro Max, whole scheme, non-destructive | `xcodebuild test … 'platform=iOS,id=C7C6CE6E-…' -allowProvisioningUpdates` | 0 | iPhone 14 Pro Max (iOS 26.6) hosted 166/166 with the two P03-05A source scans skipped by design + XCUI 15/15; screenshots exported to `p04_00_screens/after_device/`; non-destructive | `evidence/p04_00_xcodebuild_device_all.log` |
| static: docs + boundaries | `python3 -I validation/check_p03_03_docs.py` | 0 | PASS incl. P04-00: six deliverables cite the baseline, NT-LX-01…12 rows present, ADR-BOOT-011 present, `Experience/` imports no vault module and carries no forbidden copy, 152 NT rows | `evidence/p04_00_check_docs.log` |
| static: package spec | `python3 -I validation/validate_package.py` | 0 | PASS spec structure (worktree); does NOT verify an iOS build | `evidence/p04_00_validate_package.log` |

Acceptance checklist (directive §7): meaningful first minute — screenshots A1→A6; no encyclopedia — card counts in the journey doc §2; no dead navigation — journey doc §4, every push has back, no sheets; Life Path trace correct — `Kök sayı 9` asserted on Bugün and Ben for 1998-06-30 and the full trace one tap down; no false certainty — lexicon tests + badges on every card; contrast — NT-LX-11 (court pairs) + existing ContrastTests; Dynamic Type — accessibility-size audit test; VoiceOver — labels/traits/hints audited by XCUI, human pass MANUAL_PENDING; Reduce Motion — `XRMotion` test + court paused by construction, device visual MANUAL_PENDING; every claimed interaction backed by running code — the XCUI tests tap each one.

## §8 Parallel security readiness (read-only)
`P04_00_P03_05B_READINESS.md`: nine items with evidence definitions and owners; none produced here; nothing weakened.

## §9 Visual limitations and remaining decisions
Limitations: full court height on Ben (≈ 770 pt), compact court at the largest type sizes, Turkish-only titles on screen, the chosen weekly step is marked by text and VoiceOver value but has no checkmark glyph (the daily intention has one), no haptics, no device Reduce-Motion visual check, no SE-class device. Decisions for the reviewer/founder: merge the branch or not; accept `court.v1` (epistemic reviewer pass on stone meanings); P03-05B GO (readiness register) vs. P04-01 (design-system export under ADR-011); whether stone 6 ("Bağ") stays visible before third-party consent exists.

## Implementation commit
<!-- FINAL-SHA --> on branch `p04-00-living-experience` (pushed to origin; main unchanged at `4c5235f`).

**STOP.** No merge, no P03-05B, no P04-01 until the review block in `NEXT_TASK.md` is filled.
