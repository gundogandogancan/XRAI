# P03_03_ARCHITECTURE_GATE_REPORT — data lifecycle · consent authority · secure persistence architecture

**Date:** 2026-10-20 · **Baseline:** `713468e` (HEAD == baseline at start, tree clean, in sync with origin) · **Phase type:** design only — no persistence implemented, no vault/Keychain/BOOT-01 code changed · **Recommendation:** CONDITIONAL GO (see §9).

Türkçe özet: Bu faz yalnız tasarım üretti: veri envanteri, yaşam döngüsü matrisi, izin otoritesi sözleşmesi, kalıcı depolama ADR'si (ADR-BOOT-009, PROPOSED), silme/kurtarma tasarımı, tehdit ve negatif test planı, gizlilik/zekâ sınırı. Kod değişmedi; kişisel veri hâlâ diske yazılmıyor. Statik kontroller gerçek çıkış kodlarıyla aşağıda. Öneri: KOŞULLU GO — P03-04 (şifreli kayıt deposu) ancak ChatGPT ADR-BOOT-009'u ve InteractionGate sınırını onayladıktan sonra başlar.

## 1. Deliverables (all in `docs/status/`)

| doc | answers |
|---|---|
| `P03_03_DATA_INVENTORY.md` | every item held today or planned (12 coded classes, 6 proposed, 10 security items, content, never-list) |
| `P03_03_DATA_LIFECYCLE_MATRIX.md` | the 13 lifecycle questions per class; derived-data dependency contract; revocation semantics |
| `P03_03_CONSENT_AUTHORITY_SPEC.md` | purpose registry, versioned receipts, interaction proof, replay/rollback persistence, fail-closed rules, user history, privacy-preserving audit |
| `P03_03_SECURE_PERSISTENCE_ADR.md` (= ADR-BOOT-009, PROPOSED) | GRDB+SQLCipher vs file-based vs field-encrypted SQLite; layout; threats folded in; `VaultStore` port; store proof |
| `P03_03_DELETION_AND_RECOVERY_DESIGN.md` | deletion kinds, journaled cascade, tombstones, backup reconciliation, key retirement proof, limits, recovery scenarios |
| `P03_03_THREAT_AND_NEGATIVE_TEST_PLAN.md` | N1–N20 requirement→design→risk→test→evidence→limit |
| `P03_03_PRIVACY_INTELLIGENCE_BOUNDARY.md` | six epistemic classes, Knowledge DNA / Future Self / Evolution Brain limits, AHTOVIA line |
| this report | decisions, conflicts, open risks, checks, next task, GO recommendation |

## 2. Design decisions

| id | decision | rationale |
|---|---|---|
| D1 | First persistent vault = record-per-file `RecordEnvelope`s + encrypted manifest; no SQLCipher yet | reuses the device-verified crypto path; no third-party crypto; no WAL/SHM/plaintext metadata; SQLCipher revisited by its own ADR when queries are needed |
| D2 | `derivedFrom[]` inside the authenticated header (format v3) + manifest reverse index; derived records never outlive, outrank or out-consent sources | makes invalidation and cascade deterministic and tamper-evident |
| D3 | Deletion = journaled, idempotent cascade (dependents first) + tombstone (id, deletedAt), tombstones kept 90 days, restore reconciled against them | deleted data must not return from backups; crashes must not leave half states |
| D4 | Consent-gated revoke: reads blocked at once (exists), derived invalidated, 7-day grace then delete | immediate privacy effect, reversible mistake window |
| D5 | Key forgetting requires a store-issued `KeyRetirementProof` bound to the manifest hash and a full-scan zero count | resolves `FORGET_REQUIRES_STORE_PROOF` by contract; closes only with P03-04 tests |
| D6 | Consent authority persisted as append-only receipts + payload-free events in the same vault; purposes come from a versioned registry; a grant covers the purpose version it was shown for | auditable, revocable, cannot be widened silently |
| D7 | `InteractionGate` + `InteractionProof` minted only inside a consent/confirm control's action closure, scene active, 5 s TTL, single use; `AuthorizationIssuer.issue` removed from the public surface | typing is never consent; one explicit tap is; honest about not being an OS boundary |
| D8 | Consumed-token ring + clock high-water mark persisted (`authz.v1`) | closes `AUTHZ_PERSISTENCE` design; replay/rollback across relaunch |
| D9 | Vault directory excluded from OS backups, Data Protection complete, random file names, 4 KiB padding | only the user's sealed backup leaves the device |
| D10 | `REINSTALL_KEY_POLICY` specified: keys without manifest → wipe-or-restore prompt, never silent reuse | removes a stale-key ambiguity |
| D11 | Crypto-shredding is promised; physical erasure is not | flash wear-levelling, APFS snapshots, memory |
| D12 | AHTOVIA: no app group, no shared container, no shared keychain group; future bridge only by typed, user-initiated export | verified: entitlements carry only the app's own keychain access group |

