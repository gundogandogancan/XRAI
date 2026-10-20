# P03_04BH2_GLOBAL_DELETION_SECURITY_REPORT — global deletion invariant & write-path security gate

**Date:** 2026-10-20 · **Baseline:** `bff2bd33b41d7fd9dfe38d4115c727e8b486713d` · **Finding:** F-P04BH-01 [P0] · **App persistence:** NO-GO (unchanged) · **SECURITY_REVIEWED:** NO.

Türkçe özet: Bulgu gerçek ve yeniden üretildi: silinmiş bir RecordID, `put` ile aynı kimlik altında yeniden yaratılıyor, okunuyor ve yeniden açılışta hayatta kalıyordu (düzeltme öncesi başarısız test logu saklı). Kök neden: yazma yolları yalnız manifeste bakıyor, silme defterine bakmıyordu. Düzeltme: tek kaynaklı `IdentityPolicy` (clear / deleted / possiblyDeleted / historyUntrusted) her giriş noktasında — put, putAttachment, kabul, etkinleştirme, yeniden içe aktarma hedefi, günlük replay'i, kurtarma uzlaştırması ve okumalar. Yedi uçtan uca saldırı akışı yeniden açılış sonrası kalıcı durumla doğrulandı; `releaseQuarantined` kaldırıldı; performans/kurtarma borç kaydı açıldı. Üç host'ta koşuldu.

## 1. Is the defect really reproducible? — YES

`evidence/p03_04bh2_repro_attackA_FAIL_before_fix.log`: NT-GD-01 run against `bff2bd3` + only the new error cases: `put(same id)` after delete threw nothing, the record was active and readable, and after reopen the vault was read-write with the manifest listing the id while the ledger said deleted (4 failed expectations). Classification: **CONFIRMED P0**.

## 2. Root cause

`storeEnvelope` and `putAttachment` guarded only `manifest.records[id] == nil`. Deletion removes the manifest entry and appends to the ledger, so a caller-supplied `RecordID` (legal in `RecordDescriptor`) of a deleted record passed the guard. The same gap existed in the `put` journal replay (adopt any present file), in the re-import target id, and in recovery (a manifest/ledger contradiction was not detected) — the invariant lived only in the restore path (P03-04bH), not globally.

## 3. Fix with code evidence

| requirement | code |
|---|---|
| single testable policy | `StoreModel.swift` — `IdentityPolicy.classify(id, ledger:, historyTrusted:) → .clear/.deleted/.possiblyDeleted/.historyUntrusted`, `requireClear` (throws `recordIDDeleted` / `possiblyDeletedForever` / `deletionHistoryUntrusted`), `contradicts(entry, verdict:)` |
| put / storeEnvelope | `requireClear` inside `storeEnvelope`, after `SecureVault.seal` authorized the caller (no deletion oracle before authorization), in the same actor section as the journal begin |
| putAttachment | `requireClear` after `createAttachment`, before the journal begin |
| admitRestored | `classify` decides: `.deleted` → `skippedDeleted`, `.possiblyDeleted` → staged with the risk, `.historyUntrusted` → staged with `untrustedLocalHistory`; never active |
| activateRestored | refuses the `possiblyDeleted` and `untrustedLocalHistory` risks, then `requireClear` live at activation time |
| reimportUnderNewID (renamed) | eligible for compacted or unprovable evidence; the NEW id passes `requireClear` and must not collide with a manifest entry |
| journal replay | `put`/`admit`: every id classified; a non-acceptable id aborts the batch (files removed, journal dropped, `needsRecovery` for put); `activate` of a non-clear id → read-only "journal activates a deleted identity"; `reimport` target re-checked |
| recovery reconciliation | after journals settle: any manifest entry that `contradicts` its verdict → read-only "manifest contradicts the deletion ledger" |
| reads | `get` / `readAttachment` run `requireClear` first: a contradiction is never read through |
| unprovable history | creation and activation refuse (`deletionHistoryUntrusted`); staging, export, delete and re-import under new ids still work |

## 4. End-to-end adversarial tests (persistent state checked after reopen)

NT-GD-01 attack A (`attackA_putSameID`), NT-GD-02 attack B (`attackB_attachmentSameID`), NT-GD-03 attack C (`attackC_afterCompaction`), NT-GD-04 attack D (`attackD_oldIDAfterReimport`), NT-GD-05 attack E (`attackE_journalReplay`: crash loop after a delete + a correctly bound forged `put` journal with the deleted envelope planted), NT-GD-06 attack F (`attackF_contradiction`: pre-delete manifest/authz over a post-delete ledger; policy unit matrix), NT-GD-07 attack G (`attackG_historyUnchanged`: ledger and manifest bytes, generation, staged state and journal directory compared before/after and after reopen). Each test compares manifest state, files on disk, ledger lookups, quarantine registry, journal directory and the reopened vault.

## 5. Crash / reopen results

Attack E1 crashed a put at every syscall after a delete: at every step the reopened vault was read-write, the deleted id absent, exactly deleted and without a file. Attack E2: the forged journal was refused by the policy, the planted file removed, the journal dropped, the id unreadable. The P03-04/04H/04b crash loops (NT-H5-01/03, NT-FS-08, NT-RR-12, NT-AT-05, NT-BH-09) re-ran green.

## 6. GATE 3 regression of the P03-04bH fixes

