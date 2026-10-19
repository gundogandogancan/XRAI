# P03_04_IMPLEMENTATION_CONTRACT — the smallest safe scope for the first encrypted store

**Date:** 2026-10-20 · **Baseline:** `7fc3091` · **Pre-condition:** independent architecture approval of ADR-BOOT-009 + Amendment H written into `NEXT_TASK.md` · **Not started.**

Türkçe özet: P03-04 yalnız kütüphane düzeyinde `XRAIVaultStore` hedefi ekler; uygulama bağlanmaz, gerçek kişisel veri yazılmaz, testler fikstür verisi ve geçici dizinlerle çalışır. Kapsam dışı: izin arayüzü, InteractionGate, ekler (attachments), yedek gövdesi v3'ün arayüzü, SQLCipher. Kabul: `P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md`'deki zorunlu testlerin tamamı macOS ve Simulator'da, cihazda ise yıkıcı olmayan alt küme geçmeden TESTED yazılmaz.

## 1. Scope IN (phase 1)
| item | contract |
|---|---|
| target `XRAIVaultStore` | imports Foundation, `XRAIVaultContracts`, `XRAIVaultCryptoKit` only; never Security, never CryptoKit directly (import-boundary test extended); `XRAIVaultTesting` stays test-only |
| `actor FileVaultStore: VaultStore` | single writer; all mutations journaled; opened only after `recover()` succeeds |
| `VaultStore` port | `put`, `get`, `delete(ids, grant)` (immediate), `revoke(purpose, mode)`, `restoreSuspended(ids, authorization)`, `rewrapAll`, `retirementProof(for:)`, `recover()`, `state(of:)`, `integrityReport()` |
| layout | `root/{system/manifest.v1, system/ledger.v1, system/authz.v1, records/<32hex>.env, journal/<seq>.j, orphans/, .tmp-*}`; root under Application Support, `isExcludedFromBackup = true`, `NSFileProtectionComplete`; 4 KiB padding |
| manifest | encrypted envelope; `{ generation, prevHash, minimumWrapVersion, retiredVersions, records[id → {dataClass, tier, retention, createdAt, keyVersion, derivedFrom, dependents, state}], keyUsage, lastExportedGeneration, vaultInstanceID }` |
| deletion ledger | permanent, append-only, cross-bound to manifest; digest compaction code path present but disabled below 200 000 entries |
| journal | length-prefixed AEAD entries; `begin{tokenID, scope, ids, epoch}` … `commit`; replay on launch; truncated tail discarded; mid-file failure → quarantine + `needsRecovery` |
| authz persistence | `authz.v1 { epoch, clockHighWaterMark, lastManifestGeneration, lastManifestHash }`; epoch++ on every open; `PersistedGuardClock` wraps `MonotonicGuardClock` |
| Keychain anchor | `vault/anchor` item via `KeychainStore` pointer mechanism (add new, delete old); `(generation, manifestHash)`; mismatch → read-only + no restore |
| key retirement | protocol v2 R0–R7 (`P03_03H_SECURITY_REMEDIATION_REPORT.md` H2); `KeyRetirementCoordinator` is the only caller of `forget` |
| derived graph | `derivedFrom` in authenticated header **v3** (new records only); reverse index; back-edge rejection; cascade dependents-first; stale state |
| path safety | id validation, `O_NOFOLLOW`, `lstat` root, regular-file check |
| fault injection | test-only `FileSystemFaults` seam (kill/throw at syscall k) injected through the initializer; production initializer uses `RealFileSystem` with no fault hooks (compile-negative test as in P03-00) |
| header v3 | `EnvelopeHeader.formatVersion = 3` adds `derivedFrom: [RecordID]`, `schemaVersion: UInt16`; v2 still decodes as a leaf; no migration of personal data exists |

## 2. Scope OUT (explicitly)
No app wiring (`SecurityStatus` composition root unchanged); no consent UI; no `InteractionGate` (P03-05); no attachments/chunking (P03-04b); no backup body v3 / restore reconciliation UI (P03-04b: `BackupBody` v3 with `vaultInstanceID`, `backupGeneration`, embedded ledger; `BackupCodec` extension); no SQLCipher; no biometrics; no cloud; no real personal data; no changes to BOOT-01, `XRAIVaultKeychain`, or the crypto primitives except the additive header v3 and a new `VaultError` cases list (`staleKeyVersion`, `storeIntegrityFailed`, `manifestRollback`, `authzStateUntrusted`, `needsRecovery`, `recordSuspended`, `recordMissing`).

## 3. Invariants the implementation must keep (test-enforced)
1. Nothing is readable through `get` unless manifest state == `active` and policy/consent/quarantine pass (NT-H5-14).
2. A known-deleted id can never return to `active` (NT-H1-01…04).
3. `forget(N)` cannot succeed unless protocol v2 R1–R5 produced a proof for the current manifest generation inside the same exclusive section (NT-H2-01…08).
4. No envelope with `keyVersion < minimumWrapVersion` is ever written (NT-H2-04).
5. Every mutation is journaled before its first side effect; recovery is idempotent (NT-H5-01…03).
6. `authz.v1` never leaves the device in a backup; epoch strictly increases (NT-H3-01…05).
7. Revoke is linearizable with reads (NT-H3-06); "Kalıcı sil" has no grace (NT-H4-01).
8. Directory listing of a populated vault reveals only hex names, `system/*.v1`, `journal/*.j`, padded sizes (NT-H5-15).
9. Production target never links `XRAIVaultTesting` or fault seams (manifest + compile-negative tests).

## 4. Evidence required before "TESTED"
macOS `swift test` log + exit code; Simulator hosted run log (temp directory inside the app container, Data Protection class asserted via `FileManager` attributes); iPhone 14 Pro Max hosted run for the non-destructive subset (no reinstall, no passcode change); all logs hashed in `TEST_EVIDENCE_LEDGER.json`. DEVICE_VERIFIED may be PARTIAL; SECURITY_REVIEWED stays NO until `VAULT_SECURITY_REVIEW`.

## 5. Definition of done for P03-04
All rows marked MANDATORY in `P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md` TESTED with evidence; no change to protected paths beyond §2; `validate_package.py`, `check_p03_03_docs.py`, import-boundary and compile-negative tests green; report `P03_04_STORE_REVIEW_REPORT.md`; STOP for review. Still no personal data persisted by the app.
