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
| JOURNAL_SECURITY | P02 | CODED + TESTED (library, P03-04) | `FileVaultStore` (record-per-file envelopes, encrypted manifest/ledger/authz, no SQLite); directory hygiene, padding, Data Protection attribute (iOS hosts) tested. App NOT wired; no real data. Remaining: on-device audit under lock/unlock, independent review. |
| KEYCHAIN_PROVIDER | P02-02 | CODED + TESTED (macOS host) | `KeychainKeyProvider` + Secure Enclave wrapping exist (ADR-BOOT-006). DEVICE_VERIFIED: NO. |
| DEVICE_TESTS_KEYCHAIN_SE | P02-02+ | PARTIAL 2026-10-20 | create/read/rotate/retire/forget/wipe, SE wrapping, cache, serialization VERIFIED on iPhone 14 Pro Max (non-destructive). Still NOT_RUN: lock/unlock behaviour, passcode removal, reinstall — need a dedicated test device + explicit approval. |
| ROTATION_CROSS_PROCESS | P02+ | BLOCKED | keychain rotation sequence is not a CAS; in-process serialized; app extensions must never rotate (main-app ownership rule) until a cross-process mechanism exists. |
| FORGET_REQUIRES_STORE_PROOF | pre-persistence | CODED + TESTED (library, 2026-10-20, P03-04) | `prepareRetirement`/`forgetRetired`/`retireKey` implement protocol v2; `KeyRetirementVerifier` recomputes the inventory independently; NT-H2-01…09 TESTED on macOS (see matrix). Not SECURITY_REVIEWED; not exercised with the production Keychain provider on device beyond the anchor test. |
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
| DELETION_GRANT_VALIDATION | pre-persistence | CODED + TESTED (P03-04) | `FileVaultStore.delete(_:grant:)` validates coverage, consumes the grant once (`deletionGrantInvalid` on reuse), cascades dependents-first, ledgers every id (NT-H4-01, NT-DG-01). |
| VAULT_SECURITY_REVIEW | P02/P12 | NOT_DONE | independent review/pen test before any 'vault complete' claim. ChatGPT code review round 1 (V32-02-01H) applied: 5 findings closed, see P02_01H report. |
| CONSENT_AUTHORITY_IMPL | P02+ | SPECIFIED 2026-10-20 (P03_03_CONSENT_AUTHORITY_SPEC), NOT_STARTED | purpose registry, versioned receipts, payload-free events, persisted in the vault; UI in P03-05. |
| AUTHZ_PERSISTENCE | P02+ | CODED + TESTED (P03-04) | `authz.v1` {epoch, clock mark, manifest binding}; `AuthorizationIssuer(epoch:)`; `MonotonicGuardClock(initialHighWaterSeconds:)`; NT-H3-01…07 TESTED. LIMIT: a rollback beyond tolerance fails closed (vault opens, tokens/reads refuse) until the clock is sane. |
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

