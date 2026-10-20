# P03_05A_GATE_REVIEW_REPORT — consent, interaction & trusted user experience foundation

**Date:** 2026-10-20 · **Approval:** CONDITIONAL GO — P03-05A only (recorded in `NEXT_TASK.md`) · **Baseline:** `1a3a4485e562aea7b9fb9f05470b7eb3b989c77b` · **SECURITY_REVIEWED:** NO · **Real personal data persistence:** NOT AUTHORIZED, not done · **App composition root:** still `NoConsentAuthority` + no store.

Türkçe özet: Dokuz kapı. Uzlaştırma (8 çelişki), yetki-sırası ve türetilmiş-kaynak denetimi (iki doğrulanmış hata düzeltildi), sürümlü amaç kaydı + değişmez izin zinciri (depoda kalıcı, geri alınamaz), InteractionGate (süreç içi sınır, dürüstçe adlandırıldı), sentetik durumla izin ve geri yükleme risk ekranları, F-UX-5 ölçümle kapandı, karar kaydı, üç host koşusu. Gerçek kişisel veri hâlâ yazılmıyor; P03-05B için gereken onay son bölümde.

## GATE 0 — canonical reconciliation
Done: `P03_05A_CANONICAL_RECONCILIATION.md` (eight conflicts + five extra divergences, each with the ruling source; consent spec §2/§4/§5/§7 superseded; ADR-BOOT-010 PROPOSED).

## GATE 1 — pre-integration review
| item | class | finding | fix | tests |
|---|---|---|---|---|
| PRE-01 | **CONFIRMED** | `get`, `readAttachment`, `put`, `putAttachment`, `reimportUnderNewID`, `exportBackup` inspected manifest/ledger state before the token was validated: an unauthorized caller learned existence (`recordMissing`), state, kind and deletion status (`recordIDDeleted`) from the error type; `exportBackup` burned a generation and read every file first | `AuthorizationValidator.validate` (non-consuming) + `SecureVault.precheckAuthorization` run first; `put` seals (authorizes) before `validateSources`/`duplicateRecordID`; `delete`/`revoke`/`activateRestored`/`admitRestored` already consumed first | NT-PR-01 |
| PRE-02 | **CONFIRMED** (reachable via restored batches) | derived reads checked only direct sources for state/consent and not the deletion ledger | `requireSourcesReadable`: transitive walk; each source active, present, not corrupt, clear in `IdentityPolicy`, consent now | NT-PR-02 |
| PRE-03 | decided | behaviour under untrusted history was implicit | decision table (reconciliation doc §"Decision table") asserted row by row | NT-PR-03 |
| recovery through a damaged chain | ACCEPTED (already fail-closed) | a manifest/ledger contradiction opens read-only (P03-04bH2) and reads refuse | — | NT-GD-06 |

## GATE 2 — production purpose & consent model
`PurposeDefinition`/`PurposeRegistry` (versioned, immutable, `covers`), `ConsentEvent`/`ConsentLedger` (append-only, payload-free, chain), `XRAIPurposes.registryV1()` (five purposes, TR/EN). Store: `system/consent.v1` as `storeMetadata` (bootstrap solved), manifest v3 `consentHash`, `consentWritten` journal rule, `LedgerBinding.verifyConsent`, `StoreConsentAuthority`, `grantConsent`, revocation events inside `revoke`, `mayBackup(.consentReceipts)` denies. Tests NT-CA-01…06 (incl. crash at every syscall of a grant and rollback/missing/unreadable → read-only).

## GATE 3 — InteractionGate
`XRAIVaultInteraction`: private issuer, `mint` (active scene only), `authorize` (≤ 5 s, single use, kind per scope, purpose equality, consumes the proof even on refusal), payload-free trail. App: `SecurityStatus` constructs the gate inline; `runSelfTest` and `ConsentFlow` go through it; `TokenSourceScanTests` forbids direct issuer use. Tests NT-IG-01…06 (replay, expiry, background, wrong scope/purpose, forged/other-gate proof, rogue issuer, 200 parallel, interrupted). **Limit stated verbatim** in the architecture doc, ADR-010 and T53: in-process misuse prevention, not an OS boundary, not proof of human intent. OS user authentication for high-risk operations: evaluated in T53, left as an open decision (`OS_USER_AUTH_HIGH_RISK`), no biometric mandate.

