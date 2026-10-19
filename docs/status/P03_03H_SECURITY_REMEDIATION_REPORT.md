# P03_03H_SECURITY_REMEDIATION_REPORT — hardening of the P03-03 design before any store code

**Date:** 2026-10-20 · **Baseline:** `7fc3091` (HEAD == baseline, tree clean, in sync with origin) · **Mode:** design hardening only; no store implemented; no Swift code changed · **Supersedes parts of:** ADR-BOOT-009 (Amendment H, history kept) · **Status words:** DESIGN (specified here), TESTED (existing test in the ledger), PLANNED (test id in `P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md`), LIMIT (cannot be closed by design).

Türkçe özet: ChatGPT'nin H1–H6 bulguları tasarım düzeyinde kapatıldı: (H1) 90 günlük mezar taşı süresi kaldırıldı; silme defteri kalıcı, yedek nesilleriyle bağlı, eksik/bozuk defter asla "boş" sayılmıyor, şüpheli geri yüklemeler karantinaya giriyor, silindiği bilinen kayıt aynı kimlikle asla geri gelmiyor; cihaz kaybı + eski yedek senaryosunda silme geçmişinin bilinemeyeceği sınır olarak yazıldı. (H2) Anahtar emekliliği yedi adımlı, yarışa dayanıklı protokol: dondurma, tam envanter taraması, manifest nesil bağı, günlük tamamlanma kanıtı, aynı özel bölüm içinde unutma. (H3) 10.000'lik token halkası yerine kalıcı epoch tasarımı; token tüketimi ile günlük girişi aynı kritik bölümde; yetki durumu yedeğe asla girmiyor; saat işareti manifest ve Keychain çapasına bağlı. (H4) "Kalıcı sil" anında siler; izin geri çekme ayrı işlemdir, erişim anında durur, 7 günlük askı yalnız kullanıcının açıkça seçtiği sınıflarda; yeniden izin otomatik diriltmez. (H5) Atomik yazma, dayanıklı commit sınırı, geri alma tespiti, kesik günlük, yetim/eksik kayıt, symlink/yol koruması, tek yazar kilidi, güç kaybı kurtarma sözleşmeleri ve negatif testleri. (H6) F-UX-4/5 açık; F-UX-5 sonraki UX kapısının zorunlu kabul testi.

## 0. Reality check
HEAD `7fc3091` == baseline; `git status` clean; `origin/main` == HEAD. Facts re-read from code before designing: `AuthorizationIssuer` keeps `issued`/`consumed` in memory (ids 128-bit random, per process); `MonotonicGuardClock` mark is per process; `BackupCodec.export` unwraps DEKs with the device key and seals them under the recovery-derived key, `restore` re-wraps under THIS device's current key → backups never reference device KEK versions; `restoreBackup` quarantines consent-inactive records via the trusted `QuarantineAuthority`.

## H1 — delete must never silently resurrect

### Old decision (P03-03 D3) → new decision (H1)
| aspect | P03-03 | P03-03H |
|---|---|---|
| tombstone retention | 90 days, then dropped | **permanent deletion ledger**; compaction only into a fail-closed digest (never dropped) |
| missing/corrupt tombstones | "treat as empty and warn" | **never empty**: ledger untrusted → every restore quarantines all records; vault flags `deletionHistoryUntrusted` |
| resurrection after window | user confirms by class | **a known-deleted id is never reactivated**, with or without consent; only an explicit per-record re-import creates a *new* record id with an audit event |
| backup ↔ deletion link | none | every backup carries `vaultInstanceID`, `backupGeneration`, and the deletion ledger digest at export, inside the authenticated sealed body (backup body v3) |
| old-backup restore | allowed with a warning | explicit risk screen + per-class quarantine release; restore is blocked without the user's informed choice |

