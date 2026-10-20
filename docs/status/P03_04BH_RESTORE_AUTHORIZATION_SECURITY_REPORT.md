# P03_04BH_RESTORE_AUTHORIZATION_SECURITY_REPORT — restore identity, authorization & deletion integrity gate

**Date:** 2026-10-20 · **Mode:** targeted security remediation after the P03-04b independent review · **Baseline:** `619407553ef44ff78f7dfff7f9e737634e896b20` · **P03-05 app persistence:** NO-GO (unchanged) · **SECURITY_REVIEWED:** NO (this is the response to the review, not the review).

Türkçe özet: Üç bulgu doğrulandı ve kapatıldı. (1) Bloom özetine katlanmış bir silme, "possiblyDeleted" riskini onaylayarak aynı kimlikle geri dönebiliyordu; artık bu kimlik asla etkinleşemez, yalnız açık bir yeniden içe aktarma yeni kimlik + yeni DEK üretir ve eski kimlik kesin silinmiş olur. (2) `putEnvelope` yalnız `.write` token'ı tüketip amaç/izin/bütünlük kontrolünü atlıyordu; üretim yüzeyinden kaldırıldı. (3) Çağıranın kurduğu `RestoreResult` doğrulanmış kaynak gibi davranabiliyordu; facade artık her sonucu HMAC ile mühürlüyor, depo yalnız doğrulanmış sonucu kabul ediyor. Altı ek kontrol: döngü reddi, tam risk onayı, tek tanımlayıcıyla iki geçişli ek okuma, eksik yedek bayrağı, çökme sonrası kayıt-karantina tutarlılığı. Yeni testler iki ek hata daha buldu ve düzeltildi.

## 1. Confirmed defects and exact fixes

| finding | classification | defect (before `6194075`) | fix | tests |
|---|---|---|---|---|
| F-P04B-01 Bloom deletion resurrection | **CONFIRMED P0** | `activateRestored` refused only `.deleted`; `.possiblyDeleted` could be acknowledged and activated under the old id | `activateRestored` and `releaseQuarantined` refuse any such id with `VaultError.possiblyDeletedForever` (both from the persisted risk bit and from a live ledger lookup); new `reimportPossiblyDeleted(id, authorization:)`: `.reimport(recordID:)` scope, purpose must equal the record's, active grant required (`SecureVault.reimport` = validate → authorize → `mayStore` → AEAD open → seal under a NEW id and fresh DEK), journaled as one mutation that writes the new file, unlinks the old file, appends an EXACT ledger entry for the old id, and refuses while any record derives from it | NT-BH-01, NT-BH-02 |
| found by NT-BH-01 | **CONFIRMED** (new) | `DeletionLedger.append` skipped ids that only hit the digest, so a re-deletion of a possibly-deleted id never became exact evidence | append skips only exact duplicates | NT-BH-01 |
| F-P04B-02 unauthorized envelope write | **CONFIRMED P0** | `putEnvelope` stored a caller-sealed envelope with a `.write(class)` token only (no purpose match, consent, tier, key binding or AEAD check) | removed from the production surface (compile-negative test); the remaining write paths are `put`/`putAttachment` (`SecureVault.seal`/`createAttachment`: purpose, consent, tier, key binding, AEAD) and verified admission (the facade re-wraps every DEK under the current key and re-verifies every payload) | NT-BH-03 |
| F-P04B-03 verified restore provenance | **CONFIRMED P1** | `RestoreResult`/`BackupProvenance` public initialisers let a caller present any metadata as verified | `RestoreResult.verificationSeal` = HMAC-SHA256 over provenance + every envelope + every quarantine reason under a per-facade random key; `SecureVault.isVerified`; `admitRestored` throws `restoreUnverified` otherwise; history merges only from verified results; legacy v2 stays verified with `legacyFormat` | NT-BH-04 |
| check 1 derived cycles | **CONFIRMED** (reachable with legacy headers) | two restored records deriving from each other activated together | DFS cycle refusal over the batch at activation; created-at ordering check; self-reference refused at construction (admission guard kept) | NT-BH-05 |
| check 2 trusted-time re-check | OK | activation already used the trusted time from the consumed token | — | NT-BH-06 |
| check 3 acknowledgment semantics | **CONFIRMED** mismatch | code used `isSubset`, the documented contract said "exactly" | exact set equality | NT-BH-06 |
| check 4 two-pass attachment read | **RISK** (mitigated) | pass 2 reopened the path: a replacement between passes was read and authenticated chunk by chunk (never leaked, but the "verified first" claim did not cover it) | one descriptor for both passes (`rewind`); in-place writes by a same-UID process remain out of model | NT-BH-07 |
| check 5 incomplete backup | **CONFIRMED** | a v3 body did not say that attachments were excluded | `excludedAttachmentCount` inside the sealed body (schema 2); importers stage with `attachmentsMissing` | NT-BH-08 |
| check 6 states after crash | **CONFIRMED** (new, found by NT-BH-09) | an activation committed by journal replay left the in-memory quarantine registry entry | recovery mirrors the manifest both ways; untrusted-journal ids stay quarantined and are flagged `needsRecovery` | NT-BH-09 |

