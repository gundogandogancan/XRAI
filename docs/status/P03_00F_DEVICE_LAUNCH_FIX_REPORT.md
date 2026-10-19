# P03_00F_DEVICE_LAUNCH_FIX_REPORT — real iPhone launch fix, monotonic key cache, rotation serialization

**Date:** 2026-10-20 · **Agent:** Claude Fable 5.1 · **Basis:** founder message "XRAI — P03-00F REAL IPHONE LAUNCH FIX" (P03-00 conditionally accepted at `7eb8196`). **Scope executed:** F1–F5 plus the founder's note that the logo had not been used. **Gate:** STOP for ChatGPT code review; next target P03-01.

Türkçe özet: Cihazdaki `dyld: Library not loaded` hatası güven sorunu değil paketleme hatasıydı: frameworkler app bundle içinde gömülüydü ama app binary'sinin rpath listesinde `@executable_path/Frameworks` yoktu, çünkü kurulu xcodegen platform önayarlarını yükleyemiyor ("No iOS settings found") ve Xcode'un varsayılanlarını üretmiyor. Düzeltme `project.yml`'de kalıcı: açık `LD_RUNPATH_SEARCH_PATHS` (app ve host-test), tam Debug/Release varsayılanları. Kanıt: `otool -L`, `LC_RPATH`, gömülü framework listesi, `codesign --verify --deep --strict`, entitlements. Uygulama iPhone 14 Pro Max'e `devicectl` ile yüklendi, normal açıldı (süreç çalışıyor), ardından host testleri **gerçek cihazda 24/24** geçti (cihazın gerçek Secure Enclave'i ile KEK sarmalama dahil). F3: önbellek TTL'si artık monoton `CLOCK_MONOTONIC_RAW` üzerinde; zaman kaynağı hata verirse önbellek temizlenir ve işlem `clockUnavailable` ile kapanır. F4: aynı süreçteki örnekler için (service, keyID) başına serileştirme kilidi; süreçler arası rotasyon BLOCKED (yalnız ana uygulama rotasyon yapar). macOS 108/108, simülatör 24/24, cihaz 24/24, numeroloji çekirdeğinde diff yok. Logo artık uygulama ikonu (AppIcon 1024) ve Bugün sekmesinde görsel olarak kullanılıyor. Kalıcı depolama olmadığı için "eski anahtarı silmeden önce tüm kayıtlar yeniden sarıldı" kanıtı hâlâ üretilemiyor; blocker olarak duruyor. Yıkıcı cihaz senaryoları (kilit/açma, parola kaldırma, yeniden kurulum) çalıştırılmadı.

## F1 — dyld root cause and fix

| finding | evidence |
|---|---|
| Frameworks were embedded (`XRAI.app/Frameworks/XRAIVaultContracts.framework` etc.) but `LC_RPATH` of `XRAI.app/XRAI` was only `/usr/lib/swift` and the Mac-absolute `…/Debug-iphoneos/PackageFrameworks`. dyld therefore searched only those paths (see the failing log's "tried:" list). | `p03_00_xcodebuild_device_iphone14promax_FAILED_launch.log` lines 208–210 |
| Cause: xcodegen 2.42 installed at `~/.local/bin` has no `SettingPresets` → warnings "No iOS settings found" / "No release config settings found"; no default `LD_RUNPATH_SEARCH_PATHS`, no `DEBUG` condition, no optimisation levels were generated. | xcodegen output; `project.yml` header note |
| Fix (in `project.yml`, survives regeneration): app `LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/Frameworks`; hosted bundle `… @executable_path/Frameworks @loader_path/Frameworks` (host copy first → one copy loaded); full Debug/Release default settings; `ASSETCATALOG_COMPILER_APPICON_NAME`. | `project.yml` |
| Linkage after fix: plain app build → package products linked **statically** (no `Frameworks/`, `otool -L` shows only `XRAI.debug.dylib`); test build → Xcode dynamic `PackageFrameworks`, embedded and signed in the app (`codesign --verify --deep --strict`: valid, satisfies Designated Requirement; each `XRAI*.framework` verifies). No duplicate load path, no unsigned framework, no host-test dependency in the app target. | `p03_00f_device_bundle_verification.txt` |
| Entitlements on device: `application-identifier 47XQMQZLF6.com.xrai.app`, `keychain-access-groups [47XQMQZLF6.com.xrai.app]`, `get-task-allow` (development). | same |

## F2 — real device run

| step | result | evidence |
|---|---|---|
| `xcodebuild build` for iPhone 14 Pro Max "Dogi (2)" | BUILD SUCCEEDED, exit 0 | `p03_00f_xcodebuild_device_app_build.log` |
| `devicectl device install app` | installed | `p03_00f_device_install_launch_process.log` |
| `devicectl device process launch com.xrai.app` | "Launched application"; process `XRAI.app/XRAI` listed after 5 s | same |
| `xcodebuild test` on device (hosted bundle inside the signed app) | **TEST SUCCEEDED, 24 tests in 7 suites**, exit 0; includes `secureEnclaveRequired` (device enclave), lifecycle, rotation, two-instance, interrupted rotation, conflict, corruption, mode mismatch, wipe, concurrency, end-to-end backup/restore, cache TTL/purge/stale, clock-failure, rotation serialization, isolation, hosted smoke | `p03_00f_xcodebuild_device_hosted_tests.log`, `p03_00f_device_xcresult_summary.json`, `p03_00f_device_info.txt` |

No user step (trust/unlock) was required this time: the previous failure was fully explained by the missing rpath. Only non-destructive tests ran on the personal phone.

## F3 — key cache fail-closed on clock failure

Before: `loadKEKLocked` used `(try? clock.now()) ?? 0`; with `now = 0` the TTL check `0 - loadedAt < ttl` was true, so a clock failure meant **indefinite** reuse of the cached KEK. After: TTL measured on `SystemUptime` (`clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)`, immune to wall-clock changes); any time-source error purges the cache and throws `clockUnavailable`; `now < loadedAt` is treated as expired; entries are cached only when a timestamp is available. The `KeychainKeyProvider` no longer takes a `VaultClock`. Tests: `ClockFailureCacheTests.failingTimeSource` (stale KEK never served, recovery after the source returns, deletion during failure visible afterwards), `backwardsTimeDoesNotExtend`, `systemUptime`.

## F4 — rotation concurrency

`readPointer → SecItemAdd → SecItemUpdate` is explicitly **not** an atomic CAS. In-process: `KeySetSerializer` gives every provider instance on the same (service, keyID) one shared lock around create/rotate/retire/forget/repairOrphan/wipe. Test `RotationSerializationTests.concurrentRotateTwoInstances`: two instances, 24 concurrent rotations → 24 distinct versions, pointer 25, no conflicts, both instances agree. Cross-process writers (app + extension) remain **BLOCKED**: ownership rule "only the main app rotates" recorded in ADR-BOOT-007 Amendment F and `OPEN_BLOCKERS.md`. The store-side proof that all records were re-wrapped before `forget` is impossible without persistence → blocker `FORGET_REQUIRES_STORE_PROOF` kept.

## F5 — evidence

| host | command | exit | result |
|---|---|---|---|
| macOS | `swift build` / `swift test --package-path Packages/XRAICore` | 0 / 0 | **108 tests in 27 suites passed**; 0 test keychain items left |
| iPhone 17 Simulator | `xcodebuild build` / `xcodebuild test` | 0 / 0 | app builds (AppIcon compiled); **24/24** hosted |
| iPhone 14 Pro Max (device) | build / install / launch / test | 0 / ok / ok / 0 | normal launch confirmed; **24/24** hosted |
| — | `git diff` on BOOT-01 dirs | 0 | empty |

SHA-256 of every log is in `TEST_EVIDENCE_LEDGER.json`. Numerology engine unchanged; no data persisted; no cloud/API/payment; no history rewrite.

## Logo
The founder's logo is now the app icon (`App/XRAI/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, opaque 1024×1024 from `brand/xrai_logo_1024.png`) and is shown on the Bugün tab (`XRAILogo` imageset). Launch screen and a dedicated icon rendering (gradient border/glow at icon scale) remain for P03-01.

## Status words
`KeychainKeyProvider`: CODED + TESTED on macOS host, iOS Simulator host and **one physical iPhone (non-destructive suite)**. **DEVICE_VERIFIED: PARTIAL** — keychain create/read/rotate/retire/forget/wipe, Secure Enclave wrapping, cache and serialization verified on iPhone 14 Pro Max; lock/unlock behaviour, passcode removal and reinstall NOT_RUN (need a dedicated test device and explicit approval). SECURITY_REVIEWED: NO.

**STOP — awaiting ChatGPT code review. Next target: P03-01 real user experience and onboarding.**