### Deletion ledger (replaces "tombstones")
- Entry: `(recordID 16 B, deletedAtUnixSeconds 8 B, manifestGenerationAtDelete 8 B)` = 32 B; no class, no content. 100 000 deletions ≈ 3.2 MiB before padding; realistic volume is thousands → **unbounded retention is affordable**. Privacy effect: only the padded ledger size leaks a coarse deletion count (same 4 KiB granularity as everything else). The ledger is a `RecordEnvelope` (AEAD) and is cross-bound to the manifest (H5).
- Alternatives evaluated: (a) drop after N days — rejected (silent resurrection); (b) drop entries older than the oldest backup the user still holds — rejected (backups are user files, the app cannot know which ones exist); (c) compaction into a **sealed deletion digest** (Bloom filter, false-positive rate ≤ 1e-6 at 1 M entries ≈ 3.6 MB; false positives cause quarantine, never resurrection) — **adopted only beyond 200 000 entries**; (d) keep forever — adopted as the default. Compaction is a fail-closed transformation: an id that *might* have been deleted is treated as deleted-until-reviewed (quarantine), never as live.
- The ledger is **exported inside every backup** (body v3) so the backup itself proves the deletions that happened before export.

### Restore reconciliation (fail-closed order)
1. Verify the backup (exists). Read `vaultInstanceID`, `backupGeneration`, embedded ledger `L_b`.
2. Load the local ledger `L_l` only if its AEAD verifies **and** its (generation, hash) matches the manifest's and the Keychain anchor's record of it (H5). Otherwise `L_l = UNTRUSTED`.
3. For each entry `e` of the backup: if `e.id ∈ L_b ∪ L_l` → `skippedDeleted` (never restored, logged by id only). If `L_l == UNTRUSTED` → `quarantined(reason: unverifiedDeletionHistory)`. If consent inactive → `quarantined` (exists). Otherwise active.
4. **Suspicious backups** are quarantined whole, pending per-class release: different `vaultInstanceID` from a vault that currently has data; `backupGeneration` lower than the local manifest's `lastExportedGeneration`; embedded ledger shorter than the local ledger's state at that generation; a backup created before the local vault's newest deletion. Release needs a `.releaseQuarantine` token + fresh grant + the risk screen acknowledgement (interaction proof `confirmDialog`).
5. The risk screen states, in plain words: "Bu yedek <tarih>'de alındı. O tarihten sonra sildiğin veriler bu yedekte olabilir. XRAI bunları karantinada tutar; sen sınıf sınıf gözden geçirmeden hiçbiri etkinleşmez."
6. Known-deleted ids never return under their id. A per-record "yeniden içe aktar" action creates a new `RecordID`, requires the same consent as a new entry, and writes a `reimportedFromBackup` event (ids only).

### Stated limit (LIMIT, not closable by design)
Device lost + only an old portable backup: deletions made **after** that backup's export are unknowable; the restored vault contains those records in quarantine, the user is told, and must review them. No physical erasure, no "absolute forgetting" is claimed. The ledger inside the backup covers deletions **before** export only.

## H2 — race-safe key retirement (replaces P03-03 D5 "zero count")

### Retirement protocol v2 (seven steps, all inside one exclusive maintenance section of the store actor)
| step | action | invariant produced |
|---|---|---|
| R0 rotate | `KeychainKeyProvider.rotate()` → N+1 current (exists) | all new wraps use N+1 (pointer re-read before wrap, exists) |
| R1 freeze | manifest `minimumWrapVersion = N+1`, generation++ , durable commit | any envelope presented for write with `wrappedDEK.keyVersion < minimumWrapVersion` is refused with `staleKeyVersion` — **before, during and after** the proof |
| R2 rewrap | journal `rewrap-N` begun with the inventory count; each record, attachment, and **system envelope** (manifest, ledger, authz, journal entries) rewrapped via atomic file replace; each step logged; journal committed with the count | an envelope on disk is either fully old or fully new, never mixed |
| R3 inventory | full enumeration of `records/`, `attachments/`, `system/`, `journal/`: parse **every file's authenticated header** and count by key version; refuse if any file fails AEAD, any `.tmp-*` exists, or any file is not in the manifest | scan digest `D = SHA-256(sorted (path, recordID, keyVersion))` |
| R4 cross-check | scan count for N == 0 **and** manifest `keyUsage[N] == 0` **and** journal `rewrap-N` committed with count == inventory count at R2 | three independent sources agree |
| R5 proof | `KeyRetirementProof{ keyVersion: N, manifestGeneration, manifestHash, scanDigest, journalCommitHash, sectionToken, issuedAtMonotonic }` | bound to the exact manifest generation and the exclusive section |
| R6 retire+forget | still inside the section: `retire(N)` then `forget(N, proof)`; coordinator re-reads the manifest and refuses if `generation != proof.manifestGeneration` or the section token differs; purge key cache for N | no write can interleave; TOCTOU window is zero within the actor |
| R7 record | manifest `retiredVersions += N`, generation++ , durable commit; event `keyRetired(N)` (no key material) | relaunch knows N is gone |

