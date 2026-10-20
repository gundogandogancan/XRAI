# P03_04B_BACKUP_RESTORE_REVIEW_REPORT — ledger binding, backup body v3, restore reconciliation, chunked attachments

**Date:** 2026-10-20 · **Approval:** CONDITIONAL GO (recorded in `NEXT_TASK.md`) · **Baseline:** `42c3f4ea8d9ff68b24df17b3a3606e2a1709fe32` · **Scope:** `XRAIVaultStore` / `XRAIVaultCryptoKit` / `XRAIVaultContracts` library only. App NOT wired, no consent UI, no InteractionGate, no cloud, no real personal data, no destructive device tests. **SECURITY_REVIEWED: NO. APP_PERSISTENCE: NOT AUTHORIZED.**

Türkçe özet: Önce P0 engel LEDGER_ONLY_ROLLBACK kapatıldı: her günlük begin girdisi manifestin bağladığı defter hash'ini taşıyor, defter dosyası değiştirilmeden önce yeni hash günlüğe "ilan" ediliyor; yükleyici diskteki defteri yalnız bu iki durumdan biri olarak kabul ediyor, aksi halde salt-okunur. Bozuk defter artık yapışkan biçimde güvenilmez (manifest bayrağı). Sonra yedek gövdesi v3 (instance id, üretim sayacı, manifest bağı, gömülü silme geçmişi), iki aşamalı restore (önce karantina, sonra riskleri onaylayarak etkinleştirme) ve parça bazlı ekler (tek DEK, türetilmiş parça anahtarı, benzersiz nonce, bağlı AAD, teslimden önce doğrulama geçişi, sınırlı bellek) eklendi. Üç host'ta koşuldu; sayılar §4'te. Ekler henüz yedeğe girmiyor; bu açıkça sınır olarak yazıldı.

## 1. Requirement chains (Requirement → Code → Test → Security → Privacy → Performance → Evidence → Remaining Limit)

### GATE 1 — LEDGER_ONLY_ROLLBACK [P0]

| link | content |
|---|---|
| Requirement | an older but AEAD-valid ledger must never become trusted through a pending journal; recovery must verify pre-state, post-state and journal identity; missing/contradicting history fails closed; verified replay is distinguished from rollback |
| Code | `StoreModel.swift`: journal v2 (`XRAI-J-2`: `begin(… ledgerHash:)`, `ledgerWritten(hash:)`), `LedgerBinding.verify`, manifest v2 (`XRAI-MANIFEST-2`, sticky `ledgerHistoryTrusted`); `FileVaultStore.swift`: begin binds `manifest.ledgerHash`, `commitTail` announces the post-state before replacing the file, loader runs `LedgerBinding.verify` with the persisted epoch, corrupt ledger + pending journal → read-only, `commitTail` persists distrust |
| Test | NT-LR-01…08 (`StoreLedgerBindingTests`), NT-H5-03 crash loop now asserts trust after every crash |
| Security | rollback to any state other than the bound pre-state or the announced post-state → read-only "deletion ledger state is not proven by the journal"; foreign journal → "journal does not bind to the manifest"; epoch mismatch → "journal does not bind to the authorization state"; stale generation → read-only; a corrupt ledger can no longer be laundered by a rewrite (sticky flag, exported as `deletionHistoryTrusted = false`) |
| Privacy | the ledger carries ids only; nothing new leaves the device |
| Performance | one extra journal rewrite per ledger-changing mutation (~5 syscalls); `ledger.hash` is computed once per announcement (O(n) encode) |
| Evidence | macOS/Simulator/iPhone runs §4; first attempt log `evidence/p03_04b_gate1_run2_FAIL_1_test_expectation.log` (test compared envelope bytes instead of plaintext state; product unchanged) |
| Remaining limit | a rollback to the exact pre-state is indistinguishable from "not yet written" and is replayed — that is the correct state by construction; legacy journal/manifest formats are refused, not migrated (no persisted vaults exist) |

### GATE 2 — backup body v3

