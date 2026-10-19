# XRAI Vault — Threat model v1.1 (P02, V32-02-01 + V32-02-01H hardening, 2026-10-19)

**Scope:** the on-device personal vault (encrypted records of birth data, names, optional family data, psychometrics, journals, goals, evidence, consent receipts) and the optional user-held encrypted backup. **Out of scope here:** UI, network broker, model router, StoreKit (own threat models later). **Status:** design + library-level tests; **no device verification, no independent security review yet.** Nothing in this document claims the vault is unbreakable (constitution §83: "No 'unbreakable' promise").

## Assets (constitution §59)
A1 date of birth, exact birth time/place · A2 legal/chosen names · A3 parent names, sibling order (third-party data, high sensitivity) · A4 psychometric answers · A5 journals, private guide history · A6 goals/Future Self, evidence artifacts · A7 derived results (charts, traces) · A8 consent receipts and audit trail · A9 cryptographic keys (DEKs, device KEK, recovery key) · A10 the portable backup file.

## Trust boundaries
B1 process boundary of the app (other apps, extensions, keyboards, clipboard) · B2 OS boundary (lock screen, Data Protection classes, iCloud/iTunes backup) · B3 device boundary (lost/stolen phone, new device) · B4 user boundary (the user is the only key holder; XRAI operates no server for personal data) · B5 content boundary (PDF/web/book excerpts fed to a local model are untrusted data).

## Adversaries and the control that applies (what is implemented now vs. later)