- **Writer quiescence:** `FileVaultStore` is a Swift actor; retirement is a single actor method, so no put/delete can interleave in-process. Cross-process: main-app-only rule plus an advisory lock file `vault.lock` (`O_CREAT|O_EXCL`, contains launch uuid + epoch); a stale lock (epoch older than the current `authzEpoch`) is broken only by the main app on launch. **LIMIT:** advisory, not an OS boundary; app extensions remain forbidden (`ROTATION_CROSS_PROCESS` stays BLOCKED).
- **Crash during rewrap:** on launch, an uncommitted `rewrap-N` journal is replayed from the first unlogged step; files already rewrapped are detected by their header version (idempotent). Until the journal commits, no proof can exist; N is not retired; records remain readable under N (not forgotten). If N's Keychain item is unexpectedly missing (T28) the records under N are marked `unreadable(keyMissing)` and the user is told — no silent loss.
- **Write with old version after proof:** refused by R1 (`staleKeyVersion`); R1 is durable before R3, so a crash between R1 and R6 cannot reopen the window.
- **Attachment vs backup separation:** attachments have one DEK each (wrapped once by the KEK in the attachment header; chunks are sealed under that DEK) and are counted in R3. Backups never reference device KEK versions (`BackupCodec` seals DEKs under the recovery-derived key) → retirement of N has no effect on any backup; restore always re-wraps under the current version (≥ `minimumWrapVersion`).
- **Independent verification:** the proof can be recomputed by a verifier that only has read access to the directory: re-run R3 and compare `scanDigest` and `manifestHash`. Test NT-H2-07 does exactly this.

## H3 — replay and clock-rollback hardening

### Review of the 10 000-id ring (P03-03 D8) → replaced by an epoch design
| question | ring | epoch design (adopted) |
|---|---|---|
| ring full → old id reusable? | yes if >10 000 tokens are consumed within one TTL window (impossible for a human, possible for in-process code) | no ring; a token is valid only in the epoch it was issued in; in-memory consumed set per epoch, purged by TTL |
| token id unique across process lifetimes? | 128-bit random only | id = `epoch (u64) ‖ counter (u64) ‖ random (128 bit)`; epoch is persisted and incremented on **every launch and every restore** |
| crash: consumption before durable record? | consumed set persisted asynchronously → window | consumption is in-memory, but the **journal entry carrying `tokenID`+scope is written in the same actor critical section** as `consume`; after a crash the journal (not the token) completes the operation; the token is dead with its epoch |
| atomic token ↔ operation link | no | `JournalBegin{ tokenID, scope, recordIDs, epoch }` is the first durable step of every authorized mutation; reads are not journaled (no side effect) |
| backup restores old authz state? | risk | `authz.v1` is **never exported**; restore increments the epoch; a backup's authz data (if forged in) is ignored by schema |
| clock mark vs rollback / old snapshot | per-file | the mark lives in `authz.v1`, bound to the manifest generation and to the Keychain anchor (H5); an older `authz.v1` snapshot fails the binding → `authzStateUntrusted`, vault read-only until the user re-confirms via a trusted interaction; effective time = max(wall, mark) always |

