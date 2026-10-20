# P03_05A_SECURITY_NEGATIVE_TEST_MATRIX — attack → fix → regression → crash/reopen → persistent state

**Date:** 2026-10-20 · **Baseline:** `1a3a448` · Rows live in the single acceptance matrix (`P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md`, P03-05A addendum) so the documentation validator resolves every id; this file is the per-finding chain.

Türkçe özet: Her güvenlik bulgusu için zincir: saldırı → düzeltme → regresyon → çökme/yeniden açılış → kalıcı durum kanıtı. Üç bulgu CONFIRMED, iki RISK, üç ACCEPTED_LIMIT.

| finding | class | attack (test) | fix | regression | crash/reopen | persistent state evidence |
|---|---|---|---|---|---|---|
| PRE-01 read/write APIs revealed existence, state and deletion history to unauthorized callers (error types differed before the token was checked) | **CONFIRMED** | NT-PR-01 | non-consuming `AuthorizationValidator.validate` + `SecureVault.precheckAuthorization` called first in `get`, `readAttachment`, `putAttachment`, `reimportUnderNewID`, `exportBackup`; `put` seals (authorizes) before any check | all P03-04…bH2 rows green on three hosts | NT-PR-01 asserts no journal, no burned generation | ledger/manifest unchanged; attachment sink empty |
| PRE-02 derived reads checked only DIRECT sources | **CONFIRMED** (reachable through restored batches; by construction unreachable through cascade) | NT-PR-02 | `requireSourcesReadable` walks `derivedFrom` transitively: active, present, clear in the ledger, consent now | NT-DG-01…03, NT-BH-05 green | reopen with a missing root → leaf/mid refuse | integrity report lists the missing root |
| PRE-03 behaviour under untrusted history was implicit | **RISK → decided** | NT-PR-03 | decision table (reconciliation doc) asserted row by row | NT-LR-06, NT-BK-05/06 green | relaunch keeps sticky distrust and the re-imported record | manifest flag persisted |
| consent could not be persisted without a token (bootstrap) | **CONFIRMED** (design gap) | NT-CA-03 | `system/consent.v1` through the system path; `StoreConsentAuthority` | NT-H4-* green (record consequences unchanged) | NT-CA-05 crash loop: chain unchanged or +1 | consent file hash bound in manifest v3 |
| consent history could be rolled back like the deletion ledger | **RISK → closed** | NT-CA-05 | `consentWritten` announcement + `LedgerBinding.verifyConsent` | NT-LR-01…08 green | read-only on rollback/missing/unreadable | manifest/consent binding |
| consent receipts would travel in backups and re-grant on another device | **CONFIRMED** (old spec) | NT-CA-06 | `mayBackup(.consentReceipts)` denies | NT-BK-02 (cleartext) green | — | restored vault has no grants |
| tokens could be issued by any app code | **CONFIRMED** (app `SecurityStatus` called `issuer.issue`) | NT-UX-05, NT-IG-05 | `InteractionGate` owns the issuer privately; source-scan test | hosted suite | — | — |
| InteractionGate is not an OS boundary | **ACCEPTED_LIMIT** | NT-IG-05 (forged proof from another gate refused, but in-process forgery of the gate's own registry is out of model) | stated in the architecture doc and T53 | — | — | — |
| `duplicateRecordID` for an EXISTING id after authorization (existence oracle for authorized callers only) | **ACCEPTED_LIMIT** | NT-PR-01 (authorized branch) | by design: an authorized caller may learn about ids within its scope | — | — | — |
| restore seal per facade instance (a result must be admitted in the session that restored it) | **ACCEPTED_LIMIT** | NT-BH-04 | documented | — | — | — |
