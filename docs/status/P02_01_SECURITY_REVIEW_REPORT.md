# P02_01_SECURITY_REVIEW_REPORT — V32-02-01 (vault contracts + crypto adapter)

**Date:** 2026-10-19 · **Agent:** Claude Fable 5.1 · **Approval basis:** founder message "XRAI — GOD LEVEL P02 SECURITY APPROVAL" after ChatGPT review of BOOT_00_REPORT (recorded in `docs/status/NEXT_TASK.md`). **Scope executed:** V32-02-01 only. **Gate:** STOP for ChatGPT review.

Türkçe özet: Kasa için saf sözleşme modülü (`XRAIVaultContracts`, hiçbir import yok) ve ayrı CryptoKit adaptörü (`XRAIVaultCryptoKit`) yazıldı. AES-256-GCM zarf şifreleme, kayıt başına rastgele DEK, her mühürlemede yeni nonce, kimliği doğrulanmış sürümlü başlık, DEK'in kayda bağlı sarmalanması, anahtar rotasyonu, kurtarma anahtarıyla uçtan uca şifreli taşınabilir yedek ve geri yükleme uygulandı. Yanlış anahtar, değiştirilmiş veri/etiket/nonce/başlık, DEK değiş tokuşu, bozuk/kısaltılmış/sıralaması değişmiş yedek, yanlış kurtarma anahtarı, nonce tekrarı, politika ihlali senaryoları test edildi. Sonuç: build 0, test 0, 64/64 (BOOT-01'in 35 testi dahil, regresyon yok). Keychain/Secure Enclave üretim sağlayıcısı henüz yazılmadı; gerçek veri kalıcılığı yok; bağımsız güvenlik denetimi yapılmadı. Kasa "tamamlandı" DEĞİL.

## 1. What was built (files)

| file | lines | purpose |
|---|---|---|
| `Packages/XRAICore/Sources/XRAIVaultContracts/PrivacyModel.swift` | 196 | `PrivacyTier`, `DataClass` (+ default tiers from the egress matrix), `Destination`, `RetentionClass`, `ConsentScope`, `ConsentReceipt`, `VaultPolicy` (deny-by-default), `PolicyDecision` |
| `…/XRAIVaultContracts/Envelope.swift` | 236 | `VaultError`, `EnvelopeAlgorithm`, `RecordDescriptor`, `EnvelopeHeader` (authenticated canonical bytes), `WrappedKey`, `RecordEnvelope` (redacted description), ports `KeyProvider`, `EnvelopeSealer` |
| `…/XRAIVaultContracts/Backup.swift` | 130 | `RecoveryKey` (256-bit, redacted, display/parse), `PortableBackup` (versioned, salted, MAC-covered, strict decoder) |
| `…/XRAIVaultContracts/CanonicalCoding.swift` | 86 | deterministic big-endian encoder/decoder, constant-time compare |
| `…/XRAIVaultCryptoKit/AESGCMEnvelopeSealer.swift` | 170 | AES-256-GCM sealer; `InMemoryKeyProvider` (dev/test double) with rotate/forget |
| `…/XRAIVaultCryptoKit/BackupCodec.swift` | 96 | HKDF-SHA256 key derivation, export/restore with HMAC-SHA256 integrity |
| `Packages/XRAICore/Tests/XRAIVaultTests/VaultContractsTests.swift` | 165 | policy, consent, tiers, canonical coding, recovery key contract |
| `Packages/XRAICore/Tests/XRAIVaultTests/VaultCryptoTests.swift` | 332 | round trip, nonce strategy, redaction, wrong key, tamper (bytes + header), DEK swap, versions, rotation, backup/migration, corruption, reorder, salts, import boundary |
| `Packages/XRAICore/Package.swift` | edit | two new targets + test target |
| `…/Tests/XRAINumerologyTests/PrivacyNegativeTests.swift` | edit | scan scoped to the pure-math modules (vault modules get the stricter `ImportBoundaryTests`) |
| `docs/adr/ADR-BOOT-005-vault-envelope-and-recovery.md`, `docs/security/VAULT_THREAT_MODEL_P02.md` | new | decisions, alternatives, threat table T1–T17 |

Total new Swift in this task: 1,315 lines (sources + tests).

## 2. Commands and exit codes

