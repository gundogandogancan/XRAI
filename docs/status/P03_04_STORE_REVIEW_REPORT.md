# P03_04_STORE_REVIEW_REPORT — `XRAIVaultStore`: the first encrypted record store (library only)

**Date:** 2026-10-20 · **Approved baseline:** `56a5ece40f433d06a4e27c0f65d8dc1c9548b48a` · **Approval:** CONDITIONAL GO (library only; `NEXT_TASK.md` approval record) · **HEAD of this report:** see the commit that carries it (given in the session's final answer and the ledger) · **Status words:** CODED, TESTED (with evidence), DEVICE_VERIFIED (physical iPhone run), MANUAL_PENDING, DEFERRED, LIMIT.

Türkçe özet: `XRAIVaultStore` hedefi eklendi: actor tabanlı `FileVaultStore`, şifreli manifest, kalıcı şifreli silme defteri (Bloom özetli), günlüklü atomik mutasyonlar ve çökme kurtarma, türetilmiş veri grafı, epoch tabanlı yetki durumu, Keychain çapası (`KeychainAnchorStore`), emeklilik protokolü v2 (`prepareRetirement` / `forgetRetired` / `retireKey`), yol ve dosya sistemi doğrulaması, fail-closed restore kabulü ve test-only hata enjeksiyonu. Uygulama store'a BAĞLANMADI; gerçek kişisel veri yazılmadı; tüm testler fikstür verisi ve geçici dizinlerle çalıştı. Sonuçlar aşağıda gerçek çıkış kodlarıyla. SECURITY_REVIEWED: HAYIR.

## 1. Changed files (code)
| file | change |
|---|---|
| `Packages/XRAICore/Package.swift` | new target `XRAIVaultStore` (deps: Contracts, CryptoKit adapter) + `XRAIVaultStoreTests` |
| `Sources/XRAIVaultStore/FileVaultStore.swift` | the actor: open/recover, put/putEnvelope/get, delete, revoke/restoreSuspended/expireSuspended, admitRestored/releaseQuarantined, rewrapAll, prepareRetirement/forgetRetired/retireKey, journaled mutation engine, loader with bindings and lock |
| `Sources/XRAIVaultStore/StoreModel.swift` | `Manifest`, `ManifestEntry`, `RecordState`, `DeletionLedger` + `BloomFilter`, `AuthzState`, `JournalEntry`, framing/codec |
| `Sources/XRAIVaultStore/KeyRetirement.swift` | `KeyRetirementProof`, `StoreInventory`, `KeyRetirementVerifier` (read-only recomputation), `StoreLayout` |
| `Sources/XRAIVaultStore/VaultFileSystem.swift` | `VaultFileSystem` port (syscall granularity), `RealFileSystem` (O_NOFOLLOW, O_EXCL, F_FULLFSYNC, lstat, Data Protection complete, backup exclusion), `AtomicWriter` |
| `Sources/XRAIVaultContracts/Envelope.swift` | additive: 15 `VaultError` cases; header **v3** (`derivedFrom`, `schemaVersion`; v2 unchanged byte-for-byte); `RetirableKeyProvider`, `VaultAnchor`, `VaultAnchorStore` ports |
| `Sources/XRAIVaultContracts/Authorization.swift` | additive scopes `.revokeConsent`, `.restoreSuspended`, `.retireKey`, `.admitRestored`; failure `.epochMismatch` |
| `Sources/XRAIVaultContracts/PrivacyModel.swift` | `DataClass.storeMetadata` (never in backups); `DenialReason` + 3 cases |
| `Sources/XRAIVaultContracts/CanonicalCoding.swift` | `appendU64` / `readU64` |
| `Sources/XRAIVaultCryptoKit/Authorization.swift` | `AuthorizationIssuer(epoch:)`, id = epoch‖counter‖random, `epochMismatch`; `MonotonicGuardClock(initialHighWaterSeconds:)` + `highWaterMark` |
| `Sources/XRAIVaultCryptoKit/SecureVault.swift` | `consumeAuthorization`, `sealSystem`/`openSystem`/`rewrapSystem` (storeMetadata only), `rewrapBatch`, `VaultDigest.sha256` |
| `Sources/XRAIVaultKeychain/KeychainAnchorStore.swift` | Keychain-backed anchor (add/update/delete, same mode rules as the provider); `KeychainKeyProvider: RetirableKeyProvider` |
| `Sources/XRAIVaultTesting/TestingDoubles.swift` | `InMemoryKeyProvider` retire/isRetired + two test hooks; `InMemoryAnchorStore` |
| `Tests/XRAIVaultStoreTests/*` (4 files) | harness with `FaultingFileSystem`, 36 tests; `Tests/XRAIVaultKeychainTests/KeychainAnchorStoreTests.swift` (real keychain) |
| `project.yml` / `XRAI.xcodeproj` | hosted test bundle compiles the store suite and links `XRAIVaultStore`; **the app target does not** (test-enforced) |
Untouched: BOOT-01 core (`XRAIIdentityTime`, `XRAINumerology`), `App/XRAI` sources, the sealer/backup codec internals.

## 2. Architecture modules delivered
- **Actor `FileVaultStore`** — every mutation is one synchronous isolated method; the only `await` in the file is the static `open` calling `recover()` (source-scan test). Writers are serialized by the actor, the advisory `vault.lock` (pid:epoch, stale-pid reclaim) and the main-app-only rule.
- **Encrypted manifest** — generation chain (`prevHash`), `minimumWrapVersion`, retired versions, ledger hash, record table with state/provenance/`derivedFrom`; sealed as a `storeMetadata` envelope; hash over canonical plaintext.
- **Header v3** — `derivedFrom[]` + `schemaVersion` inside the authenticated header; produced only when a descriptor carries sources, so every existing v2 record/test is unchanged.
- **Deletion ledger** — permanent, O(1) exact index, Bloom digest compaction above the threshold (default 200 000, fail-closed `possiblyDeleted`), cross-bound to the manifest; `skippedDeleted` on admission; known-deleted ids never reactivate.
- **Journaled mutations** — begin{op, tokenID, ids, target, epoch} → effects (steps logged) → [ledger] → manifest(g+1) → `manifestWritten` → authz → anchor → commit → journal removed. Recovery replays put/admit/delete/revoke/unsuspend/release/freeze, finishes the tail when the manifest was durable, and *reconciles* (not replays) rewrap/retire (they need a fresh maintenance token).
- **Derived-data graph** — reverse index on demand, dependents-first cascade, back-edge/unknown/self rejection, consent inherited at read time.
- **Epoch authorization state** — `authz.v1` {epoch, clock mark, manifest binding}; epoch++ on every open; never exported (policy); older snapshot → read-only.
- **Keychain anchor** — `vault/anchor` item = (instance id, generation, hash); mismatch or absence → read-only; crash between manifest and anchor is provable by chain + open journal and completed by recovery (GATE B).
- **Retirement protocol v2** — R1 freeze (durable), R2 journaled rewrap incl. the ledger system file, R3 full inventory from authenticated headers (records, system, journal entries; orphans reported separately), R4 three-way cross-check, R5 proof bound to generation + section token, R6 retire+forget in the same actor method, R7 manifest record. Independent `KeyRetirementVerifier`.
- **Path/filesystem integrity** — `lstat` root (symlink refused), 32-hex id validation before any path, `O_NOFOLLOW`/`O_EXCL`, regular-file checks, temp cleanup, orphans quarantined, missing flagged.
- **Fail-closed restore admission** — ledger (`deleted`/`possiblyDeleted`), untrusted history, foreign/unknown instance, pre-quarantined → `quarantined`; per-record release via `SecureVault.releaseQuarantine`.
- **Fault injection** — only in the test target (`FaultingFileSystem` crashes at the k-th mutating syscall); the production module contains no fault seam (scan).

## 3. The 48 matrix rows
See `P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md` for each row's test name and real result. Summary: 46 MANDATORY rows TESTED on macOS; NT-H5-16 TESTED only on iOS hosts (Simulator/device, see §4); NT-H1-06 DEFERRED (backup body v3). Rows whose evidence is a source/compile scan (NT-B-01, GATE A) run on macOS only.

Deviations from the wording of the matrix, stated honestly:
- NT-H2-01: a proof cannot exist while manifest usage > 0 (prepare refuses with `keyVersionInUse`), and `forgetRetired` re-checks usage; the "forget with usage > 0" path is therefore unreachable without bypassing the actor. Tested at the prepare step and by the guard.
- NT-H3-07: a rollback **within** tolerance (300 s) yields the mark; a rollback **beyond** tolerance fails closed (`clockRegressed` on every token/read) rather than "returning the mark" — stricter than the row's wording. The vault still opens so existing data is not lost; nothing expires or activates.
- NT-H1-02 vs NT-H1-03: a **corrupt** ledger keeps the vault operating with every admission quarantined (as NT-H1-02 specifies); a **missing** ledger opens read-only with restore refused (as NT-H1-03 specifies).

## 4. Test runs (real results)
| run | command | exit | result | log |
|---|---|---|---|---|
| macOS package | `swift test` (Packages/XRAICore) | 0 | **145 tests in 36 suites passed** (108 existing + 36 store + 1 keychain anchor); Bloom: 0 false positives in 2 000 000 probes | `evidence/p03_04_swift_test_macos.log` |
| Simulator hosted | `xcodebuild test … 'platform=iOS Simulator,name=iPhone 17' -only-testing:XRAIHostedTests` | 0 | **73 tests in 21 suites passed** (keychain + anchor + store suites inside the signed app; data-protection keychain; NT-H5-16 cannot assert a protection class on the Simulator — KNOWN_LIMITATION) | `evidence/p03_04_xcodebuild_sim_hosted.log` |
| Simulator hosted, first run | same, before the NT-H5-16 adjustment | 65 | 72/73: NT-H5-16 failed because the Simulator reports no Data Protection class (kept as evidence of the limitation, not hidden) | `evidence/p03_04_xcodebuild_sim_hosted_run1_NT-H5-16_sim_limitation.log` |
| iPhone 14 Pro Max (iOS 26.6, "Dogi (2)") | `xcodebuild test … 'platform=iOS,id=C7C6CE6E-…' -only-testing:XRAIHostedTests` | 0 | **73 tests in 21 suites passed** — non-destructive: temp directory inside the app container, unique keychain services cleaned up; NT-H5-16 asserts `NSFileProtectionComplete` on every vault file and backup exclusion on the root (real device evidence); real Secure Enclave anchor/keychain | `evidence/p03_04_xcodebuild_device_hosted.log` |
| store suite development runs | `swift test --filter XRAIVaultStoreTests` | 1, 1, 0… | run 1: stale `ledger.v1` under the old key + O(n) ledger lookup (fixed); run 2: 3 issues (manifest-block parsing in a test, verifier timing, clock-regressed open) (fixed); later runs 36/36 | `evidence/p03_04_store_tests_run1_*.log`, `…run2_*.log` |
| spec validator | `python3 -I validation/validate_package.py` | 0 | PASS | `evidence/p03_04_validate_package.log` |
| docs consistency | `python3 -I validation/check_p03_03_docs.py` (extended for P03-04) | 0 | see ledger entry P03-04-STATIC-DOCS | `evidence/p03_04_check_docs.log` |

DEVICE_VERIFIED: **PARTIAL** (non-destructive hosted suite incl. the store on a physical iPhone; no reinstall/passcode/lock-transition scenarios). SECURITY_REVIEWED: **NO**. Not run: UI tests and the accessibility audit (no UI changed), destructive scenarios (not authorized).

## 5. Security invariants preserved (checked by tests)
- Only `SecureVault` touches cryptography; the store has no second decryption route. The system path (`sealSystem`/`openSystem`) accepts only `storeMetadata` and refuses every personal class; a `storeMetadata` envelope can never be stored as a user record or exported.
- Every read goes through `SecureVault.open` (token, purpose, consent, quarantine) *plus* the manifest state and source checks; every mutation consumes a token through the same issuer (`consumeAuthorization`) or a `DeletionGrant` issued by the vault.
- `XRAIVaultTesting` and the fault seam never reach production targets; the app target does not link the store (manifest/project scans, compile-negative).
- BOOT-01 math core untouched; header v2 bytes unchanged (existing 108 tests pass as before).

## 6. Open security risks (unchanged or new)
1. The single-writer lock is advisory; isolation is the actor + the rule; app extensions must never link the store (`SINGLE_WRITER_LOCK_ADVISORY`).
2. The interaction gate (P03-05) does not exist yet: tokens are issued by whoever holds the issuer. In-process code is not an OS boundary (`INTERACTION_PROOF_LIMIT`).
3. Corrupt-record state is in-memory only (re-detected on each read); not persisted to the manifest.
4. Attachments, backup body v3 (instance id + embedded ledger), restore UI and consent persistence are DEFERRED (P03-04b / P03-05).
5. `F_FULLFSYNC` cost makes each mutation ~10 durable syncs; acceptable for human-paced writes, not measured on device for large vaults.
6. Memory: unwrapped DEKs and plaintext live in process memory while in use (no zeroization guarantee).
7. No independent security review (`VAULT_SECURITY_REVIEW`).

## 7. Points that need independent verification
- Recovery state machine completeness (resolveJournal cases) against an adversarial crash model beyond single-syscall faults (e.g. torn directory fsync on power loss on real flash).
- The Bloom digest parameters and the "fail-closed on false positive" policy.
- The decision to keep a corrupt ledger operating (NT-H1-02) versus read-only.
- The `storeMetadata` system path as a tokenless but class-restricted seal/open route.
- Device Data Protection class on every file (attribute asserted on iOS hosts, not audited under lock/unlock transitions).

## 8. Next smallest step
**P03-04b — backup body v3 + restore reconciliation (library):** `BackupBody` v3 with `vaultInstanceID`, `backupGeneration`, embedded deletion ledger digest; `BackupCodec` extension; `admitRestored` taking the backup's provenance from the sealed body (closes NT-H1-06); attachment envelopes (one DEK, chunked). Still no app wiring, no real data. Then **P03-05** — consent UI + `InteractionGate` + persisted consent receipts, wiring the store into `SecurityStatus` behind the gate.
