# P03_03_DATA_LIFECYCLE_MATRIX — per-class lifecycle policies and the derived-data dependency contract

**Date:** 2026-10-20 · **Baseline:** `713468e` · Companion to `P03_03_DATA_INVENTORY.md`. Column vocabulary: **origin · purpose · consent · persistence · location · encryption · derives · readers · deletion · on revoke · in backup · deletion limits · tests**.

Türkçe özet: Her veri sınıfı için kaynak, amaç, izin, geçicilik, yer, şifreleme, türettiği veriler, erişen modüller, silinme anı, izin geri çekilince olan, yedekteki durumu, silmenin sınırları ve testi tek tabloda. Türetilmiş veri kaynaksız yaşayamaz: bağımlılık grafiği, geçersizleştirme ve kaskad silme sözleşmesi aşağıda.

## 1. Lifecycle matrix (today → planned)

| class | origin | purpose | consent | persistence | location | encryption | derives | readers (modules) | deleted when | on consent revoke | in user backup | deletion limits | tests (exist / planned) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| birth_date | user input | Life Path; astronomy later | explicit `.write` token (user act), no purpose consent | today: memory; planned: vault record | `SessionState` → `RecordEnvelope` file | AES-256-GCM, DEK wrapped by SE/Keychain KEK | derived_result (trace), later charts | XRAINumerology, XRAIAstronomy (future) via SecureVault.open | `forgetAll()` now; delete record (cascade) | n/a (consent-free) | yes, if user exports | crypto-shred + file unlink; no physical erase guarantee | `DataLifecycleTests`, UI forget test / store cascade tests |
| birth_time | user input + precision | time-sensitive charts | `.write` token | planned | vault | same | charts, HD design epoch | Astronomy/HD | with birth record or alone (cascade to charts) | n/a | yes | same | planned |
| birth_place | user place name → canonical coords | astronomy/Local Space | `.write` token; geocoder is a consented egress (`perCallConsentedProvider`) | planned | vault | same | charts, Local Space rays | Astronomy/LocalSpace | cascade | geocoder consent revoke → cached coords kept as user data (they are the user's), geocoder no longer called | yes | same | planned |
| parents_names | user, optional | symbolic family lens | purpose-bound grant required to **store and read** (`mayStore`/`mayRead`) | planned | vault, high-sensitivity tier | same; pseudonym allowed | symbolic name values | Numerology (names) only | user delete or purpose consent revoke → record quarantined then deleted after grace (see §3) | **read blocked immediately**; record scheduled for deletion | yes but quarantined on restore if grant inactive | same | `ReadAccessTests`, `QuarantineEnforcementTests` / cascade tests |
| sibling_order | user | autobiographical lens | purpose grant | planned | vault | same | none | Psychology lens | same as parents_names | same | same | same | same |
| spiritual_practices | user | lens preferences | purpose grant | planned | vault | same | none | Traditions | same | same | same | same | planned |
| psychometrics | consented answers | non-diagnostic reflection | purpose grant + instrument licence | planned | vault | same | scores (derived_result) | Psychometrics | same; scores cascade | read blocked; scores invalidated | yes (quarantine rule) | same | planned |
| journal | user text | private reflection | purpose grant | planned | vault | same | none by default; **never** model input without separate per-call consent | Journal UI only | user delete | read blocked | yes | same | planned |
| goal_roadmap / future_self | user-authored | planning | `.write` token; future_self lens grant | planned | vault | same | progress_evidence links | Learning/Evidence | user delete; cascade to evidence links (not evidence itself) | lens revoke → future_self read blocked | yes | same | planned |
| evidence_files / progress_evidence | user artifacts | learning proof | `.write` token | planned | vault (attachments as separate envelopes) | same | evidence tier summaries | Evidence | user delete | n/a | yes (size-limited) | same + attachment residue | planned |
| derived_result | engines | display/cache | inherits every source's consent | today: not stored; planned: optional cache | vault, `derivedFrom[]` in authenticated header | same | nothing (leaf) | the engine that made it + UI | **automatically** when any source is deleted, changed, or its consent revoked | invalidated immediately | **no** (recomputed after restore) | n/a | `trace` recompute tests / invalidation tests |
| consent_receipts | authority | audit | n/a | planned (P03-04) | vault, append-only log | same | consent views for the user | ConsentAuthority only | never while any referencing record exists; after full wipe | n/a | yes (restored log drives quarantine) | same | planned |
| tombstones | store | keep deletions deleted | n/a | planned | vault manifest | same | — | Store | after backup reconciliation window (90 d) | n/a | yes (ids only) | — | planned |

Security items S1–S10 (inventory §B): KEKs live until `retire`→`forget` with store proof (`P03_03_DELETION_AND_RECOVERY_DESIGN.md` §4); tokens and clock mark persist across launches once P03-04 lands; key cache purged on inactive; the onboarding flag is the only non-personal persisted value until a preferences layer exists.

## 2. Derived-data dependency contract

**Rule:** a derived record cannot outlive, outrank or out-consent any of its sources.

- Every stored derived record carries `derivedFrom: [RecordID]` **inside the authenticated header** (format v3 of `EnvelopeHeader`; v2 records have none and are treated as leaves). Tampering with the list fails AEAD.
- The manifest keeps the reverse index `dependents[sourceID] = [derivedID…]` (encrypted, see persistence ADR).
- **Invalidation triggers:** source record deleted · source record rewritten (new version) · a consent grant covering the source's class+purpose revoked or expired · source quarantined on restore.
- **Invalidation effect:** every dependent is marked `stale` in the manifest and **unreadable** through `SecureVault.open` (policy: `derivedInvalidatable` records require all sources `present && consent-active && not stale`); stale derived records are deleted at the next maintenance pass or immediately when the source deletion is a user deletion (cascade).
- **Cascade order:** leaves first (dependents of dependents), then the derived record, then the source; each step tombstoned; a crash mid-cascade leaves tombstones that the next launch's recovery pass completes (idempotent).
- **No cycles:** `derivedFrom` must point only to records created earlier (manifest rejects back-edges).
- **Consent inheritance:** `mayRead(derived)` = AND over sources of `mayRead(source)` evaluated at read time; a derived record never has a looser policy than its tightest source.

## 3. Revocation semantics (per class)

| event | consent-free classes | consent-gated classes |
|---|---|---|
| user deletes record | cascade delete + tombstone | same |
| user revokes purpose consent | n/a | reads blocked **immediately** (already enforced); derived invalidated; the record enters `PENDING_DELETE` with a 7-day grace during which re-granting restores it; then deleted + tombstoned |
| grant expires | n/a | same as revoke |
| restore from backup with inactive grant | restored | quarantined (already enforced), never auto-released; after 7 days unreleased → deleted |
| `forgetAll()` (today) | memory cleared | memory cleared |

## 4. Test plan mapping (exists → planned)
Exists: `DataLifecycleTests`, `PrivacySemanticsTests`, `ReadAccessTests`, `QuarantineEnforcementTests`, `BackupTests`, UI forget flow. Planned (P03-04 store): cascade delete, stale-derived unreadable, back-edge rejection, crash-mid-cascade recovery, revoke→grace→delete timeline, tombstone wins over restore, manifest reverse-index consistency property test.
