# ADR-BOOT-005 — Vault envelope encryption, key lifecycle and user-held recovery

**Status:** ACCEPTED (2026-10-19, V32-02-01, founder decisions 1–6 recorded in `docs/status/NEXT_TASK.md`) · library TESTED · **not** SECURITY_REVIEWED, **not** DEVICE_VERIFIED · **Refines:** spec ADR-004/012, constitution §83–§84 · **Threat model:** `docs/security/VAULT_THREAT_MODEL_P02.md`

## Context
XRAI must keep all sensitive personal data encrypted on the iPhone by default, with no server-side key, no silent cloud sync, and an honest recovery story. The pure math core (BOOT-01) must stay free of crypto and IO.

## Decisions
1. **Two modules.** `XRAIVaultContracts` (stdlib only: tiers, data classes, policy, consent, header/envelope/backup shapes, ports, canonical coding) and `XRAIVaultCryptoKit` (the only module allowed to import CryptoKit; AES-256-GCM sealer, in-memory key provider, backup codec). A test enforces the import boundary.
2. **Envelope encryption.** Random 256-bit DEK per record; AES-256-GCM with a fresh 96-bit CSPRNG nonce per seal; the versioned header (`formatVersion`, algorithm id, recordID, dataClass, privacyTier, retention, createdAt) is authenticated as associated data. DEKs are wrapped by the `KeyProvider`'s KEK with AES-GCM and AAD = (keyID, keyVersion, recordID). Key identity lives in `WrappedKey`, not in the header, so rotation re-wraps without re-encrypting payloads.
3. **KeyProvider is a port** (`wrap`, `unwrap`, `rotate`, `forget`), designed so a Secure Enclave-backed implementation never exposes the KEK. The in-memory provider is a development/test double only. **Production provider (Keychain, `ThisDeviceOnly`, Secure Enclave where `isAvailable`) is P02-02 and needs a physical iPhone.** Until then, no persistence of real data (hard limit).
4. **Policy is pure and deny-by-default.** `VaultPolicy` hard-denies analytics, model training, cloud sync and advertising for every personal class regardless of consent; device vault and user-encrypted backup are the only consent-free destinations; provider/crash-log flows require an active, purpose-matched `ConsentReceipt`. Parent names and sibling order are third-party data requiring purpose consent to store (decision 6).
5. **Recovery (decisions 3–4).** Optional, user-initiated `PortableBackup`: HKDF-SHA256 derives a backup KEK and a MAC key from a 256-bit `RecoveryKey` plus a random 16-byte salt; DEKs are re-wrapped under the backup KEK; payload ciphertext is unchanged; HMAC-SHA256 over the whole body (incl. entry order and count). Restore verifies the MAC in constant time, re-wraps under fresh device keys. XRAI never stores the recovery key; losing backup + key means loss, which the UI must state. No automatic cloud sync.
6. **Time and randomness are injected or system-provided**: timestamps are Unix seconds passed by the caller; randomness comes from CryptoKit/`SystemRandomNumberGenerator`. No `Date()`, no custom RNG.
7. **No home-made cryptography.** Only CryptoKit primitives (AES.GCM, HKDF, HMAC, SymmetricKey). PQC is not used (nothing here needs it; §83).
8. **Error vocabulary is typed** (`VaultError`): wrong key and tamper are indistinguishable by design (`authenticationFailed`), as are wrong recovery key and altered backup (`backupIntegrityFailed`).

## Alternatives considered
- HKDF-derived per-record keys from the KEK instead of random wrapped DEKs: rejected because rotation would force re-encryption and SE-backed KEKs cannot run HKDF.
- Password-based backup (PBKDF2/Argon2): rejected for now; a user password is low entropy, and the founder chose an independent high-entropy recovery key. May be added as an *additional* layer later.
- AES-KW (RFC 3394) for DEK wrapping: not in CryptoKit; AES-GCM wrap with binding AAD gives authentication as well.
- Storing key identity in the header: rejected (would break AEAD on rotation).

## Consequences
The vault can seal, open, rotate, export and restore at the library level with adversarial tests (64/64). It cannot yet persist anything safely: the Keychain/SE provider, Data Protection file classes, app-lock, egress broker and device tests are explicit follow-ups. Status words: CODED + TESTED (library); SECURITY_REVIEWED: NO; DEVICE_VERIFIED: NO.
