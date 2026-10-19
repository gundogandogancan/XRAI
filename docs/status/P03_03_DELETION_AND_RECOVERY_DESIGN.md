# P03_03_DELETION_AND_RECOVERY_DESIGN — deletion, tombstones, grace, backup reconciliation, key retirement

**Date:** 2026-10-20 · **Baseline:** `713468e` · Companion to the persistence ADR (P03_03_SECURE_PERSISTENCE_ADR.md) and the lifecycle matrix.

Türkçe özet: Silme = kaskad (türetilmişler önce) + mezar taşı + günlüklenmiş çok adımlı işlem; çökme sonrası idempotent tamamlanır. Yedekten geri yükleme mezar taşlarıyla uzlaştırılır: silinmiş kayıt geri gelmez, izni aktif olmayan kayıt karantinada kalır. Anahtar unutma yalnızca store kanıtıyla. Şifreleme anahtarını silmek "kripto-parçalama"dır, fiziksel silme garantisi değildir.

## 1. Deletion kinds

| kind | trigger | authorization | effect |
|---|---|---|---|
| record delete | user action ("Sil") | `.delete(recordIDs)` token → `DeletionGrant` (exists) | cascade (§2) + tombstone |
| forget-now (today) | "Tarihi unut" | none needed (memory only) | `forgetAll()` clears date + draft |
| consent-driven | revoke/expiry on a consent-gated class | automatic, logged | read block now → `pendingDelete` with 7-day grace → delete |
| wipe | "Her şeyi sil" | `.delete(all)` + `WipeConfirmation` + biometric (later) | delete all records, tombstones, manifest; then `wipeAllKeys` |
| crypto-shred | key forgotten after retirement | store proof (§4) | all records under that key become permanently unreadable |

## 2. Cascade algorithm (journaled, idempotent)

```
delete(S):
  J = journal.begin(kind: delete, roots: S)
  order = topologicalDependentsFirst(S)        // dependents (derived) before sources
  for id in order:
     manifest.state[id] = pendingDelete; write manifest        (step logged)
     unlink records/<id>.env (+ attachments)                   (step logged)
     tombstones.append(id, now); write tombstones              (step logged)
     manifest.remove(id); write manifest                       (step logged)
  journal.commit(J)
on launch: for each uncommitted J: re-run from the first unlogged step (every step is safe to repeat)
```
Derived records of a deleted source are deleted in the same cascade; derived records whose source merely changed are marked `stale` and deleted at the next maintenance pass (lifecycle matrix §2).

## 3. Tombstones and backup reconciliation

- Tombstone = `(RecordID, deletedAt)`; no class, no content. Kept 90 days, then dropped (a backup older than 90 days could resurrect a record; the restore UI says so and lists resurrected ids by class for the user to confirm or delete).
- Restore: staged → every envelope verified → for each entry: if a tombstone exists with `deletedAt > entry.createdAt` → skipped (logged as `skippedDeleted`); if consent inactive → quarantined (exists); else active. Then the atomic swap. The old vault is kept as `vault.previous` until the user confirms the restore (one launch), then deleted via the same cascade.
- Backups never contain tombstones' timestamps beyond ids (ids are random, non-personal).

## 4. Key retirement with store proof (closes `FORGET_REQUIRES_STORE_PROOF` once implemented)

```
rotate()  → new KEK version N+1 (exists)
rewrapAll → every envelope and attachment rewrapped to N+1; journaled; manifest.keyUsage[N] → 0
proof     → store scans all envelope files, asserts no wrappedDEK.keyVersion == N, hashes the manifest → KeyRetirementProof
retire(N) → KeychainKeyProvider.retire (exists)
forget(N, proof) → coordinator verifies proof.manifestHash == current manifest hash and usage == 0 → KeychainKeyProvider.forget (exists)
```
Failure modes: proof stale (a record was written under N after the scan) → refused; rewrap journal incomplete → refused; scan interrupted → no proof.

## 5. What deletion does NOT guarantee
- Physical erasure on flash (wear-levelling, APFS snapshots, Spotlight is not used, Time Machine not applicable on iOS).
- Removal from the user's own exported backups (they are the user's files).
- Removal from memory until the process ends (Swift has no zeroization guarantee; the key cache and `forgetAll()` drop references).
- Removal from third parties — none receive data by design; if a per-call provider consent is ever used, retrospective deletion cannot be promised (ADR-005 §84 rule stays).

## 6. Recovery scenarios

| scenario | outcome |
|---|---|
| device lost, user has backup + recovery key | restore on new device, new key set, quarantine rules apply |
| device lost, no backup | data gone (stated in onboarding) |
| recovery key lost | backup unreadable by anyone, XRAI included (stated) |
| app reinstalled, device intact | manifest gone, keys remain → `REINSTALL_KEY_POLICY`: wipe keys unless restoring |
| corrupted manifest | rebuild from `records/` headers (each header is authenticated; derivedFrom inside); tombstones file authoritative for deletions; if tombstones corrupt → treat as empty and warn (resurrection risk shown) |
| corrupted record | marked corrupt; recover from backup only |
| passcode removed | with `WhenUnlocked` keys nothing is lost; the user is told the device-level protection weakened |

## 7. Tests (P03-04)
cascade order · tombstone beats restore · restore of consent-inactive record quarantined · crash after each journal step → recovery completes · proof refused with usage > 0 · proof refused when manifest changed · wipe leaves no file and no key · corrupted manifest rebuilt from headers · 90-day tombstone expiry resurrects only with user confirmation.
