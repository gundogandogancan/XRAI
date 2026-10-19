# Open blockers and decisions (BOOT-00, 2026-10-19)

Vocabulary: `BLOCKED` (cannot proceed without an external fact/right/decision), `OPEN_DECISION` (user/legal choice), `NOT_VERIFIED` (claimable only after a real test), `RESOLVED_TODAY`.

## Resolved today
| id | resolution |
|---|---|
| LOCAL_REPO_STATE (OPEN_DECISIONS_v3.1) | RESOLVED_TODAY: repo rebuilt from scratch; facts in `REPO_FACTS.json`. |
| 16-vs-20 open decision count | RESOLVED_TODAY: `OPEN_DECISIONS_v3.1.json` has 16 records; `historical_v3.0/OPEN_BLOCKERS_v3.json` has 20. The "20" in the first prompt refers to the v3.0 blockers list. Id-level diff: `SOURCE_COVERAGE_AND_TRACEABILITY_AUDIT.md` §8. |
| Toolchain safety for BOOT-01 | RESOLVED_TODAY: Xcode 26.6 / Swift 6.3.3 present; `swift test` exit 0. |
| Tool/skill installs | RESOLVED_TODAY with ledger: 7 repos already installed globally, 3 installed partially/project-local after scan, `clodfarm` rejected, ECC hooks rejected. |
| Components-method ambiguity | RESOLVED_TODAY: ADR-BOOT-004 / Amendment A1. |

