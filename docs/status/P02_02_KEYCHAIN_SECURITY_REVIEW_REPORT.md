# P02_02_KEYCHAIN_SECURITY_REVIEW_REPORT — production key provider on Keychain / Secure Enclave

**Date:** 2026-10-19 · **Agent:** Claude Fable 5.1 · **Basis:** founder message "XRAI — P02-02 KEYCHAIN / SECURE ENCLAVE ENGINEERING" (H2 accepted at library level). **Scope executed:** GATE 0 (two fixes), GATE 1 (KeychainKeyProvider), GATE 2 (Secure Enclave design + implementation), GATE 3 (tests on macOS host and iOS Simulator), GATE 4 (limits, blockers). **Gate:** STOP for ChatGPT code review. **DEVICE_VERIFIED: NO — no physical iPhone was connected or tested.**

Türkçe özet: GATE 0: etkin zaman artık asla yüksek su işaretinin altına inmiyor (tolerans içindeki geri alma işareti döndürür, dışı reddedilir; 1–300 s geri alma iptal edilmiş izni canlandıramıyor, test edildi); karantina güvenilir `QuarantineAuthority` kaydıyla her `open`'da denetleniyor, yeniden izin tek başına açmıyor, release için geçerli yetki + aktif izin şart. GATE 1–2: yeni `XRAIVaultKeychain` modülü (Security'yi import eden tek modül): cihaza bağlı, eşitlenmeyen, `ThisDeviceOnly` Keychain KEK'leri; sürümleme, rotasyon (önce yeni öğe sonra işaretçi), güvenli unutma, bozuk/eksik/çakışan kayıtta fail-closed; Secure Enclave P-256 anahtarı ile ECDH+HKDF+AES-GCM üzerinden KEK sarmalama; donanım yokken sessiz düşürme yok, `required` politikası fail-closed, koruma düzeyi doğru raporlanıyor. GATE 3: macOS'ta gerçek Keychain ve bu Apple-silicon Mac'in gerçek Secure Enclave'i ile 100/100 test (exit 0); iOS simülatöründe host app yetkisi olmadığından sağlayıcı fail-closed davrandı (−34018), işlevsel Keychain testleri simülatörde host app gerektiriyor. Fiziksel iPhone testi yapılmadı. Numeroloji çekirdeğinde diff yok. Kalan açık koşullar: cihaz testleri, simülatör host app, yeniden kurulum anahtar politikası, `AuthorizationIssuer.issue()`'nun gerçek kullanıcı etkileşimine bağlanması, `DeletionGrant` doğrulaması, bağımsız güvenlik denetimi.

## 1. GATE 0 — mandatory fixes

| item | before | after | tests |
|---|---|---|---|
| 0A clock rollback | `MonotonicGuardClock` returned the (lower) base time when within tolerance | returns the high-water mark whenever the base clock is below it; beyond tolerance throws `clockRegressed`; limits documented (per-process mark, undetectable pre-first-observation rollback → blocker AUTHZ_PERSISTENCE kept) | `ClockRollbackTests.revokedStaysRevoked` (back 1/60/150/299/300 s: effective time = mark, revoked consent stays revoked; 301 s → refused), `expiredTokenStaysExpired`; `clockRollback` updated |
| 0B quarantine | quarantine existed only as a returned wrapper value; after re-granting consent the same envelope could be `open()`ed | new port `QuarantineAuthority`; `restoreBackup` registers quarantined ids; `open()` consults the registry **before** consent (`quarantined` error); `releaseQuarantine` requires `.releaseQuarantine` token AND an active grant for the bound purpose, only then removes the id; releasing a non-quarantined id is an error | `QuarantineEnforcementTests.reGrantAlone` (direct open refused, open after re-grant refused, wrong-scope and forged token refused, proper release works, double release errors), `tokenAlone`, `registryIsSourceOfTruth` |

## 2. GATE 1 — `KeychainKeyProvider` (new module `XRAIVaultKeychain`)

