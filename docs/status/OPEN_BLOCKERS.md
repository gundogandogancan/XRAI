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
| JOURNAL_SECURITY | P02 | DESIGN_RESOLVED 2026-10-20 (P03-03), NOT_VERIFIED | engine chosen: record-per-file envelopes + encrypted manifest, no SQLCipher (ADR-BOOT-009 D1, PROPOSED); WAL/temp/backup leak tests belong to P03-04 on device. Persistence layer NOT_STARTED. |
| KEYCHAIN_PROVIDER | P02-02 | CODED + TESTED (macOS host) | `KeychainKeyProvider` + Secure Enclave wrapping exist (ADR-BOOT-006). DEVICE_VERIFIED: NO. |
| DEVICE_TESTS_KEYCHAIN_SE | P02-02+ | PARTIAL 2026-10-20 | create/read/rotate/retire/forget/wipe, SE wrapping, cache, serialization VERIFIED on iPhone 14 Pro Max (non-destructive). Still NOT_RUN: lock/unlock behaviour, passcode removal, reinstall — need a dedicated test device + explicit approval. |
| ROTATION_CROSS_PROCESS | P02+ | BLOCKED | keychain rotation sequence is not a CAS; in-process serialized; app extensions must never rotate (main-app ownership rule) until a cross-process mechanism exists. |
| FORGET_REQUIRES_STORE_PROOF | pre-persistence | PROTOCOL v2 SPECIFIED 2026-10-20 (P03-03H H2), still BLOCKED until P03-04 | freeze `minimumWrapVersion`, journaled rewrap incl. system envelopes, full inventory digest, three-way cross-check, proof bound to manifest generation + exclusive section, retire+forget in one section. Closes only with NT-H2-01…09. |
| XCODEGEN_PRESETS_MISSING | tooling | NOTE | installed xcodegen lacks SettingPresets; all defaults are explicit in project.yml; re-check when xcodegen is reinstalled. |
| SIM_HOST_APP | P03-00 | RESOLVED_TODAY | `XRAI.xcodeproj` app target + `XRAIHostedTests` (TEST_HOST) run the Keychain tests on the iPhone 17 Simulator: 20/20. |
| DEVICE_TRUST_AND_RUN | P03-00F | RESOLVED 2026-10-20 — the real cause was a missing rpath (packaging), not trust; app launches and 24/24 hosted tests pass on iPhone 14 Pro Max. Original note kept for history: | iPhone 14 Pro Max 'Dogi (2)': signing/provisioning OK, app installed, runner crashed at launch. Founder must unlock the phone, approve the developer profile (Settings › General › VPN & Device Management) / Developer Mode, keep it unlocked, then rerun `xcodebuild test … -destination 'platform=iOS,id=C7C6CE6E-B577-558A-8992-DC6C1F492B39' -allowProvisioningUpdates`. Destructive scenarios (reinstall, passcode removal) need a dedicated test device and explicit approval. |
| SIM_SE_IS_HOST_MAC | note | — | On Apple-silicon Macs the Simulator proxies the host's Secure Enclave; simulator SE results are NOT iPhone hardware evidence. |
| REINSTALL_KEY_POLICY | P03 | SPECIFIED 2026-10-20 (P03-03 D10) | keys present but no manifest → wipe-or-restore prompt, never silent reuse; test N16 PLANNED. |
| APP_ICON_AND_LAUNCH | P03-01 | RESOLVED_TODAY | AppIcon, LaunchLogo/LaunchBackground, tr/en string catalog. |
| UX_POLISH_P03_02 | P03-02 | RESOLVED_TODAY (partially) | F-UX-1/2/3 fixed and asserted; contrast + a11y gates automated; Reduce Motion run; English agent-proofread. Still open: F-UX-4 quiet-button affordance, SE-class layout (no simulator), native English review, human VoiceOver pass (MANUAL_PENDING), app-switcher snapshot visual check. |
| TABBAR_CONTRAST_AUDIT | known limitation | NOTE | iOS 26 translucent floating tab bar blends scrolled content; XCUI `.contrast` audit excluded on tab screens; token pairs measured separately. |
| ONBOARDING_FLAG_IN_DEFAULTS | pre-persistence | NOTE | the only persisted value is the non-personal onboarding flag in UserDefaults (test-asserted); moves to a preferences layer with the vault store. |
| AUTHZ_ISSUER_UI_BINDING | pre-persistence | SPECIFIED 2026-10-20 (P03-03 D7), OPEN until P03-05 | `InteractionGate` + `InteractionProof` minted only inside consent/confirm action closures (scene active, 5 s, single use); `issue()` leaves the public surface. In-process limit stated (INTERACTION_PROOF_LIMIT). |
| DELETION_GRANT_VALIDATION | pre-persistence | SPECIFIED 2026-10-20 (P03-03 D3), OPEN until P03-04 | `VaultStore.delete(ids, grant)` consumes the grant, runs the journaled cascade and writes tombstones. |
| VAULT_SECURITY_REVIEW | P02/P12 | NOT_DONE | independent review/pen test before any 'vault complete' claim. ChatGPT code review round 1 (V32-02-01H) applied: 5 findings closed, see P02_01H report. |
| CONSENT_AUTHORITY_IMPL | P02+ | SPECIFIED 2026-10-20 (P03_03_CONSENT_AUTHORITY_SPEC), NOT_STARTED | purpose registry, versioned receipts, payload-free events, persisted in the vault; UI in P03-05. |
| AUTHZ_PERSISTENCE | P02+ | RE-SPECIFIED 2026-10-20 (P03-03H H3), NOT_STARTED | persisted epoch (launch/restore increments), token id = epoch‖counter‖random, journal-bound consumption, `authz.v1` never exported, clock mark bound to manifest generation + Keychain anchor; the 10 000 ring is withdrawn. Tests NT-H3-01…07 PLANNED. |
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