## Blocking the next phases (unchanged from v3.1, restated with current gate)
| id | gate | status | what is needed |
|---|---|---|---|
| IPHONE_TEST | P02 | NOT_VERIFIED | a physical iPhone + developer signing to test vault, model, thermals. |
| DEVICE_BACKUP_POLICY | P02 | RESOLVED 2026-10-19 (founder decisions 3–4) | Optional user-held 256-bit recovery key + E2EE portable backup; fresh device keys on restore; loss of both = unrecoverable, stated plainly. Implemented at library level (ADR-BOOT-005). |
| JOURNAL_SECURITY | P02 | NOT_VERIFIED | encrypted store engine choice (GRDB/SQLCipher licence) + WAL/temp/backup leak tests on device. Envelope layer exists (ADR-BOOT-005); persistence layer NOT_STARTED. |
| KEYCHAIN_PROVIDER | P02-02 | CODED + TESTED (macOS host) | `KeychainKeyProvider` + Secure Enclave wrapping exist (ADR-BOOT-006). DEVICE_VERIFIED: NO. |
| DEVICE_TESTS_KEYCHAIN_SE | P02-02+ | PARTIAL 2026-10-20 | create/read/rotate/retire/forget/wipe, SE wrapping, cache, serialization VERIFIED on iPhone 14 Pro Max (non-destructive). Still NOT_RUN: lock/unlock behaviour, passcode removal, reinstall — need a dedicated test device + explicit approval. |
| ROTATION_CROSS_PROCESS | P02+ | BLOCKED | keychain rotation sequence is not a CAS; in-process serialized; app extensions must never rotate (main-app ownership rule) until a cross-process mechanism exists. |
| FORGET_REQUIRES_STORE_PROOF | pre-persistence | BLOCKED | without a store there is no proof every record was re-wrapped before `forget`; the store layer must produce it. |
| XCODEGEN_PRESETS_MISSING | tooling | NOTE | installed xcodegen lacks SettingPresets; all defaults are explicit in project.yml; re-check when xcodegen is reinstalled. |
| SIM_HOST_APP | P03-00 | RESOLVED_TODAY | `XRAI.xcodeproj` app target + `XRAIHostedTests` (TEST_HOST) run the Keychain tests on the iPhone 17 Simulator: 20/20. |
| DEVICE_TRUST_AND_RUN | P03-00F | RESOLVED 2026-10-20 — the real cause was a missing rpath (packaging), not trust; app launches and 24/24 hosted tests pass on iPhone 14 Pro Max. Original note kept for history: | iPhone 14 Pro Max 'Dogi (2)': signing/provisioning OK, app installed, runner crashed at launch. Founder must unlock the phone, approve the developer profile (Settings › General › VPN & Device Management) / Developer Mode, keep it unlocked, then rerun `xcodebuild test … -destination 'platform=iOS,id=C7C6CE6E-B577-558A-8992-DC6C1F492B39' -allowProvisioningUpdates`. Destructive scenarios (reinstall, passcode removal) need a dedicated test device and explicit approval. |
| SIM_SE_IS_HOST_MAC | note | — | On Apple-silicon Macs the Simulator proxies the host's Secure Enclave; simulator SE results are NOT iPhone hardware evidence. |
| REINSTALL_KEY_POLICY | P03 | DESIGN | on fresh install with no store: adopt key set explicitly or `wipeAllKeys()`; user told that device-only keys need the recovery-key backup. |
| APP_ICON_AND_LAUNCH | P03-01 | RESOLVED_TODAY | AppIcon, LaunchLogo/LaunchBackground, tr/en string catalog. |
| UX_POLISH_P03_02 | P03-02 | OPEN | F-UX-1 skip link below the fold at accessibility sizes; F-UX-2 floating tab bar overlaps last card; F-UX-3 trace date wraps; automated contrast/a11y gates; VoiceOver + Reduce Motion manual checklist; English proofreading; SE/landscape layouts. |
| ONBOARDING_FLAG_IN_DEFAULTS | pre-persistence | NOTE | the only persisted value is the non-personal onboarding flag in UserDefaults (test-asserted); moves to a preferences layer with the vault store. |
| AUTHZ_ISSUER_UI_BINDING | pre-persistence | OPEN | `AuthorizationIssuer.issue()` must be callable only from trusted user-interaction paths; no integration proves tokens come from real user actions yet. |
| DELETION_GRANT_VALIDATION | pre-persistence | OPEN | store layer must validate/consume `DeletionGrant`. |
| VAULT_SECURITY_REVIEW | P02/P12 | NOT_DONE | independent review/pen test before any 'vault complete' claim. ChatGPT code review round 1 (V32-02-01H) applied: 5 findings closed, see P02_01H report. |
| CONSENT_AUTHORITY_IMPL | P02+ | NOT_STARTED | production consent registry behind the `ConsentAuthority` port (encrypted store, audit trail, UI). |
| AUTHZ_PERSISTENCE | P02+ | NOT_STARTED | persist the monotonic clock high-water mark and consumed-token ids (currently per process). |
| IN_PROCESS_ISOLATION | P02-02+ | PARTIAL | SE-wrapped KEK means the Keychain item alone is useless, but in-process code can still call the provider; app hardening and review remain. |
| BACKUP_SIZE_SIDECHANNEL | P02+ | PARTIAL | 4 KiB block padding only; bucketed padding once backup cadence is designed. |
| PARENT_NAME_SCOPE | P02 | RESOLVED 2026-10-19 (founder decision 6) | Optional; purpose-bound consent required to store; never analytics/model/cloud/ads. Encoded in `VaultPolicy` and tested. |
| APPLE_ACCOUNT | P11 | NOT_VERIFIED | Apple Developer account, bundle id, entitlements, privacy labels. |
| STOREKIT_REAL_PRICE | P11 | OPEN_DECISION | user said: paid subscription, model to be chosen later. No price may be hard-coded; $5.55/$49.99 in §48 is a hypothesis only. |
| EPHEMERIS_RIGHTS | P08 | BLOCKED | Swiss Ephemeris AGPL vs professional licence vs alternative; nothing installed. |
| HD_METHOD_COMPLETENESS / HD_TRANSLATION_COPYRIGHT | P09 | BLOCKED | gate-wheel order/anchor, −88° solver reference values, channel/center/type tables from rights-clear independent sources; book scans are private study only and not fully read. |
| PSYCHOLOGICAL_INSTRUMENT | P07 | BLOCKED | no licensed Big Five/16-type instrument; original non-diagnostic items need psychometric review. |
| BOW_FULL_COVERAGE | P10 | BLOCKED | Book of Wisdom not acquired/licensed. |
| CLOUD_CONSENT_LEGAL / LOCAL_ML_TURKISH | P06 | NOT_VERIFIED | no model benchmarked; no provider contract. |
| COLLECTIVE_RESEARCH_RIGHTS | P13 | BLOCKED | no opt-in rights-clean dataset. |
| FUTURE_CHILD_SAFETY | FUTURE | OPEN_DECISION | AHTOVIA boundary; not in scope. |

## New today
| id | status | detail |
|---|---|---|
| GITHUB_REMOTE_REWRITE | RESOLVED_TODAY | Force-pushed over `origin/main` via SSH (`git@github.com:gundogandogancan/xrai.git`): old head `fb502a6` replaced by `6b3fcae`. HTTPS had no stored credential; first SSH push was rejected by GitHub email-privacy, so the commit author uses the GitHub noreply address. Old content is gone from the remote. |
| SUBSCRIPTION_MODEL | OPEN_DECISION | monthly/annual/lifetime, free tier boundary, regional pricing; to be decided before P11 with real App Store Connect data. |
| SOURCE_COVERAGE_GAPS | see `SOURCE_COVERAGE_AND_TRACEABILITY_AUDIT.md` and `MISSING_REQUIREMENTS_REGISTER.json` | requirements found in older material without a v3.1 id. |
| SWIFTLINT_FORMAT | low | not installed; optional for P03. |
