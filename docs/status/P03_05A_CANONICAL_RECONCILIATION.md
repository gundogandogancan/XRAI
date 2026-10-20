# P03_05A_CANONICAL_RECONCILIATION — where the older design and the accepted decisions diverge, and which one rules

**Date:** 2026-10-20 · **Baseline:** `1a3a4485e562aea7b9fb9f05470b7eb3b989c77b` · **Compared:** Constitution v3.2 (§72–§93), `P03_03_*` (design), `P03_03H_*`, ADR-BOOT-005/006/009 (+ Amendments H…H.4), P03-04 / 04H / 04b / 04bH / 04bH2 reports, `P03_03_CONSENT_AUTHORITY_SPEC.md`, `VAULT_THREAT_MODEL_P02.md` v1.12, `OPEN_BLOCKERS.md`, current Swift sources and test matrices.

Türkçe özet: P03-03'teki ilk tasarımla bugünkü kabul edilmiş kararlar sekiz noktada çelişiyor. Kural: en son kabul edilmiş ADR/amendment üstündür; eski belge sessizce izlenmez. Her satırda hangi karar geçerli, kodun durumu ve P03-05A'da ne yapıldığı yazılı. Belge, consent spesifikasyonunun eski §4/§7 maddelerini resmen geçersiz kılar (metni tarih için saklanır).

## Precedence rule applied
ADR-BOOT-001 vocabulary: an accepted ADR (and its later amendment) overrides a design doc; a design doc overrides nothing that is implemented and tested. Where the consent spec (design, 2026-10-20 morning) and Amendment H/H.1–H.4 (accepted after independent reviews) disagree, the amendment rules. Items marked **SUPERSEDED** below are struck in spirit; the old text stays in the repository for history and is cross-referenced here.

## The eight conflicts

| # | topic | old design (P03-03 / consent spec) | accepted decision (ruling source) | code today | P03-05A action |
|---|---|---|---|---|---|
| 1 | Token ring vs epoch | consumed-token **ring of 10 000 ids + launch counter** persisted in `authz.v1` (spec §4) | **persisted epoch**, token id = epoch‖counter‖random, no ring (ADR-009 Amendment H; P03-04 H3; NT-H3-01/02: 20 000 tokens, no eviction) | `AuthorizationIssuer(epoch:)`, `AuthzState.epoch` | spec §4 rows "consumed set persisted … ring" **SUPERSEDED**; no ring will be built |
| 2 | Authorization state in backup | spec §7: "receipts, events, consumed-token ring and clock mark are records in the same store … same backup" | **never in a backup**: `authz.v1` and every `storeMetadata` envelope are excluded (`mayBackup` denies; NT-H3-05); backup body v3 has no field for them (NT-BK-08) | `VaultPolicy.mayBackup`, `BackupBodyV3` | **SUPERSEDED**; consent events are device-bound too (item 8) |
| 3 | Restore quarantine / activation | "active unless a tombstone exists; consent-inactive → quarantined; release = `releaseQuarantine`" (P03-03 deletion design §3, spec §7) | **two phases** (P03-04b GATE 3) + verified provenance (P03-04bH) + global identity policy (P03-04bH2): everything staged quarantined with persisted `RestoreRisk`; `activateRestored` with EXACT acknowledgment; `possiblyDeleted`/`untrustedLocalHistory` never activate; `reimportUnderNewID`; `releaseQuarantined` removed | `admitRestored`, `activateRestored`, `reimportUnderNewID`, `IdentityPolicy` | GATE 5 screens follow the accepted contract 1:1; the old "release" wording is **SUPERSEDED** |
| 4 | Consent persistence | spec §7: receipts as `consent_receipts` **records** (envelopes, read with a `.read` token), "manifest links the latest receipt chain" | **system file** `system/consent.v1` sealed as `storeMetadata`, hash-bound in the manifest (`consentHash`, manifest v3), announce-then-write journal rule (`consentWritten`), proven at open like the deletion ledger; derived active state from an immutable event chain; the store's own `StoreConsentAuthority` answers policy | implemented in P03-05A (NT-CA-03…06) | **DECIDED here** (reason: records need user tokens to read → the authority could not evaluate grants; system path solves the bootstrap, item 2 of the directive) |
| 5 | Revocation vs deletion | P03-03 lifecycle: revoke → 7-day grace → delete; P03-03 design: "consent-driven … pendingDelete with 7-day grace" | **two operations** (Amendment H / H4): `delete` (immediate, ledgered, never graced) and `revoke(purpose:mode:)` (`.deleteNow` or `.suspend(grace)` for grace-eligible own-authored classes only; third-party classes delete now); re-grant never reactivates; `restoreSuspended` is explicit | implemented P03-04; P03-05A appends `revoked` consent events in the SAME mutation (NT-CA-04) | GATE 4 presents grant / revoke+delete / revoke+suspend / delete records / restore suspended as five distinct actions |
| 6 | Interaction proof issuance | spec §2: `AuthorizationIssuer.issue` **removed from the public surface of the crypto module**; proof minted by a SwiftUI modifier with a private initializer in the same file | **kept public in the crypto module** (the store and every test issue tokens through it) but **unreachable from app code**: `InteractionGate` owns the issuer privately, mints proofs only in an active scene, 5 s, single-use, exact scope/purpose; a source-scan test forbids `.issue(` and `AuthorizationIssuer(` in `App/XRAI` except inline inside the gate construction (NT-UX-05) | `XRAIVaultInteraction` (new target) | spec §2.1/2.2 wording **adjusted**; the limit statement (§2.5) is kept verbatim: in-process, not an OS boundary, not proof of human intent |
| 7 | Legacy public APIs | P02-era facade methods assumed to stay: `SecureVault.releaseQuarantine`, v2 `exportBackup`, caller-built `RestoreResult`, `putEnvelope` | removed or demoted: `putEnvelope` gone (F-P04B-02), `releaseQuarantined` gone (P03-04bH2 GATE 4), caller-built results unverified (F-P04B-03), v2 export = legacy test path only; `SecureVault.releaseQuarantine` remains (registry-only, store-less P02 API) | as listed | **DECISION**: `SecureVault.releaseQuarantine` and the v2 export stay until P03-05B decides whether the store-less facade is a supported surface at all (OPEN_BLOCKERS `LEGACY_FACADE_SURFACE`) |
| 8 | Consent receipts and backup policy | spec §5/§7: "exportable with the backup (it is part of the vault)" | **device-bound**: `mayBackup(.consentReceipts)` denies (P03-05A); a backup restored on a new device carries no grant, the user is asked again (NT-CA-06) | implemented | **SUPERSEDED** |