| command (cwd `Packages/XRAICore`) | exit | result | evidence |
|---|---|---|---|
| `swift build` (first) | 1 | `String(validating:as:)` needs macOS 15; replaced by decode-and-compare | — |
| `swift build` | 0 | ok | `docs/status/evidence/p02_01_swift_build.log` (sha256 `61cf76d3…ad9b`) |
| `swift test` run 1 | 1 | compile error in a test (`try` missing on a throwing `#expect`) | fixed |
| `swift test` run 2 | 1 | 64 tests, **63 pass / 1 fail**: my static-scan token `contentsOf:` matched `Array.append(contentsOf:)`, a false positive; token narrowed to `Data(contentsOf`/`String(contentsOf` and `Keychain`/`SecItem` added | `evidence/p02_01_swift_test_run2_FAILED_1_of_64.log` (`2062be90…7ccd`) |
| `swift test` run 3 | **0** | **64 tests in 16 suites passed** | `evidence/p02_01_swift_test_run3.log` (`ca22c2b2…850b`) |

BOOT-01 regression: the 35 BOOT-01 tests are part of the 64 and all pass (suites listed in the log). Exit codes were captured with `$?` directly after each command.

## 3. Security scenarios tested (all pass)

- **Wrong key:** different KEK with same key id → `authenticationFailed`; unknown key id → `keyUnavailable`.
- **Tampered ciphertext / tag / nonce / wrapped-DEK ciphertext / wrapped-DEK tag** → `authenticationFailed`; original still opens.
- **Tampered authenticated metadata** (data class, tier downgrade, retention, timestamp, record id) → `authenticationFailed`.
- **DEK swap between records** → rejected (AAD binding).
- **Nonce strategy:** 500 seals of the same plaintext → 500 distinct payload nonces, 500 distinct ciphertexts, 500 distinct wrap nonces.
- **Key rotation:** rotate → rewrap keeps payload bytes identical, changes wrap; forget old version → old envelope `keyUnavailable`, rewrapped opens; current version cannot be forgotten.
- **Backup / new device:** export → bytes → decode equals → restore under a new provider; plaintext recovered; old keys useless for restored envelopes; backup bytes contain neither plaintext nor recovery key.
- **Corrupted backup:** single-bit flips at 7 positions (magic, version, salt, body, tag) all rejected; truncation, trailing bytes, bad magic rejected; entry reorder and drop rejected by MAC; wrong recovery key rejected.
- **Privacy policy:** every personal class × {analytics, model training, cloud sync, advertising} denied even with blanket consent; provider egress needs active matching consent; revocation is effective at the revocation second; parent names cannot be stored without purpose consent.
- **Redaction / leakage:** envelope and recovery key descriptions redacted; envelope has no plaintext field (Mirror); ciphertext does not contain plaintext substrings.
- **Module boundary:** contracts import nothing; adapter imports only CryptoKit/Foundation/contracts; no other module imports CryptoKit/Security/Foundation; no IO/log/Keychain tokens in vault modules.

## 4. What is NOT done (hard limits respected)

| item | status |
|---|---|
| Production `KeychainKeyProvider` (Keychain `ThisDeviceOnly`, Secure Enclave where available, biometric/app-lock gating) | NOT_STARTED (P02-02, needs physical iPhone) |
| Persistent store (encrypted SQLite/GRDB/SQLCipher choice, WAL/temp/backup-exclusion, Data Protection class) | NOT_STARTED (JOURNAL_SECURITY stays open) |
| Derived-data invalidation / deletion graph | NOT_STARTED (V32-02-02) |
| Runtime `NetworkEgressBroker` and on-device traffic trace | NOT_STARTED (P06/P12) |
| Any real user data persisted | NONE (hard limit) |
| Cloud backup / sync | NONE (decision 3) |
| Independent security review / pen test | NOT DONE — vault is **CODED + TESTED (library)**, not SECURITY_REVIEWED, not DEVICE_VERIFIED |
| Memory zeroization of keys | best effort only; documented residual risk |

## 5. Decisions recorded
Founder decisions 1–6 → `NEXT_TASK.md` approval record; engineering decisions → ADR-BOOT-005; threats → `VAULT_THREAT_MODEL_P02.md`. `OPEN_BLOCKERS.md` updated: DEVICE_BACKUP_POLICY and PARENT_NAME_SCOPE resolved by decision; KEYCHAIN_PROVIDER added as NOT_STARTED.

## 6. Commit
Normal commit on `main`, pushed without force (see git log). No history rewritten.

## 7. Next smallest implementable task (proposal, not started)
**P02-02 `KeychainKeyProvider`**: Security-framework adapter implementing the `KeyProvider` port (KEK in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, Secure Enclave wrapping where `SecureEnclave.isAvailable`, capability flag in `KeyIdentity`), plus a simulator smoke test and a **physical-iPhone** test checklist (passcode removed, reinstall, backup/restore exclusion). Alternatively V32-02-02 (derived-data invalidation graph) can run first since it is pure. ChatGPT review decides.

**STOP — awaiting review.**
