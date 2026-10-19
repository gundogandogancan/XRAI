# P03_00_NATIVE_IOS_HOST_REVIEW_REPORT — native iOS host, simulator Keychain validation, key lifecycle hardening

**Date:** 2026-10-19 · **Agent:** Claude Fable 5.1 · **Basis:** founder message "XRAI — P03-00 NATIVE IOS HOST & KEYCHAIN VALIDATION" (P02-02 conditionally accepted at commit `c8630b7`). **Scope executed:** §1 app, §2 simulator keychain tests, §3 key cache, §4 rotation/data-loss, §5 device attempt, §6 limits. **Gate:** STOP for ChatGPT code review. **DEVICE_VERIFIED: NO.**

Türkçe özet: Gerçek `XRAI.xcodeproj` (xcodegen) ile iOS 17+ SwiftUI uygulaması oluşturuldu; beş sekme dürüst iskelet, yalnız "Ben" sekmesinde gerçek güvenlik durumu (anahtar koruması, enclave, önbellek, kalıcılık yok, izin kaydı yok, cihazda doğrulanmadı, denetlenmedi) ve hiçbir şey saklamayan Yaşam Yolu hesabı var. İmzalı host uygulama içinde Keychain testleri iPhone 17 simülatöründe gerçekten koştu: 20/20 (−34018 sorunu TEST_HOST ile çözüldü). Mac paketi 104/104. Anahtar önbelleği TTL'li ve kilit/arka plan olayında temizleniyor; rotasyon artık işaretçiyi Keychain'den okuyor (iki örnek çakışmıyor), yarım kalan rotasyonda okunabilir artık benimseniyor / okunamayan onarım gerektiriyor, unutma iki aşamalı (retire→forget), wipe onay nesnesi istiyor, üretim yüzeyindeki tüm `debug*` yardımcıları kaldırıldı ve compile-negative ile kanıtlandı. Cihaz: imzalama ve provisioning başarılı, uygulama iPhone 14 Pro Max'e yüklendi ve başlatıldı, ancak test koşucusu bağlantı kurmadan kapandı; cihazda geliştirici profilini güvenilir işaretleyip kilidi açık tutman gerekiyor. DEVICE_VERIFIED hâlâ HAYIR. Önemli dürüstlük notu: Apple-silicon Mac üzerindeki simülatör Mac'in Secure Enclave'ini vekil olarak sunuyor; simülatördeki SE sonuçları iPhone donanım kanıtı değildir.

## 1. Deliverables

| item | state | where |
|---|---|---|
| Native SwiftUI app target (iOS 17+, Swift 6) | BUILT for iPhone 17 Simulator, exit 0 | `project.yml`, `XRAI.xcodeproj`, `App/XRAI/*.swift` |
| Five tabs Bugün · Ben · Keşfet · Yolum · XRAI | CODED, honest empty states with planned phase; no fake insight, no fake controls | `App/XRAI/RootTabView.swift` |
| Truthful security status + self-test + Life Path (nothing stored) | CODED, exercised by hosted test `appStatusBootstrap` | `App/XRAI/SecurityStatus.swift`, `SelfView.swift` |
| Bundle id / signing / entitlements | `com.xrai.app`, team `47XQMQZLF6`, automatic signing, `keychain-access-groups`; provisioning succeeded for the device | `project.yml` |
| Hosted test bundle (TEST_HOST) | 20/20 on iPhone 17 Simulator | `App/XRAIHostedTests` + package keychain tests |
| Key cache policy | TTL 30 s default, `.disabled`, `purgeCache()` on scene inactive/background and protected-data-unavailable | `KeychainKeyProvider`, `XRAIApp.swift` |
| Rotation / data-loss safety | pointer refresh, orphan adopt/repair, retire→forget, confirmed wipe | `KeychainKeyProvider` |
| Debug surface removal | no `debug*` in production; compile-negative + source scan | `KeychainKeyProvider`, `CompositionBoundaryTests`, `IsolationTests` |
| Reports / ADR / threat model | ADR-BOOT-007, threat model v1.4 (T31–T34), ledgers | `docs/` |

## 2. Commands and exit codes