| link | content |
|---|---|
| Requirement | versioned body with instance id, backup generation, manifest binding, verifiable deletion history, schema versions; recovery-key model kept; legacy accepted only under a policy; no authz/key/token material in the body |
| Code | `Backup.swift`: `BackupExportFacts`, `BackupProvenance`, `BackupBodyV3` (schema 1), `SealedBackup` v3 (`supportedFormatVersions = [2, 3]`); `BackupCodec.swift`: `exportV3`, format-separated HKDF contexts, restore returns provenance and verifies the embedded digest; `SecureVault.exportBackup(_:facts:…)`; `FileVaultStore.exportBackup` (durable generation burned before sealing, `lastExportedGeneration` mirror) |
| Test | NT-BK-01…08 |
| Security | relabelled versions fail AEAD; forged inner facts refused; digest mismatch refused at the facade and at admission; untrusted source history never merged |
| Privacy | cleartext = magic, version, salt, nonce only (NT-BK-02); attachments, suspended/quarantined records and store metadata never exported |
| Performance | NT-SC-01 (2 000 records) numbers in §4; whole body in memory (≤ 256 MiB enforced) |
| Evidence | §4; `evidence/p03_04b_gate23_run1_FAIL_legacy_forge_version.log` (legacy forging test had to pin version 2), `evidence/p03_04b_gate23_run3_FAIL_admission_partial_replay.log` (admission replay was partial → made all-or-nothing) |
| Remaining limit | attachments are not in the backup (`ATTACHMENTS_NOT_IN_BACKUP`); streaming export/restore deferred |

### GATE 3 — restore reconciliation

| link | content |
|---|---|
| Requirement | two phases: verify & quarantine, then activate when deletion, source, consent and user-confirmation conditions hold; the ten mandatory negative scenarios; known-deleted ids never reactivate |
| Code | `FileVaultStore.admitRestored` (stage with persisted `RestoreRisk`), `activateRestored(_:acknowledging:)` (scope `.activateRestored(recordIDs:)`), `releaseQuarantined` refuses restored records, `DeletionLedger.merge`, `BloomFilter.formUnion`, replay case `admit` all-or-nothing (+ `history`, `export`, `activate` cases), `DenialReason.pendingUserConfirmation` |
| Test | NT-RR-01…14 (mapping to the ten mandatory scenarios in the matrix addendum) |
| Security | nothing is active after admission; activation re-checks deletion (sticky), sources (same batch allowed), consent at trusted time, token scope narrowed to ids, file presence; foreign/legacy/older/untrusted/possibly-deleted/consent-inactive/unmerged risks must be acknowledged exactly |
| Privacy | quarantined records are never decrypted; reasons are typed, id-only |
| Performance | admission writes one file per record inside one journaled mutation (NT-SC-01) |
| Evidence | §4 |
| Remaining limit | the risk screen (UI) is P03-05; the quarantine registry is in-memory and rebuilt from the manifest at open |

### GATE 4 — chunked attachments

| link | content |
|---|---|
| Requirement | one DEK per attachment, unique nonce + authenticated chunk layout, manifest binding, integrity/order checks, missing/duplicate chunk refusal, size/resource limits, partial-write recovery, retirement + cascade compatibility, bounded memory |
| Code | `Envelope.swift`: `AttachmentLayout` (AAD + nonce rules); `SecureVault.createAttachment/openAttachment`, `AttachmentCipher` (CryptoKit module only); `KeyRetirement.swift`: `AttachmentFile` layout + inventory scanning of `attachments/`; `VaultFileSystem.swift`: streamed reads (`openRegularForRead`, `read`, `entryCount`), `AtomicWriter.replaceStreaming`; `FileVaultStore.swift`: `putAttachment`, `readAttachment` (verify pass then deliver pass), `rewriteAttachmentHeader`, cascade by kind, recovery of `attachments/`, `StoreLimits.attachmentChunkBytes/maxAttachmentBytes/maxDirectoryEntries` |
| Test | NT-AT-01…11 |
| Security | AAD binds record id, index, count, sizes and last flag; nonce = random 8-byte prefix ‖ index; chunk key derived from the DEK per record id; a tampered/reordered/truncated/duplicated chunk or non-zero padding yields no plaintext; `get` and `readAttachment` refuse the other kind |
| Privacy | file names random, sizes padded to 4 KiB (chunk granularity leaks length, documented); attachments inherit source consent via `derivedFrom` |
| Performance | NT-AT-10: write 0.59 s, read(2 passes) 0.59 s, RSS delta write 1 MiB, read 0 MiB (macOS), write 0.70 s, read(2 passes) 0.64 s, RSS delta write 0 MiB, read 0 MiB (Simulator), write 0.88 s, read(2 passes) 0.95 s, RSS delta write 0 MiB, read 0 MiB (iPhone 14 Pro Max); two decrypt passes by design |
| Evidence | §4 |
| Remaining limit | not in backups; two-pass CPU; thermal budget not measured beyond wall time; actor is blocked for the duration of a streamed read/write (human-paced use assumed) |

### GATE 5 — security and resource evidence