## New in P03-05A (2026-10-20, consent, interaction & trusted UX foundation — library + synthetic UI)
| id | status | detail |
|---|---|---|
| PRE_01_AUTHORIZATION_ORDERING | RESOLVED (CONFIRMED → CODED + TESTED) | read/write/re-import/export APIs inspected state before validating the token; now `SecureVault.precheckAuthorization` (non-consuming) runs first; `put` seals first (NT-PR-01). |
| PRE_02_TRANSITIVE_SOURCES | RESOLVED (CONFIRMED → CODED + TESTED) | derived reads now walk `derivedFrom` transitively (active, present, clear, consented) (NT-PR-02). |
| PRE_03_UNTRUSTED_HISTORY_TABLE | DECIDED + TESTED | decision table in `P03_05A_CANONICAL_RECONCILIATION.md`; asserted by NT-PR-03. |
| CONSENT_BOOTSTRAP | RESOLVED | consent events are store system state (`system/consent.v1`, manifest v3 `consentHash`, `consentWritten` journal rule); storing a grant never needs a prior consent (NT-CA-03…05). |
| CONSENT_RECEIPTS_IN_BACKUP | RESOLVED (policy) | `mayBackup(.consentReceipts)` denies; a new device asks again (NT-CA-06). |
| INTERACTION_GATE | CODED + TESTED (in-process) | `XRAIVaultInteraction`; app code cannot call the issuer (NT-UX-05); limit stated verbatim in T53. |
| INPUT_FIELD_BOUNDARY_CONTRAST (F-UX-5) | **CLOSED** | `XRColor.inputBorder` ≥ 3:1 vs fill, card and background in both appearances (NT-UX-06, attachment). |
| F_UX_4_QUIET_BUTTON | RESOLVED (automated) · human judgement MANUAL_PENDING | accent + underline + chevron, 44pt. |
| CONSENT_UI_SYNTHETIC | BY DESIGN until P03-05B | the consent and restore-risk screens run on in-memory synthetic state; the composition root still uses `NoConsentAuthority` and no store; `SecurityStatus.consentRegistryImplemented` stays false. |
| LEGACY_FACADE_SURFACE | OPEN DECISION (P03-05B) | `SecureVault.releaseQuarantine` and the v2 `exportBackup` remain as store-less P02 APIs; decide whether the store-less facade is a supported surface or is removed. |
| OS_USER_AUTH_HIGH_RISK | OPEN DECISION (threat model T53) | `LAContext`/SE user presence for export, delete-all, retire key, history reset — evaluate with UX; no biometric mandate without evidence. |
| DESIGN_TOOLING_AUTHORIZATION | RECORDED (founder, 2026-10-20) | Figma connector + Claude design skills authorised for P04+ design phases; ADR-BOOT-011 to be written at P04 start; not used in P03-05A (`P03_05A_PRODUCT_VISION_RECON.md`). |
| SIMULATOR_PROTECTION_CLASS_EPERM | KNOWN_LIMITATION (recorded 2026-10-20) | during the P03-05A Simulator run the host began refusing `F_SETPROTECTIONCLASS` with EPERM (98 hosted store failures, log kept); the Simulator never provided Data Protection evidence, so the descriptor-class enforcement is now compiled for physical iOS only (`#if os(iOS) && !targetEnvironment(simulator)`); device assertions (NT-FS-04, NT-H5-16) unchanged. |
| MANUAL_PENDING_P03_05A | MANUAL_PENDING | human VoiceOver pass, native English review of the new strings, visual app-switcher check, SE-class layout (no simulator). |

## New in P03-04bH2 (2026-10-20, global deletion invariant & write-path security gate)
| id | status | detail |
|---|---|---|
| F_P04BH_01_DELETED_ID_RECREATED | RESOLVED (reproduced, then CODED + TESTED) | `put`/`putAttachment` checked only `manifest.records[id] == nil`; a deleted id was re-created and survived reopen (repro log kept). `IdentityPolicy` is now the single source: `.deleted` → `recordIDDeleted`, `.possiblyDeleted` → `possiblyDeletedForever`, unprovable history → `deletionHistoryUntrusted`, at every entry point incl. journal replay, recovery reconciliation and reads (NT-GD-01…07). |
| RELEASE_QUARANTINED_REMOVED | RESOLVED (GATE 4) | no production flow could use it (every quarantined manifest entry is a restored record; activation goes through `activateRestored` / `reimportUnderNewID`); removed, compile-negative. The facade-level `SecureVault.releaseQuarantine` (registry only, P02) stays for the store-less API and is unchanged. |
| UNTRUSTED_HISTORY_BLOCKS_CREATION | BY DESIGN (fail closed) | with sticky distrust, `put`/`putAttachment`/activation refuse (`deletionHistoryUntrusted`); reads, deletes, export and re-import under new ids still work. Needs the user-confirmed reset design below. |

