# P03_04H_FILESYSTEM_SECURITY_REVIEW — atomic exclusive creation, durable directory commit, neighbouring integrity audit

**Date:** 2026-10-20 · **Baseline reviewed:** `f888040d634310a5bc5aa539154f060b006a5a14` (P03-04 HEAD) · **Trigger:** first independent code review of P03-04 (findings F-P04-01, F-P04-02) · **Scope:** `XRAIVaultStore` library only. No backup body v3, no attachments, no consent UI, no app persistence (app target still does not link the store).

Türkçe özet: Bağımsız incelemenin iki P0 bulgusu düzeltildi. (1) iOS'ta "exclusive create" aslında `createFile` + `open(O_TRUNC)` idi: var olan dosyayı sessizce sıfırlıyor, symlink'e karşı açık kalıyordu; artık her platformda tek bir `O_CREAT|O_EXCL|O_NOFOLLOW` open, tanımlayıcı üzerinde doğrulama ve iOS'ta dosya boşken descriptor'a uygulanıp geri okunan Data Protection "complete". (2) Dizin fsync sonucu yok sayılıyor ve `F_FULLFSYNC` her hatada sessizce `fsync`e düşüyordu: artık her dayanıklılık adımı tipli `ioFailed` ile raporlanıyor, geri düşüş yalnız "desteklenmiyor" hatalarında, EINTR ele alınıyor; bir mutasyon içindeki her hata örneği salt-okunur "yeniden açma gerekli" durumuna alıyor ve karar diskteki günlüğe bırakılıyor. Komşu denetimde dört ek hata bulunup düzeltildi (defter-yalnız geri alma, kabulde kısmi yazım, kilitten önce temizlik, kapatıldıktan sonra okuma). 12 yeni negatif test; macOS 158/158, Simulator 86/86, iPhone 14 Pro Max sonucu §4'te. Güç kesintisi testi yok; bunun ötesinde dayanıklılık iddiası yapılmıyor.

## 1. Before → fix → code evidence

### F-P04-01 — exclusive creation (GATE 1)

| | before (`f888040`) | after (this commit) |
|---|---|---|
| iOS creation | `FileManager.createFile(atPath:…attributes: [.protectionKey: .complete, .posixPermissions: 0o600])` then `open(path, O_WRONLY|O_NOFOLLOW|O_CLOEXEC|O_TRUNC)` | one `open(path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0o600)` on every platform (`RealFileSystem.openExclusive`) |
| pre-existing file | `createFile` overwrote it (returns true), `O_TRUNC` truncated it | EEXIST → `storeIntegrityFailed("exclusive create refused: path exists")`; inode, size, content untouched (NT-FS-01) |
| symlink at the path | `createFile` followed/replaced it; `O_NOFOLLOW` only on the second call | O_EXCL refuses any existing name incl. links; target never created or modified (NT-FS-02) |
| race between the two calls | a substituted path between create and open was opened and truncated | there is no pair; one syscall creates and opens |
| permissions | attribute at create, no verification | `fstat` on the descriptor: regular, nlink 1, size 0; `fchmod(0600)` when the umask changed the mode (NT-FS-04 runs under umask 000) |
| Data Protection | attribute given to `createFile` (path-based), never read back | descriptor-based: `fcntl(F_GETPROTECTIONCLASS)`; if not A, `fcntl(F_SETPROTECTIONCLASS, 1)`, then read back; all while the file is empty, so no content exists under a weaker class (NT-FS-04 device assertions in a vault directory AND in a plain directory) |
| error after creation | temp removed by name | `removeIfOwned(path, by: fd)`: unlink only while `lstat(path)` and `fstat(fd)` are the same dev/ino and a regular file (NT-FS-05) |
| concurrent writers | second writer truncated the first's file | exactly one succeeds, the others see EEXIST (NT-FS-03: 1 / 15 / 0) |

Code: `Packages/XRAICore/Sources/XRAIVaultStore/VaultFileSystem.swift` (`openExclusive`, `ensureCompleteProtection`, `removeIfOwned`, `AtomicWriter.replace`).

### F-P04-02 — durable directory commit (GATE 2)