- **Persisted state (`authz.v1`):** `{ epoch, clockHighWaterMark, lastManifestGeneration, lastManifestHash }`, written at launch (epoch++) and after every mutation batch. Not in backups. Rollback of the file alone is detected by the manifest/anchor binding; rollback of all files together is detected by the Keychain anchor (ThisDeviceOnly, separate storage).
- **First-observation gap (T25/T27):** after a reboot the monotonic clock resets; the persisted mark covers wall-clock rollback across launches; a rollback that happens before the first launch after the mark was written is bounded by the tolerance and still cannot go below the mark. LIMIT: a wall clock moved forward and then back within one process is handled by the in-process guard; nothing covers a fully compromised OS.
- **Revocation ↔ later access contract:** revoke is a manifest + receipt-log write inside the actor (generation++). Every `open`/`get` runs inside the actor after any earlier revoke completes → **linearizable**: a read that starts after the revoke returns cannot see the grant. Tokens issued before the revoke are re-checked against the authority at consume time (exists) → denied. App layer must drop decrypted views of the class on revoke (ADR-008 pattern, test NT-H3-06).

## H4 — consent revocation vs deletion: two operations
| operation | scope | effect | grace |
|---|---|---|---|
| `deleteRecords(ids)` ("Kalıcı sil") | `.delete` | journaled cascade now; ledger entries; no grace, no undo except from the user's own older backup (which then lands in quarantine, H1) | **none** |
| `revokeConsent(purposeID)` | `.revokeConsent` (new) | all processing and reads for that purpose stop at once; derived records invalidated and deleted now (not graced); records enter `suspended` | only if the user chose it |

