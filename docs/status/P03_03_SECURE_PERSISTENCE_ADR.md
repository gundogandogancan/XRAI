# P03_03_SECURE_PERSISTENCE_ADR — ADR-BOOT-009: how encrypted personal records will be stored

**Status:** PROPOSED for ChatGPT review (2026-10-20) · **Baseline:** `713468e` · **Depends on:** ADR-BOOT-005 (envelope encryption, backup), 006 (Keychain/SE KEK), 007 (cache, rotation), 008 (session/UX) · **Implements nothing yet.**

Türkçe özet: Depolama için SQLCipher/GRDB, dosya tabanlı şifreli kayıt ve mevcut zarf şifreleme bağımsız değerlendirildi. Karar: ilk kalıcı kasa, test edilmiş `RecordEnvelope`'ların kayıt-başına-dosya olarak atomik yazıldığı, rastgele kimlik adlı, Data Protection "complete" sınıfında, iCloud/iTunes yedeğinden hariç tutulmuş bir dosya deposu ve yine zarf olarak şifrelenmiş bir manifest. SQL yok, üçüncü taraf kripto yok, düz metin metadata yok, WAL/SHM yok. Arama/ilişki ihtiyacı doğduğunda (P05+) GRDB+SQLCipher ayrı bir ADR ile değerlendirilecek. Anahtar silmek fiziksel silme garantisi değildir; bu açıkça belirtildi.

## 1. Options evaluated

| criterion | A. GRDB + SQLCipher | B. record-per-file envelopes (chosen) | C. SQLite (plain) + field encryption |
|---|---|---|---|
| crypto | SQLCipher's own AES-256-CBC + HMAC (OpenSSL/CommonCrypto); page-level | our CryptoKit AES-256-GCM envelopes, already tested (91 vault tests, device-verified) | ours, per field; metadata in plain SQLite |
| plaintext metadata | none on page level, but WAL/SHM/journal/temp files exist (encrypted by SQLCipher, yet their presence/size leaks activity) | file names = random `RecordID` hex; sizes leak coarse volume only (already accepted at 4 KiB granularity for backups; apply 4 KiB padding to files too) | **leaks** schema, ids, timestamps |
| atomic writes | SQLite journaling | temp file + `rename` (atomic on APFS) + fsync; manifest rewritten the same way | SQLite |
| queries | SQL | manifest in memory (small); linear scans fine for thousands of records; no full-text search | SQL |
| performance / energy | good; extra C library | excellent for ≤ 10 k records; per-record open is one GCM | good |
| dependency / licence | SQLCipher community: BSD-style; GRDB: MIT; binary +1–2 MB; two more supply-chain items to pin and audit | none | none |
| iOS Data Protection | applies to the db file; WAL needs same class | per file, `.complete` | same |
| OS backup exclusion | one flag | one directory flag | one flag |
| rotation / rewrap | must touch every row anyway | rewrap = rewrite envelope file | same |
| reviewability | more surface | smallest surface; one code path already reviewed by ChatGPT rounds | medium |

**Decision D1:** Option B for the first persistent vault. Revisit A in a separate ADR when search/relations are needed (P05 goals/evidence), with SQLCipher pinned and audited; migration path = export envelopes → import into SQLCipher rows (envelopes stay the unit of encryption either way).

## 2. Layout

```
<AppSupport>/XRAIVault/            (isExcludedFromBackup = true; NSFileProtectionComplete)
  manifest.v1                       RecordEnvelope(dataClass: .consentReceipts tier system) containing the Manifest
  records/<recordID>.env            RecordEnvelope bytes (canonical encoding), padded to 4 KiB
  attachments/<recordID>.env        large evidence files, same envelope format, streamed in 1 MiB chunks (each chunk its own GCM seal, chained by chunk index in AAD)
  tombstones.v1                     RecordEnvelope containing [RecordID + deletedAt]
  authz.v1                          RecordEnvelope: consumed-token ring, clock high-water mark, launch counter
  journal/                          pending multi-step operations (cascade deletes, rotations) as envelopes; replayed on launch
```
- Manifest = `{ records: [id → {dataClass, tier, retention, createdAt, keyVersion, derivedFrom[], dependents[], state ∈ {active, pendingDelete, stale, quarantined}}], purposes, keyUsage: [keyVersion → count] }`. The manifest is itself an envelope → every metadata field is encrypted and authenticated. Writes: serialize → seal → temp → rename → fsync directory.
- Header format v3 adds `derivedFrom[]` and `schemaVersion` to the authenticated header (new records only; v2 reads as leaf, no migration of personal data exists because nothing is persisted yet).