Covered: rollback/replay (NT-LR-01…08, NT-BK-05, NT-RR-10/14), wrong key and corruption (NT-BK-03/07, NT-AT-02), partial backup import (NT-RR-12), missing/duplicated chunks (NT-AT-02), crash at each durable transition (NT-H5-01/03, NT-RR-12, NT-AT-05, NT-FS-08), cross-record authorization (NT-RR-13, NT-AT-09), manifest/ledger/anchor divergence (NT-RR-04/06, NT-LR-*), key retirement with attachments (NT-AT-06), v2/v3 compatibility (NT-BK-04/07), recovery memory and file-count limits (NT-AT-08, NT-AT-10, NT-SC-01).

## 2. Modified files

- Contracts: `Envelope.swift` (+`AttachmentLayout`), `Backup.swift` (v3 body, facts, provenance, version policy), `Authorization.swift` (`RestoreResult.provenance`, `.activateRestored`), `PrivacyModel.swift` (`pendingUserConfirmation`).
- CryptoKit: `BackupCodec.swift` (v3, provenance, digest check), `SecureVault.swift` (v3 export, attachments, `AttachmentCipher`).
- Store: `StoreModel.swift` (manifest v2, journal v2, `LedgerBinding`, `RestoreRisk`, `EntryKind`, ledger merge), `FileVaultStore.swift` (GATE 1 wiring, export, two-phase restore, attachments, limits), `VaultFileSystem.swift` (streamed reads, `replaceStreaming`), `KeyRetirement.swift` (`AttachmentFile`, inventory).
- Tests: `StoreLedgerBindingTests.swift`, `StoreBackupRestoreTests.swift`, `StoreAttachmentTests.swift`, `StoreScaleTests.swift` (new), `BackupV3Tests.swift` (new, XRAIVaultTests), updated `StoreCoreTests`, `StoreCrashAndRetirementTests`, `StoreFileSystemTests`, `StoreBoundaryTests`, `StoreHarness`, `VaultCryptoTests` (legacy forging pins v2).
- `XRAI.xcodeproj` regenerated (hosted bundle picks up the new test files; app target unchanged).
- Docs: this report; matrix addendum; threat model v1.10 (T49, T50); `OPEN_BLOCKERS.md`; ADR-BOOT-009 Amendment H.2; `NEXT_TASK.md`; `TEST_EVIDENCE_LEDGER.json`; `CLAUDE.md`; `validation/check_p03_03_docs.py`; evidence logs `evidence/p03_04b_*`.

## 3. Compatibility policy (stated)

| artifact | older format | policy |
|---|---|---|
| sealed backup | v2 | accepted as LEGACY: staged with `legacyFormat`, never "ours", no history; v1/unknown → `unsupportedFormat` |
| backup body v3 schema | ≠ 1 | `unsupportedFormat(schema)` |
| manifest | `XRAI-MANIFEST-1` | open refused `unsupportedFormat(1)` (no persisted vaults exist; no migration code) |
| journal | `XRAI-J-1` | vault opens read-only "journal format unsupported" |

## 4. Test runs (real results, exit codes)

| run | command | exit | result | log |
|---|---|---|---|---|
| GATE 1 first attempt | `swift test --filter StoreLedgerBindingTests…` | 1 | 1 test-expectation error (bytes vs plaintext); product unchanged | `evidence/p03_04b_gate1_run2_FAIL_1_test_expectation.log` |
| GATE 2/3 first attempt | `swift test --filter XRAIVaultStoreTests|BackupTests` | 1 | legacy forging test sealed with the new default version | `evidence/p03_04b_gate23_run1_FAIL_legacy_forge_version.log` |
| GATE 2/3 third attempt | same + BackupV3Tests | 1 | NT-BK-05/NT-RR-04 probes hit framing instead of the AEAD tag; NT-RR-12 found admission replay PARTIAL → replay made all-or-nothing (product fix) | `evidence/p03_04b_gate23_run3_FAIL_admission_partial_replay.log` |
| macOS package tests | `swift test` (Packages/XRAICore) | 0 | 191 tests in 44 suites passed (158 before + 33 new: NT-LR 8, NT-BK 8, NT-RR 5 suites-worth, NT-AT 11, NT-SC 1); compile-negative, import-boundary and GATE A scans included | `evidence/p03_04b_swift_test_macos.log` |
| Simulator hosted | `xcodebuild test … 'platform=iOS Simulator,name=iPhone 17' -only-testing:XRAIHostedTests` | 0 | 117 tests in 28 suites passed (86 before + 31 new; Data Protection assertions compiled out on the Simulator as in P03-04H) | `evidence/p03_04b_xcodebuild_sim_hosted.log` |
| iPhone 14 Pro Max hosted, non-destructive | `xcodebuild test … 'platform=iOS,id=C7C6CE6E-…' -only-testing:XRAIHostedTests -allowProvisioningUpdates` | 0 | 117 tests in 28 suites passed on iPhone 14 Pro Max "Dogi (2)" (iOS 26.6): GATE 1–4 suites, 64 MiB attachment streamed on device NAND, 500-record scale probe, real Keychain anchor, Data Protection assertions; non-destructive | `evidence/p03_04b_xcodebuild_device_hosted.log` |
| static: package spec | `python3 -I validation/validate_package.py` | 0 | PASS spec structure (files=4792); does not verify an iOS build | `evidence/p03_04b_validate_package.log` |
| static: docs consistency | `python3 -I validation/check_p03_03_docs.py` | 0 | PASS: 102 NT rows (48 + 12 + 42), T44–T50 present, P03-04b review consistent, admission no longer takes the instance id from the caller | `evidence/p03_04b_check_docs.log` |