## Additional divergences found while reconciling (not in the directive's list)

| topic | finding | ruling |
|---|---|---|
| Spec §1 `ConsentReceipt` "extended with purposeVersion, interactionProofID, supersedes" | the receipt type was never extended; P03-05A introduces `ConsentEvent` (immutable, payload-free, chain) instead and leaves `ConsentReceipt` to the in-memory test double | **ACCEPTED_LIMIT**: `ConsentReceipt` stays for tests/legacy authority; production = events |
| Spec §4 "purpose version drift → `PurposeRegistry.covers(receipt)`" | implemented as `PurposeRegistry.covers(id:grantedVersion:requestedVersion:)` on the ledger's derived grant | as planned |
| P03-03 threat plan N3 "tombstones expire at 90 d" | permanent ledger since H1; Bloom digest since P03-04; **possibly-deleted is permanent** since P03-04bH | SUPERSEDED |
| Constitution §84 "users can correct/revoke/delete" | satisfied by the five distinct actions; "correct" (edit a record) is not yet a store operation | OPEN (P03-05B+) |
| `SecurityStatus.consentRegistryImplemented = false` (app screen) | still honest: the production authority exists in the library, the app is not wired to a store | unchanged until P03-05B |

## Decision table — what the vault allows under UNTRUSTED deletion history (PRE-03)

| operation | allowed? | reason / test |
|---|---|---|
| open | yes, read-write, `deletionHistoryTrusted == false` sticky | NT-LR-06 |
| read existing clear records | yes | NT-PR-03 |
| create (`put`, `putAttachment`) | **no** — `deletionHistoryUntrusted` | NT-PR-03 (fail closed: a caller-supplied id may have been deleted) |
| delete / revoke | yes (history grows, stays untrusted) | NT-PR-03 |
| export | yes, body flag `deletionHistoryTrusted = false`; importers never merge it | NT-BK-06 |
| restore admission | staged with `untrustedLocalHistory` | NT-H1-02, NT-PR-03 |
| activation under the same id | **no** — `deletionHistoryUntrusted` | NT-PR-03 |
| re-import under a NEW id | yes (authorized, consent, verified payload) | NT-PR-03 |
| key retirement | yes | unchanged |
| reset of the sticky flag | **does not exist** (design in `P03_05A_PERFORMANCE_AND_RECOVERY_DECISIONS.md`) | — |

## Status
GATE 0 complete. The consent spec's §2 (proof issuance), §4 (ring), §5/§7 (receipts in backup, receipts as records, `releaseQuarantine` as the restore path) are superseded by this document; `P03_05A_CONSENT_AND_INTERACTION_ARCHITECTURE.md` is the ruling description from now on.