| id | adversary / scenario | control | state |
|---|---|---|---|
| T1 | Stolen encrypted store (file copied off device, backup extracted) | Every record is AES-256-GCM under a random per-record DEK; DEK wrapped by the device KEK; without the KEK the file is noise. | IMPLEMENTED (adapter) · TESTED (wrong-key, tamper) · KEK-at-rest protection NOT_STARTED (Keychain/SE adapter, P02-02) |
| T2 | Tampering: modify ciphertext, tag, nonce, wrapped key, or metadata (downgrade tier, change retention, change record class) | AEAD tag covers payload; header canonical bytes are associated data; wrapped DEK carries its own AEAD bound to (keyID, version, recordID). | TESTED (`SealAdversarialTests`) |
| T3 | DEK substitution / record confusion (move one record's key to another) | Wrap AAD binds DEK to recordID; sealer rejects header/wrap recordID mismatch before any crypto. | TESTED (`dekSwap`) |
| T4 | Nonce reuse (catastrophic for GCM) | Fresh 96-bit nonce from CryptoKit's system CSPRNG per seal and per wrap; DEK is per record, so even a nonce collision would be under a different key. | TESTED (500-seal uniqueness, same plaintext distinct ciphertext) · formal bound: 2^96 space, random; per-key message count is 1 for payloads |
| T5 | Wrong/unknown key version after rotation; stale envelopes | Versioned KEK identity in `WrappedKey`; rotation re-wraps DEKs without re-encrypting payloads; `forget(version)` makes un-rewrapped envelopes unreadable (explicit, typed). | TESTED (`KeyRotationTests`) |
| T6 | Lost device / lost backup / lost recovery key | Decision 4: unrecoverable by design if both backup and recovery key are lost; UI must say so plainly. Recovery key is 256-bit random, shown once, never stored by XRAI. | CONTRACT (`RecoveryKey`), UI copy NOT_STARTED |
| T7 | Backup file tampered, truncated, reordered, replayed with wrong key, old version | v2: outer AES-256-GCM over the whole body (order/count inside), AAD = magic/version/salt/nonce; strict decoder; v1 rejected. | TESTED (`corruptedOrWrongKey`, `forgedBody`) |
| T8 | Backup leaks plaintext or the recovery key | Export re-wraps DEKs only; payload ciphertext is carried unchanged; tests assert neither plaintext nor key bytes occur in the backup bytes. | TESTED |
| T9 | Silent cloud sync / data broker SDK / analytics / model training on personal data | `VaultPolicy` hard-denies analytics, model training, cloud sync, advertising for every data class regardless of consent; provider egress needs an active, purpose-matched consent receipt. | TESTED (`PolicyTests`) · runtime `NetworkEgressBroker` NOT_STARTED (P06) |
| T10 | Family data used beyond the chosen purpose (decision 6) | `parentsNames`/`siblingOrder` flagged third-party; storage needs purpose-bound consent; destination hard rules apply. | TESTED (`storeGate`) |
| T11 | Logs/crash reports contain DOB, names, journal | Redacted `description` on `RecordEnvelope`, `RecoveryKey`, `CivilDate`, `NumerologyTrace`; crash-log destination requires consent; static scan forbids print/NSLog/os_log in vault modules. | TESTED (library) · OS-level crash telemetry audit NOT_STARTED (P12) |
| T12 | Memory disclosure (unlocked borrowed phone, malicious accessibility app, jailbreak) | Best effort only: short-lived DEKs; Swift cannot guarantee zeroization; app-lock/biometric gating and Data Protection class belong to P02-02/P03. | NOT_STARTED, residual risk documented |
| T13 | Supply chain (CryptoKit misuse, third-party crypto) | Only Apple CryptoKit; no third-party crypto; the only module importing CryptoKit is `XRAIVaultCryptoKit` (test-enforced). | TESTED (`ImportBoundaryTests`) |
| T14 | Format/algorithm downgrade | `formatVersion` and algorithm id inside the authenticated header; unknown versions/algorithms rejected typed. | TESTED |
| T15 | Timing side channel on MAC compare | Constant-time compare for backup tag (AES-GCM tag compare is CryptoKit's own). | IMPLEMENTED |
| T16 | Hardware capability over-claim (Secure Enclave on devices/simulators without it) | Decision 2: `KeyProvider` is a port; SE is used only where `SecureEnclave.isAvailable`; otherwise Keychain-only with explicit capability flag in the key identity. | DESIGN (P02-02) |
| T17 | Minors / shared devices | Out of scope of the vault; separate age gate and AHTOVIA boundary (FUTURE_CHILD_SAFETY). | OPEN |
| T18 | Backup size side channel | Zero padding to 4 KiB blocks; total volume still leaks coarsely. Bucketed/fixed-size padding deferred until backup cadence is designed. | PARTIAL, residual documented |
| T19 | Policy bypass by calling crypto directly; forged/stale/revoked consent receipts | `SecureVault` is the only public path; raw sealer/codec internal (test-enforced); `ConsentAuthority` port is the sole source of grants; revocation/expiry honoured at the instant. | TESTED (`EnforcementTests`, `PolicyTests`) |
| T20 | Privacy-tier downgrade at creation, read or import | Class floors; throwing descriptor; `validate()` on seal/open/rewrap/decode. | TESTED (`descriptorFloor`, `tamperHeader`, `forgedBody` #1) |
| T21 | Identifier/metadata leakage through descriptions, errors, logs | Random `RecordID`, redacted descriptions, identifier-free `VaultError`, crash logs hard-denied. | TESTED (`errorHygiene`, `redaction`, `hardRules`) |
| T22 | Resource exhaustion / malformed backup on import; corrupted or foreign envelope laundered into a backup on export | `BackupLimits` (256 MiB, 100k entries, field lengths), duplicate ids, binding check, padding check, payload verification on both export and restore. | TESTED (`unauthorizedExport`, `forgedBody`, `corruptedOrWrongKey`) |

## Residual risks stated honestly
- Keys live in process memory while in use; a compromised OS or a debugger can read them.
- A device with passcode removed or a jailbroken device weakens Keychain guarantees.
- A user who loses both backup and recovery key loses the data. This is intended.
- The in-memory `KeyProvider` is a development double; the production Keychain/SE provider does not exist yet. **Until it does, nothing may be persisted.**
- The `ConsentAuthority` is a port; its production implementation (own encrypted store, audit trail, UI) is future work.
- No independent security review or penetration test has happened. Statuses are library TESTED, not SECURITY_REVIEWED.

## Test-to-threat map
`VaultContractsTests.swift` → T6, T9, T10, T14, T19, T20, T21 · `VaultCryptoTests.swift` → T1–T5, T7, T8, T11, T13, T14, T18–T22 · `PrivacyNegativeTests.swift` (BOOT-01) → T11 for pure math modules.
