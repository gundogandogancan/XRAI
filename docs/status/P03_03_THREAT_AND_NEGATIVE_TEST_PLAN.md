# P03_03_THREAT_AND_NEGATIVE_TEST_PLAN — requirement → design → risk → test → evidence → remaining limit

**Date:** 2026-10-20 · **Baseline:** `713468e` · Extends `docs/security/VAULT_THREAT_MODEL_P02.md` (v1.5, T1–T38). Status words: `TESTED` (a test exists and passed in the ledger), `PLANNED` (test named for P03-04), `MANUAL_PENDING`, `LIMIT`.

Türkçe özet: Her mimari iddia için başarısızlık senaryosu; mevcut testler ve P03-04'te yazılacak negatif testler tek zincirde. Kişisel veri sızıntısı, izinsiz kayıt, iptal sonrası erişim, yedekten diriliş, yanlış kullanıcı, anahtar kaybı, token tekrarı, bozuk kayıt, saat geri alma, eşzamanlı rotasyon ve yarım kalan silme kapsanır.

| # | requirement | design element | risk if violated | negative test | evidence today | remaining limit |
|---|---|---|---|---|---|---|
| N1 | no record without authorization | `.write` token from `InteractionGate`; `mayStore` for gated classes | silent data collection | seal without token → `unknownToken`; seal gated class without grant → `consentRequired`; typing ≠ consent | TESTED (`EnforcementTests`, `continueWithoutDateDropsDraft`) | InteractionGate PLANNED |
| N2 | no access after revoke/expiry | `mayRead` at read time; derived invalidation; grace→delete | stale consent exploited | revoked → `open` denied; expired → denied; derived of revoked source unreadable | TESTED (`ReadAccessTests`); derived PLANNED | — |
| N3 | deleted record must not return from backup | tombstones + reconciliation | resurrection of deleted data | restore backup containing a tombstoned id → skipped | PLANNED | tombstones expire at 90 d → user-confirmed resurrection |
| N4 | no access to another user's data | one OS user, one vault, keys ThisDeviceOnly; backups openable only with the recovery key | cross-user exposure | foreign device key set cannot open (TESTED `createAndReuse`); wrong recovery key → `backupIntegrityFailed` (TESTED) | TESTED | shared-device scenario not modelled (single-user assumption, LIMIT) |
| N5 | key loss = data unreadable, never silent fallback | fail-closed provider; no legacy fallback in production config | plaintext fallback | missing/corrupt KEK → `keyUnavailable`/`keychainCorrupted` (TESTED on device) | TESTED | physical erasure not promised |
| N6 | token replay impossible | single-use ids; consumed ring persisted (P03-04) | replayed consent | replay → `alreadyConsumed` (TESTED); replay after relaunch → PLANNED (persisted ring) | TESTED / PLANNED | in-process forgery LIMIT (not OS boundary) |
| N7 | corrupted record detected, never partially decrypted | AEAD per record; header authenticated; import limits | garbage treated as data | flipped bytes anywhere → `authenticationFailed`/`backupIntegrityFailed` (TESTED) | TESTED | — |
| N8 | clock rollback cannot revive anything | effective time ≥ high-water mark; mark persisted (P03-04) | revoked consent returns | rollback 1–300 s → still revoked (TESTED); rollback across relaunch → PLANNED | TESTED / PLANNED | first observation after reboot LIMIT |
| N9 | concurrent rotation safe | in-process `KeySetSerializer`; single-writer rule cross-process | lost pointer / unreadable records | two instances rotate concurrently → monotonic (TESTED) | TESTED | cross-process BLOCKED by rule, not mechanism |
| N10 | crash mid-delete leaves no half state | journaled cascade, idempotent replay | dangling derived data / half-deleted source | kill after each journal step → replay completes | PLANNED | — |
| N11 | personal data never in logs | no logging in vault modules (static scan); redacted descriptions; audit events without payload | leak via crash/analytics | source scans (TESTED); description redaction (TESTED); app-level log audit PLANNED | TESTED (library) | OS-level crash telemetry audit in P12 |
| N12 | app-switcher snapshot shows no data | `PrivacyShieldPolicy` | shoulder-surf / snapshot leak | policy unit test (TESTED); visual snapshot check MANUAL_PENDING | TESTED / MANUAL_PENDING | — |
| N13 | derived data cannot outlive sources | `derivedFrom` in authenticated header; manifest reverse index; cascade | orphan interpretations | delete source → derived gone; back-edge rejected | PLANNED | — |
| N14 | backup leaks no metadata | sealed backup v2 | ids/classes in the clear | bytes contain no ids/classes/tiers/timestamps (TESTED) | TESTED | size leak at 4 KiB granularity |
| N15 | file store leaks no metadata | random file names, encrypted manifest, padding | activity profiling | directory listing contains only hex names and padded sizes | PLANNED | file count/size LIMIT |
| N16 | reinstall does not silently reuse stale keys | REINSTALL_KEY_POLICY | confusing or unsafe state | launch with keys but no manifest → wipe-or-restore prompt | PLANNED | — |
| N17 | a tap is the only consent | `InteractionProof` minted inside the action closure; scene active; 5 s | programmatic consent | issue without proof / inactive / stale / reused → denied | PLANNED | in-process LIMIT |
| N18 | no egress of personal data | `VaultPolicy` hard rules; no network broker yet | cloud/analytics leak | hard-denied destinations even with blanket consent (TESTED) | TESTED | runtime `NetworkEgressBroker` + traffic capture P06/P12 |
| N19 | forget key only with proof | `KeyRetirementProof` | data loss by premature forget | forget with usage > 0 refused; proof stale refused | PLANNED (two-phase retire/forget TESTED) | — |
| N20 | AHTOVIA gets nothing automatically | no shared container, no app group with data, typed bridge only (future) | child/adult data mixing | app has no app-group entitlement (verify in entitlements) | TESTED (entitlements file shows none) | bridge design future |

## Evidence chain rule
A row moves from PLANNED to TESTED only with a log in `docs/status/evidence/` and an entry in `TEST_EVIDENCE_LEDGER.json`; MANUAL_PENDING rows need a human-signed note; LIMIT rows are never closed, only re-assessed.