| | before | after |
|---|---|---|
| `syncDirectory` | `if fcntl(fd, F_FULLFSYNC) != 0 { _ = fsync(fd) }` — fallback result discarded | `flush(fd, step: "dirsync")`: `F_FULLFSYNC` → 0 returns; ENOTSUP/ENOTTY/EINVAL → `fsync` whose failure throws; any other errno throws immediately |
| `sync` (file) | any `F_FULLFSYNC` failure (incl. EIO) fell back to `fsync` | same policy as above: EIO is never masked by a fallback |
| errors | string reasons inside `storeIntegrityFailed` | new `VaultError.ioFailed(operation: String, errno: Int32)` for open/fstat/fchmod/setprotectionclass/write/fullfsync/fsync/close/rename/opendir/dirsync/unlink/lstat (NT-FS-06) |
| EINTR | not handled (a `write` returning −1/EINTR aborted the write) | retried for open, write, read, fsync, fcntl, rename; **not** for `close` (XNU releases the descriptor even on EINTR; a retry could close a reused descriptor) — EINTR on close counts as closed |
| short write | loop assumed progress | a 0-byte write throws (`"write made no progress"`) |
| audit of ignored results | `_ = Darwin.close(fd)` in read paths and the directory flush; `try?` in `AtomicWriter` cleanup | read-only descriptors keep the ignored close (nothing to flush, documented); `AtomicWriter` cleanup still uses `try?` **only** on the error path after the real error is already being thrown; every success path checks every result |
| mutation success vs durability | `runMutation` → `commitTail` → `finishTail` propagated errors but the instance stayed writable on in-memory state | any error inside the journaled section → `modeValue = .readOnly("mutation interrupted: reopen required")`, `get`/mutations refuse, reopen replays the journal (NT-FS-08, NT-FS-12). In-memory `manifest/ledger/authz` are assigned only after the journal was removed (unchanged) |
| failure injection | crash model only (`SimulatedCrash`) | `FaultingFileSystem.arm(at:k, .fail(errno:))`: the k-th mutating syscall returns an error **without acting**, the process continues; every k for `put` and for a cascade `delete` (NT-FS-08a/b) |

Why the read-only transition is necessary (confirmed, not theoretical): with the old code a failed `unlink(journal)` after a durable commit left the in-memory manifest one generation behind the disk; the next mutation would have written a manifest **without** the committed record (orphan at the next open). A failed ledger write in the middle of a cascade delete left unlinked files whose ids were neither in the ledger nor reliably replayed once the next mutation overwrote `journal/<g+1>.j`.

### GATE 3 — neighbouring integrity audit

| area | verdict | detail | fix / test |
|---|---|---|---|
| temp file ownership & cleanup | **confirmed bug** | cleanup unlinked the temp by name after any error; a name taken over by another writer would be deleted | `removeIfOwned` (dev/ino) before close; by private random name only after close (NT-FS-05) |
| cross-process lock acquisition | **confirmed bug** | loader removed `.tmp-*` (and, with no manifest, every record/system/journal file) **before** `takeLock`; a locked-out opener could delete a live writer's in-flight temp or bootstrap files | lock first in both branches; `clearAnchor` also after the lock (NT-FS-11) |
| stale-lock handling | plausible risk (availability) | staleness = pid dead or epoch behind; a reused pid of an unrelated live process keeps the lock "live" → `storeLocked` until it exits; malformed/oversized lock fails closed; symlinked lock refused | documented (`PID_REUSE_LOCK`); no change |
| symlink / path substitution | plausible risk, out of model | reads and creates are descriptor-based (`O_NOFOLLOW`, `fstat`); `removeIfOwned` and `excludeFromBackup` keep an lstat→act window; a same-UID writer inside the container is outside the threat model | documented (`SAME_UID_TOCTOU`); NT-FS-02 covers the symlinked directory flush (XNU answers ENOTDIR, not ELOOP, for `O_DIRECTORY|O_NOFOLLOW` on a link) |
| anchor/manifest divergence after partial commits | tested, no new defect | chain + open journal already resolve "manifest durable, anchor not"; now also under failed (not crashed) steps | NT-FS-08a asserts anchor == manifest after every reopen |
| journals with interrupted durable writes | tested, no new defect | a failed journal rewrite leaves the previous version; bodies are idempotent; a begin entry that became durable completes the op at reopen (same rule as NT-H3-03) | NT-FS-08b exercises ≥ 2 record pairs because the replay path consumed the first |
| key retirement after recovery | minor defect | `prepare` reconciliation guessed the retiring version as `minimumWrapVersion − 1` (wrong when retiring an older version) | the `prepare` journal now carries the version in `params[1]`; NT-H2-05/08 unchanged |
| unknown or corrupted ledger state | **confirmed bug** | an **authentic** ledger whose hash the manifest does not bind to (ledger-only rollback) opened read-write with `deletionHistoryTrusted == false`; the next mutation rebound the manifest to the rolled-back ledger and the next open trusted it | read-only "deletion ledger does not bind to the manifest" when no pending journal explains it (NT-FS-09). Residual: a rollback coinciding with a pending delete journal is laundered by replay (`LEDGER_ONLY_ROLLBACK`) |
| restore admission | **confirmed bug** | `staleKeyVersion` was checked per envelope inside the journaled body: a refusal mid-batch left earlier files on disk and replay admitted them | validation before the journal begins (NT-FS-10) |
| read-only fail-closed transitions | **confirmed bug** (minor) | `get` ignored `closed`; a closed instance still decrypted | refused with `storeReadOnly("closed")`; interrupted instances refuse reads too (NT-FS-12). Other read-only reasons keep serving reads by design (read-only, not sealed) |