### Performance & recovery debt register (GATE 5 — scoped, not started; no durability-reducing optimisation in this phase)
| item | scope | evidence | proposed next negative tests |
|---|---|---|---|
| FSYNC_COST | ≈10 `F_FULLFSYNC` per mutation: ≈84 ms/put macOS, ≈130 ms/put iPhone, ≈20 ms per admitted file on iPhone (NT-SC-01) | `evidence/p03_04b_*` | measure per-step flush counts with the fault injector's op log; assert the count never drops below the contract |
| BATCH_ADMISSION_GROUPED_COMMIT | feasibility: write N temp files, one `F_FULLFSYNC` per file is required for content durability, but the directory flush and the journal rewrites can be grouped per batch (one journal rewrite per k files, one dirsync per batch); keep all-or-nothing semantics | design only | crash at every syscall of a grouped batch → all-or-nothing; power-loss simulation by dropping un-flushed writes in the test file system |
| STICKY_DISTRUST_RESET | user-confirmed `resetDeletionHistory(acknowledgement:)`: new `.resetHistory` scope + InteractionProof (P03-05), journaled, writes a new empty ledger bound to the manifest and clears the flag, records an audit event; until then: fail closed | design only | reset without proof refused; reset is journaled and crash-safe; after reset, old backups' ids are `legacyFormat`-style risks, never silently active |
| PERSISTED_CORRUPT_STATE | manifest entry state `.corrupt` persisted by a journaled mutation when AEAD fails (today in-memory); export refuses corrupt entries with a typed error; the user can delete them | design only | corrupt mark survives reopen; delete of a corrupt record works; export lists them |
| ATTACHMENTS_IN_BACKUP | streamed backup container (chunked body, bounded memory) so attachments ≤ 64 MiB can travel; `excludedAttachmentCount` keeps the gap visible until then | design only | restore with a truncated container; attachment chunk missing in the container; memory bound during restore |
| DATA_LOSS_ROLLBACK_DURABILITY_SUITE | next-phase negative-test design: (1) rollback of every system file individually and in pairs, (2) write loss simulation (test FS drops writes after a cut-off, i.e. power-loss model), (3) resource exhaustion (ENOSPC / EMFILE injected at every step), (4) directory-entry and journal-size limits, (5) clock rollback during recovery | design only | each → read-only or clean replay; never partial state; never resurrection |

## New in P03-04bH (2026-10-20, restore identity, authorization & deletion integrity gate)
| id | status | detail |
|---|---|---|
| F_P04B_01_BLOOM_RESURRECTION | RESOLVED (CODED + TESTED) | `activateRestored` and `releaseQuarantined` refuse any id whose deletion evidence is compacted (`possiblyDeletedForever`); `reimportPossiblyDeleted` (new scope `.reimport(recordID:)`, `SecureVault.reimport`) re-encrypts under a NEW id and deletes the old id exactly. Found on the way: `DeletionLedger.append` skipped ids that only hit the digest, so a re-deletion never became exact evidence — fixed (NT-BH-01). |
| F_P04B_02_UNAUTHORIZED_ENVELOPE_WRITE | RESOLVED (CODED + TESTED) | `putEnvelope` removed from the production surface (compile-negative); writes = `put`/`putAttachment` (full `SecureVault.seal` checks) or verified admission (the facade re-wraps and re-verifies every payload). No trusted-migration seam exists; if migration is ever needed it must be a new, reviewed facade path (NT-BH-03). |
| F_P04B_03_VERIFIED_PROVENANCE | RESOLVED (CODED + TESTED; in-process boundary) | `RestoreResult.verificationSeal` = HMAC over provenance + entries + reasons under a per-facade random key; `SecureVault.isVerified`; admission requires it; history merges only from verified results; legacy v2 stays verified with its explicit risk (NT-BH-04). LIMIT: the seal binds results to the facade instance in this process — not an OS boundary. |
| REIMPORT_DEPENDENCY_MIGRATION | LIMIT (refused, not implemented) | a possibly-deleted record that other records derive from cannot be re-imported until those dependents are deleted (NT-BH-02). Rewriting authenticated `derivedFrom` edges would require re-sealing dependents; deferred with evidence. |
| QUARANTINE_REGISTRY_RELEASE_ON_REPLAY | RESOLVED (found by NT-BH-09) | an activation committed by journal replay left the in-memory registry entry; recovery now mirrors the manifest both ways (untrusted-journal ids stay quarantined and are flagged `needsRecovery`). |
| EXACT_RISK_ACKNOWLEDGMENT | RESOLVED | `isSubset` → exact set equality, matching the documented UX contract (NT-BH-06). |
| ATTACHMENT_READ_SINGLE_DESCRIPTOR | RESOLVED (mitigation) | both passes read one open descriptor; a path substitution mid-read cannot change the delivered bytes (NT-BH-07). In-place writes by a same-UID process remain out of model (every chunk is still authenticated in pass 2). |
| INCOMPLETE_BACKUP_FLAG | RESOLVED | `excludedAttachmentCount` travels inside the sealed body (schema 2); importers stage with `attachmentsMissing` (NT-BH-08). |
| STALE_KEY_ADMISSION_GUARD_UNREACHABLE | NOTE | the `staleKeyVersion` guard in admission is unreachable through the verified path (the facade re-wraps under the current key); kept as defense in depth, like NT-H2-01. |

