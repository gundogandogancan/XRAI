# P02_01H_SECURITY_HARDENING_REPORT — V32-02-01H

**Date:** 2026-10-19 · **Agent:** Claude Fable 5.1 · **Basis:** founder message "XRAI — V32-02-01H SECURITY HARDENING" (ChatGPT review of P02-01 code). **Scope executed:** V32-02-01H only. **Gate:** STOP for ChatGPT review. P02-02 not started.

Türkçe özet: ChatGPT'nin altı bulgusu kapatıldı. (1) Yedek artık dış AES-256-GCM zarfı: kayıt kimlikleri, sınıflar, tier'lar, zamanlar ve sayı şifreli gövdede; açıkta yalnız magic, sürüm, salt, nonce ve etiket var; 4 KiB blok dolgusu ile boyut sızıntısı kabalaştırıldı (tam gizlenmedi, belirtildi). (2) Politika zorunlu: tek yetkili giriş noktası `SecureVault`; ham mühürleyici ve yedek kodlayıcı dışa kapalı; izin yalnız `ConsentAuthority` portundan sorulur, çağıranın elindeki makbuz hiçbir yetki vermez; iptal/süre sonu uygulanır. (3) Tier downgrade fail-closed: `RecordDescriptor` oluşturulurken, her `open`'da ve içe alımda `validate()`; `parentsNames` + `publicContent` reddedilir. (4) `RecordID` rastgele 128-bit; açıklamalar ve hata değerlerinde kayıt/anahtar kimliği yok; crash log ham veri için sert red. (5) Export'ta her zarf gerçekten doğrulanıyor (bozuk/yabancı/karışık zarf reddedilir); içe alımda boyut, kayıt sayısı, alan uzunluğu, yinelenen kimlik, dolgu sınırları. Sonuç: build 0, test 0, 71/71; BOOT-01 numeroloji dosyalarında sıfır diff. Bağımsız güvenlik denetimi hâlâ yapılmadı; kasa "tamamlandı" değil.

## 1. Findings → fixes → evidence

| # | finding (before) | fix (after) | files | tests |
|---|---|---|---|---|
| F1 | `PortableBackup` v1 carried every `RecordEnvelope` header in the clear (record ids, data classes, tiers, retention, timestamps, entry count) protected only by HMAC. | **Format v2 `SealedBackup`**: outer AES-256-GCM envelope; `BackupBody` (createdAt + entries) is the ciphertext; AAD = magic‖version‖salt‖nonce; body length-prefixed and zero-padded to 4096-byte blocks. HKDF-SHA256 with two context strings (`xrai.backup.kek.v2` for DEK wrapping, `xrai.backup.outer.v2` for the outer key). HMAC layer removed (GCM tag authenticates). v1 files are rejected as `unsupportedFormat(1)`. **Size leakage:** padded ciphertext length still reveals total size at 4 KiB granularity; documented in `Backup.swift` and threat model T18. | `Backup.swift`, `BackupCodec.swift` | `metadataConfidentiality` (asserts byte layout = header + ciphertext only; no record id / class / tier / timestamp / inner ciphertext / plaintext / recovery key bytes present; padding multiple), `corruptedOrWrongKey` (v1 rejected), `salts` (context separation) |
| F2 | `VaultPolicy` was advisory; `AESGCMEnvelopeSealer` and `BackupCodec` were public and could be called without any policy check; `decide(consent:)` trusted a caller-supplied `ConsentReceipt`. | **`SecureVault`** is the only public entry point (seal/open/verify/rewrap/exportBackup/restoreBackup). `AESGCMEnvelopeSealer` and `BackupCodec` are `internal`. New port **`ConsentAuthority`**; `VaultPolicy.decide/mayStore` take the authority, never a receipt. `ConsentReceipt` gained `expiresAtUnixSeconds`. `mayBackup` requires `userInitiated` and excludes `sessionOnly`. | `PrivacyModel.swift`, `SecureVault.swift`, sealer/codec visibility | `EnforcementTests` (consent gate, revocation re-locks, forged receipt ignored, facade-only reflection), `PolicyTests.forgedReceipt/revocationAndExpiry/backupGate`, `ImportBoundaryTests` (asserts the raw types are not `public`) |
| F3 | A caller could label `parentsNames` as `publicContent`; `defaultTier` was only a default. | `DataClass.minimumTier` floor; `RecordDescriptor.init` **throws** below floor; `EnvelopeHeader.validate()` runs at seal, at every open, at rewrap and inside `EnvelopeHeader.decode` (import). Fail closed with `privacyTierBelowMinimum`. | `PrivacyModel.swift`, `Envelope.swift` | `TierTests.descriptorFloor` (every class × publicContent rejected), `CanonicalTests.headerBytes` (decode of downgraded header throws), `SealAdversarialTests.tamperHeader` (open with downgraded header fails before crypto), `BackupTests.forgedBody` #1 (downgrade inside a validly encrypted backup rejected) |
| F4 | `RecordEnvelope.description` printed `recordID` and key id; `keyUnavailable(keyID:version:)` carried the key id; record ids were free-form strings. | `RecordID`: 128-bit CSPRNG hex, strict parser (rejects upper-case, wrong length, non-hex, name/date-shaped input), redacted description; contract documented. Envelope description shows only class/tier/alg/keyVersion. `VaultError` carries no identifiers (`keyUnavailable(version:)`). `crashLogs` added to `hardDeniedForPersonalData` (raw personal content never reaches crash logs; a generic receipt cannot unlock it). | `Envelope.swift`, `PrivacyModel.swift` | `CanonicalTests.recordIDs`, `RecoveryKeyContractTests.errorHygiene`, `SealRoundTripTests.redaction`, `PolicyTests.hardRules` (crashLogs) |
| F5 | Export re-wrapped DEKs without verifying the payload; a tampered or foreign envelope became part of a "valid" backup. Import had no size/count/length/duplicate limits. | Export: `userInitiated` required, header validate, `mayBackup`, unique ids, length limits, **payload verify (decrypt-and-discard) for every envelope** → `envelopeIntegrityFailed`. Import: 256 MiB file cap, strict decode, entry cap 100 000, per-field length checks, DEK/record binding check, duplicate id rejection, padding check, and **payload verify under the new keys** before returning. `BackupLimits` constants. | `SecureVault.swift`, `Backup.swift` | `unauthorizedExport` (not user-initiated, session-only, duplicate, tampered, foreign device, mixed DEK), `corruptedOrWrongKey` (wrong key, 7 bit-flips, truncation, trailing, bad magic, v1, oversize), `forgedBody` (downgrade, duplicate, forged count, smuggled session-only, tampered inner payload, bad padding; sanity restore) |
| F6 | — | Existing 64 tests kept or updated with reasons: policy tests now go through the authority (signature change); backup tests rewritten for v2; record ids are `RecordID`; `keyUnavailable` arity changed. Numerology/CivilDate sources and tests: **zero diff** (`git diff --stat` empty). | — | 71/71 |

