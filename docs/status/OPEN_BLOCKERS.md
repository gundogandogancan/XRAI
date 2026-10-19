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
| DEVICE_BACKUP_POLICY | P02 | OPEN_DECISION | ThisDeviceOnly keys (unrecoverable on device loss) vs user-chosen encrypted backup. Needed before vault ADR. |
| JOURNAL_SECURITY | P02 | NOT_VERIFIED | encrypted store engine choice (GRDB/SQLCipher licence) + WAL/temp/backup leak tests on device. |
| PARENT_NAME_SCOPE | P02 | OPEN_DECISION | purpose/retention/third-party consent for optional parent names and sibling order. |
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