## New in P03-04b (2026-10-20, backup integrity, restore reconciliation, attachments — library)
| id | status | detail |
|---|---|---|
| LEDGER_ONLY_ROLLBACK | RESOLVED (CODED + TESTED, P03-04b GATE 1) | journal v2: every begin entry carries the ledger hash the manifest binds (pre-state); the post-state hash is announced in the journal BEFORE the ledger file is replaced; `LedgerBinding.verify` accepts the disk ledger only as that pre-state or that announced post-state, binds the journal to the persisted epoch and generation; anything else → read-only, never replayed (NT-LR-01…05, 08). |
| LEDGER_CORRUPT_LAUNDERING | RESOLVED (found in the GATE 1 audit) | an AEAD-corrupt ledger used to be rebuilt from an empty history by the next delete and trusted again after relaunch. Now `Manifest.ledgerHistoryTrusted` is sticky-false, a corrupt ledger with a pending journal opens read-only, and an export from such a vault carries `deletionHistoryTrusted = false` which importers never merge (NT-LR-06/07, NT-BK-06). Resetting the flag needs an explicit user-confirmed operation that does not exist yet (P03-05+). |
| BACKUP_BODY_V3 | RESOLVED (CODED + TESTED, P03-04b GATE 2) | `BackupBodyV3` (schema 1): instance id, backup generation, source manifest generation + hash, embedded deletion history + SHA-256 + trust flag; `SealedBackup` v3 with separate HKDF contexts; v2 accepted as LEGACY only; v1/unknown refused; `FileVaultStore.exportBackup` burns the generation durably before sealing (NT-BK-01…08). |
| RESTORE_TWO_PHASE | RESOLVED (CODED + TESTED, P03-04b GATE 3) | `admitRestored` stages everything quarantined with persisted `RestoreRisk` flags; `activateRestored` needs the exact acknowledgment, re-checks deletion/sources/consent/scope; `releaseQuarantined` refuses restored records; admission replay is all-or-nothing (NT-RR-01…14). UI for the risk screen is P03-05. |
| ATTACHMENTS | RESOLVED (CODED + TESTED, P03-04b GATE 4) | `attachments/<id>.att` = header record envelope + AEAD chunks (1 MiB, ≤ 64 MiB), nonce prefix ‖ index, AAD binds layout; streamed write/read with bounded memory; verify pass before delivery; cascade, retirement, recovery, limits (NT-AT-01…11). |
| ATTACHMENTS_NOT_IN_BACKUP | DEFERRED (next library step) | v3 export excludes attachment records; a restored parent comes back without its attachments (NT-AT-11). Needs a streamed backup container (the whole-backup-in-memory limit forbids 64 MiB attachments in the current body). |
| RESTORE_WHOLE_BACKUP_IN_MEMORY | LIMIT (unchanged) | export and restore hold the whole sealed body in memory (≤ 256 MiB, enforced). Streaming is the same work item as attachments-in-backup. |
| ATTACHMENT_READ_TWO_PASS | LIMIT (by design) | every read authenticates all chunks before delivering any plaintext → 2× AES-GCM work (64 MiB: see review numbers). |
| HISTORY_DIGEST_GEOMETRY | LIMIT | two compacted Bloom digests with different geometry cannot be merged; such a backup is staged with `unmergedBackupHistory` (exact entries still merge). |
| OLDER_GENERATION_REACHABILITY | NOTE | an older `backupGeneration` of our own instance can only stage records when local history was lost (otherwise their ids are deleted or existing); covered at unit level with a caller-built provenance (NT-BK-05). |
| QUARANTINE_REASON_AT_REOPEN | RESOLVED (minor) | the in-memory quarantine registry is rebuilt from the manifest at open; restored entries are re-registered with `pendingUserConfirmation`, others with `consentRequired`. |
| CORRUPT_STATE_IN_MEMORY | OPEN (carried; not in the P03-04b directive) | still in-memory only. |