- The revoke screen offers two explicit choices, no default: "Geri çek ve hemen sil" → revoke + immediate delete; "Geri çek, 7 gün askıda tut" → revoke + `suspended`. The screen states what suspension means. Suspension is offered only for classes marked `graceEligible` in the purpose registry (own-authored content: journal, goals/future self, psychometrics, lens preferences); third-party classes (parents' names, sibling order) are **not** grace-eligible → always immediate delete on revoke.
- During suspension: `open` denied (policy state check); DEK never unwrapped; not exported in backups; not used by any engine; appears in the consent history as "askıda, <tarih>'e kadar"; maintenance may rewrap the ciphertext (no plaintext); audit events carry ids only.
- Re-granting consent does **not** reactivate suspended records. The consent screen shows "askıdaki kayıtlar: N — geri getir" as a separate action with its own interaction proof and `.restoreSuspended` scope; otherwise the records are deleted by the cascade at grace end (journaled, ledgered).
- Grace expiry is evaluated against the trusted clock (effective time ≥ mark); a rollback cannot extend the grace.

## H5 — manifest and journal integrity contracts
| concern | contract | negative test |
|---|---|---|
| atomic file replace | write `.tmp-<uuid>` in the same directory with the protection class set before the first byte; `fsync` (`F_FULLFSYNC` on iOS); `rename(2)`; `fsync` of the directory | NT-H5-01 kill between each syscall → either old or new file, never partial |
| durable commit boundary | an operation is committed only when its last journal `commit` entry is durable (file + directory fsync); callers get success only after that | NT-H5-02 |
| crash recovery | launch runs `recover()`: delete `.tmp-*`; replay uncommitted journals; reconcile manifest ↔ files; verify bindings; only then open for reads | NT-H5-03 |
| manifest rollback detection | manifest `{ generation, prevHash }` chain; `authz.v1` stores `(lastManifestGeneration, lastManifestHash)`; the deletion ledger stores the same; a Keychain anchor item `vault/anchor` (ThisDeviceOnly, pointer mechanism as `<keyID>/current`) stores `(generation, manifestHash)`; on launch all four must agree or the vault opens **read-only with a warning and no restore allowed** until the user chooses recovery | NT-H5-04 (replace manifest with an older copy), NT-H5-05 (replace all three files with an older snapshot → anchor mismatch) |
| truncated journal | journal = sequence of length-prefixed AEAD entries; a trailing entry that fails length or AEAD is discarded as uncommitted; an AEAD failure **before** the tail → journal untrusted → the operation's record ids (from the begin entry) are quarantined, the vault reports `needsRecovery` | NT-H5-06, NT-H5-07 |
| enumeration integrity | manifest is authoritative; file not in manifest → moved to `orphans/` (never adopted, never opened, user may delete); manifest entry without file → `missing`, unreadable, shown; counts emitted as events | NT-H5-08, NT-H5-09 |
| partially written envelopes | impossible to observe via rename; any `.tmp-*` at launch deleted; an envelope whose AEAD fails → `corrupt` state, unreadable | NT-H5-10 |
| symlink / path traversal | `RecordID` validated as exactly 32 lowercase hex before any path is built; files opened with `O_NOFOLLOW`; the vault root must be a real directory under Application Support (`lstat`, not a symlink); any entry that is not a regular file aborts `recover()` with `storeIntegrityFailed` | NT-H5-11, NT-H5-12 |
| single writer | actor + advisory `vault.lock` + main-app-only rule; extensions never link the store (manifest test like `XRAIVaultTesting`) | NT-H5-13 |
| power loss | all of the above; fault injection through a test-only `FileSystemFaults` seam (kill at syscall k) | NT-H5-01…03 |
| "encrypted ≠ current" | every `get` checks manifest state (`active`), not just AEAD; stale/suspended/quarantined/missing/corrupt/orphan states are all unreadable | NT-H5-14 |

## H6 — UX & accessibility debt (unchanged, now gated)
F-UX-4 and F-UX-5 stay OPEN. **F-UX-5 (3:1 input boundary) becomes a mandatory acceptance test of the next UX implementation gate** (`ContrastTests` must assert `inputBorder` vs surface ≥ 3.0 in light and dark). VoiceOver, SE-class layout, native English review, app-switcher screenshot and full device regression stay MANUAL_PENDING / NOT_RUN.

## Resolved vs unresolved
| risk | status |
|---|---|
| silent resurrection via tombstone expiry | RESOLVED by design (permanent ledger, fail-closed digest, quarantine, no reactivation of known-deleted ids) |
| deletion history unknown after device loss + old backup | LIMIT (documented, quarantine + review) |
| key forgotten while a record still references it; TOCTOU | RESOLVED by design (protocol v2) — PLANNED tests |
| cross-process writer | LIMIT (advisory lock; rule) |
| token replay after ring eviction | RESOLVED by design (epoch) |
| authz rollback by file snapshot | RESOLVED by design (bindings + Keychain anchor); LIMIT: compromised OS |
| consent revoke vs delete ambiguity; re-grant resurrection | RESOLVED by design |
| manifest rollback, truncated journal, orphans, symlinks | RESOLVED by design — PLANNED tests |
| physical erasure, memory zeroization | LIMIT |
| independent security review | NOT_DONE (`VAULT_SECURITY_REVIEW`) |

## Checks run
| check | command | exit | result | log |
|---|---|---|---|---|
| package regression (no code changed) | `swift test --package-path Packages/XRAICore` | 0 | 108 tests in 27 suites passed | `evidence/p03_03h_swift_test_macos.log` |
| spec validator | `python3 -I validation/validate_package.py` | 0 | PASS; files=4414 | `evidence/p03_03h_validate_package.log` |
| doc consistency (extended) | `python3 -I validation/check_p03_03_docs.py` | 0 | H docs cite `7fc3091`; 48 NT rows; every referenced NT id resolves; T44–T46 present | `evidence/p03_03h_check_docs.log` |
| protected paths | `git status --porcelain` on `Packages/`, `App/`, `project.yml` | — | no changes | — |

Not run: Simulator, device, UI and accessibility runs — nothing executable changed, so no device claim is made. DEVICE_VERIFIED: n/a · SECURITY_REVIEWED: NO.