## GATE 4 — consent UX (synthetic state)
`ConsentFlow` + `ConsentView`/`PurposeDetailView`/`ConsentHistoryView`: eight questions per purpose before any grant; grant / revoke+delete / revoke+suspend / delete records / restore suspended as distinct confirmations; third-party classes without suspension; re-grant never reactivates; typing never grants; history without payload; "örnek durum" labelling. Tests NT-UX-01…03 (hosted), NT-UX-07 (XCUI).

## GATE 5 — restore risk UX
`RestoreRiskPresenter` + `RestoreRiskView`: 8/8 risks explained differently; exact-set acknowledgment (button enabled only when equal); `possiblyDeleted`/`untrustedLocalHistory` never activatable, re-import offered; no reset control (labelled "Henüz yok"). Tests NT-UX-04 (hosted), NT-UX-07 (XCUI).

## GATE 6 — accessibility
F-UX-5 **closed**: `XRColor.inputBorder` measured ≥ 3:1 against the input fill, the card and the page background in light and dark (NT-UX-06, attachment `input-boundary-contrast.txt`). F-UX-4: quiet buttons now accent + underline + chevron. Dynamic Type/Reduce Motion: unchanged tokens. XCUI accessibility audits on the three new screens (NT-UX-07). MANUAL_PENDING: human VoiceOver pass, native English review, app-switcher visual, SE-class layout. Full matrix: `P03_05A_PRIVACY_UX_ACCEPTANCE_MATRIX.md`.

## GATE 7 — recovery & performance decision register
`P03_05A_PERFORMANCE_AND_RECOVERY_DECISIONS.md`: ten decisions with invariants and test contracts, provisional budgets for the founder, security-cost table. No grouped-commit optimisation implemented.

## GATE 8 — boundaries kept
No real personal data; `XRAIVaultStore` not linked by the app (docs check); no cloud; no remote AI; no destructive device tests; no release/subscription work; no reset or history erasure.

## GATE 9 — acceptance runs (real results, exit codes)

| run | command | exit | result | log |
|---|---|---|---|---|
| store suite, attempt 1 | `swift test --filter XRAIVaultStoreTests` | 1 | 6 test-expectation issues (state-before-consent order, a stale snapshot in the rollback probe, consumed-token probe design, an extra expected risk); product unchanged by the corrections | `evidence/p03_05a_store_run1_FAIL_6_test_expectations.log` |
| macOS package tests | `swift test` | 1 → 0 → 0 | run 1: 18 issues, all `secureEnclaveUnavailable` in the Keychain provider tests because the Mac screen session was locked (environmental; kept as `…macos_run1_FAIL_secure_enclave_unavailable.log`); run 2 after unlock: 222 tests in 51 suites passed (kept as `…macos_run2_PASS_before_scan_split.log`); run 3 after the NT-IG-05 scan split: 223 tests in 51 suites passed (store, consent, interaction, keychain, scale NT-SC-01) | `evidence/p03_05a_swift_test_macos.log` |
| Simulator hosted + XCUI | `xcodebuild test … 'platform=iOS Simulator,name=iPhone 17'` (whole scheme) | 65 → 65 → 0 → 0 | run 1: hosted 154 tests with 1 issue (smoke self-test needed an active scene for the gate → test adapted) + 3 ConsentUITests failures (value-based NavigationLink destinations not registered on a pushed screen → view-based links), kept as `…sim_all_run1_FAIL_4_issues.log`; run 2: 98 hosted store failures `ioFailed(setprotectionclass, EPERM)` — the Simulator host started refusing `F_SETPROTECTIONCLASS` (never Data Protection evidence; enforcement now compiled for physical iOS only), kept as `…sim_all_run2_FAIL_simulator_protection_EPERM.log`; run 3: hosted 154 tests in 39 suites passed + XCUI 11/11 (kept as `…sim_all_run3_PASS_before_scan_split.log`); run 4 after the scan split: hosted 155 tests in 39 suites (both source scans executed) + XCUI 11/11 (OnboardingUITests 7 + ConsentUITests 4 incl. the three accessibility audits) — exit 0 | `evidence/p03_05a_xcodebuild_sim_all.log` |
| iPhone 14 Pro Max hosted + XCUI, non-destructive | `xcodebuild test … 'platform=iOS,id=C7C6CE6E-…' -allowProvisioningUpdates` (whole scheme) | 65 → 0 | run 1: 2 hosted issues — NT-IG-05 (source-scan half) and NT-UX-05 read the Mac source tree through `#filePath`, which does not exist on a physical iPhone (ENOENT / 0 files); runtime assertions and XCUI 11/11 passed; kept as `…device_all_run1_FAIL_2_issues.log`. Fix: the scan was split out of NT-IG-05 into NT-IG-05b and both scans carry a physical-device `.disabled` trait (reported SKIPPED, never passed; the same rule is enforced statically by the docs check). Run 2: hosted 155 tests in 39 suites passed with the two scans skipped + XCUI 11/11 (OnboardingUITests 7 + ConsentUITests 4 incl. accessibility audits), non-destructive — exit 0 | `evidence/p03_05a_xcodebuild_device_all.log` |
| static: package spec | `python3 -I validation/validate_package.py` | 0 | PASS spec structure; files=5120; does NOT verify an iOS build | `evidence/p03_05a_validate_package.log` |
| static: docs + import boundary + app token-source rule | `python3 -I validation/check_p03_03_docs.py` (+ `StoreModuleBoundaryTests`, `TokenSourceScanTests`) | 0 | PASS: P03-05A deliverables present, 140 NT rows, T44–T53, ADR-010, no `.issue(` in app code, app does not link `XRAIVaultStore` | `evidence/p03_05a_check_docs.log` |