## 3. Conflicts with prior architecture
None found against ADR-BOOT-005/006/007/008. One tension recorded, not a conflict: ADR-006 D2 keeps `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so passcode removal does not shred data; the sealed backup remains the user's protection. One **surface change** proposed: `AuthorizationIssuer.issue` becomes non-public once `InteractionGate` exists (P03-04); existing tests use the testing target and keep working.

## 4. WCAG 2.2 SC 1.4.11 assessment of the 1.3:1 border threshold (asked by the P03-02 review)

Measured in P03-02 (resolved light / dark pairs, ratios rounded):

| component | pair | light | dark | required by SC 1.4.11? | verdict |
|---|---|---|---|---|---|
| text input (Y/M/D fields) | field fill vs surface | 1.17 | 1.11 | **yes** — the boundary is what identifies the control; placeholder text alone does not mark the hit area | **FAIL → new finding F-UX-5** |
| primary button | fill vs background | 5.62 | 5.62 | n/a (text identifies it; fill also ≥ 3:1) | pass |
| secondary ("quiet") button | accentSoft vs background | 1.13 | 1.32 | no — a button identified by its text label does not need a 3:1 boundary under the SC; the affordance concern stays F-UX-4 | not an SC failure; UX finding open |
| card border | border vs surface | 1.34 | 1.56 | no — decorative grouping, not required to identify or operate anything | pass (decorative) |
| card surface | surface vs background | 1.06 | 1.09 | no | pass (decorative) |
| focus / VoiceOver cursor | system-drawn | — | — | user-agent exception | n/a |

Conclusion: the 1.3:1 threshold in `ContrastTests` is an **internal decorative minimum**, not a claim of SC 1.4.11 conformance. The text-input boundary is the one component where the SC applies and it fails; fix in the next UX phase with an explicit `inputBorder` token measured at ≥ 3:1 against the surface in both schemes, asserted by `ContrastTests`. Recorded in `OPEN_BLOCKERS.md` as `INPUT_FIELD_BOUNDARY_CONTRAST` (F-UX-5) and in `P03_02_ACCESSIBILITY_CHECKLIST.md`.

## 5. P03-02 findings — status (none closed by this phase)
F-UX-4 quiet-button affordance OPEN · SE-class layout OPEN (no simulator) · human VoiceOver pass MANUAL_PENDING · native English review OPEN · app-switcher snapshot visual check MANUAL_PENDING · full device regression with the final build OPEN · `TABBAR_CONTRAST_AUDIT` exception KNOWN_LIMITATION · new F-UX-5 (§4).

## 6. Blockers touched (see `OPEN_BLOCKERS.md` for wording)
Design-resolved, implementation pending: `FORGET_REQUIRES_STORE_PROOF`, `JOURNAL_SECURITY` (engine chosen), `REINSTALL_KEY_POLICY`, `AUTHZ_ISSUER_UI_BINDING`, `DELETION_GRANT_VALIDATION`, `CONSENT_AUTHORITY_IMPL`, `AUTHZ_PERSISTENCE`. New: `PERSISTENCE_ADR_REVIEW`, `DERIVED_DATA_GRAPH`, `TOMBSTONE_RESURRECTION_WINDOW`, `INTERACTION_PROOF_LIMIT`, `INPUT_FIELD_BOUNDARY_CONTRAST`. Unchanged: `VAULT_SECURITY_REVIEW`, `IN_PROCESS_ISOLATION`, `ROTATION_CROSS_PROCESS`, `UX_POLISH_P03_02`.

## 7. Open risks (honest)
1. The interaction proof is in-process; malicious code in the app can forge it. Real boundaries: code signing, sandbox, SE keys, optional biometrics (deferred).
2. Tombstones expire after 90 days, so an older backup can resurrect a deleted record unless the user declines in the restore review.
3. File count and padded sizes leak coarse volume.
4. No independent security review yet; everything here is design + prior library tests.
5. The single-writer rule is a rule, not a mechanism; cross-process rotation stays BLOCKED.
6. Attachment chunking, biometric gating and manifest sharding are UNKNOWN/deferred.

## 8. Checks run (real results)
| check | command | exit | result | log (sha256 in ledger) |
|---|---|---|---|---|
| package regression (no code changed) | `swift test --package-path Packages/XRAICore` | 0 | 108 tests in 27 suites passed | `evidence/p03_03_swift_test_macos.log` |
| spec validator | `python3 -I validation/validate_package.py` | 0 | PASS; files=4380; methods=19; tests=98; tasks=18 | `evidence/p03_03_validate_package.log` |
| P03-03 doc consistency | `python3 -I validation/check_p03_03_docs.py` | 0 | 12 data classes cross-checked; blocker ids resolve; ADRs present; no app groups; baseline cited | `evidence/p03_03_check_docs.log` |
| protected paths untouched | `git status --porcelain` on `Packages/`, `App/`, `project.yml` | — | no changes (BOOT-01 core, vault, Keychain, app: zero diff) | — |

Not run (by design of this phase): Simulator/device builds, UI tests, accessibility audit — nothing executable changed. DEVICE_VERIFIED: n/a · SECURITY_REVIEWED: NO.

## 9. Next smallest implementable task
**P03-04 — `VaultStore` phase 1 (file-based envelope store, no UI):** `VaultStore` port + `FileVaultStore` in a new target `XRAIVaultStore` (Foundation file I/O only, composes `SecureVault`), encrypted manifest, atomic temp+rename writes, Data Protection + backup exclusion, tombstones, journaled cascade delete, `KeyRetirementProof` + coordinator, persisted `authz.v1`; tests: round-trip, crash-after-each-journal-step, tombstone beats restore, proof refused with usage > 0, directory listing leaks nothing, hosted run on Simulator and iPhone. Still **no real personal data**: tests use fixtures only; the app does not wire the store until P03-05 (consent UI + InteractionGate).

## 10. Recommendation
**CONDITIONAL GO.** Conditions: (1) ChatGPT accepts ADR-BOOT-009 D1 (file-based first, SQLCipher deferred) and D7 (in-process interaction proof with stated limit); (2) P03-04 scope stays library-level with fixture data; (3) F-UX-5 is scheduled for the next UX phase. NO-GO triggers: any request to persist real personal data before the store tests exist on device, or to open cloud sync.
