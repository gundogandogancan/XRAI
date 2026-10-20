# P03_03_DATA_INVENTORY — every data item XRAI holds today or plans to hold

**Date:** 2026-10-20 · **Baseline:** `713468e` · **Status words:** `EXISTS_IN_CODE` (a type/path in the repo), `PLANNED` (constitution/registry only), `UNKNOWN` (not derivable from code or docs). Nothing here is persisted yet except the one non-personal flag (asserted by `PrivacySemanticsTests.relaunch`).

Türkçe özet: XRAI'nın bugün tuttuğu ve ileride tutacağı her veri öğesi; kaynağı, amacı, bilgi sınıfı, hassasiyet tabanı, bugünkü yeri ve kalıcılık durumu. Bugün diske yazılan tek kişisel olmayan değer onboarding bayrağıdır; Keychain yalnız şifreleme anahtarı tutar.

## A. Personal data classes (`DataClass` in `XRAIVaultContracts/PrivacyModel.swift`)

| id | class | source | purpose (first) | epistemic class of the item | min tier (`minimumTier`) | consent to store | today (`713468e`) | planned persistence |
|---|---|---|---|---|---|---|---|---|
| D1 | `birth_date` | user types Y/M/D (`SessionState.draft` → `CivilDate`) | exact Life Path; later astronomy | USER_REPORT (input) | DEVICE_ONLY_SENSITIVE | no (class is consent-free; storing still needs an explicit user act via `.write` token) | memory only; cleared by `forgetAll()`, termination | P04+: `RecordEnvelope` in the vault store |
| D2 | `birth_time` | user, with `TimePrecision` | houses/HD (time-sensitive) | USER_REPORT | DEVICE_ONLY_SENSITIVE | no | not collected | P08/P09 |
| D3 | `birth_place` | user-entered place name → canonical lat/long with geocoder provenance; never current GPS | astronomy/Local Space | USER_REPORT + SOURCED (geocode) | DEVICE_ONLY_SENSITIVE | no | not collected | P08 |
| D4 | `parents_names` | user, optional, per tradition | optional symbolic lens | USER_REPORT (third-party person) | DEVICE_ONLY_HIGH_SENSITIVITY | **yes, purpose-bound** | not collected; policy coded (`requiresPurposeConsentToStore`) | P07 |
| D5 | `sibling_order` | user, optional | autobiographical lens | USER_REPORT (third-party) | DEVICE_ONLY_PRIVATE | **yes** | not collected | P07 |
| D6 | `spiritual_practices` | user, optional | lens preferences | USER_REPORT | DEVICE_ONLY_SENSITIVE | **yes** | not collected | P07/P10 |
| D7 | `psychometrics` | consented questionnaire answers (licensed items only) | non-diagnostic reflection | USER_REPORT (+ SOURCED scoring) | DEVICE_ONLY_SENSITIVE | **yes** | not collected; instrument BLOCKED | P07 |
| D8 | `journal` | user text | private reflection | USER_REPORT | DEVICE_ONLY_SENSITIVE | **yes** | not collected | P05 |
| D9 | `goal_roadmap` | user-authored goals, Future Self hypotheses | planning | USER_REPORT | DEVICE_ONLY_PRIVATE | no (own words) | not collected | P05 |
| D10 | `evidence_files` | user-supplied artifacts (P1–P5 evidence) | learning proof | ACTIVITY_EVIDENCE | DEVICE_ONLY_PRIVATE | no | not collected | P05 |
| D11 | `consent_receipts` | the consent authority itself | audit of consent | SYSTEM record | DEVICE_ONLY_PRIVATE | n/a | in-memory test double only | P03-04 (persisted registry) |
| D12 | `derived_result` | computed by engines from D1–D7 (`NumerologyTrace`, later charts) | display/caching | EXACT_MATH / SYMBOLIC | DEVICE_ONLY_PRIVATE | inherits sources | computed on demand, never stored | P04+: optional cache with `derivedFrom[]` |
| D19 | `store_metadata` (added P03-04) | the store itself | manifest, deletion ledger, authorization state, journal entries | SYSTEM record (ids, classes, generations — never contents) | DEVICE_ONLY_PRIVATE | n/a (sealed/opened only through the `storeMetadata` system path; never in a user backup) | P03-04: `system/*.v1`, `journal/*.j` under `XRAIVaultStore` (library only, app not wired) | same |