## New in P03-04H (2026-10-20, filesystem atomicity & durability gate after independent review)
| id | status | detail |
|---|---|---|
| F_P04_01_EXCLUSIVE_CREATE | RESOLVED (CODED + TESTED, P03-04H) | iOS `openExclusive` used `FileManager.createFile` + `open(O_TRUNC)` (non-exclusive, truncating, symlink-substitutable). Now one `O_CREAT\|O_EXCL\|O_NOFOLLOW` open on every platform with descriptor verification and class A applied/verified on the empty descriptor (NT-FS-01…05). |
| F_P04_02_DIRSYNC_RESULT | RESOLVED (CODED + TESTED, P03-04H) | `syncDirectory` ignored the fallback `fsync` result and `sync` fell back on ANY `F_FULLFSYNC` error. Now typed `ioFailed`, fallback only for ENOTSUP/ENOTTY/EINVAL, EINTR handled, every mutating result checked (NT-FS-06…08). |
| MUTATION_FAILS_CLOSED | RESOLVED (CODED + TESTED, P03-04H) | an error inside a journaled mutation left the instance writable on in-memory state that could diverge from disk (a committed op dropped by the next manifest write; a half-delete whose journal the next mutation overwrote → records neither in manifest-consistent state nor in the ledger). Now `.readOnly("mutation interrupted: reopen required")`, reads/writes refused, reopen replays (NT-FS-08, NT-FS-12). |
| LEDGER_ONLY_ROLLBACK (P03-04H entry) | SUPERSEDED — fully RESOLVED in P03-04b GATE 1 (see above) | an authentic older ledger under a newer manifest is now read-only. If a ledger rollback coincides with a pending delete journal, replay re-adds the op's ids to the rolled-back ledger and the manifest rebinds to it. Closing it needs the journal begin entry to carry the pre-op ledger hash (format change → P03-04b candidate). |
| LOCK_BEFORE_CLEANUP | RESOLVED (NT-FS-11) | the loader removed `.tmp-*` files (and, with no manifest, every record/system/journal file) before taking the writer lock; a locked-out opener could delete a live writer's in-flight temp. Lock first now. |
| ADMISSION_ALL_OR_NOTHING | RESOLVED (NT-FS-10) | the frozen-version check ran per envelope inside the journaled body; a refusal mid-batch left earlier files on disk and the journal replayed them. Checks now run before the journal begins. |
| PID_REUSE_LOCK | PLAUSIBLE RISK (availability) | `vault.lock` staleness = pid dead or epoch behind; a reused pid of an unrelated live process keeps the lock "live" → `storeLocked` until that process exits. Not an integrity risk; iOS runs one app process. |
| DIRECTORY_FSYNC_SEMANTICS | LIMIT (unsupported guarantee) | `F_FULLFSYNC` on directory descriptors returns 0 on macOS, Simulator and iPhone (NT-FS-07) but Apple documents neither directory-fsync semantics on APFS nor that every storage honours the flush. No power-cut rig exists; nothing here claims power-loss survival beyond "every documented step taken and verified". |
| PROTECTION_CLASS_NUMERIC | LIMIT (verified empirically) | the value 1 for NSFileProtectionComplete is from XNU's `sys/fcntl.h` private section (the fcntl commands are public). Verified on the physical iPhone through `FileManager` (NT-FS-04); the Simulator stores the attribute but reports no class (KNOWN_LIMITATION). |
| SAME_UID_TOCTOU | OUT OF MODEL (documented) | `removeIfOwned` (lstat→unlink) and `excludeFromBackup` (lstat root → URL resource) have path-based windows; an attacker able to write inside the app container already holds the data. Reads/creates themselves are descriptor-based (`O_NOFOLLOW`, `fstat`). |
| CORRUPT_STATE_IN_MEMORY | OPEN (unchanged) | see P03-04 section. |

## New in P03-04 (2026-10-20, library implementation)
| id | status | detail |
|---|---|---|
| STORE_NOT_WIRED | BY DESIGN until P03-05 | `XRAIVaultStore` exists and is tested; the XRAI app target does not link it (test-enforced). No personal data is persisted by the app. |
| STORE_METADATA_SYSTEM_PATH | NEEDS REVIEW | `SecureVault.sealSystem/openSystem` is a tokenless path restricted to `DataClass.storeMetadata` (ids/classes/generations, never contents, never exported). Negative tests cover both directions; reviewer should confirm the class-restriction model. |
| CORRUPT_STATE_IN_MEMORY | OPEN | a record whose AEAD fails is marked corrupt in memory only (re-detected on each read); persisting the state is a P03-04b item. |
| BACKUP_BODY_V3 (P03-04 entry) | RESOLVED in P03-04b (see above); was: DEFERRED | instance id, backup generation and embedded ledger digest inside the sealed body; `admitRestored` currently takes the provenance from the caller. |
| ATTACHMENTS (P03-04 entry) | RESOLVED in P03-04b (see above); was: DEFERRED | chunked attachment envelopes (one DEK per attachment). |
| FSYNC_COST_ON_DEVICE | NOT_MEASURED | ~10 `F_FULLFSYNC` per mutation; human-paced writes only; large-vault performance not measured on device. |
| STORE_DEVICE_RUN | see ledger | hosted store suite on Simulator and iPhone 14 Pro Max (non-destructive, temp dir in the app container). |