## 2. Files changed

- Contracts: `Envelope.swift` (`restoreUnverified`, `possiblyDeletedForever`), `Authorization.swift` (`.reimport(recordID:)`, `RestoreResult.verificationSeal` + `sealedBytes`), `Backup.swift` (`excludedAttachmentCount`, provenance `encode`, body schema 2).
- CryptoKit: `SecureVault.swift` (`restoreSealKey`, `isVerified`, sealed `restoreBackup`, `reimport`), `BackupCodec.swift` (schema field).
- Store: `FileVaultStore.swift` (`putEnvelope` removed; verified-only admission; `possiblyDeletedForever`; exact acknowledgment; cycle refusal; `reimportPossiblyDeleted` + replay case; excluded attachment count; single-descriptor attachment read; registry mirroring; `needsRecovery` for untrusted journal ids), `StoreModel.swift` (`attachmentsMissing`, exact-duplicate ledger append), `VaultFileSystem.swift` (`rewind`).
- Tests: new `StoreRestoreHardeningTests.swift`; updated `StoreCoreTests`, `StoreCrashAndRetirementTests`, `StoreFileSystemTests`, `StoreLedgerBindingTests`, `StoreBackupRestoreTests`, `StoreBoundaryTests`, `StoreHarness`.
- Docs: this report; matrix addendum (NT-BH-01…09); threat model v1.11 (T51); `OPEN_BLOCKERS.md`; ADR-BOOT-009 Amendment H.3; `NEXT_TASK.md`; `CLAUDE.md`; ledger; validator; evidence logs `evidence/p03_04bh_*`.

## 3. Test names and results

NT-BH-01 `bloomResurrectionAttack`, NT-BH-02 `reimportAuthorization`, NT-BH-03 `writePaths` (+ `compileNegative` snippet "putEnvelope removed"), NT-BH-04 `forgedProvenance`, NT-BH-05 `derivedCycle`, NT-BH-06 `exactAcknowledgment`, NT-BH-07 `attachmentReplacedBetweenPasses`, NT-BH-08 `incompleteBackupFlag`, NT-BH-09 `activationCrashEverywhere` — all in `StoreRestoreHardeningTests`. Regression: every earlier row re-ran; intended assertion changes: NT-H1-02 restores in the same session as it admits (seal is per facade instance); NT-H1-05 uses a genuine foreign backup and asserts `restoreUnverified` for a caller-built result; NT-FS-10 asserts `restoreUnverified` (the stale-key admission guard is unreachable through the verified path); NT-BK-04/05 use the exact-acknowledgment message and the genuine lost-history path for `olderBackupGeneration`; NT-BK-01 expects schema 2; NT-H2-04 no longer uses `putEnvelope`.

