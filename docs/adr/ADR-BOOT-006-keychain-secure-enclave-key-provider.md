# ADR-BOOT-006 — Production key provider on Apple Keychain with Secure Enclave wrapping

**Status:** ACCEPTED (2026-10-19, P02-02) · macOS-host TESTED (real Keychain + real Secure Enclave of an Apple-silicon Mac) · iOS Simulator: fail-closed verified, functional tests blocked (no host app entitlement) · **DEVICE_VERIFIED: NO** · **Refines:** ADR-BOOT-005 §3, founder decision 2 ("Keychain + Secure Enclave where appropriate; never claim hardware the device lacks") · **Threat model:** v1.3 T27–T30

## Context
The vault's `KeyProvider` port needs a production implementation that keeps the device KEK off the file system, bound to the device, and protected by hardware where the hardware actually offers it. The Secure Enclave does not store arbitrary symmetric AES keys; it holds non-extractable P-256 keys and performs ECDH / signing inside the enclave.

## Decisions

### D1 — Keychain layout and invariants (`XRAIVaultKeychain`, the only module importing Security)
Generic-password items, `kSecAttrSynchronizable = false`, data-protection keychain (`kSecUseDataProtectionKeychain = true`):
`<keyID>/meta` (mode + accessibility, canonical bytes) · `<keyID>/current` (u32) · `<keyID>/kek/v<N>` (32 raw bytes, or a Secure Enclave blob).
Items are only ever **added** (`SecItemAdd`); a duplicate is `keychainConflict`, never an overwrite. Rotation writes `v(N+1)` **before** moving `current`; an interrupted rotation leaves an orphan that is ignored (versions above `current` are unusable) and makes the next rotation fail closed with a conflict instead of adopting unknown material. Malformed, wrong-length, mode-mismatched or missing items → `keychainCorrupted` / `keyUnavailable` (fail closed, including at provider initialisation). `forget(version)` deletes the item; the current version cannot be forgotten. `wipeAllKeys()` is the explicit, irreversible user wipe.

### D2 — Accessibility class (UX vs. security)
Default **`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`**: items never migrate to another device through backups, never sync to iCloud Keychain, and are readable only while unlocked (the vault is a foreground feature; background reads would need `afterFirstUnlockThisDeviceOnly`, offered as an explicit opt-in).
**`WhenPasscodeSetThisDeviceOnly`** is offered but not default: it is the strongest class, yet iOS **deletes** such items when the user removes the passcode, which destroys every record irrecoverably. Until onboarding can explain that consequence and the recovery-key backup flow exists in the UI (P03), the default stays `WhenUnlocked`. The choice is recorded in the `meta` item; changing it later is a migration, never a silent switch.

### D3 — Secure Enclave design
Per KEK version: SE P-256 KeyAgreement key (access control `.privateKeyUsage`, ThisDeviceOnly) → ECDH with a fresh software ephemeral P-256 key → HKDF-SHA256 (16-byte salt, info `xrai.se.kek.v1`) → AES-256-GCM seals the 32-byte KEK; the Keychain stores `{ seKeyBlob, ephemeralPublic, salt, nonce, ct, tag }` (`XRAI-SE` blob, version 1, AAD binds blob/pub/salt). Unwrapping requires the enclave of **this** device; the Keychain item alone does not reveal the KEK.
Policy `SecureEnclavePolicy`: `required` (fail closed without SE), `preferred` (use SE when `SecureEnclave.isAvailable`, otherwise record `keychainDeviceBound` truthfully), `disabled`. The chosen level is reported by `KeyProvider.protection` and shown through `SecureVault.keyProtection`; a stored mode that differs from the configuration fails closed (no silent downgrade). Biometric gating (`.biometryCurrentSet`) is intentionally not enabled yet: it changes the UX (Face ID prompt per unwrap) and the recovery story; to be decided with P03 onboarding.

| option | security | performance | recovery | compatibility |
|---|---|---|---|---|
| Keychain-only, WhenUnlocked | KEK readable by any code with the app's keychain access once unlocked | fastest | survives passcode removal | all devices |
| Keychain-only, WhenPasscodeSet | as above + OS wipes on passcode removal | fastest | **data lost on passcode removal** | all devices with passcode |
| SE-wrapped KEK (chosen, `preferred`) | KEK unusable without this device's enclave; extraction of the item is not enough | one ECDH + HKDF + AES per KEK load (cached per process) | same as its accessibility class; restore on a new device only via the user's recovery-key backup | A7+ devices and Apple-silicon/T2 Macs; **absent on Simulator** |
| SE + biometry | adds user presence per unwrap | prompt latency | biometry change invalidates key (`biometryCurrentSet`) | needs enrolled biometrics; deferred |

### D4 — Test hosts and what they prove
- **macOS `swift test` (unsigned CLI):** the data-protection keychain is unavailable (`errSecMissingEntitlement`, −34018). Production configuration **fails closed** (tested). With the explicit `allowLegacyMacOSKeychainForTesting` flag the provider uses the login keychain and reports `keychainLegacyMacOSTestOnly`; on this Apple-silicon Mac `SecureEnclave.isAvailable == true`, so the **SE wrapping path is exercised for real** (blob written and unwrapped by the Mac's enclave). ThisDeviceOnly semantics are not verifiable on this host.
- **iOS Simulator (`xcodebuild test`, host-less logic bundle):** keychain → −34018 → fail closed (tested, evidence log). Functional keychain tests on iOS need a signed host app (blocker `SIM_HOST_APP`, P03). Simulator has no Secure Enclave.
- **Physical iPhone:** not run. Locked-device (`errSecInteractionNotAllowed`), passcode removal, reinstall and background-unlock behaviours are mapped and unit-tested at the error-mapping level only; they stay `NOT_RUN` on device.

### D5 — Reinstall lifecycle
iOS keeps data-protection keychain items across app reinstall (until device wipe). A reinstalled app would find a KEK set without any records. Required P03 integration rule: on first launch with no vault store present, the app must either adopt the existing key set explicitly (for a restore-in-progress) or call `wipeAllKeys()` before creating a new store, and must tell the user that a device-only key cannot recover records without their recovery-key backup. Recorded as blocker `REINSTALL_KEY_POLICY`.

## Consequences
The vault can run on a real device key provider with hardware-backed KEK protection where available, with every failure typed and closed. What is **not** proven: device-only semantics, lock/unlock, passcode removal and reinstall behaviour on a physical iPhone; simulator functional runs; independent security review. Status: `KeychainKeyProvider` **CODED + TESTED (macOS host, real Keychain/SE)**; **DEVICE_VERIFIED: NO**; **SECURITY_REVIEWED: NO**.