## New in P03-03 (2026-10-20, design only)
| id | status | detail |
|---|---|---|
| PERSISTENCE_ADR_REVIEW | AWAITING_REVIEW | ADR-BOOT-009 (file-based envelope store, SQLCipher deferred) is PROPOSED; P03-04 starts only after acceptance. |
| DERIVED_DATA_GRAPH | SPECIFIED, NOT_STARTED | `derivedFrom[]` in authenticated header v3 + manifest reverse index; cascade/invalidation rules in P03_03_DATA_LIFECYCLE_MATRIX §2; tests N13 PLANNED. |
| TOMBSTONE_RESURRECTION_WINDOW | SUPERSEDED 2026-10-20 (P03-03H H1) | the 90-day window is withdrawn; replaced by DELETION_LEDGER_PERMANENT and DELETION_HISTORY_AFTER_DEVICE_LOSS. |
| INTERACTION_PROOF_LIMIT | LIMIT | the interaction proof is in-process, not an OS boundary; malicious in-process code can forge it. Mitigations: code signing, sandbox, SE keys, optional biometrics (deferred, UX decision). |
| INPUT_FIELD_BOUNDARY_CONTRAST (P03-03 entry) | CLOSED in P03-05A (see above); was: OPEN (F-UX-5) | WCAG 2.2 SC 1.4.11: text-input boundary measures 1.17:1 light / 1.11:1 dark against the surface, below the 3:1 non-text requirement; needs an `inputBorder` token ≥ 3:1 asserted by `ContrastTests`. The 1.3:1 border threshold is an internal decorative minimum, not an SC claim (P03_03_ARCHITECTURE_GATE_REPORT §4). |
| DELETION_LEDGER_PERMANENT | CODED + TESTED (P03-04) | `DeletionLedger` + `BloomFilter` (p ≤ 1e-6 measured at 250 000 entries), cross-bound to the manifest; corrupt → every admission quarantined; missing → read-only; known-deleted ids skipped on admission; reimport = new id with provenance (NT-H1-01…05, 07). NT-H1-06 (embedded ledger in backup body v3) DEFERRED to P03-04b. |
| DELETION_HISTORY_AFTER_DEVICE_LOSS | LIMIT | with only an old portable backup, deletions made after its export are unknowable; restored records are quarantined and reviewed per class; no absolute-forgetting claim. |
| MANIFEST_ROLLBACK_ANCHOR | CODED + TESTED (P03-04) | `KeychainAnchorStore` (real keychain test on every host) + `InMemoryAnchorStore`; rollback of manifest alone or of the whole system/ snapshot → read-only (NT-H5-04/05); crash between manifest and anchor recovered via chain + open journal (GATE B). LIMIT: compromised OS. |
| SINGLE_WRITER_LOCK_ADVISORY | LIMIT | `vault.lock` is advisory; isolation is the actor + main-app-only rule; extensions never link the store (test-enforced in P03-04). |
| REVOKE_VS_DELETE_SPLIT | CODED + TESTED (P03-04, library) | `revoke(purpose:mode:)` (`.deleteNow` / `.suspend(grace)`), `restoreSuspended`, `expireSuspended`; third-party classes refuse suspension; re-grant never reactivates (NT-H4-01…05). UI choice screen is P03-05. |
| F_UX_5_GATE | MANDATORY for next UX phase | `ContrastTests` must assert `inputBorder` vs surface ≥ 3.0:1 light and dark before that phase is TESTED. |
| P03_02_OPEN_FINDINGS | OPEN (unchanged) | F-UX-4, SE-class layout, human VoiceOver (MANUAL_PENDING), native English review, app-switcher snapshot visual check (MANUAL_PENDING), full device regression with the final build, tab-bar contrast exception. |