## 3. Threats folded into the design

| threat | design |
|---|---|
| SQLite WAL/SHM/temp | none exist (no SQLite); temp files are our own, same directory, same protection, removed on rename or by launch recovery |
| plaintext metadata | none: names random, contents envelopes, manifest encrypted; residual = file count and padded sizes |
| crash logs | vault modules forbid logging (static test); app must not log record contents; `MetricKit`/crash SDKs not integrated |
| OS backups | directory excluded; Keychain items ThisDeviceOnly; the ONLY backup is the user's sealed backup |
| device reinstall | files gone, Keychain keys remain → `REINSTALL_KEY_POLICY`: on first launch with no manifest, the app wipes the key set (confirmation flow) unless the user is restoring a backup; stale keys never silently reused |
| passcode removal | `WhenUnlocked` keys survive; (`WhenPasscodeSet` would be deleted by the OS → data loss) — default stays WhenUnlocked (ADR-006 D2); documented to the user |
| key loss | records unreadable = crypto-shredded; only the user's sealed backup + recovery key can recover |
| key rotation | rewrap envelope files one by one; `keyUsage` counters in the manifest; retire/forget gated by store proof (§5) |
| interrupted writes | temp+rename atomicity; multi-step ops journaled and replayed; manifest and files reconciled on launch (orphan files → quarantine folder, never silently adopted) |
| restore rollback | restore is staged into `restore-staging/`, verified (every payload opens), reconciled with tombstones, then swapped in atomically; failure leaves the old vault untouched |
| corrupted records | AEAD failure → record marked `corrupt` in manifest, unreadable, shown to the user, recoverable only from backup |
| cross-process races | single-writer rule: only the main app opens the vault for writing; extensions read-only (none planned); file coordination via `NSFileCoordinator` not needed under that rule; rotation already serialized in-process |
| secure deletion limits | unlink + key forgetting; flash wear-levelling and APFS snapshots may retain ciphertext; **we promise crypto-shredding, not physical erasure** |
| backup rekeying | restore re-wraps every DEK under fresh device keys (exists); after restore, old device key set is irrelevant |

## 4. Interfaces (ports to add in P03-04)

```swift
protocol VaultStore {                       // single writer, main app only
  func put(_ env: RecordEnvelope, derivedFrom: [RecordID], authorization: OperationAuthorization) throws
  func get(_ id: RecordID, authorization: OperationAuthorization) throws -> RecordEnvelope   // policy + quarantine + stale checks via SecureVault
  func delete(_ ids: Set<RecordID>, grant: DeletionGrant) throws                               // cascade + tombstone + journal
  func rewrapAll(toCurrentKey maintenance: OperationAuthorization) throws -> RewrapReport
  func keyUsage() -> [UInt32: Int]
  func retirementProof(for version: UInt32) throws -> KeyRetirementProof                      // §5
}
```
`SecureVault` stays the only crypto entry point; `VaultStore` composes it.

## 5. Store proof for forgetting a key (resolves `FORGET_REQUIRES_STORE_PROOF`)

`KeyRetirementProof { keyVersion, manifestHash, recordsStillWrapped: 0, rewrapReportID, issuedAt }` is produced by the store **only** when: manifest `keyUsage[version] == 0`, the rewrap journal for that version is complete, and a full scan of `records/` + `attachments/` finds no envelope whose `wrappedDEK.keyVersion == version` (the scan result hash is part of the proof). `KeyRetirementCoordinator.forget(version:, proof:)` checks the proof's manifest hash against the current manifest and only then calls `KeychainKeyProvider.retire` → `forget`. Without a store there is no proof — which is exactly today's state, so the blocker stays open until P03-04 and then closes with tests: forget refused with nonzero usage; proof invalid after a new record is written under the old version; proof bound to the manifest hash.

## 6. Consistency with existing ADRs
ADR-005 (envelopes, sealed backup v2) unchanged; ADR-006 (Keychain/SE, accessibility class) unchanged; ADR-007 (cache, rotation, two-phase forget) extended by §5 proof; ADR-008 (session in memory, onboarding flag) — the flag moves into `authz.v1`/preferences once the store exists. **Contradiction check:** none found; one tension recorded — ADR-006 D2 keeps `WhenUnlocked`, so passcode removal does not shred data; the sealed-backup story is the user's protection, and the threat model says so.

## 7. Not decided (UNKNOWN / deferred)
Attachment size caps; biometric gating per operation; whether the manifest should be sharded above ~10 k records; SQLCipher adoption timing; multi-user devices (one vault per OS user by construction).