- Items: generic passwords, `kSecAttrSynchronizable=false`, data-protection keychain, accessibility `WhenUnlockedThisDeviceOnly` (default), `AfterFirstUnlockThisDeviceOnly` (opt-in), `WhenPasscodeSetThisDeviceOnly` (offered; trade-off in ADR-BOOT-006 D2: OS deletes items on passcode removal → irrecoverable, so not default until onboarding explains it).
- Layout `<keyID>/meta`, `<keyID>/current`, `<keyID>/kek/v<N>`; add-only (`SecItemAdd`), duplicates are `keychainConflict`; rotation writes the new version before moving the pointer; orphans above `current` are unusable and block the next rotation (fail closed); `forget` deletes an old version; `wipeAllKeys` is the explicit irreversible wipe; mode/accessibility stored in `meta` and compared on load (mismatch → fail closed).
- Fail closed on: missing item, wrong length, bad SE blob, mode mismatch, keychain unavailable (locked, denied, missing entitlement), SE required but absent. OSStatus → identifier-free `VaultError` via a pure, unit-tested mapping.
- Key material is never written to UserDefaults, files, logs, crash logs or Git (source scan test; module imports only Security/CryptoKit/Foundation/contracts/cryptokit adapter). `InMemoryKeyProvider` stays in `XRAIVaultTesting`; a manifest test proves no production target depends on it and that `XRAIVaultKeychain` does not import it.
- Reinstall lifecycle evaluated: iOS keeps keychain items across reinstall → stale KEK set without records; policy recorded as blocker `REINSTALL_KEY_POLICY` for P03 (adopt explicitly or `wipeAllKeys()` on fresh install).

## 3. GATE 2 — Secure Enclave

Implemented `SecureEnclaveWrapper`: per KEK version an SE P-256 KeyAgreement key (access control `.privateKeyUsage`, ThisDeviceOnly) → ECDH with a fresh software ephemeral key → HKDF-SHA256 → AES-256-GCM seals the 32-byte KEK; the Keychain holds only the `XRAI-SE` blob (SE key representation, ephemeral public, salt, nonce, ct, tag; AAD-bound). No assumption that the SE stores AES keys. `SecureEnclavePolicy.required` fails closed without hardware; `preferred` records `keychainDeviceBound` truthfully; `KeyProvider.protection` and `SecureVault.keyProtection` expose the level. Option comparison (security/performance/recovery/compatibility) and the deferral of biometric gating are in ADR-BOOT-006 D3.

## 4. GATE 3 — what was actually run

| host | command | exit | result | evidence (sha256) |
|---|---|---|---|---|
| macOS 26.4, Apple silicon, unsigned `swift test` | `swift build` | 0 | ok | `p02_02_swift_build.log` (`dd5decb9…29e1`) |
| same | `swift test` run 1 | 1 | 100 tests, 98 pass, 2 issues: a source-scan hit on a comment, and the G4 test expecting the old error kind for a quarantined open (now `quarantined`, by design) | `p02_02_swift_test_run1_FAILED_2_of_100.log` (`4d0ab634…afad`) |
| same | `swift test` run 5 (final) | **0** | **100 tests in 24 suites passed**; test keychain items cleaned up (0 left) | `p02_02_swift_test_run5_macos.log` (`1ababf13…7175`) |
| iOS Simulator iPhone 17 (host-less logic bundle) | `xcodebuild test … -only-testing:XRAIVaultKeychainTests` run 1 | 65 | 14 tests: 2 pass; 12 fail with `keychainUnavailable(-34018)` = **fail closed as designed** (no keychain entitlement without a host app) | `p02_02_xcodebuild_sim_keychain_run1_FAIL_CLOSED.log` (`b7bea6ce…5b14`) |
| same | run 2 after accepting fail-closed in the production-config test | 65 | 3 pass (status mapping, isolation, production-config fail-closed), 11 keychain-functional tests cannot run without a host app | `p02_02_xcodebuild_sim_keychain_run2.log` (`c8d0e5b0…7626`) |
| physical iPhone | — | — | **NOT RUN** | — |