| run | command | exit | result | log |
|---|---|---|---|---|
| store suite, attempt 1 | `swift test --filter XRAIVaultStoreTests` | 1 | 13 issues: 2 product defects found by the new tests (ledger append, registry release) + test expectations (schema, messages, seal per session, test ordering) | `evidence/p03_04bh_store_run1_FAIL_13_issues.log` |
| store suite, attempt 2 | same | 1 | 5 issues: registry mirroring released untrusted-journal ids (fixed: `needsRecovery`); test used wrong plaintext/existing-id assumptions | `evidence/p03_04bh_store_run2_FAIL_5_issues.log` |
| macOS package tests | `swift test` | 1 → 0 | first full run FAILED on 2 expectations of `BackupV3Tests` (schema 1 → 2, kept as `evidence/p03_04bh_swift_test_macos_run1_FAIL_schema_expectation.log`); rerun: 200 tests in 45 suites passed (191 before + 9 new); compile-negative, import-boundary and GATE A scans included | `evidence/p03_04bh_swift_test_macos.log` |
| Simulator hosted | `xcodebuild test … iPhone 17 Simulator -only-testing:XRAIHostedTests` | 0 | 126 tests in 29 suites passed (NT-BH-01…09 included; Data Protection assertions compiled out on the Simulator as before) | `evidence/p03_04bh_xcodebuild_sim_hosted.log` |
| iPhone 14 Pro Max hosted, non-destructive | `xcodebuild test … id=C7C6CE6E-… -allowProvisioningUpdates` | 0 | 126 tests in 29 suites passed on iPhone 14 Pro Max "Dogi (2)" (iOS 26.6): NT-BH-01…09 incl. the bloom resurrection attack and the activation crash loop; real Keychain anchor; non-destructive | `evidence/p03_04bh_xcodebuild_device_hosted.log` |
| static: package spec | `python3 -I validation/validate_package.py` | 0 | PASS spec structure (files=4893); does not verify an iOS build | `evidence/p03_04bh_validate_package.log` |
| static: docs + import boundary | `python3 -I validation/check_p03_03_docs.py` (+ `StoreModuleBoundaryTests` in the macOS run) | 0 | PASS: 111 NT rows, T44–T51, P03-04bH report consistent, `putEnvelope` absent, verified-only admission and `possiblyDeletedForever` present (source greps) | `evidence/p03_04bh_check_docs.log` |

Not run: UI/XCUI (no UI change), destructive device scenarios, power loss.

## 4. Remaining risks

1. The restore seal is an in-process boundary (per-facade random key); it proves "this facade produced this result in this process", nothing more. The OS-level boundary is P03-05's job (InteractionGate, app layer).
2. Dependency migration on re-import is refused, not implemented (`REIMPORT_DEPENDENCY_MIGRATION`).
3. In-place modification of an attachment by a same-UID process during a read is detected (authentication) but earlier authentic chunks were already delivered.
4. Attachments remain outside backups; the body now says so, the UI must show it (P03-05).
5. Sticky ledger distrust still has no user-confirmed reset path; corrupt-state marking is still in memory.
6. Measured fsync cost (P03-04b numbers) is unchanged by this gate.

## 5. HEAD SHA

Implementation + evidence commit: `54964790dfd7b755ccd79f62c7f36f50b634e59a` (on top of baseline `6194075`). This stamp is added in the small follow-up commit that is HEAD; no history was rewritten.

## 6. GO/NO-GO for P03-05

**NO-GO for P03-05 app persistence** until the next independent review accepts this gate (recommended focus: `SecureVault.reimport`, the restore seal, the removed write path, and the exact-acknowledgment UX contract). The three P0/P1 findings are closed with tests on three hosts; what remains open is listed in §4 and is stated, not hidden. The decision belongs to the reviewer and the founder.
