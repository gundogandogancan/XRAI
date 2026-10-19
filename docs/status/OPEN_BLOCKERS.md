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
| DEVICE_TESTS_KEYCHAIN_SE | P02-02+ | NOT_RUN | physical iPhone: ThisDeviceOnly semantics, lock/unlock, passcode removal, reinstall, SE on A-series. Requires signing + device. |
| SIM_HOST_APP | P03 | NOT_STARTED | signed host app so Keychain tests can run on the iOS Simulator (host-less bundles get errSecMissingEntitlement). |
| REINSTALL_KEY_POLICY | P03 | DESIGN | on fresh install with no store: adopt key set explicitly or `wipeAllKeys()`; user told that device-only keys need the recovery-key backup. |
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