## 2. Commands and exit codes

| command (cwd `Packages/XRAICore`) | exit | result | evidence |
|---|---|---|---|
| `swift build --build-tests` (first) | 1 | 4 test-compile errors (`Comment` type for dynamic messages, a stray expression, missing `try`); fixed | — |
| `swift build` | 0 | ok | `evidence/p02_01h_swift_build.log` (`61cf76d3…ad9b`) |
| `swift test` run 1 | 1 | 71 tests, **70 pass / 1 fail**: my hygiene test searched for the substring "device", which legitimately occurs in tier names (`DEVICE_ONLY_*`); narrowed to the key id `device-main` | `evidence/p02_01h_swift_test_run1_FAILED_1_of_71.log` (`1a9d832d…ec15`) |
| `swift test` run 2 | **0** | **71 tests in 17 suites passed** | `evidence/p02_01h_swift_test_run2.log` (`76fc6b76…f4b3`) |
| `git diff --stat` on BOOT-01 dirs | 0 | empty (pure numerology core untouched) | — |

Test count: 35 BOOT-01 + 36 vault (was 29). New Swift in this task: vault sources + tests now 1,741 lines (was 1,315).

## 3. Residual risks (honest)
- Backup size leaks total volume at 4 KiB granularity; a fixed-size or bucketed padding scheme can be added when the UI defines backup cadence.
- Keys live in process memory while in use; no zeroization guarantees in Swift.
- `InMemoryKeyProvider` is a test double; the production Keychain/Secure Enclave provider does not exist (P02-02). **No real data may be persisted.**
- `ConsentAuthority` is a port; the real registry (its own encrypted storage, audit trail, UI) is future work. The test double lives only in tests.
- Restore verifies every payload, which decrypts each record once in memory; acceptable for a user-initiated restore, noted.
- Backup `createdAt` is now inside the ciphertext; the file system's own mtime may still leak when it was written.

## 4. Independent security review status
**NOT DONE.** Statuses remain: contracts/adapter **CODED + TESTED (library)**; **SECURITY_REVIEWED: NO**; **DEVICE_VERIFIED: NO**. ADR-BOOT-005 amended (hardening section), threat model v1.1 (T7/T8 updated, T18–T22 added).

## 5. Commit
Normal commit on `main`, normal push (no force, no history rewrite).

**STOP — awaiting ChatGPT review. Next phase (P02-02 Keychain provider or V32-02-02) is not started.**
