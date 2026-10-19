# P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX — tests that must exist and pass before the store is called TESTED

**Date:** 2026-10-20 · **Baseline:** `7fc3091` · All rows are **PLANNED** today (no store code exists). MANDATORY rows gate P03-04 completion; DEFERRED rows belong to P03-04b/P03-05. Each row names the hardening item (H1–H5), the threat rows it covers, the exact failure injected, and the expected typed outcome.

Türkçe özet: Depo "TESTED" sayılmadan önce yazılması ve geçmesi zorunlu negatif testlerin tam listesi; her satırda enjekte edilen hata ve beklenen tipli sonuç. Hiçbiri bugün çalıştırılmadı; hepsi PLANNED.

| id | gate | H | threats | scenario (injected failure) | expected outcome | status |
|---|---|---|---|---|---|---|
| NT-H1-01 | MANDATORY | H1 | T41 | restore a backup containing an id present in the local ledger | `skippedDeleted`; record never `active`; event by id only | PLANNED |
| NT-H1-02 | MANDATORY | H1 | T41 | local ledger AEAD-corrupted, then restore | `deletionHistoryUntrusted`; every entry `quarantined(unverifiedDeletionHistory)` | PLANNED |
| NT-H1-03 | MANDATORY | H1 | T41 | ledger file deleted; manifest/anchor still reference it | vault opens read-only; restore refused; `storeIntegrityFailed` | PLANNED |
| NT-H1-04 | MANDATORY | H1 | T41 | release quarantine for a known-deleted id with valid token + fresh grant | refused; only `reimport` creates a **new** id with audit event | PLANNED |
| NT-H1-05 | MANDATORY | H1 | T41 | backup `vaultInstanceID` ≠ local, local vault non-empty | whole restore quarantined pending per-class release | PLANNED |
| NT-H1-06 | DEFERRED (P03-04b) | H1 | T41 | backup body v3 embedded ledger applied on a fresh device | ids in embedded ledger skipped | PLANNED |
| NT-H1-07 | MANDATORY | H1 | T41 | 250 000 ledger entries → digest compaction; query an id that was deleted | `maybeDeleted` → quarantine, never active; false-positive rate measured ≤ 1e-6 | PLANNED |
| NT-H2-01 | MANDATORY | H2 | T33, T43 | `forget(N)` with manifest `keyUsage[N] > 0` | refused (`keyVersionInUse`) | PLANNED |
| NT-H2-02 | MANDATORY | H2 | T43 | proof issued, then one `put` (generation++), then `forget` with the old proof | refused (`proofStale`) | PLANNED |
| NT-H2-03 | MANDATORY | H2 | T43 | manifest `keyUsage[N] == 0` but a file on disk still has `keyVersion == N` (manifest tampered/unsynced) | R4 cross-check fails; no proof | PLANNED |
| NT-H2-04 | MANDATORY | H2 | T43 | after R1 freeze, `put` an envelope wrapped under N | `staleKeyVersion` | PLANNED |
| NT-H2-05 | MANDATORY | H2 | T43 | crash (fault injection) after rewrapping k of n records | relaunch replays `rewrap-N`; n rewrapped; no proof existed; N still readable before completion | PLANNED |
| NT-H2-06 | MANDATORY | H2 | T37, T43 | concurrent `put` tasks during retirement (actor contention) | puts serialized after the section or refused by freeze; proof generation matches; no interleaving observed | PLANNED |
| NT-H2-07 | MANDATORY | H2 | T43 | independent read-only verifier recomputes `scanDigest`/`manifestHash` | equals the proof's values | PLANNED |
| NT-H2-08 | MANDATORY | H2 | T43 | crash between `retire(N)` and `forget(N)` | relaunch: N retired-not-forgotten; proof must be re-derived; records readable (no loss) | PLANNED |
| NT-H2-09 | MANDATORY | H2 | T28 | Keychain item for N missing while records still under N | `unreadable(keyMissing)` per record; user-facing report; no crash, no silent drop | PLANNED |
| NT-H3-01 | MANDATORY | H3 | T25, T42 | consume a token after relaunch (epoch++) | `unknownToken`/`epochMismatch` | PLANNED |
| NT-H3-02 | MANDATORY | H3 | T42 | 20 000 tokens issued and consumed, replay the first | `alreadyConsumed` (no eviction) | PLANNED |
| NT-H3-03 | MANDATORY | H3 | T42 | crash after `consume` + journal begin, before side effect | relaunch completes the op from the journal; token not re-usable | PLANNED |
| NT-H3-04 | MANDATORY | H3 | T27, T42 | replace `authz.v1` with an older copy | `authzStateUntrusted`; effective time ≥ manifest-recorded mark | PLANNED |
| NT-H3-05 | MANDATORY | H3 | T42 | backup bytes containing an `authz` section | ignored by schema; epoch increments on restore | PLANNED |
| NT-H3-06 | MANDATORY | H3 | T24 | revoke and concurrent reads (100 tasks) | no read that starts after revoke returns succeeds | PLANNED |
| NT-H3-07 | MANDATORY | H3 | T27 | wall clock set back 1 day across relaunch | effective time = persisted mark; grace/expiry unchanged | PLANNED |
| NT-H4-01 | MANDATORY | H4 | T41 | `deleteRecords` ("Kalıcı sil") | cascade now; ledger entry; no `suspended` state ever | PLANNED |
| NT-H4-02 | MANDATORY | H4 | T24, T40 | revoke with "askıda tut" | records `suspended`, `get` denied, derived deleted now, excluded from export | PLANNED |
| NT-H4-03 | MANDATORY | H4 | T24 | re-grant after revoke | suspended records stay suspended | PLANNED |
| NT-H4-04 | MANDATORY | H4 | T24 | revoke a non-grace-eligible class (parents' names) with "askıda tut" | refused; immediate delete is the only option | PLANNED |
| NT-H4-05 | MANDATORY | H4 | T27 | grace expiry with clock rolled back | expiry evaluated at effective time; cascade runs | PLANNED |
| NT-H5-01 | MANDATORY | H5 | T39 | kill at each syscall of write/fsync/rename/dirsync | file is old or new, never partial; `.tmp-*` cleaned | PLANNED |
| NT-H5-02 | MANDATORY | H5 | — | `put` returns before commit (fault: throw at commit) | caller gets error; file state consistent on recovery | PLANNED |
| NT-H5-03 | MANDATORY | H5 | T41 | kill after each journal step of a cascade delete | `recover()` completes; ledger has all ids; manifest consistent | PLANNED |
| NT-H5-04 | MANDATORY | H5 | T39 | replace manifest with its previous generation | `manifestRollback`; read-only; restore refused | PLANNED |
| NT-H5-05 | MANDATORY | H5 | T39 | replace manifest+ledger+authz with a consistent older snapshot | Keychain anchor mismatch → `manifestRollback` | PLANNED |
| NT-H5-06 | MANDATORY | H5 | T39 | truncate the last journal entry | tail discarded; op treated as uncommitted; replay | PLANNED |
| NT-H5-07 | MANDATORY | H5 | T39 | flip a byte in a middle journal entry | journal untrusted; ids quarantined; `needsRecovery` | PLANNED |
| NT-H5-08 | MANDATORY | H5 | T39 | extra `.env` file not in manifest | moved to `orphans/`; never opened | PLANNED |
| NT-H5-09 | MANDATORY | H5 | T39 | manifest entry whose file is missing | state `missing`; `get` → `recordMissing` | PLANNED |
| NT-H5-10 | MANDATORY | H5 | T7 | flip a byte in a record file | `corrupt`; `get` → `envelopeIntegrityFailed` | PLANNED |
| NT-H5-11 | MANDATORY | H5 | T39 | symlink inside `records/` pointing outside the vault | `recover()` aborts with `storeIntegrityFailed` | PLANNED |
| NT-H5-12 | MANDATORY | H5 | T39 | id with `..`/slash/uppercase passed to `get` | rejected before any filesystem call | PLANNED |
| NT-H5-13 | MANDATORY | H5 | T37 | second store instance on the same root | lock refused; first instance unaffected | PLANNED |
| NT-H5-14 | MANDATORY | H5 | T19, T40 | `get` on stale / suspended / quarantined / missing / corrupt / orphan | each a distinct typed denial; never plaintext | PLANNED |
| NT-H5-15 | MANDATORY | H5 | T39 | list the directory of a populated vault | only hex names, `system/*.v1`, `journal/*.j`, sizes multiple of 4 KiB | PLANNED |
| NT-H5-16 | MANDATORY (Simulator/device) | H5 | T39 | file attributes | `NSFileProtectionComplete` and backup-excluded on every file | PLANNED |
| NT-DG-01 | MANDATORY | D2 | T40 | delete a source with two levels of derived records | dependents deleted first; all ledgered | PLANNED |
| NT-DG-02 | MANDATORY | D2 | T40 | `put` with a `derivedFrom` back-edge or unknown id | rejected | PLANNED |
| NT-DG-03 | MANDATORY | D2 | T40 | revoke the purpose of a source | derived unreadable immediately | PLANNED |
| NT-B-01 | MANDATORY | — | T13, T23 | import-boundary + manifest: store target imports only allowed modules; app never links fault seams | compile-negative + manifest test | PLANNED |

Status rule: a row becomes TESTED only with a log in `docs/status/evidence/` and a ledger entry; device rows may be NOT_RUN if the device is unavailable, and then DEVICE_VERIFIED stays PARTIAL.