| host | command | exit | result | evidence (sha256 in `TEST_EVIDENCE_LEDGER.json`) |
|---|---|---|---|---|
| macOS (unsigned CLI, login keychain + host SE) | `swift test` run 1 | 1 | 104 tests, 103 pass; the compile-negative test did not accept the "has no member" diagnostic for the removed debug hook → test widened | `p03_00_swift_test_macos_run1_FAILED_1_of_104.log` |
| macOS | `swift test --package-path Packages/XRAICore` run 3 | **0** | **104 tests in 25 suites passed**, 0 test keychain items left | `p03_00_swift_test_macos_run3.log` |
| iPhone 17 Simulator | `xcodebuild build -scheme XRAI` | **0** | BUILD SUCCEEDED (first attempts: product name, Info.plist, x86_64/arm64 mismatch fixed) | `p03_00_xcodebuild_sim_app_build.log` |
| iPhone 17 Simulator, signed app host | `xcodebuild test -scheme XRAI` | **0** | **20 tests in 5 suites passed** (18 keychain provider + 2 hosted smoke). Data-protection keychain worked; `SecureEnclave.isAvailable == true` via the host Mac | `p03_00_xcodebuild_sim_hosted_tests.log` |
| iPhone 14 Pro Max "Dogi (2)" (connected) | `xcodebuild test … -allowProvisioningUpdates` | 65 | profile created and embedded, app installed and launched; "test runner crashed before establishing connection … terminated at launch". **0 tests executed on device.** | `p03_00_xcodebuild_device_iphone14promax_FAILED_launch.log` |
| — | `git diff` on BOOT-01 dirs | 0 | empty | — |

Earlier mid-task fixes also recorded: an app-host test file needed `@testable import XRAI`; the keychain test file needed `@testable import XRAIVaultCryptoKit` to see the package-scoped `GCMKeyWrapper` from the Xcode bundle.

## 3. Simulator keychain validation (§2)
The host-less `-34018` problem is resolved by running the suite as an app-hosted bundle: `TEST_HOST`/`BUNDLE_LOADER` point at `XRAI.app`, the app carries `application-identifier` and `keychain-access-groups`, and the production configuration (`useDataProtectionKeychain = true`, no legacy fallback) opens the data-protection keychain. Every keychain lifecycle test (create/reuse, rotation, two instances, interrupted rotation, conflict, corruption, mode mismatch, confirmed wipe, concurrency, end-to-end backup/restore, cache TTL/purge/stale-instance, mode selection, SE required) passed in the Simulator. **Not claimed:** iPhone Secure Enclave hardware (the Simulator's enclave is the Mac's), device lock/unlock, passcode removal, reinstall.

## 4. Key cache (§3) — audit result
Before: KEK bytes cached per version for the process lifetime; cleared only by `forget`. After: TTL (30 s default), `purgeCache()` wired to app lifecycle, `.disabled` option, `cachedVersions` visible in the status screen. Tests: `ttlAndPurge` (deleted item still served within TTL — documented bound — then fails; purge makes loss immediate), `disabled`, `staleCacheAcrossInstances` (B serves v1 after A retire+forget until B purges; a fresh instance fails closed). SE guarantee stated in ADR-BOOT-007 D3: at-rest only; memory exposure bounded, never zero.

## 5. Rotation and data-loss prevention (§4)
- Two instances: `twoInstances` — stale B refreshes on a newer wrap, never wraps under a stale version, rotates to 3 instead of conflicting.
- Interrupted rotation: `interruptedRotation` — readable orphan adopted (and proven to use the orphan's material), unreadable orphan blocks until `repairOrphan`, orphans never unwrap, repair below the pointer refused.
- Forget contract: `rotation` — `forget` without `retire` → `keyVersionNotRetired`; retired versions still unwrap; current cannot be retired/forgotten.
- Wipe: `wipe` — wrong key id or missing acknowledgement → refused and nothing changes.
- Debug surface: `IsolationTests` forbids `func debug`/`package func` in the module; `compileNegative` proves `KeychainStore`, `SecureEnclaveWrapper`, `debugDeleteItem` unreachable externally.

## 6. Physical iPhone (§5)
Connected: "Dogi (2)" iPhone 14 Pro Max; two valid Apple Development identities; automatic provisioning created "iOS Team Provisioning Profile: *". Install + launch succeeded; the test runner exited before bootstrapping. Most likely causes: developer profile not yet trusted on the phone / Developer Mode / locked screen. Founder action: unlock, trust the profile (Settings › General › VPN & Device Management), keep unlocked, rerun the command in `OPEN_BLOCKERS.md`. No destructive scenario was attempted on the personal phone. **DEVICE_VERIFIED: NO.**

## 7. Limits respected (§6)
BOOT-01 untouched (empty diff); no regression (all prior tests pass within 104 + 20); no persistent store; no personal records; no cloud/analytics/API; no history rewrite; nothing declared complete. Still separate production gates: token-from-real-user-action binding, production consent registry, deletion-grant validation, cross-session authz state, independent security review.

Note on repo hygiene: `AGENTS.md` (a Codex copy of `CLAUDE.md`) appeared in the working tree during H2 and was swept into commit `9dbb1bf` by `git add -A`; it is the founder's file, left as is.

**STOP — awaiting ChatGPT code review.**
