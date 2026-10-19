# NEXT_TASK — awaiting external review (2026-10-19)

**Current gate:** BOOT-00 (reality audit) and BOOT-01 (pure Swift core, 35/35 tests, exit 0) are complete. Per `CLAUDE_FIRST_SESSION_v3.2.md` and constitution §93, **STOP here**. The user will submit `docs/status/BOOT_00_REPORT.md` to ChatGPT for independent audit. P02 does not start without written approval appended to this file.

## Proposed next smallest implementable task (not started)

**V32-02-01 — Envelope crypto + backup recovery ADR (P02, part 1 of vault)**
Scope: an ADR only plus a pure-Swift *contract* layer, no persistence yet:
1. `docs/adr/ADR-BOOT-005-vault-envelope-and-recovery.md`: AES-256-GCM via CryptoKit, per-record keys wrapped by a Keychain/Secure Enclave-protected master key, privacy tiers from `SECURITY_DATA_EGRESS_MATRIX_v3.2.json`, explicit `ThisDeviceOnly` vs user-encrypted-backup choice (DEVICE_BACKUP_POLICY), threat list from §83.
2. `Packages/XRAICore/Sources/XRAIVaultContracts/` : typed `PrivacyTier`, `RecordEnvelope` (alg/version tagged), `ConsentReceipt`, `RetentionClass`, and a `KeyProvider` port protocol. Still no Foundation in domain types where avoidable; CryptoKit adapter lives in a separate target with its own negative tests (no plaintext DOB in ciphertext metadata, tamper detection, wrong-key failure).
3. Tests: round-trip, tamper, key-rotation, and a static scan that only the adapter target may import CryptoKit/Security.

Dependencies satisfied: V32-01-01 and V32-01-02 (this session). Requires user decisions: DEVICE_BACKUP_POLICY, PARENT_NAME_SCOPE (can be deferred by designing the field tier as data).

## Approval block (to be filled by the user after ChatGPT review)
```
APPROVED_BY:
DATE:
SCOPE_APPROVED:
CHANGES_REQUESTED:
```
