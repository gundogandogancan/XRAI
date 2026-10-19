# ADR-BOOT-007 — Native iOS host, key-cache policy and rotation / forgetting safety

**Status:** ACCEPTED (2026-10-19, P03-00) · macOS 104/104 · iPhone 17 Simulator (signed app host) 20/20 · **DEVICE_VERIFIED: NO** · **Refines:** ADR-BOOT-006 (D1, D4, D5), ADR-BOOT-005 H2

## Context
P02-02 left three gaps: no app host (so no simulator keychain evidence), an unbounded in-process KEK cache, and rotation/forgetting that could lose data or diverge between provider instances.

## Decisions

### D1 — App host
`XRAI.xcodeproj` is generated from `project.yml` (xcodegen 2.42). iOS 17+, SwiftUI, Swift 6 strict concurrency. The app links only production products of `XRAICore`; `XRAIVaultTesting` is linked by the `XRAIHostedTests` bundle alone (test on `Package.swift` + `project.yml`). Bundle id `com.xrai.app`, team `47XQMQZLF6`, automatic signing, entitlement `keychain-access-groups = $(AppIdentifierPrefix)com.xrai.app`. The hosted bundle uses `TEST_HOST` so keychain calls run inside the signed app process; that is what removed `errSecMissingEntitlement (-34018)`.
Five tabs exist as honest skeletons. The only working content is in **Ben**: the truthful security status of the build (key protection, enclave availability, cache TTL, "no persistence", "no consent registry", "not device-verified", "not security-reviewed", Debug/Release) with a self-test that seals/opens synthetic bytes and stores nothing, and the free Life Path calculation labelled as exact arithmetic without meaning and never stored.
Simulator arch: `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` (the package built arm64 while the app defaulted to x86_64).

### D2 — Secure Enclave truth in the Simulator
On Apple-silicon Macs the iOS Simulator proxies the **host Mac's** Secure Enclave: `SecureEnclave.isAvailable == true` and SE wrapping works. This is useful for exercising the code path but is **not** evidence of iPhone hardware behaviour. The hosted test asserts consistency between CryptoKit's report and the provider's `protection`, never a fixed assumption; reports and status screens say "host Mac enclave" where applicable.

### D3 — Key cache policy
`KeyCachePolicy(ttlSeconds: 30)` default; `.disabled` available. Unwrapped KEK bytes live in memory for at most the TTL, keyed by version, per provider instance. `purgeCache()` is called by the app on `scenePhase != .active` and on `protectedDataWillBecomeUnavailable`. Guarantees, stated exactly: the Secure Enclave protects the KEK **at rest** (the keychain item alone is useless); after the first unwrap the KEK is ordinary process memory until TTL/purge; Swift provides **no zeroization guarantee**; a second instance's stale cache can outlive a `forget` by at most its TTL (tested and documented).

### D4 — Rotation and forgetting without data loss
- `wrapDataKey` always re-reads the `current` pointer (never wraps under a stale version); `unwrapDataKey` refreshes when it sees a version above memory; `rotate` computes `next = stored + 1` from the keychain, so two instances on one service never conflict on rotation.
- Interrupted rotation: a readable orphan `v(N+1)` is **adopted** by the next rotation (pointer moved to it); an unreadable orphan blocks rotation (`keychainCorrupted`) until `repairOrphan(version:)` deletes it — only versions above the pointer can be repaired. Orphans never unwrap.
- Two-phase forgetting: `retire(version:)` marks a non-current version (unwrap-only); `forget(version:)` requires the retired marker (`keyVersionNotRetired` otherwise) and refuses the current version. The store layer must re-wrap every record of a version between retire and forget.
- `wipeAllKeys(confirmation:)` requires a `WipeConfirmation` naming the key id and acknowledging irreversible loss. A value type cannot stop a determined caller; it stops an accidental one and is reviewable.
- All `debug*` hooks were removed from the production module; adversarial tests manipulate the store through `@testable`. Compile-negative snippets prove `KeychainStore`, `SecureEnclaveWrapper` and the former `debugDeleteItem` are unreachable from external modules; the source scan forbids `func debug`/`package func` in `XRAIVaultKeychain`.

### D5 — Physical device
Signing works (profile created, app installed, launched on iPhone 14 Pro Max "Dogi (2)"), but the test runner terminated at launch before bootstrapping: device-side trust/unlock is required from the founder. No destructive scenario (reinstall, passcode removal) may run on a personal phone without a dedicated test device and explicit approval. DEVICE_VERIFIED remains NO.

## Consequences
Simulator keychain evidence now exists through a signed host; the key lifecycle has explicit recovery and loss-prevention contracts; the app shell is honest and empty by design. Still open: device verification, persisted authz state, consent registry, deletion-grant validation, independent review.