Unsupported guarantees (stated, not claimed): power-loss survival (no power-cut rig; `F_FULLFSYNC` is Apple's flush-to-media request, APFS directory-fsync semantics are undocumented, storage may ignore flushes); Data Protection on the Simulator (attribute stored, no class-key encryption, FileManager reports nothing); the numeric class mapping (1 = A) beyond its empirical device verification; `kill(pid, 0)`/EPERM as "process alive".

## 2. New negative tests

`Packages/XRAICore/Tests/XRAIVaultStoreTests/StoreFileSystemTests.swift` — suites `StoreFileSystemTests` (NT-FS-01…07, real syscalls) and `StoreDurabilityFailureTests` (NT-FS-08…12, store with the failed-syscall injector). Rows and real results are in the P03-04H addendum of `P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md`. Changed existing test: `StoreCrashTests.consumedTokenThenCrash` (NT-H3-03) now asserts the interrupted instance is read-only and that the consumed grant resurrects nothing after reopen. Harness: `FaultingFileSystem` gained the `.fail(errno:)` injection and the `removeIfOwned` passthrough (test target only; the production module still contains no fault seam — `importBoundary` source scan unchanged).

## 3. Remaining platform limitations

1. No power-loss testing; the durability claim is "every Apple-documented step taken, every result verified" (`DIRECTORY_FSYNC_SEMANTICS`).
2. Simulator: Data Protection assertions compile out (`#if os(iOS) && !targetEnvironment(simulator)`); the Simulator run is evidence for the POSIX semantics only (`PROTECTION_CLASS_NUMERIC`).
3. The class value 1 comes from XNU's private header section; the fcntl commands are public API. Verified on the device by reading `NSFileProtectionComplete` back through `FileManager`.
4. Same-UID TOCTOU windows in cleanup/backup-exclusion remain (out of model).
5. `vault.lock` is advisory; pid reuse can delay reopening.
6. Ledger rollback combined with a pending delete journal (residual, needs a journal format change in P03-04b).
7. Large-vault `F_FULLFSYNC` cost on device still not measured (`FSYNC_COST_ON_DEVICE`).

## 4. Complete test outcomes (real runs, exit codes)

| run | command | exit | result | log |
|---|---|---|---|---|
| store suite, first attempt | `swift test --filter XRAIVaultStoreTests` | 1 | 49 tests, 2 test-expectation errors (NT-FS-02 expected ELOOP, XNU returns ENOTDIR; NT-FS-08b did not account for the begin-durable replay). Product code unchanged by the fix; tests corrected | `evidence/p03_04h_store_tests_run1_FAIL_2_test_expectations.log` |
| macOS package tests | `swift test` (Packages/XRAICore) | 0 | 158 tests in 38 suites passed (145 before + 13 new); includes compile-negative, import-boundary and GATE A source scans | `evidence/p03_04h_swift_test_macos.log` |
| Simulator hosted | `xcodebuild test … 'platform=iOS Simulator,name=iPhone 17' -only-testing:XRAIHostedTests` | 0 | 86 tests in 23 suites passed (73 before + 13 new); NT-FS-04 protection assertions compiled out on the Simulator (KNOWN_LIMITATION) | `evidence/p03_04h_xcodebuild_sim_hosted.log` |
| iPhone 14 Pro Max hosted, non-destructive | `xcodebuild test … 'platform=iOS,id=C7C6CE6E-…' -only-testing:XRAIHostedTests -allowProvisioningUpdates` | 0 | 86 tests in 23 suites passed on iPhone 14 Pro Max "Dogi (2)" (iOS 26.6): NT-FS-04 asserted `NSFileProtectionComplete` on files created through the new exclusive path in a vault directory (inherited, verified on the descriptor) and in a plain temp directory (set on the empty descriptor, verified); NT-H5-16 still green; failed-syscall injection suites green; real Keychain anchor; non-destructive | `evidence/p03_04h_xcodebuild_device_hosted.log` |
| static: package spec | `python3 -I validation/validate_package.py` | 0 | PASS spec structure (files=4667, methods=19, tests=98, tasks=18); does not verify an iOS build | `evidence/p03_04h_validate_package.log` |
| static: docs consistency | `python3 -I validation/check_p03_03_docs.py` | 0 | PASS: 13 data classes, 60 NT rows (48 + 12 NT-FS), T44–T48 present, review cites `f888040`, blockers present, `VaultFileSystem.swift` contains neither `createFile(atPath`/`O_TRUNC` nor an ignored fsync (new greps) | `evidence/p03_04h_check_docs.log` |

Compile-negative and import-boundary checks: part of the macOS run (`StoreModuleBoundaryTests`: 6 snippets fail to compile, imports limited to Foundation/Contracts/CryptoKit adapter, no fault seams, exactly one `await` in the static `open`). The 48-row P03-04 matrix: every previously TESTED row re-ran green on all three hosts (regression status: no regression; NT-H3-03 expectation tightened, NT-H1-06 still DEFERRED).

Not run (unchanged scope): UI/XCUI tests (no UI change), destructive device scenarios (reinstall, passcode removal, data deletion), power-loss tests (no rig).

## 5. Regression status

| suite set | before P03-04H | after | note |
|---|---|---|---|
| macOS package | 145/145 | 158/158 | +13 |
| Simulator hosted | 73/73 | 86/86 | +13 |
| iPhone 14 Pro Max hosted | 73/73 | 86/86 | +13 expected |
| 48-row matrix | 46 TESTED + 1 device + 1 DEFERRED | unchanged | NT-H3-03 assertion tightened |

## 6. Device verification status

DEVICE_VERIFIED: **PARTIAL** — hosted non-destructive suite only, temp directories inside the app container, real Keychain anchor, Data Protection "complete" read back on files created through the new exclusive path both in a vault directory and in a plain directory (NT-FS-04 and NT-H5-16, `evidence/p03_04h_xcodebuild_device_hosted.log`, exit 0). Not covered: lock/unlock transitions, passcode removal, reinstall, power loss.

## 7. Modified files

- `Packages/XRAICore/Sources/XRAIVaultContracts/Envelope.swift` — `VaultError.ioFailed(operation:errno:)` (additive).
- `Packages/XRAICore/Sources/XRAIVaultStore/VaultFileSystem.swift` — rewritten port implementation (exclusive create, descriptor verification, protection on descriptor, `removeIfOwned`, typed sync/dirsync/rename/unlink/close errors, EINTR policy, `AtomicWriter` cleanup ownership).
- `Packages/XRAICore/Sources/XRAIVaultStore/FileVaultStore.swift` — `reopenRequiredReason` + fail-closed `runMutation`; `get` guards; loader lock-before-cleanup; unbound-ledger read-only; admission pre-validation; `prepare` journal carries the version.
- `Packages/XRAICore/Tests/XRAIVaultStoreTests/StoreHarness.swift` — `.fail(errno:)` injection, `removeIfOwned` passthrough.
- `Packages/XRAICore/Tests/XRAIVaultStoreTests/StoreFileSystemTests.swift` — new (NT-FS-01…12).
- `Packages/XRAICore/Tests/XRAIVaultStoreTests/StoreCrashAndRetirementTests.swift` — NT-H3-03 tightened.
- `XRAI.xcodeproj/project.pbxproj` — regenerated (hosted bundle picks up the new test file; app target unchanged, still no `XRAIVaultStore`).
- Docs: this review; matrix addendum; `VAULT_THREAT_MODEL_P02.md` v1.9 (T47, T48); `OPEN_BLOCKERS.md` (P03-04H section); `ADR-BOOT-009` Amendment H.1; `NEXT_TASK.md`; `TEST_EVIDENCE_LEDGER.json`; `CLAUDE.md` phase line; `validation/check_p03_03_docs.py` (P03-04H checks); evidence logs `docs/status/evidence/p03_04h_*`.

## 8. Final SHA

<!-- FINAL-SHA -->

## 9. GO / NO-GO for P03-04b

**Recommendation: CONDITIONAL GO for P03-04b** (library: backup body v3 with embedded ledger digest + instance id, journal begin entry carrying the pre-op ledger hash, restore reconciliation, attachments). Conditions: (a) the second review confirms the F-P04-01/02 fixes in §1 and accepts the residuals in §3; (b) `LEDGER_ONLY_ROLLBACK` is closed inside P03-04b, not deferred again; (c) no app wiring and no real personal data before P03-05 approval. **NO-GO** for P03-05 / app persistence until P03-04b lands and is reviewed. The decision itself belongs to the reviewer and the founder; this report only states that no P0 finding of the first round remains open.

Invariants kept: BOOT-01 untouched; no real personal data; app not wired to the store; no cloud; no force push; no security threshold loosened (the Simulator exclusion is compile-time and documented; the device asserts the stronger property). SECURITY_REVIEWED: NO (this is the response to the first review round, awaiting the second).