New classes required by the planned product (not yet in `DataClass`; to be added by the persistence phase, append-only):

| id | class (proposed) | purpose | epistemic | tier | consent |
|---|---|---|---|---|---|
| D13 | `name_variants` | name numerology (legal/chosen/birth/phonetic, each opt-in) | USER_REPORT | DEVICE_ONLY_SENSITIVE | per variant |
| D14 | `hd_chart` / `natal_chart` | Human Design / astrology charts (derived from D1–D3) | SYMBOLIC (derived) | DEVICE_ONLY_SENSITIVE | inherits |
| D15 | `future_self` | user-edited Future Self scenarios ("Digital Twin" is a hypothesis, never a model of the person) | USER_REPORT + SYSTEM_INVITATION | DEVICE_ONLY_SENSITIVE | yes (explicit lens) |
| D16 | `progress_evidence` | P0–P5 learning evidence records (ties to D10) | ACTIVITY_EVIDENCE | DEVICE_ONLY_PRIVATE | no |
| D17 | `lens_preferences` | which interpretive lenses the user enabled | USER_REPORT | DEVICE_ONLY_PRIVATE | no |
| D18 | `tombstones` | ids of deleted records + deletedAt (no content) | SYSTEM | DEVICE_ONLY_PRIVATE | n/a (needed to keep deletions deleted across restore) |

## B. Security material and system state

| id | item | where | protection today | notes |
|---|---|---|---|---|
| S1 | device KEK versions `<keyID>/kek/vN` | Keychain (data-protection, ThisDeviceOnly, non-sync) | SE-wrapped where SE exists; add-only; two-phase retire/forget (`KeychainKeyProvider`) | EXISTS_IN_CODE; device-verified non-destructively |
| S2 | KEK pointer `<keyID>/current`, meta, retired markers | Keychain | same | EXISTS_IN_CODE |
| S3 | per-record DEKs | inside each `RecordEnvelope.wrappedDEK` | AES-GCM wrapped by KEK, bound to recordID | EXISTS_IN_CODE |
| S4 | recovery key | never stored by XRAI; shown once | user-held | EXISTS_IN_CODE (`RecoveryKey`), no UI |
| S5 | sealed backup file | user-chosen location (export sheet) | outer AES-256-GCM, HKDF from recovery key | EXISTS_IN_CODE (`SealedBackup`), no UI |
| S6 | operation tokens (ids, consumed set) | process memory (`AuthorizationIssuer`) | single-use, TTL ≤ 300 s | EXISTS_IN_CODE; **not persisted** (AUTHZ_PERSISTENCE) |
| S7 | clock high-water mark | process memory (`MonotonicGuardClock`) | — | EXISTS_IN_CODE; not persisted |
| S8 | quarantine registry | process memory (`InMemoryAppQuarantineRegistry` in the app) | — | EXISTS_IN_CODE; not persisted |
| S9 | onboarding-completed flag | `UserDefaults` key `xrai.onboarding.completed.v1` | plain boolean, non-personal | EXISTS_IN_CODE; asserted sole persisted value |
| S10 | key cache (unwrapped KEK bytes) | process memory, TTL 30 s, purged on inactive | — | EXISTS_IN_CODE |

## C. Non-personal content (never mixed with A)

| id | item | rights status | where |
|---|---|---|---|
| C1 | method registry (`num.life_path.*`) | original | code + `docs/registries` |
| C2 | string catalog, design tokens, logo | founder-owned | app bundle |
| C3 | future ephemeris bundle, lessons, Wisdom Atlas | RIGHTS_BLOCKED / PLANNED | signed content packs (`SIGNED_CONTENT_PUBLIC` tier) |
| C4 | HD book scans, Book of Wisdom | private study only, never in app or repo | founder's Mac |

## D. Things that must never exist
No analytics identifiers, no advertising identifiers, no crash-log payloads with A-class content, no cloud copy of A or S1–S4, no model-training corpus from A, no third-party SDK with network access. Verified today by the static import scans and the deny-by-default `VaultPolicy`; must be re-verified by on-device traffic capture in P12.

## E. UNKNOWN
Exact field list for D7 (instrument not chosen), D13 script/transliteration policy, D14 method tables (RIGHTS_BLOCKED), size/retention of D10 attachments.