All re-ran without reopening a finding: RestoreResult HMAC (NT-BH-04), `SecureVault.reimport` authorization (NT-BH-02, NT-GD-07), exact acknowledgment (NT-BH-06), derived-cycle detection (NT-BH-05), single-descriptor two-pass read (NT-BH-07), sticky distrust (NT-LR-06, NT-BK-05/06), post-crash quarantine reconciliation (NT-BH-09). Intended assertion changes: a staged possibly-deleted record now reads as `possiblyDeletedForever` (policy before state); NT-BK-05 asserts `deletionHistoryUntrusted` for a put under unprovable history and refuses activation of such a staged id.

## 7. GATE 4 — `releaseQuarantined`

Production usage search: none (the app does not link the store; every quarantined manifest entry is a restored record; activation goes through `activateRestored` / `reimportUnderNewID`). Decision: **removed** (compile-negative snippet). The facade-level `SecureVault.releaseQuarantine` (in-memory registry, P02 API) is unchanged.

## 8. GATE 5 — debt register

Recorded in `OPEN_BLOCKERS.md` ("Performance & recovery debt register"): FSYNC_COST (measured), BATCH_ADMISSION_GROUPED_COMMIT (feasibility: content flush per file stays; journal rewrites and directory flushes can be grouped per batch without losing all-or-nothing), STICKY_DISTRUST_RESET (user-confirmed reset design), PERSISTED_CORRUPT_STATE, ATTACHMENTS_IN_BACKUP, and DATA_LOSS_ROLLBACK_DURABILITY_SUITE (proposed next-phase negative tests: per-file and paired rollbacks, write-loss/power-loss model in the test file system, ENOSPC/EMFILE injection at every step, limits, clock rollback during recovery). No durability-reducing optimisation was made.

## 9. Test runs (real results, exit codes)

| run | command | exit | result | log |
|---|---|---|---|---|
| reproduction before the fix | `swift test --filter StoreDeletionInvariantTests` | 1 | attack A succeeds on the unfixed store (4 issues) | `evidence/p03_04bh2_repro_attackA_FAIL_before_fix.log` |
| store suite, attempt 1 after the fix | `swift test --filter XRAIVaultStoreTests` | 1 | 13 issues: the contradiction check ran before pending journals were settled (legitimate crash window flagged) → moved after journal resolution; the policy ran before authorization (oracle) → moved after; two test assumptions | `evidence/p03_04bh2_store_run1_FAIL_13_issues.log` |
| store suite, attempt 2 | same | 0 | 96 tests in 18 suites passed | (superseded by the full run) |
| macOS package tests | `swift test` | 0 | 207 tests in 47 suites passed (200 before + 7 new NT-GD); compile-negative (incl. the removed `releaseQuarantined`/`putEnvelope` snippets), import-boundary and GATE A scans included | `evidence/p03_04bh2_swift_test_macos.log` |
| Simulator hosted | `xcodebuild test … iPhone 17 Simulator -only-testing:XRAIHostedTests` | 0 | 133 tests in 31 suites passed (NT-GD-01…07 included) | `evidence/p03_04bh2_xcodebuild_sim_hosted.log` |
| iPhone 14 Pro Max hosted, non-destructive | `xcodebuild test … id=C7C6CE6E-… -allowProvisioningUpdates` | 0 | 133 tests in 31 suites passed on iPhone 14 Pro Max "Dogi (2)" (iOS 26.6): all seven attack flows with reopen checks; real Keychain anchor; non-destructive | `evidence/p03_04bh2_xcodebuild_device_hosted.log` |
| static: package spec | `python3 -I validation/validate_package.py` | 0 | PASS spec structure (files=4980); does not verify an iOS build | `evidence/p03_04bh2_validate_package.log` |
| static: docs + import boundary / compile-negative | `python3 -I validation/check_p03_03_docs.py` (+ `StoreModuleBoundaryTests` in the macOS run) | 0 | PASS: 118 NT rows, T44–T52, P03-04bH2 report consistent, `releaseQuarantined` absent, `IdentityPolicy` consulted at ≥ 10 call sites (source greps) | `evidence/p03_04bh2_check_docs.log` |

Not run: UI/XCUI, destructive device scenarios, power loss.

## 10. Remaining risks

1. Unprovable history now blocks creation and activation until a user-confirmed reset exists (designed, not built) — a product-level consequence of failing closed.
2. The identity policy runs after authorization to avoid an oracle; `duplicateRecordID` for an EXISTING id is still thrown before authorization (existence oracle for present ids — low value, documented).
3. Reads of a contradicting entry are refused, but the vault stays open read-only; a repair path (delete the contradicting entry) needs the user-confirmed flow.
4. In-process boundaries (restore seal, token issuer) unchanged; P03-05 brings the OS-level boundary.
5. Items in the debt register are designs only.

## 11. Final SHA

Implementation + evidence commit: `b6d87f1924ff6c953f6896b8d350c72e0974a1ba` (on top of baseline `bff2bd3`). This stamp is added in the small follow-up commit that is HEAD; no history was rewritten.

## 12. GO / NO-GO for P03-05

**NO-GO for P03-05 app persistence** until the next independent review accepts this gate (start at `IdentityPolicy` and its call sites, the recovery contradiction rule and the fail-closed consequence for unprovable history). Recommended review question for the next round: should the policy also refuse `duplicateRecordID` before authorization, or is the existence oracle acceptable? The decision belongs to the reviewer and the founder.
