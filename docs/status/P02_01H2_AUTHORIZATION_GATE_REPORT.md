# P02_01H2_AUTHORIZATION_GATE_REPORT — V32-02-01H2

**Date:** 2026-10-19 · **Agent:** Claude Fable 5.1 · **Basis:** founder message "XRAI — V32-02-01H2 FINAL AUTHORIZATION GATE" (ChatGPT review of commit `026bbca`). **Scope executed:** G1–G5 only (F2 authorization boundary). **Gate:** STOP for ChatGPT review. P02-02 not started.

Türkçe özet: Kasaya erişim sözleşmesi kuruldu. Her işlem (seal/open/verify/rewrap/export/restore/release/delete) güvenilir `AuthorizationIssuer`'dan alınmış, kapsamlı, kısa ömürlü, tek kullanımlık bir yetki ister; çağıranın elindeki token kopyasına değil, ihraççının kayıtlı kopyasına bakılır. Zaman artık parametre değil, `VaultClock` portundan gelir; `MonotonicGuardClock` geri alınan saati reddeder. Her kayıt izin amacına (`consentPurpose`) kimlik doğrulamalı başlıkta bağlıdır; `open` için o amaca ait izin o anda aktif olmalıdır (iptal/süre sonu → red). Teknik bakım (`verify`, `rewrap`) düz metin döndürmez ve ayrı dar kapsam kullanır; `rewrap` öncesi bütünlük doğrulanır. Export ve silme kullanıcı hakkıdır, izin durumuna bağlı değildir; geri yüklemede izni aktif olmayan hassas kayıtlar karantinaya alınır ve yalnız yeni izin + ayrı yetkiyle serbest bırakılır. `SecureVault.keyProvider` private; `InMemoryKeyProvider` ayrı `XRAIVaultTesting` hedefine taşındı; derleyiciyle doğrulanan compile-negative test eklendi. build 0, test 0, 81/81; numeroloji çekirdeğinde diff yok. Swift erişim denetiminin aynı süreçteki kötü niyetli koda karşı güvenlik sınırı olmadığı açıkça kaydedildi. Bağımsız güvenlik denetimi hâlâ yok.

## 1. Gate items → implementation → tests

| gate | before | after | files | tests |
|---|---|---|---|---|
| **G1** unauthorized decryption | `open` only validated the header and decrypted; no purpose/consent check at read; `verify` returned nothing but used the same path; user rights undefined | Access contract in `XRAIVaultContracts/Authorization.swift`: `OperationScope` {write(class), read(recordIDs?), exportBackup, restoreBackup, releaseQuarantine, delete(ids), maintenance(kind)}. `open` requires a `.read` token covering the record **with purpose == record's `consentPurpose`** and `VaultPolicy.mayRead` (active grant now). `consentPurpose` is a new authenticated header field (format v2; v1 rejected). `verify`/`rewrap` need `.maintenance(...)` tokens, never return plaintext, need no consent. `exportBackup` (`.exportBackup`) and `authorizeDeletion` (`.delete`) are explicit user-rights paths independent of consent state. | `Authorization.swift` (contracts), `Envelope.swift`, `PrivacyModel.swift` (`mayRead`), `SecureVault.swift` | `ReadAccessTests`: revokedConsent, expiredConsent, purposeBinding, scopeOnRead, maintenanceSeparation, userRights |
| **G2** key provider boundary | `SecureVault.keyProvider`/`consentAuthority` were `public let`; `InMemoryKeyProvider` was public in the adapter | All vault ports are `private let`; only `currentKeyIdentity` (no material) is exposed. `InMemoryKeyProvider`, `InMemoryConsentAuthority`, `ManualClock` moved to a new **`XRAIVaultTesting`** target; the adapter keeps an internal `GCMKeyWrapper` for backup keys only. Composition root = `SecureVault.init(keyProvider:consentAuthority:clock:authorizations:)`, called once by the app layer. Test enforces that no non-test target depends on `XRAIVaultTesting`. **Compile-negative test** runs `swiftc -typecheck` against the built modules: a positive control compiles; six negative snippets (raw sealer, codec, key wrapper, `vault.keyProvider`, `vault.sealer`, `InMemoryKeyProvider` via the adapter) fail to compile. Residual risk documented (threat model T23): `KeyProvider` remains a public protocol so a production adapter can implement it; Swift access control is not a boundary against malicious same-process code. | `SecureVault.swift`, `AESGCMEnvelopeSealer.swift`, `XRAIVaultTesting/TestingDoubles.swift`, `Package.swift` | `CompositionBoundaryTests`: manifestRule, vaultSurface, compileNegative |
| **G3** fake time / fake user action | `nowUnixSeconds` and `userInitiated: true` were caller parameters | `VaultClock` port; `SystemClock` + `MonotonicGuardClock` (tolerance 300 s, per-process high-water mark; limits documented: rollback before first observation undetectable, mark not persisted). `AuthorizationIssuer` issues tokens (random 128-bit id, TTL ≤ 300 s), `consume` is atomic and single-use even on a failed attempt; unknown/replayed/expired/not-yet-valid/over-long-TTL rejected; caller-side tampering with scope/expiry has no effect because the issuer's copy is used; tokens from another issuer are unknown. `userInitiated` parameter removed. Explicitly NOT an OS boundary. | `XRAIVaultCryptoKit/Authorization.swift`, contracts | `ClockAndTokenTests`: clockRollback, tokenLifecycle, fakeUserAction |
| **G4** integrity and recovery | `rewrap` re-wrapped without verifying payload; restore re-enabled every record; export cap only checked ciphertext per record | `AESGCMEnvelopeSealer.rewrap` opens (verifies) first. `restoreBackup` returns `RestoreResult{active, quarantined}`: consent-gated records without an active grant for their bound purpose are quarantined, unreadable, and released only via `releaseQuarantine` with a `.releaseQuarantine` token **and** an active grant (a grant for another purpose does not release). Export: running size check per record, padded body measured **before** sealing against `maxBackupBytes`; memory ≈ 2× backup size, streaming deferred (documented). | `AESGCMEnvelopeSealer.swift`, `SecureVault.swift`, `BackupCodec.swift` | `IntegrityAndQuarantineTests`: rewrapVerifies, quarantine; `BackupTests.saltsAndLimits` |
| **G5** evidence | — | see §2; all 71 prior tests kept (updated for the new signatures: tokens instead of `userInitiated`/`nowUnixSeconds`, header v2, `consentPurpose`) + 10 new; compile-negative implemented with the real compiler | — | 81/81 |