Not run: destructive device scenarios, power loss, human VoiceOver, native English review.

## Files changed (code)
- Contracts: `Consent.swift` (new: purposes, events, ledger, `XRAIPurposes`, `RestoreRisk` moved here), `Authorization.swift` (`validate`, `.grantConsent`), `PrivacyModel.swift` (receipts never in backups).
- CryptoKit: `Authorization.swift` (`AuthorizationIssuer.validate`), `SecureVault.swift` (`precheckAuthorization`).
- Store: `StoreModel.swift` (manifest v3, `consentWritten`, `LedgerBinding.verifyConsent`), `FileVaultStore.swift` (consent persistence + authority, `grantConsent`, revocation events, PRE-01 ordering, PRE-02 transitive), `KeyRetirement.swift` (`consentFile`).
- New target `XRAIVaultInteraction` (`InteractionGate.swift`) + `XRAIVaultInteractionTests`.
- App: `Consent/ConsentFlow.swift`, `Consent/ConsentView.swift`, `Consent/RestoreRiskPresenter.swift`, `Consent/RestoreRiskView.swift` (new); `SecurityStatus.swift` (gate), `XRAIApp.swift` (scene activity), `SelfView.swift` (links), `DesignSystem/Theme.swift` (`inputBorder`), `Components.swift` (quiet button), `Onboarding/OnboardingFlow.swift` (input boundary), `Localizable.xcstrings` (en entries), `project.yml`/`XRAI.xcodeproj` (interaction product; hosted bundle includes the interaction tests).
- Tests: `StoreConsentTests.swift` (new), `ConsentAndInteractionTests.swift` (hosted, new), `ConsentUITests.swift` (XCUI, new), `StoreLedgerBindingTests.swift` (manifest init).

## Remaining blockers (exact)
`CONSENT_UI_SYNTHETIC`, `LEGACY_FACADE_SURFACE`, `OS_USER_AUTH_HIGH_RISK`, `MANUAL_PENDING_P03_05A`, plus the carried P03-04b/bH2 items (attachments in backup, sticky-distrust reset, persisted corrupt state, grouped commit — all DESIGN).

## Implementation SHA
<!-- FINAL-SHA -->

## Exact approval required for P03-05B
1. Independent review accepts ADR-BOOT-010, the PRE-01/PRE-02 fixes and the reconciliation table.
2. Founder decides: `OS_USER_AUTH_HIGH_RISK` (which operations get OS user authentication), `LEGACY_FACADE_SURFACE` (keep or remove the store-less facade), the provisional performance budgets, and whether the P04 design-system gate runs in parallel (`P03_05A_PRODUCT_VISION_RECON.md` §5).
3. Written GO for wiring `FileVaultStore` + `StoreConsentAuthority` + `InteractionGate` into the production composition root for ONE class (`birthDate`, purpose `life_path_calculation`), with the device-tested Keychain provider — still no cloud, no AI egress, no destructive tests.
