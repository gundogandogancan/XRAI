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

---

## APPROVAL RECORD — 2026-10-19 (user, after ChatGPT review of BOOT_00_REPORT)

```
APPROVED_BY: founder (via "XRAI — GOD LEVEL P02 SECURITY APPROVAL" message)
DATE: 2026-10-19
SCOPE_APPROVED: V32-02-01 only — threat model + vault ADR; PrivacyTier, RecordEnvelope, ConsentReceipt, RetentionClass, KeyProvider contracts; crypto adapter separated from the pure core; tests for wrong key, tampered ciphertext, nonce strategy, corrupted backup, key rotation, privacy violation; real swift build/test exit codes; BOOT-01 regression check; P02_01_SECURITY_REVIEW_REPORT.md; commit.
CHANGES_REQUESTED: none to BOOT-01.
HARD_LIMITS: no persistent storage of real user data yet; no cloud backup; vault not "complete" before an independent security review; no history rewrite or force-push.
```

### Binding security decisions recorded (resolve DEVICE_BACKUP_POLICY and PARENT_NAME_SCOPE)
1. Local-first: all sensitive personal data encrypted on the iPhone by default; no silent cloud sync, no central personal memory.
2. Device keys: Apple Keychain, Secure Enclave where appropriate; never claim hardware capabilities the device lacks.
3. Recovery: optional user-initiated, end-to-end encrypted portable backup protected by an independent high-entropy recovery key the XRAI server never knows. No automatic cloud sync for now.
4. New device: encrypted backup restorable only with explicit consent; fresh device keys on the new device; loss of backup + recovery key may make data unrecoverable, and the user is told so plainly.
5. Cryptography: CryptoKit AES-256-GCM, unique nonce per seal, authenticated versioned metadata, secure key lifecycle; no home-made algorithms.
6. Family data: parent names and sibling order optional, processed only for the user's explicitly chosen purpose; never for ads, analytics, model training or cloud transfer by default.

---

## V32-02-01 RESULT (2026-10-19) — DONE AT LIBRARY LEVEL, STOP

`swift build` exit 0; `swift test` exit 0, 64/64 (35 BOOT-01 + 29 vault). Report: `docs/status/P02_01_SECURITY_REVIEW_REPORT.md`. ADR-BOOT-005, threat model v1. Not SECURITY_REVIEWED, not DEVICE_VERIFIED, no data persisted.

### Proposed next (awaiting ChatGPT review; not started)
- **Option A — P02-02 `KeychainKeyProvider`**: Security-framework adapter for the `KeyProvider` port (Keychain `ThisDeviceOnly`, Secure Enclave where available, capability flag), simulator smoke test, physical-iPhone checklist.
- **Option B — V32-02-02 derived-data invalidation and deletion graph** (pure, no device needed).

```
APPROVED_BY:
DATE:
SCOPE_APPROVED:
CHANGES_REQUESTED:
```

---

## V32-02-01H RESULT (2026-10-19) — HARDENING APPLIED, STOP

ChatGPT review findings F1–F5 closed (sealed backup v2, mandatory `SecureVault` + `ConsentAuthority`, tier floors fail-closed, identifier hygiene, export/import verification and limits). `swift build` exit 0; `swift test` exit 0, 71/71. BOOT-01 core: zero diff. Report: `docs/status/P02_01H_SECURITY_HARDENING_REPORT.md`. Still NOT SECURITY_REVIEWED / DEVICE_VERIFIED; no persistence.

Decision pending from ChatGPT review: P02-02 (Keychain provider) vs V32-02-02 (invalidation graph).

```
APPROVED_BY:
DATE:
SCOPE_APPROVED:
CHANGES_REQUESTED:
```

---

## V32-02-01H2 RESULT (2026-10-19) — AUTHORIZATION GATE APPLIED, STOP

G1–G5 implemented: access contract with scoped single-use tokens from a trusted issuer, purpose-bound consent on read, trusted clock with monotonic guard, maintenance separation, rewrap-after-verify, quarantine on restore, private vault ports, `XRAIVaultTesting` split, compiler-verified compile-negative test. `swift build` exit 0; `swift test` exit 0, 81/81. BOOT-01 core: zero diff. Report: `docs/status/P02_01H2_AUTHORIZATION_GATE_REPORT.md`. Not SECURITY_REVIEWED / DEVICE_VERIFIED; no persistence.

If H2 is accepted → next task **P02-02 `KeychainKeyProvider`** (Keychain ThisDeviceOnly KEK, Secure Enclave where available, capability flag, simulator smoke test, physical-iPhone checklist).

```
APPROVED_BY:
DATE:
SCOPE_APPROVED:
CHANGES_REQUESTED:
```