Measured numbers (no performance claim; recorded from the logs):

| probe | macOS (Apple silicon) | Simulator (iPhone 17) | iPhone 14 Pro Max |
|---|---|---|---|
| NT-AT-10 64 MiB attachment write / read (2 passes) / RSS delta | write 0.59 s, read(2 passes) 0.59 s, RSS delta write 1 MiB, read 0 MiB | write 0.70 s, read(2 passes) 0.64 s, RSS delta write 0 MiB, read 0 MiB | write 0.88 s, read(2 passes) 0.95 s, RSS delta write 0 MiB, read 0 MiB |
| NT-SC-01 2 000 records: put / reopen / export v3 / restore+admit / activate / RSS delta | n=2000: put 168.55 s, reopen 0.06 s, export v3 0.54 s (0.5 MiB), restore+admit 57.27 s, activate 0.54 s, RSS delta 0 MiB | n=500: put 65.18 s, reopen 0.03 s, export v3 0.18 s (0.1 MiB), restore+admit 9.02 s, activate 0.14 s, RSS delta 1 MiB | n=500: put 66.17 s, reopen 0.05 s, export v3 0.17 s (0.1 MiB), restore+admit 10.38 s, activate 0.34 s, RSS delta 0 MiB |

Regression: every P03-04 (48) and P03-04H (12) row re-ran green on all three hosts, with these intended assertion changes: NT-H1-01/02/05/07 and NT-LR-06 use the two-phase admission API; NT-H1-05 now activates through `activateRestored` and asserts `releaseQuarantined` refuses restored records; NT-H5-03 asserts ledger trust after every crash; the legacy forging test pins version 2.

Not run: UI/XCUI (no UI change); destructive device scenarios; power-loss; thermal profiling.

## 5. Device verification status

DEVICE_VERIFIED: **PARTIAL** — hosted non-destructive suite (117/117) on iPhone 14 Pro Max "Dogi (2)", iOS 26.6, temp directories in the app container, real Keychain anchor, Data Protection assertions of P03-04H still green; 64 MiB attachment and 2 000-record scale probes executed on the device (numbers above). Not covered: lock/unlock transitions, reinstall, passcode removal, power loss, thermal throttling.

## 6. Open risks after P03-04b

1. Attachments are not part of backups; a restore brings parents without attachments (`ATTACHMENTS_NOT_IN_BACKUP`).
2. Whole backup in memory (≤ 256 MiB); streaming deferred.
3. The restore risk screen, consent UI and InteractionGate do not exist (P03-05); activation is a library API.
4. Corrupt-state marking is still in memory (`CORRUPT_STATE_IN_MEMORY`).
5. Unmergeable compacted digests fall back to a risk flag.
6. Resetting sticky ledger distrust needs a user-confirmed operation that does not exist yet.
7. No independent security review; no power-loss rig; SECURITY_REVIEWED: NO.

## 7. Final SHA

<!-- FINAL-SHA -->

## 8. GO / NO-GO

**Recommendation: NO-GO for app persistence until the next independent review; CONDITIONAL GO to plan P03-05** (consent UI, InteractionGate, restore risk screen, wiring behind the gate) once that review accepts GATE 1–4 and the stated limits (attachments not in backups, whole backup in memory, sticky distrust without a reset path, measured fsync cost: ≈ 84 ms per put on macOS, ≈ 130 ms on the iPhone, ≈ 20 ms per admitted file on the iPhone). The decision belongs to the reviewer and the founder.