## 2. Commands and exit codes

| command (cwd `Packages/XRAICore`) | exit | result | evidence |
|---|---|---|---|
| `swift build` | 0 | ok | `evidence/p02_01h2_swift_build.log` (`8bcfbe88…9f3a`) |
| `swift build --build-tests` (first) | 0 | ok | — |
| `swift test` run 1 | 1 | 81 tests, 79 pass, 3 issues: replay reported as `unknownToken` instead of `alreadyConsumed` (issuer removed the id before checking the consumed set; fixed by checking `consumed` first) and a source-scan false positive on a comment mentioning `InMemoryKeyProvider` (test narrowed to `class InMemoryKeyProvider`). **Compile-negative test passed on the first run.** | `evidence/p02_01h2_swift_test_run1_FAILED_3_issues.log` (`f39d6478…74df`) |
| `swift test` run 2 | **0** | **81 tests in 19 suites passed** | `evidence/p02_01h2_swift_test_run2.log` (`cd2feec0…652d`) |
| `git diff --stat` on BOOT-01 dirs | 0 | empty (numerology engine untouched) | — |

Vault sources + tests: 2,286 lines (was 1,741).

## 3. G5 negative-test checklist

| required | test | result |
|---|---|---|
| open with revoked consent denied | `ReadAccessTests.revokedConsent` | pass |
| read with expired consent denied | `ReadAccessTests.expiredConsent` | pass |
| rolled-back clock gains no authority | `ClockAndTokenTests.clockRollback` (guard throws `clockRegressed`; expired token stays expired) | pass |
| forged / replayed user-action authorization denied | `ClockAndTokenTests.tokenLifecycle`, `fakeUserAction` | pass |
| direct KeyProvider access surface limited | `CompositionBoundaryTests.vaultSurface`, `compileNegative` (compiler-verified), `manifestRule` | pass |
| corrupted envelope cannot be rewrapped as valid | `IntegrityAndQuarantineTests.rewrapVerifies` | pass |
| revoked sensitive consent does not silently return from an old backup | `IntegrityAndQuarantineTests.quarantine` | pass |
| no regression in the existing 71 | all prior suites pass (35 BOOT-01 unchanged, 36 vault updated to the new contract) | pass |

## 4. Residual risks (honest)
- **Not an OS boundary.** Tokens, clock guard, private properties and the testing-target split stop accidental misuse and make access explicit; malicious code in the same process can still call `KeyProvider` implementations or use `@testable`. Real isolation needs Keychain/Secure Enclave non-extractable keys (P02-02) and app-level hardening.
- `KeyProvider` and `ConsentAuthority` are public protocols by necessity (production adapters). Documented (T23).
- Monotonic clock high-water mark is per process; a rollback before the first observation is invisible; persisting the mark is a store-layer task.
- Consumed-token ids are retained in memory for the process lifetime (small, random); a persisted replay list is future work.
- Restore decrypts each payload once to verify it; acceptable for user-initiated restore.
- Backup size leaks at 4 KiB granularity (unchanged from H1).
- No persistence, no Keychain adapter, no independent security review yet. Status: library **CODED + TESTED**; **SECURITY_REVIEWED: NO**; **DEVICE_VERIFIED: NO**.

## 5. Records
ADR-BOOT-005 Amendment H2; threat model v1.2 (T23–T26); `TEST_EVIDENCE_LEDGER.json`, `OPEN_BLOCKERS.md`, `NEXT_TASK.md` updated. Normal commit and push; no history rewrite.

**STOP — awaiting ChatGPT review. If H2 is accepted, next task: P02-02 `KeychainKeyProvider`.**
