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
