# P03_05A_PERFORMANCE_AND_RECOVERY_DECISIONS — decision register and test contracts for work NOT yet done

**Date:** 2026-10-20 · **Baseline:** `1a3a448` · Every row below is a decision proposal and a test contract. Nothing here is implemented in P03-05A; nothing is shown as done.

Türkçe özet: On konu için karar önerisi ve test sözleşmesi. Ölçülen cihaz değerleri (kayıt başına ≈130 ms, 500 kayıtlık geri yükleme ≈10 s) temel alınır. Önerilen ürün bütçeleri kurucunun kararına sunulur; gruplu commit optimizasyonu ayrı onaylanmış bir hata modeli olmadan yapılmaz.

## Measured baseline (P03-04b, iPhone 14 Pro Max, iOS 26.6)
≈ 130 ms per record write (≈ 10 `F_FULLFSYNC`), ≈ 20 ms per admitted file, 500-record restore+admission ≈ 10 s, 64 MiB attachment write 0.88 s / verified read 0.95 s, RSS growth ≈ 0.

## Decisions and test contracts

| # | topic | decision proposal | invariant that must hold | test contract (next phase) | status |
|---|---|---|---|---|---|
| 1 | User-confirmed sticky-distrust reset | new op `resetDeletionHistory(acknowledgement:)`: `.resetHistory` scope (confirmDialog proof + OS user authentication when available), journaled, writes a fresh empty ledger bound to the manifest, clears `ledgerHistoryTrusted = false`, appends a payload-free audit event; until it exists the vault refuses creation/activation (PRE-03) | a reset never reactivates any staged id; ids restored afterwards from old backups are staged with `legacyFormat`-class risk, never active; the old untrusted ledger is kept as `system/ledger.retired.<generation>` for forensics | reset without proof refused; reset crashed at every syscall → either old state or new state; after reset: old backup ids staged, activation refused for `possiblyDeleted`, exact ledger for new deletions | DESIGN |
| 2 | Persisted corrupt-record state | manifest entry state `.corrupt` written by a journaled op when AEAD fails at read; export refuses with a typed error listing counts; delete allowed | a corrupt mark survives reopen; a corrupt record never decrypts; delete removes it and ledgers the id | corrupt mark after relaunch; export typed refusal; delete + ledger | DESIGN |
| 3 | Attachments in backup | streamed container v4: body = records + per-attachment chunk stream (header frame + sealed chunks copied verbatim, re-wrapped header DEK), bounded memory; `excludedAttachmentCount` stays for v3 | restore never holds a whole attachment in memory; a truncated container fails closed before any file is adopted | truncated container; missing chunk; memory bound ≤ 2 chunks; crash at every syscall of a container restore | DESIGN |
| 4 | Streaming backup | export/restore through the file-system port with a 1 MiB window; the outer AEAD becomes chunked (per-chunk tags with index AAD, like attachments) | the 256 MiB whole-body limit disappears without weakening authentication-before-use | per-chunk tamper → no partial plaintext; interrupted export leaves no partial file | DESIGN |
| 5 | Grouped durable commit | batch admission/import: one journal rewrite per k files and ONE directory flush per batch, content `F_FULLFSYNC` per file kept; all-or-nothing by the existing admit replay rule | durability per file unchanged; the deletion invariant unchanged; crash anywhere → all or nothing | crash at every syscall of a 50-file batch; power-loss model (test FS drops un-flushed writes) | DESIGN — **not implemented in P03-05A** (needs a separately approved failure model) |
| 6 | Restore progress / cancellation | admission in cancellable batches of N files with truthful progress (files written / total); cancellation = abort the current batch (replay rule), keep committed batches staged | no half batch; cancellation never leaves active records | cancel at every batch boundary; progress monotonic | DESIGN |
| 7 | Recovery under low disk space | ENOSPC at any step → `ioFailed`, instance read-only "reopen required", journal decides at reopen; a pre-flight check refuses an admission that cannot fit (size of the backup + 2 × 4 KiB per file + journal headroom) | never a half file adopted; never a lost committed record | ENOSPC injected at every syscall of put/admit/delete; pre-flight refusal | DESIGN (ENOSPC injection reuses `FaultingFileSystem.fail`) |
| 8 | Device lock/unlock | `NSFileProtectionComplete` makes every vault file unreadable while locked; the store must treat EACCES/EPERM on open as a transient "protected data unavailable" (not corruption), purge key cache, and retry when `protectedDataDidBecomeAvailable` | a lock during a mutation = the same as a crash (journal decides); no corrupt marks from EACCES | hosted device test: lock via `XCUIDevice`? NOT_RUN (needs a manual step) → MANUAL_PENDING | DESIGN |
| 9 | Record-count scaling | manifest is one file rewritten per mutation (O(n) encode + 4 KiB padding); at 10 000 records ≈ 1.5 MiB per write; proposal: keep single manifest to 20 000 records, shard beyond (ADR-009 §7 item) | generation chain and anchor binding unchanged | NT-SC-01 at 10 000 on macOS (time, size); shard design only after the measurement | DESIGN |
| 10 | Per-operation flush cost | keep ≈ 10 flushes per mutation for single user actions (human-paced); batch paths use decision 5 | durability never reduced for single operations | the fault injector's op log asserts the flush count per operation ≥ contract | DESIGN |

## Provisional product budgets (for the founder's decision)
1. The main thread is never blocked by vault IO: every store call runs on the actor from a background task; the UI shows state, never waits synchronously.
2. Any operation expected to exceed 500 ms shows truthful progress (counts, not spinners) and, where safe, cancellation.
3. Interrupted operations recover without silently losing committed records (already enforced: journal + reopen).
4. Batch optimisation must not reduce durability or weaken the deletion invariant (decision 5 gate).
5. Proposed targets on the tested iPhone: single record write ≤ 200 ms; 500-record restore ≤ 15 s with progress; 64 MiB attachment read ≤ 2 s. These are observations turned into budgets, not promises; the founder decides whether a faster path justifies a new failure model.

## Security cost table
| optimisation | security cost | verdict |
|---|---|---|
| fewer flushes per single write | a crash may lose the last write | **refused** |
| grouped batch flush | none for content; batch all-or-nothing already | allowed after failure-model approval |
| skip verify pass on attachment reads | plaintext could be delivered before a later chunk fails | **refused** |
| trust caller-built restore results | provenance laundering | **refused** (P03-04bH) |