## New in P03-03 (2026-10-20, design only)
| id | status | detail |
|---|---|---|
| PERSISTENCE_ADR_REVIEW | AWAITING_REVIEW | ADR-BOOT-009 (file-based envelope store, SQLCipher deferred) is PROPOSED; P03-04 starts only after acceptance. |
| DERIVED_DATA_GRAPH | SPECIFIED, NOT_STARTED | `derivedFrom[]` in authenticated header v3 + manifest reverse index; cascade/invalidation rules in P03_03_DATA_LIFECYCLE_MATRIX §2; tests N13 PLANNED. |
| TOMBSTONE_RESURRECTION_WINDOW | SUPERSEDED 2026-10-20 (P03-03H H1) | the 90-day window is withdrawn; replaced by DELETION_LEDGER_PERMANENT and DELETION_HISTORY_AFTER_DEVICE_LOSS. |
| INTERACTION_PROOF_LIMIT | LIMIT | the interaction proof is in-process, not an OS boundary; malicious in-process code can forge it. Mitigations: code signing, sandbox, SE keys, optional biometrics (deferred, UX decision). |
| INPUT_FIELD_BOUNDARY_CONTRAST | OPEN (F-UX-5) | WCAG 2.2 SC 1.4.11: text-input boundary measures 1.17:1 light / 1.11:1 dark against the surface, below the 3:1 non-text requirement; needs an `inputBorder` token ≥ 3:1 asserted by `ContrastTests`. The 1.3:1 border threshold is an internal decorative minimum, not an SC claim (P03_03_ARCHITECTURE_GATE_REPORT §4). |
| DELETION_LEDGER_PERMANENT | SPECIFIED (P03-03H H1), NOT_STARTED | permanent, encrypted, cross-bound deletion ledger; fail-closed digest compaction above 200 000 entries; missing/corrupt → all restores quarantined; known-deleted ids never reactivated. |
| DELETION_HISTORY_AFTER_DEVICE_LOSS | LIMIT | with only an old portable backup, deletions made after its export are unknowable; restored records are quarantined and reviewed per class; no absolute-forgetting claim. |
| MANIFEST_ROLLBACK_ANCHOR | SPECIFIED (P03-03H H5), NOT_STARTED | generation chain + mutual bindings + Keychain anchor `vault/anchor`; mismatch → read-only, no restore. LIMIT: compromised OS. |
| SINGLE_WRITER_LOCK_ADVISORY | LIMIT | `vault.lock` is advisory; isolation is the actor + main-app-only rule; extensions never link the store (test-enforced in P03-04). |
| REVOKE_VS_DELETE_SPLIT | SPECIFIED (P03-03H H4), NOT_STARTED | distinct scopes; "Kalıcı sil" immediate; suspension only on explicit choice for grace-eligible own-authored classes; re-grant never reactivates. |
| F_UX_5_GATE | MANDATORY for next UX phase | `ContrastTests` must assert `inputBorder` vs surface ≥ 3.0:1 light and dark before that phase is TESTED. |
| P03_02_OPEN_FINDINGS | OPEN (unchanged) | F-UX-4, SE-class layout, human VoiceOver (MANUAL_PENDING), native English review, app-switcher snapshot visual check (MANUAL_PENDING), full device regression with the final build, tab-bar contrast exception. |
