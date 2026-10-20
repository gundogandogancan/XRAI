# ADR-BOOT-009 — Secure persistence architecture for personal records (P03-03)

**Status:** PROPOSED (2026-10-20), awaiting external review · **Baseline:** `713468e` · **Implements:** nothing yet.

The full decision record, option evaluation, layout, folded-in threats, `VaultStore` port and the key-retirement store proof live in [`docs/status/P03_03_SECURE_PERSISTENCE_ADR.md`](../status/P03_03_SECURE_PERSISTENCE_ADR.md). Companion designs: [data inventory](../status/P03_03_DATA_INVENTORY.md), [lifecycle matrix](../status/P03_03_DATA_LIFECYCLE_MATRIX.md), [consent authority spec](../status/P03_03_CONSENT_AUTHORITY_SPEC.md), [deletion and recovery](../status/P03_03_DELETION_AND_RECOVERY_DESIGN.md), [threat and negative test plan](../status/P03_03_THREAT_AND_NEGATIVE_TEST_PLAN.md), [privacy/intelligence boundary](../status/P03_03_PRIVACY_INTELLIGENCE_BOUNDARY.md).

## Decisions (summary)
- D1 record-per-file `RecordEnvelope` store + encrypted manifest; SQLCipher deferred to its own ADR.
- D2 `derivedFrom[]` in the authenticated header (format v3); derived data never outlives its sources.
- D3 journaled idempotent cascade delete + tombstones (90 days) + restore reconciliation.
- D5 `KeyRetirementProof` from the store before any `forget`.
- D6–D8 persisted consent receipts/events, `InteractionGate`, persisted consumed-token ring and clock mark.
- D9 vault directory excluded from OS backups, Data Protection complete, random names, 4 KiB padding.
- D11 crypto-shredding promised, physical erasure not.

## Relation to earlier ADRs
Extends ADR-BOOT-005 (envelopes/backup), 006 (Keychain/SE), 007 (cache/rotation/two-phase forget) and 008 (in-memory session). No contradiction found; the `WhenUnlocked` accessibility tension of ADR-006 D2 is recorded.

## Acceptance
Becomes ACCEPTED only after review and once P03-04 tests exist (`P03_03_THREAT_AND_NEGATIVE_TEST_PLAN.md` rows N3, N10, N13, N15, N16, N19 move from PLANNED to TESTED).

---

## Amendment H (2026-10-20, P03-03H) — hardening after independent review; original decisions above are kept for history

| original | amended | where |
|---|---|---|
| D3 tombstones kept 90 days; older backups may resurrect with user confirmation; corrupt tombstones treated as empty | **permanent deletion ledger** cross-bound to the manifest and the Keychain anchor; fail-closed digest compaction only above 200 000 entries; missing/corrupt ledger → every restore quarantined; a known-deleted id is **never** reactivated under its id; suspicious backups quarantined whole; explicit risk screen; LIMIT: deletions after an old backup's export are unknowable after device loss | `P03_03H_SECURITY_REMEDIATION_REPORT.md` H1 |
| D5 `KeyRetirementProof` = manifest hash + zero count | **retirement protocol v2** (R0–R7): freeze `minimumWrapVersion`, journaled rewrap incl. system envelopes, full inventory digest, three-way cross-check, proof bound to manifest generation + exclusive section token, retire+forget inside the same section; backups never reference device KEK versions | H2 |
| D8 consumed-token ring (10 000) + persisted clock mark | **persisted epoch** (increments on every launch and restore), token id = epoch‖counter‖random, in-memory consumed set per epoch, journal begin carries the token id in the same critical section; `authz.v1` never exported; clock mark bound to manifest generation and Keychain anchor | H3 |
| D4 revoke → 7-day grace then delete | **two operations**: `deleteRecords` (immediate, no grace) and `revokeConsent` (immediate access stop; `suspended` only when the user explicitly chooses it and only for grace-eligible own-authored classes); re-grant never reactivates; `restoreSuspended` is a separate authorized action | H4 |
| §3 "interrupted writes / cross-process" rows | explicit contracts for atomic replace, durable commit, recovery, manifest rollback detection (generation chain + `authz` + ledger + Keychain anchor), truncated journal, orphans/missing, partial envelopes, symlink/path traversal, advisory single-writer lock, power loss; each with a negative test id | H5, `P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md` |

Status after Amendment H: still PROPOSED; D1 (record-per-file) and D7 (in-process InteractionGate with stated limit) were conditionally accepted by the reviewer; implementation scope fixed in `P03_04_IMPLEMENTATION_CONTRACT.md`.

## Amendment H.1 (2026-10-20, P03-04H) — durability contract after the first independent code review

| original (Amendment H / P03-04 code) | amended | where |
|---|---|---|
| "temp (exclusive) → write → fsync → close → rename → fsync(dir)" with iOS creation via `FileManager.createFile` + `open(O_TRUNC)` and the directory flush result ignored | exclusive creation is one `O_CREAT\|O_EXCL\|O_NOFOLLOW` open on every platform; the descriptor is verified (regular, nlink 1, 0600, empty) and on iOS carries Data Protection A, read back on the descriptor before any byte; every durability result is checked (`VaultError.ioFailed`); `F_FULLFSYNC` falls back to `fsync` only when unsupported; EINTR retried except on close | `VaultFileSystem.swift`, NT-FS-01…08 |
| mutation errors propagated, instance stayed writable | any error inside a journaled mutation → `.readOnly("mutation interrupted: reopen required")`; reads and writes refused; the on-disk journal decides at reopen | `FileVaultStore.runMutation`, NT-FS-08/12 |
| loader cleaned temp files before the writer lock; ledger hash mismatch tolerated read-write; admission checked per item in the body | lock before any removal; authentic unbound ledger → read-only; admission validated before the journal begins | NT-FS-09/10/11 |

Explicitly NOT claimed: survival of every power loss (no power-cut rig; APFS directory-fsync semantics undocumented); Data Protection semantics on the Simulator; the class-number mapping beyond its empirical device verification.