Between runs 1 and 5 two test-hygiene defects were found and fixed: the keychain cleanup helper (`~Copyable` consumed too early) leaked test items into the login keychain, and `SecItemDelete` on the legacy macOS keychain needs `kSecMatchLimitAll`; leftover items were purged by hand (`security delete-generic-password`), verified 0 before and after the final run.

GATE 3 checklist mapping:

| required scenario | macOS host | simulator | device |
|---|---|---|---|
| create & reuse (relaunch = new instance over same keychain) | TESTED `createAndReuse` | blocked (host app) | NOT_RUN |
| wrong device/key refused | TESTED (other keyID, other service, foreign material) | blocked | NOT_RUN |
| rotation + rewrap old records + forget | TESTED `rotation` | blocked | NOT_RUN |
| corrupted entry | TESTED `corruption` (garbage, wrong length, SE-blob garbage) | blocked | NOT_RUN |
| locked device / re-unlock | mapping TESTED (`errSecInteractionNotAllowed` → typed) | blocked | NOT_RUN |
| passcode removed | modelled as item deleted by OS → TESTED fail-closed; real behaviour NOT_RUN | blocked | NOT_RUN |
| keychain access denied / missing entitlement | TESTED for real (production config on macOS CLI → fail closed; simulator → fail closed) | TESTED (fail closed) | NOT_RUN |
| app relaunch | TESTED (fresh instance, no cache) | blocked | NOT_RUN |
| concurrent key operations | TESTED `concurrency` (64 parallel wrap/unwrap/rotate) | blocked | NOT_RUN |
| test provider isolation | TESTED (`IsolationTests`, manifest rule, compile-negative incl. `debug*` hooks) | TESTED | — |
| clock rollback & quarantine fixes | TESTED (Gate0Tests) | — | — |
| no regression in prior 81 | all pass within the 100 | — | — |
| Secure Enclave wrap/unwrap | **TESTED on the Mac's real enclave** (`secureEnclaveRequired`: blob written, unwrapped; `truthfulProtection` reports `keychainLegacyMacOSTestOnly` because the login keychain is not device-bound even though SE wrapping is active) | SE absent → `required` fails closed (covered by the fail-closed run) | NOT_RUN |

## 5. GATE 4 — limits respected and open security conditions

Not done, by rule: no encrypted personal database, no real user data, no cloud backup, numerology core untouched (`git diff` empty), no history rewrite.

Open security conditions recorded in `OPEN_BLOCKERS.md` (all must close before any persistent storage of real data):
- `DEVICE_TESTS_KEYCHAIN_SE` — physical iPhone: ThisDeviceOnly semantics, lock/unlock, passcode removal, reinstall, SE on A-series.
- `SIM_HOST_APP` — signed host app so simulator keychain tests can run.
- `REINSTALL_KEY_POLICY` — adopt-or-wipe rule in P03 onboarding.
- `AUTHZ_ISSUER_UI_BINDING` — `AuthorizationIssuer.issue()` must be reachable only from trusted user-interaction code paths in the app layer; today nothing proves a token came from a real user action.
- `DELETION_GRANT_VALIDATION` — the store layer must validate and consume `DeletionGrant`s.
- `AUTHZ_PERSISTENCE` — clock high-water mark and consumed-token ids survive process restart.
- `VAULT_SECURITY_REVIEW` — independent review / pen test.

## 6. Source changes
New: `Sources/XRAIVaultKeychain/{KeychainStore,SecureEnclaveWrapper,KeychainKeyProvider}.swift`, `Sources/XRAIVaultContracts` additions (`KeyProtection`, `QuarantineAuthority`, keychain/SE/clock errors, `KeyProvider.protection`), `XRAIVaultTesting/InMemoryQuarantineRegistry`, tests `Gate0Tests.swift`, `KeychainKeyProviderTests.swift`; `GCMKeyWrapper` now `package`-scoped; `SecureVault` takes a `QuarantineAuthority`; `MonotonicGuardClock` effective-time policy; `Package.swift` two new targets. Docs: ADR-BOOT-006, threat model v1.3 (T27–T30), ledgers.

**STOP — awaiting ChatGPT code review on GitHub. Next task to be decided after that review.**
