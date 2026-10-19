# SOURCE COVERAGE AND TRACEABILITY AUDIT — BOOT-00

**Date:** 2026-10-19 · **Scope:** read-only audit of `/Users/dogancangundogan/ProjectXrai` and the extracted package copies in the session scratchpad · **Author:** Claude Fable 5.1 (audit subagent) · **Authority:** this is evidence of what exists on disk, not approval of scope. Nothing below is DONE, VERIFIED or APPROVED.

## Türkçe özet (10 satır)

1. Kaynaklar: 31 kaynak ailesi sınıflandırıldı; önceki ChatGPT sohbetleri, HD kitap taramaları (repo dışında), Book of Wisdom tam metni, dört klasik astroloji eserinin modern çevirileri, NUR/AUREV/AYMORA kod dökümleri ve bugün silinen eski GitHub reposu **NOT_AVAILABLE**.
2. 100 gereksinimin tamamı eşlendi: ilk 80 kayıt `REQUIREMENT_FAMILIES_v3.json` ile birebir aynı (alan farkı yok); 20 `XRAI31-*` kaydının v3.0 aile kimliği yok.
3. Durumlar: SPECIFIED 73, SOURCE_UNVERIFIED 10, RIGHTS_BLOCKED 14, CODED 3 (CODED_PENDING_TEST_EVIDENCE; `TEST_EVIDENCE_LEDGER.json` run 3: 35/35, exit 0 — TESTED terfisi bu denetimin değil, ana rapor ve bağımsız denetçinin kararı), bu denetimde TESTED 0.
4. Eski kaynaklarda olup v3.1 matrisinde kimliği olmayan 34 gereksinim `MISSING_REQUIREMENTS_REGISTER.json` içine `XRAI32-MISSING-001..034` olarak eklendi; hiçbir mevcut kimlik silinmedi veya yeniden numaralanmadı.
5. Ekranlar: 148 tarihsel aday → 12 v3.2 sözleşmesi: KEPT 10, MERGED 97, DROPPED_NOT_YET_DETAILED 41 (bunların 25'i admin/operasyon konsolu).
6. Roller: 43 benzersiz tarihsel ajan kartı bulundu (20 v1.0 + 5 v1.1 + 10 yeni v1.2 + 8 v1.3; v1.1'in 5'i v1.2'de tekrar eder) + 16 ayrı v1.7 mantıksal rol; roller inceleme sorumluluğudur, 43 eş zamanlı model çağrısı değildir.
7. Yöntemler: kayıt dosyasında 19 yöntemin 19'u hâlâ DESIGN_ONLY_NOT_TESTED; yalnız `num.life_path.digits.v1` (+ BOOT-01'de eklenen, kayda henüz eklenmemiş `components` varyantı) CODED_PENDING_TEST_EVIDENCE; kayıt dosyası güncellenmedi, TESTED terfisi denetçiye bağlı.
8. Human Design: 13 benzersiz PDF / 298 kare; 298/298 satır PENDING_DETAILED_READING ve hesap kuralı NOT_VERIFIED; basılı s. 1–8 ve s. 300 eksik/şüpheli; 7 kare okunaksız/karanlık; lisans RIGHTS_REVIEW_REQUIRED. **Araştırma tamamlanmamıştır.**
9. 16'ya karşı 20: `OPEN_DECISIONS_v3.1.json` 16 kayıt; '20' sayısı `historical_v3.0/OPEN_BLOCKERS_v3.json` (20 kayıt) kaynaklıdır; 14 v3.0 blokörü 12 v3.1 kararına eşlenir, 5 v3.0 blokörünün v3.1 kaydı yok, 3 v3.1 kararı yenidir → toplam 21 ayrı açık konu, hiçbiri kapanmadı.
10. Araç denetimi bu belgenin kapsamı dışındadır: bkz. `docs/tools/`.

## 0. How to read this document

- Status vocabularies used exactly as instructed: sources `FULL_TEXT_AVAILABLE | SUMMARY_ONLY | NOT_AVAILABLE`; requirements/features `SPECIFIED | SOURCE_UNVERIFIED | RIGHTS_BLOCKED | CODED | TESTED`; screens `KEPT | MERGED | DROPPED_NOT_YET_DETAILED`.
- Every claim cites a file path and a section, line span or JSON id. Line numbers refer to `docs/canon/XRAI_ULU_EVREN_COMPLETE_BUILD_CONSTITUTION_v3.2.md` (35,131 lines) unless another file is named.
- Companion machine-readable outputs: `docs/status/REQUIREMENT_CROSSWALK_100.json` (100 rows) and `docs/status/MISSING_REQUIREMENTS_REGISTER.json` (append-only).
- Human Design scans in `~/Downloads` were **not opened** and are **not** in the repo. Tooling is **not** audited here (see `docs/tools/`).
- Repo facts observed during this audit: `git log` → no commits yet on `main`; working tree entirely untracked (`.claude/`, `.gitignore`, `CLAUDE_FIRST_SESSION_v3.2.md`, `Packages/`, `baseline/`, `brand/`, `docs/`, `validation/`). `docs/registries/INTEGRITY_SHA256_v3.2.json` lists 47 files: 45 present with matching SHA-256; `CLAUDE.md` is present at repo root but its SHA-256 differs from the manifest (parent-authored during this session, not the package copy); `README_START_HERE.md` is absent at root (the package README exists as `docs/README_START_HERE_v3.2.md`; a separate `README.md` was written by the parent). Parent-written status files present at audit time: `docs/status/TEST_EVIDENCE_LEDGER.json`, `REPO_FACTS.json`, `OPEN_BLOCKERS.md`, `SOURCE_AUTHORITY_LEDGER.json`, `NEXT_TASK.md`, `evidence/{swift_build_final.log, swift_test_run1_FAILED_2_of_35.log, swift_test_run3_PASS_35_of_35.log}`; they were read for reconciliation, not re-verified.

## 1. Source classification

| # | Source family | Status | Evidence (path / section) | Note |
|---|---|---|---|---|
| 1 | v3.2 overlay §70–§93 | FULL_TEXT_AVAILABLE | constitution lines 1–166; BASELINE_HASHES_v3.2.json v3_2_overlay_sha256 | binding spec |
| 2 | v3.1 master §54–§69 | FULL_TEXT_AVAILABLE | constitution lines 169–461; scratchpad md/XRAI_ULU_EVREN_COMPLETE_BUILD_CONSTITUTION_v3.1.md; baseline/XRAI_ULU_EVREN_FULL_BUILD_v3.1.zip | preserved byte-for-byte per line 167 |
| 3 | v3.0 master §39–§53 + addendum | FULL_TEXT_AVAILABLE | constitution lines 464–695; docs/canon/ARCHIVE_v3.0_ADDENDUM.md; scratchpad pkg_v30/XRAI_ULU_EVREN_BUILD_MASTER_CONSTITUTION_v3.0.md | first prompt archived at docs/canon/ARCHIVE_CLAUDE_FIRST_PROMPT_v3.0.md |
| 4 | v2.1 historical constitution (§28–§38, v1.1–v2.1 embedded) | FULL_TEXT_AVAILABLE | constitution lines 696–35131 (v2.1 header line 698; §28 at 14789; §29 at 15104; §30 at 15388; §31 at 26908; §32 at 27987; §33 at 732; §34 at 30434; §35 at 30596; §36 at 30733; §37 at 30898; §38 at 33356) | the v1.x and v2.x master MDs are embedded here, not separately present as files in the repo (listed in SOURCE_INVENTORY_LIVE_SESSION_v3.2.json as REFERENCE_PRESENT_NOT_FULLY_REVIEWED in the ChatGPT session, not on this disk) |
| 5 | Package ZIP v3.2 (XRAI_ULU_EVREN_CANONICAL_EXECUTION_v3.2) | FULL_TEXT_AVAILABLE | scratchpad pkg_v32/ (48 files); repo docs/registries/*_v3.2.json; INTEGRITY_SHA256_v3.2.json | extracted; all 45 present hashes match |
| 6 | Package ZIP v3.1 (XRAI_ULU_EVREN_FULL_BUILD_v3.1) | FULL_TEXT_AVAILABLE | baseline/XRAI_ULU_EVREN_FULL_BUILD_v3.1.zip; scratchpad pkg_v31/ (37 files) | two v3.1 members are NOT copied into the repo: docs/registries/HD_LOCAL_SCAN_SHA256_REFERENCES_v3.1.json and docs/engineering/TECHNICAL_REFERENCES_AND_NOTES.md (present only in scratchpad pkg_v31) |
| 7 | Package ZIP v3.0 (XRAI_ULU_EVREN_CLAUDE_MASTER_BUILD_PACKAGE_v3.0) | FULL_TEXT_AVAILABLE | scratchpad pkg_v30/ (217 files incl. 14 historical ZIPs + HISTORICAL_MACHINE_REGISTRIES with 180 indexed members); repo docs/registries/historical_v3.0/* | HISTORICAL_MACHINE_REGISTRY_INDEX_v3.json count=180 |
| 8 | Historical packages v1.0 … v2.1 (14 ZIPs) | FULL_TEXT_AVAILABLE (machine registries) / SUMMARY_ONLY (their master MDs) | pkg_v30/HISTORICAL_ARCHIVES/*.zip; SOURCE_AND_ARTIFACT_PROVENANCE_v3.json legacy_and_master_artifacts (43 rows with sha256) | registries extracted; the per-version master MD texts exist only as embedded copies inside the v2.1 region of the constitution |
| 9 | Founding philosophy package | FULL_TEXT_AVAILABLE | docs/canon/XRAI_FOUNDING_PHILOSOPHY_AND_GOD_LEVEL.md (370 lines); docs/canon/FOUNDING_PHILOSOPHY_MANIFEST.json; docs/canon/CLAUDE_KURUCU_FELSEFE_ILK_MESAJ.md; scratchpad pkg_felsefe/ | manifest role: 'philosophy not implementation evidence' |
| 10 | Registry: REQUIREMENT_TO_ENGINE_MATRIX_v3.1.json | FULL_TEXT_AVAILABLE | docs/registries/; 100 rows (80 + 20) | claim field: HISTORICAL_REQUIREMENTS_PRESERVED_WITH_CANDIDATE_OWNER_NOT_EACH_LINE_PARSED |
| 11 | Registry: REQUIREMENT_FAMILIES_v3.json | FULL_TEXT_AVAILABLE | docs/registries/historical_v3.0/; 80 rows; classification canonical_family_index_not_exhaustive_line_by_line_map | identical ids/intents/phases to first 80 matrix rows (verified field-by-field) |
| 12 | Registry: ORIGINAL_MATH_METHOD_REGISTRY_v3.2.json | FULL_TEXT_AVAILABLE | docs/registries/; 19 methods, all DESIGN_ONLY_NOT_TESTED |  |
| 13 | Registry: UX_PIXEL_SCREEN_CONTRACTS_v3.2.json | FULL_TEXT_AVAILABLE | docs/registries/; 12 screens, proposal_only=true, status SPEC_ONLY |  |
| 14 | Registry: OPEN_DECISIONS_v3.1.json / historical_v3.0/OPEN_BLOCKERS_v3.json | FULL_TEXT_AVAILABLE | 16 and 20 records respectively | see §8 |
| 15 | Registries: ENGINE_BOUNDED_CONTEXTS (21), PHASE_EXECUTION_DAG (14), EXECUTION_OVERLAY_TASKS (18), TASK_DEPENDENCY_GRAPH (42), NEW_ACCEPTANCE_TESTS (98), RELEASE_AND_TEST_GATES (86), ARCHITECTURE_ADRS (15), MODEL_AND_DATA_POLICY, SECURITY_DATA_EGRESS_MATRIX (15), SOURCE_RIGHTS_AND_EVIDENCE (14), SOURCE_INVENTORY_LIVE_SESSION (58), BASELINE_HASHES, INTEGRITY_SHA256 (47) | FULL_TEXT_AVAILABLE | docs/registries/*.json | all parse; all statuses NOT_VERIFIED / NOT_RUN / NOT_STARTED |
| 16 | Registries historical_v3.0: EXECUTION_PHASES (12), TEST_GATES (40), MCP_SKILLS_APIS_CAPABILITY_GATES (20), PACKAGE_SHA256_MANIFEST (216), SOURCE_AND_ARTIFACT_PROVENANCE, HISTORICAL_MACHINE_REGISTRY_INDEX (180), HUMAN_DESIGN_SOURCE_COVERAGE, HUMAN_DESIGN_298_IMAGE_PAGE_TRACKER.csv (298) | FULL_TEXT_AVAILABLE | docs/registries/historical_v3.0/ |  |
| 17 | Historical archive: screen contracts 106/119/134 + delta 14; agent cards v1.0/v1.1/v1.2/v1.3/v1.7; traceability CSVs v1.0 (106 rows) and v1.2 delta (18 rows) | FULL_TEXT_AVAILABLE | docs/registries/historical_archive/ |  |
| 18 | Legacy coding handoff notes v0.2, v0.3, v0.4 and 2026-10-12 | FULL_TEXT_AVAILABLE | docs/registries/historical_archive/legacy_coding_handoffs/*.md (258/370/485/155 lines); the 2026-10-12 note body is byte-identical to lines 16–162 of v0.2 (diff exit 0); v0.4 is also embedded at constitution line 3358 | SOURCE_AND_ARTIFACT_PROVENANCE_v3.json carries their sha256 |
| 19 | Human Design book scans (Chetan Parkyn Turkish edition, 13 unique PDFs / 17 uploads / 298 frames) | NOT_AVAILABLE (in repo); private-study-only on user's Mac | SOURCE_INVENTORY_LIVE_SESSION_v3.2.json 17 rows PRIVATE_BOOK_SCAN_INDEXED_NOT_LICENSED_FOR_APP; SOURCE_AND_ARTIFACT_PROVENANCE_v3.json human_design_pdf_sources (13, sha256); HUMAN_DESIGN_298_IMAGE_PAGE_TRACKER.csv | not opened; must never be copied in (README_START_HERE_v3.2.md item 1). Only index/tracker/notes are available = SUMMARY_ONLY of content |
| 20 | Human Design batch-1 research notes | FULL_TEXT_AVAILABLE (notes) / SUMMARY_ONLY (book content) | scratchpad pkg_v30/HUMAN_DESIGN_RESEARCH_PRIOR/BATCH1_ANALYSIS_NOTES.md; SOURCE_FILE_MANIFEST.json | notes state 'Henüz tam kitap analizi tamamlanmış değildir' |
| 21 | Book of Wisdom vols 1–2 (Harry B. Joseph) | NOT_AVAILABLE | SOURCE_RIGHTS_AND_EVIDENCE_v3.1 BOW_JOSEPH coverage 'no full text or rights'; SOURCE_AND_ARTIFACT_PROVENANCE_v3 external_books_incomplete; OPEN_DECISIONS_v3.1 BOW_FULL_COVERAGE; 12 IMG_*.jpeg screenshots listed in provenance (not in repo) | research protocol only: v2.0 package (pkg_v30/HISTORICAL_MACHINE_REGISTRIES/XRAI_CLAUDE_COMPLETE_BOOK_RESEARCH_PACKAGE_v2.0, 18 files) and constitution §36–§37 |
| 22 | Ptolemy Tetrabiblos | NOT_AVAILABLE (text) / SUMMARY_ONLY (metadata) | SOURCE_RIGHTS_AND_EVIDENCE_v3.1 PTOLEMY_TETRA 'some older translations accessible, not fully read'; constitution §38.1 (line 33361) | no edition file in repo |
| 23 | Vettius Valens Anthologies | NOT_AVAILABLE | SOURCE_RIGHTS_AND_EVIDENCE_v3.1 VALENS_ANTHO 'screenshot cover and public metadata'; rights MODERN_TRANSLATION_PROTECTED |  |
| 24 | Dorotheus Carmen Astrologicum | NOT_AVAILABLE | SOURCE_RIGHTS_AND_EVIDENCE_v3.1 DOROTHEUS_CARMEN 'screenshot cover and public metadata'; rights MODERN_TRANSLATION_PROTECTED |  |
| 25 | William Lilly Christian Astrology | NOT_AVAILABLE (text) | SOURCE_RIGHTS_AND_EVIDENCE_v3.1 LILLY_CHRISTIAN 'historical first edition public-domain evidence differs per scan' | edition registry in pkg_v30 CLASSICAL_SOURCE_AND_EDITION_REGISTRY_v2.1.json (metadata only) |
| 26 | Prior ChatGPT conversations (all versions) | NOT_AVAILABLE | constitution §91 line 150 'Unknown: all prior chats literally'; docs/README_START_HERE_v3.2.md 'Full case chat literal archive is not available as one export'; docs/audits/XRAI_V3_2_KAPSAM_EKSIK…md §Sınır | only distillations exist (the constitution versions and registries) |
| 27 | Old GitHub repository (deleted today) | NOT_AVAILABLE | docs/status/REPO_FACTS.json repo.history_before_boot ('Old repository content and .git history were deleted on 2026-10-19 at the user's explicit request … Fresh git init') and repo.remote_old (https://github.com/gundogandogancan/xrai.git); `git log` on this repo shows no commits; constitution line 1348 only says 'If current repo not available … PROPOSED_NOT_APPLIED' | no code, history or hash of the deleted repo is recoverable from the sources on disk; docs/status/OPEN_BLOCKERS.md marks LOCAL_REPO_STATE RESOLVED_TODAY and lists GITHUB_REMOTE_REWRITE as OPEN |
| 28 | NUR / AUREV / AYMORA prior code dumps | NOT_AVAILABLE | legacy handoff v0.4 §10 (lines 100–106): NUR/AUREV dumps were reviewed in a prior chat; AYMORA 'erişilebilir ayrı dump bulunamadı' | none in repo or scratchpad |
| 29 | Reference Swift test log v1.8 | FULL_TEXT_AVAILABLE but NOT THIS REPO | docs/registries/historical_archive/REFERENCE_SWIFT_TEST_LOG_v1.8_NOT_THIS_REPO.txt (built on x86_64-unknown-linux-gnu at /mnt/data/…) | must not be cited as evidence for this repo |
| 30 | Packages/XRAICore (BOOT-01, in progress by parent) | FULL_TEXT_AVAILABLE | Packages/XRAICore/Sources/{XRAIIdentityTime/CivilDate.swift, XRAINumerology/*.swift}; Tests/*; docs/status/BOOT_01_HAND_DERIVED_FIXTURES.md; docs/status/evidence/swift_test_run1_FAILED_2_of_35.log | not audited for correctness here; status CODED_PENDING_TEST_EVIDENCE |
| 31 | External tool repos (11 pins) | out of scope | docs/tools/EXTERNAL_REPO_PINS.txt; scratchpad repos/ | see docs/tools/ (parent audits) |

Counts by primary status: FULL_TEXT_AVAILABLE 21, SUMMARY_ONLY 0, NOT_AVAILABLE 9, out of scope 1 (of 31 families). Where a row carries two statuses, the first is counted.

Gaps found while classifying: (a) two v3.1 package members never reached the repo (`HD_LOCAL_SCAN_SHA256_REFERENCES_v3.1.json`, `TECHNICAL_REFERENCES_AND_NOTES.md`); (b) `README_START_HERE.md` is in `INTEGRITY_SHA256_v3.2.json` but absent at repo root, and the root `CLAUDE.md` does not match the manifest hash (parent-authored); (c) the separate master MD files v1.0–v2.1 named in `SOURCE_INVENTORY_LIVE_SESSION_v3.2.json` exist on disk only as the embedded v2.1 region of the constitution, not as files.

## 2. Requirement crosswalk (100 rows)

Full table: `docs/status/REQUIREMENT_CROSSWALK_100.json` (fields: req_id, v30_family_id, legacy_ids[], phase, owner_engine, status, evidence_note).

- Lineage check: the first 80 `req_id`s of `REQUIREMENT_TO_ENGINE_MATRIX_v3.1.json` equal the 80 `req_id`s of `historical_v3.0/REQUIREMENT_FAMILIES_v3.json` in the same order, with identical `intent`, `phase`, `category` and `canonical_source` (programmatic field diff = 0). The 20 `XRAI31-*` rows have `v30_family_id = null` (source class NEW_2026-10-19_REQUIREMENT).
- Legacy ids used: `REQ-*-001` (XRAI_REQUIREMENT_TRACEABILITY_v1.0.csv, 12 distinct ids over 106 screen rows), `UHA-REQ-01..18` (DELTA_v1.2.csv), `GAP-001..064` (§33.8, lines 843–975), `LF-01..12` (§31.2, lines 26935–26987), `AST-001..032` (CLASSICAL_ASTROLOGY_METHOD_REGISTRY_v2.1.json), `DEC-01..12` (XRAI_EXTERNAL_DECISIONS_12_v1.6.json), v1.7 method ids, ADR ids and screen ids.

| status | count | rule applied |
|---|---|---|
| SPECIFIED | 73 | spec text exists; no code, no test, no unresolved rights gate named |
| SOURCE_UNVERIFIED | 10 | governing source/edition/method table not available or not registered in SOURCE_RIGHTS_AND_EVIDENCE_v3.1.json |
| RIGHTS_BLOCKED | 14 | an ADR (BLOCKED), an OPEN_DECISIONS record or a method activation_gate names an unresolved licence/rights prerequisite |
| CODED | 3 | Swift sources exist in Packages/XRAICore; recorded as CODED_PENDING_TEST_EVIDENCE (see docs/status/TEST_EVIDENCE_LEDGER.json) |
| TESTED | 0 | no requirement has an executed, passing, reviewed test log in this repo |

Rows by status (ids only):
- **CODED**: XRAI-CALENDAR, XRAI-PYTHAGOREAN_LP, XRAI31-PHASE-BOOT-FIRST
- **RIGHTS_BLOCKED**: XRAI-EPHEMERIS, XRAI-NATAL_ASTRO, XRAI-CLASSICAL_ASTRO, XRAI-ASTROCARTOGRAPHY, XRAI-HD_DESIGN_EPOCH, XRAI-HD_GATES_LINES, XRAI-HD_CENTERS_CHANNELS, XRAI-HD_TYPE_AUTHORITY, XRAI-HD_PROFILE, XRAI-16PERSONALITIES, XRAI-BIG_FIVE, XRAI-CLASSICAL_BOOKS, XRAI31-HD-88-DEGREES, XRAI31-16-TYPE-RIGHTS
- **SOURCE_UNVERIFIED**: XRAI-JUNG, XRAI-MASLOW, XRAI-PHILOSOPHY, XRAI-HERMETICISM, XRAI-NUM_SYMBOL, XRAI-CHAKRA_MUDRA, XRAI-BOOK_OF_WISDOM, XRAI-FACE_PALM, XRAI31-BOOK-CLEAN-ROOM, XRAI31-GEMATRIA-SCRIPT
- **SPECIFIED**: the remaining 73 rows.

### 2.1 Requirements present in older sources with no v3.1 req_id

34 proposed records written to `docs/status/MISSING_REQUIREMENTS_REGISTER.json` (ids `XRAI32-MISSING-001` … `XRAI32-MISSING-034`; append-only; no existing id touched). Status mix: RIGHTS_BLOCKED 3, SOURCE_UNVERIFIED 5, SPECIFIED 26.

| id | title | proposed phase / owner | status |
|---|---|---|---|
| XRAI32-MISSING-001 | Daily rhythm loop: energy check-in, one action or rest, evening reflection, weekly review (Bugün) | P03 / DesignSystem | SPECIFIED |
| XRAI32-MISSING-002 | Notification/attention budget, quiet hours and 'why shown' disclosure | P03 / PrivacyKernel | SPECIFIED |
| XRAI32-MISSING-003 | Personal year/month/day cycles and opt-in sourced daily symbolic theme | P07 / Numerology | SPECIFIED |
| XRAI32-MISSING-004 | Place/home name numerology and city etymology (symbolic, no place-energy causal claim) | P07 / Numerology | SOURCE_UNVERIFIED |
| XRAI32-MISSING-005 | Chaldean numerology as a distinct, separately sourced mapping table | P07 / Numerology | SOURCE_UNVERIFIED |
| XRAI32-MISSING-006 | Transits, solar returns and progressions (time-sampled positions, symbolic caveats) | P08 / Astronomy | RIGHTS_BLOCKED |
| XRAI32-MISSING-007 | Hellenistic time-lord and lot methods (lots, profections, zodiacal releasing, horary/electional) as versioned registry entries | P08 / Astronomy | RIGHTS_BLOCKED |
| XRAI32-MISSING-008 | Travel Space school registry: fail closed for undocumented schools | P08 / LocalSpace | SOURCE_UNVERIFIED |
| XRAI32-MISSING-009 | Place symbolism vs practical reality layer (visa, cost, safety, access) kept separate from astro lines | P08 / LocalSpace | SPECIFIED |
| XRAI32-MISSING-010 | Human Design advanced concepts (incarnation cross, colour/tone/base, variable, HD transits, composite) behind rights gate | P09 / HumanDesign | RIGHTS_BLOCKED |
| XRAI32-MISSING-011 | Name etymology and name-history timeline as sourced language history (never trait inference) | P07 / KnowledgeDNA | SOURCE_UNVERIFIED |
| XRAI32-MISSING-012 | Voluntary cultural context with special-category consent; no protected-trait inference from name/face/location | P02 / PrivacyKernel | SPECIFIED |
| XRAI32-MISSING-013 | Purpose hypothesis and experiment lab: 2-4 user-approved hypotheses labelled EXPLORATION_ONLY, small voluntary experiments | P05 / FutureSelf | SPECIFIED |
| XRAI32-MISSING-014 | Personal decision intelligence (DecisionFrame): reversible/irreversible, alternatives, limits, 'none' option, no external action | P05 / FutureSelf | SPECIFIED |
| XRAI32-MISSING-015 | Socratic reflective questioning and epistemic calibration (observation vs interpretation, counterexamples) | P06 / OctopusOrchestrator | SPECIFIED |
| XRAI32-MISSING-016 | Relationships and boundaries practice (D4): user-authored only, no third-party profiling, no reconciliation pressure | P05 / PersonalBrain | SPECIFIED |
| XRAI32-MISSING-017 | Contribution and generativity service (D6): voluntary, no altruism score, beneficiary data only with consent | P05 / Learning | SPECIFIED |
| XRAI32-MISSING-018 | Awe, wonder and transcendence experiences (D7): optional contemplative/art/nature/science, never an enlightenment badge | P10 / WisdomAtlas | SPECIFIED |
| XRAI32-MISSING-019 | Life chapters, yearly review and legacy/portability (editable narrative, no fabricated then-vs-now) | P05 / PersonalBrain | SPECIFIED |
| XRAI32-MISSING-020 | Life transition, resilience and crisis referral: 'adjust/reflect/break/not now', no diagnosis, local human services | P06 / ResponseVerifier | SPECIFIED |
| XRAI32-MISSING-021 | Privacy-safe share card and referral attribution (no contacts access, metadata scrub, no DOB in default image) | P11 / PrivacyKernel | SPECIFIED |
| XRAI32-MISSING-022 | Optional E2EE multi-device sync with conflict UI and no silent deletion | P13 / SecureVault | SPECIFIED |
| XRAI32-MISSING-023 | Data schema migration ledger with dry-run, integrity fixtures and rollback for sensitive records | P02 / SecureVault | SPECIFIED |
| XRAI32-MISSING-024 | Versioned command/event registry (idempotent, authorised, respects deletion) | P02 / OctopusOrchestrator | SPECIFIED |
| XRAI32-MISSING-025 | Voice interaction: opt-in microphone, on-device speech, safe voice-off path | P12 / PrivacyKernel | SPECIFIED |
| XRAI32-MISSING-026 | Internal operations consoles (source/rights registry, eval lab, incident centre, privacy requests, cost guard, growth/ASO) | P12 / OctopusOrchestrator | SPECIFIED |
| XRAI32-MISSING-027 | Rights expiry jobs and disable-fallback for licensed content (signed source registry) | P13 / KnowledgeDNA | SPECIFIED |
| XRAI32-MISSING-028 | Per-request budget, max hops, circuit breaker and financial/incident kill switch | P06 / OctopusOrchestrator | SPECIFIED |
| XRAI32-MISSING-029 | Collective-learning privacy budget: small-cohort suppression / re-identification review and honest unlearning-limits disclosure | P13 / EvolutionGovernor | SPECIFIED |
| XRAI32-MISSING-030 | Scale/SLO load evidence before any capacity claim (no 'million users' statement without observed load) | P12 / OctopusOrchestrator | SPECIFIED |
| XRAI32-MISSING-031 | Legacy NUR / AUREV / AYMORA code reuse audit (licence, security, no production assumption) | BOOT-00 / OctopusOrchestrator | SOURCE_UNVERIFIED |
| XRAI32-MISSING-032 | Support and feedback channel that never exposes secrets or private data | P12 / PrivacyKernel | SPECIFIED |
| XRAI32-MISSING-033 | Legal, method and source information screen (in-app disclosure of methods, rights and privacy policy) | P03 / KnowledgeDNA | SPECIFIED |
| XRAI32-MISSING-034 | Interests/curiosity and values capture as voluntary self-report (A08, C04, C06) | P05 / PersonalBrain | SPECIFIED |

Older-source families checked for coverage: the 80 v3.0 families (all carried), the 12 `REQ-*` ids of the v1.0 CSV (REQ-DAILY-001, REQ-OPERATIONS-001 and REQ-IMPACT-OPERATIONS-001 have no v3.1 row → MISSING-001, -026), the 18 `UHA-REQ` rows (UHA-REQ-10, -11, -17 uncovered → MISSING-008, -009, -020), v2.1 §28–§38 headings, the 64-gap index (GAP-026, -027, -035, -036, -046, -047, -050, -051, -052, -059, -060, -063, -064 uncovered → MISSING-006..-030), the 7 flourishing dimensions (D4, D6, D7 services uncovered → MISSING-016..-018), the 12 LF engines of §31.2 (LF-01/03/07/09/10/11/12 uncovered), the 43 roles (DailyAlignment, AttentionGuardian, ConnectionEthicsCoach, ContributionOpportunityCurator, AweCuriosityCurator, LifeChapterArchivist map to MISSING rows), 148 screens (see §3) and the legacy handoff notes (event system, NUR/AUREV/AYMORA, scale).

## 3. Screen coverage: 148 historical candidates vs 12 v3.2 contracts

Sources: `XRAI_SCREEN_CONTRACTS_134_v1.2.json` (134 = 111 user + 23 ops) + `XRAI_SCREEN_DELTA_14_v1.3.json` (14) = 148; the 106 (v1.0) and 119 (v1.1) files are strict subsets by id. Targets: the 12 ids in `UX_PIXEL_SCREEN_CONTRACTS_v3.2.json` (`today, self, explore, path, guide, free, privacy, atlas, local, wisdom, mentor, store`), read together with the tab text of v3.2 §71 (line 15).

Classification rule: KEPT = direct one-to-one counterpart; MERGED = the contract's `user_purpose` or the §71 tab sentence explicitly covers the screen's purpose; DROPPED_NOT_YET_DETAILED = nothing in the 12 contracts or §71 names it (this is a coverage statement, not a decision that the feature is removed). No screen was invented; every target id exists in the v3.2 file.

**Counts:** KEPT 10 · MERGED 97 · DROPPED_NOT_YET_DETAILED 41 · total 148.

v3.2 contracts by number of historical screens mapped to them: today 6, self 24, explore 12, path 31, guide 9, free 3, privacy 8, atlas 4, local 5, wisdom 2, mentor 0, store 3. `mentor` has no historical screen counterpart: it originates from §32.10 (Thought-lens council, line 28140) and requirement XRAI-MENTOR_LENSES, not from a screen contract. `wisdom` has no KEPT counterpart (only ST08/ST09 merged).

| id | title | area | class | v3.2 target | note |
|---|---|---|---|---|---|
| A01 | App Store ürün sayfası | A — Satın alma ve onboarding | DROPPED_NOT_YET_DETAILED | - | external App Store page; not an in-app surface |
| A02 | Satın alma hakkı ve açılış | A — Satın alma ve onboarding | MERGED | store | absorbed into contract/tab |
| A03 | XRAI hoş geldin | A — Satın alma ve onboarding | MERGED | free | absorbed into contract/tab |
| A04 | Gizlilik tanıtımı | A — Satın alma ve onboarding | MERGED | privacy | absorbed into contract/tab |
| A05 | Kimlik bilgileri | A — Satın alma ve onboarding | MERGED | self | absorbed into contract/tab |
| A06 | Doğum bağlamı | A — Satın alma ve onboarding | MERGED | free | absorbed into contract/tab |
| A07 | Mini kişilik keşfi | A — Satın alma ve onboarding | DROPPED_NOT_YET_DETAILED | - | mini personality discovery at onboarding; no v3.2 contract (psychology is P07, ADR-008 BLOCKED) |
| A08 | Merak keşfi | A — Satın alma ve onboarding | MERGED | self | absorbed into contract/tab |
| A09 | Yaşam yönü seçimi | A — Satın alma ve onboarding | MERGED | path | absorbed into contract/tab |
| A10 | İlk kişisel atlas | A — Satın alma ve onboarding | MERGED | self | absorbed into contract/tab |
| B01 | Bugün ana ekranı | B — Bugün | KEPT | today | direct counterpart |
| B02 | Enerji check-in | B — Bugün | MERGED | today | absorbed into contract/tab |
| B03 | Günün sembolik teması | B — Bugün | MERGED | today | absorbed into contract/tab |
| B04 | Günün anlamlı eylemi | B — Bugün | MERGED | today | absorbed into contract/tab |
| B05 | Gün planlayıcısı | B — Bugün | MERGED | path | absorbed into contract/tab |
| B06 | Bildirim merkezi | B — Bugün | DROPPED_NOT_YET_DETAILED | - | notification centre; no v3.2 contract (see XRAI32-MISSING-002) |
| B07 | Akşam yansıtma | B — Bugün | MERGED | today | absorbed into contract/tab |
| B08 | Haftalık öngörü/gözlem | B — Bugün | MERGED | path | absorbed into contract/tab |
| C01 | Kimlik atlası | C — Ben | KEPT | self | direct counterpart |
| C02 | Kanıt portresi | C — Ben | MERGED | self | absorbed into contract/tab |
| C03 | Kişilik keşfi | C — Ben | MERGED | self | absorbed into contract/tab |
| C04 | Değerlerim | C — Ben | MERGED | self | absorbed into contract/tab |
| C05 | Becerilerim | C — Ben | MERGED | self | absorbed into contract/tab |
| C06 | Meraklarım | C — Ben | MERGED | self | absorbed into contract/tab |
| C07 | Yaşam zaman çizelgesi | C — Ben | MERGED | self | absorbed into contract/tab |
| C08 | Hafıza gezgini | C — Ben | MERGED | self | absorbed into contract/tab |
| C09 | Bu çıkarım neden var? | C — Ben | MERGED | self | absorbed into contract/tab |
| D01 | Keşif evreni | D — Keşfet | KEPT | explore | direct counterpart |
| D02 | Doğum ayrıntıları | D — Keşfet | MERGED | self | absorbed into contract/tab |
| D03 | Numeroloji atlası | D — Keşfet | MERGED | explore | absorbed into contract/tab |
| D04 | Hesaplama dökümü | D — Keşfet | MERGED | explore | absorbed into contract/tab |
| D05 | Astroloji haritası | D — Keşfet | MERGED | explore | absorbed into contract/tab |
| D06 | Transit keşfi | D — Keşfet | MERGED | explore | absorbed into contract/tab |
| D07 | Human Design BodyGraph | D — Keşfet | KEPT | atlas | direct counterpart |
| D08 | HD kapılar ve kanallar | D — Keşfet | MERGED | atlas | absorbed into contract/tab |
| D09 | HD ileri analiz | D — Keşfet | MERGED | atlas | absorbed into contract/tab |
| D10 | El görüntüsü yakalama | D — Keşfet | DROPPED_NOT_YET_DETAILED | - | palm image capture; no v3.2 contract (XRAI-FACE_PALM P8) |
| D11 | El sembolizmi | D — Keşfet | DROPPED_NOT_YET_DETAILED | - | palm symbolism; no v3.2 contract |
| D12 | Yüz geometrisi | D — Keşfet | DROPPED_NOT_YET_DETAILED | - | face geometry; no v3.2 contract |
| D13 | Fizyonomi tarihi | D — Keşfet | DROPPED_NOT_YET_DETAILED | - | physiognomy history; no v3.2 contract |
| D14 | Ev ve yer numerolojisi | D — Keşfet | MERGED | explore | absorbed into contract/tab |
| E01 | Future Self | E — Yolum | MERGED | path | absorbed into contract/tab |
| E02 | Gelecek senaryosu oluşturucu | E — Yolum | MERGED | path | absorbed into contract/tab |
| E03 | Senaryo karşılaştırma | E — Yolum | MERGED | path | absorbed into contract/tab |
| E04 | Hedef merkezi | E — Yolum | KEPT | path | direct counterpart |
| E05 | Beceri açığı | E — Yolum | MERGED | path | absorbed into contract/tab |
| E06 | Öğrenme rotası | E — Yolum | MERGED | explore | absorbed into contract/tab |
| E07 | Kaynak ayrıntısı | E — Yolum | MERGED | explore | absorbed into contract/tab |
| E08 | XRAI etkileşimli ders | E — Yolum | MERGED | explore | absorbed into contract/tab |
| E09 | Dış kaynak geçişi | E — Yolum | MERGED | explore | absorbed into contract/tab |
| E10 | Gerçek dünya görevi | E — Yolum | MERGED | path | absorbed into contract/tab |
| E11 | Beceri değerlendirmesi | E — Yolum | MERGED | path | absorbed into contract/tab |
| E12 | Gelişim kanıtları | E — Yolum | MERGED | path | absorbed into contract/tab |
| F01 | Kişisel rehber | F — XRAI Rehber | KEPT | guide | direct counterpart |
| F02 | Sokratik keşif | F — XRAI Rehber | MERGED | guide | absorbed into contract/tab |
| F03 | Future Self Mentor | F — XRAI Rehber | MERGED | guide | absorbed into contract/tab |
| F04 | Karar keşfi | F — XRAI Rehber | MERGED | guide | absorbed into contract/tab |
| F05 | Gerekçe ve kaynaklar | F — XRAI Rehber | MERGED | guide | absorbed into contract/tab |
| F06 | Öneri geribildirimi | F — XRAI Rehber | MERGED | guide | absorbed into contract/tab |
| F07 | Sesli etkileşim | F — XRAI Rehber | DROPPED_NOT_YET_DETAILED | - | voice interaction; no v3.2 contract (XRAI32-MISSING-025) |
| F08 | Destek ve güvenlik | F — XRAI Rehber | DROPPED_NOT_YET_DETAILED | - | safety/support; no v3.2 contract (XRAI32-MISSING-020) |
| G01 | Ayarlar | G — Ayarlar / Gizlilik | MERGED | privacy | absorbed into contract/tab |
| G02 | İzinler | G — Ayarlar / Gizlilik | KEPT | privacy | direct counterpart |
| G03 | Ortak zekâya katkı | G — Ayarlar / Gizlilik | MERGED | privacy | absorbed into contract/tab |
| G04 | AI servis izinleri | G — Ayarlar / Gizlilik | MERGED | privacy | absorbed into contract/tab |
| G05 | Veri dışa aktarma | G — Ayarlar / Gizlilik | MERGED | privacy | absorbed into contract/tab |
| G06 | Veri ve hesap silme | G — Ayarlar / Gizlilik | MERGED | privacy | absorbed into contract/tab |
| G07 | Bildirim tercihleri | G — Ayarlar / Gizlilik | DROPPED_NOT_YET_DETAILED | - | notification preferences; no v3.2 contract |
| G08 | Offline ve senkronizasyon | G — Ayarlar / Gizlilik | DROPPED_NOT_YET_DETAILED | - | offline & E2EE sync; sync has no v3.2 contract (XRAI32-MISSING-022) |
| G09 | Satın alma ve erişim hakları | G — Ayarlar / Gizlilik | MERGED | store | absorbed into contract/tab |
| G10 | Hukuk ve bilgi kaynakları | G — Ayarlar / Gizlilik | DROPPED_NOT_YET_DETAILED | - | legal & source info screen; no v3.2 contract (XRAI32-MISSING-033) |
| G11 | Erişilebilirlik ve dil | G — Ayarlar / Gizlilik | DROPPED_NOT_YET_DETAILED | - | accessibility & language settings; cross-cutting design_quality only, no settings contract |
| G12 | Yardım ve geri bildirim | G — Ayarlar / Gizlilik | DROPPED_NOT_YET_DETAILED | - | help & feedback; no v3.2 contract (XRAI32-MISSING-032) |
| H01 | Operasyon görünümü | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H02 | Bilgi kaynağı kayıtları | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H03 | Kaynak kalite stüdyosu | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H04 | Haklar ve lisanslar | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H05 | Ajan ve model kayıtları | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H06 | Değerlendirme laboratuvarı | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H07 | Güvenlik olay merkezi | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H08 | Deney ve dağıtım | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H09 | Maliyet zekâsı | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H10 | Gizlilik ve denetim | H — Operasyon panelleri | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| M01 | Life Path ücretsiz önizleme detayı | M — Freemium ve Viral | KEPT | free | direct counterpart |
| M02 | Premium abonelik paywall | M — Freemium ve Viral | KEPT | store | direct counterpart |
| M03 | Gizlilik kontrollü paylaşım kartı | M — Freemium ve Viral | DROPPED_NOT_YET_DETAILED | - | share card; no v3.2 contract (XRAI32-MISSING-021) |
| M04 | Davet ve kampanya karşılama akışı | M — Freemium ve Viral | DROPPED_NOT_YET_DETAILED | - | referral landing; no v3.2 contract (XRAI32-MISSING-021) |
| H11 | Growth Acquisition Analytics | H — Operasyon | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H12 | Paywall & Growth Experiment Console | H — Operasyon | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H13 | Campaign and ASO Studio | H — Operasyon | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| H14 | Referral Integrity & Abuse Console | H — Operasyon | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| L01 | Yıllık Pusula & Life Compass | L — Lifelong Evolution | MERGED | path | absorbed into contract/tab |
| L02 | 90 Günlük Kilometre Taşları | L — Lifelong Evolution | MERGED | path | absorbed into contract/tab |
| L03 | Aylık Gelişim Sprinti | L — Lifelong Evolution | MERGED | path | absorbed into contract/tab |
| L04 | Haftalık Plan ve Yansıtma | L — Lifelong Evolution | MERGED | path | absorbed into contract/tab |
| L05 | Yıllar İçinde Gelişim & Life Chapters | L — Lifelong Evolution | MERGED | self | absorbed into contract/tab |
| L06 | Yeniden Planlama / Ara Ver / Devam Et | L — Lifelong Evolution | MERGED | path | absorbed into contract/tab |
| I01 | Başlangıç Düzeyi ve Başarı Tanımı | I — Real-World Impact & Proof | MERGED | path | absorbed into contract/tab |
| I02 | Somut Kanıt Kaydı | I — Real-World Impact & Proof | MERGED | path | absorbed into contract/tab |
| I03 | Beceri Gösterimi | I — Real-World Impact & Proof | MERGED | path | absorbed into contract/tab |
| I04 | Gerçek Hayata Aktarım ve Takip | I — Real-World Impact & Proof | MERGED | path | absorbed into contract/tab |
| I05 | Gerçek Yaşam Etkisi Haritası | I — Real-World Impact & Proof | MERGED | path | absorbed into contract/tab |
| I06 | Kanıtı İncele, Düzelt ve İtiraz Et | I — Real-World Impact & Proof | MERGED | path | absorbed into contract/tab |
| Q01 | Ölçüm ve Kanıt Bütünlüğü | Q — Impact and Global Quality Operations | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| Q02 | Gerçek Yaşam Etki Laboratuvarı | Q — Impact and Global Quality Operations | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| Q03 | Küresel Ürün Kalitesi ve Mağaza Analitiği | Q — Impact and Global Quality Operations | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| PUP01 | Purpose Discovery Welcome | ValuesGoals | MERGED | path | absorbed into contract/tab |
| PUP02 | My Values & Meaning Compass | MeaningReflection | MERGED | path | absorbed into contract/tab |
| PUP03 | Possible Purpose Hypotheses | FutureSelf | MERGED | path | absorbed into contract/tab |
| PUP04 | First Purpose Experiment | Learning | MERGED | explore | absorbed into contract/tab |
| PUP05 | Meaning Reflection and Revision | Reflect | MERGED | path | absorbed into contract/tab |
| PUP06 | Nonlinear Flourishing Reflection | Identity | MERGED | self | absorbed into contract/tab |
| PUP07 | XRAI Deep Atlas Evidence Explorer | Identity | MERGED | self | absorbed into contract/tab |
| PUP08 | Strict Local-Only Mode & Traffic Status | Privacy | MERGED | privacy | absorbed into contract/tab |
| PUP09 | Birth-Time Sensitivity and HD Trace | Symbolic | MERGED | atlas | absorbed into contract/tab |
| PUP10 | Long-Term Purpose & Impact Review | LifeJourney | MERGED | path | absorbed into contract/tab |
| OPS01 | Book Source & Rights Research Console | Research | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| OPS02 | Human Design Method & Fixture Audit | Quality | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| OPS03 | Meaning Claims & Safety Evaluation | Safety | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| UHA01 | Interpretation Lens Picker | Keşfet | MERGED | explore | absorbed into contract/tab |
| UHA02 | Universal Human Atlas Overview | Ben | MERGED | self | absorbed into contract/tab |
| UHA03 | Optional Cultural Context | Ben | MERGED | self | absorbed into contract/tab |
| UHA04 | Name & Life History Timeline | Ben | MERGED | self | absorbed into contract/tab |
| UHA05 | Family Story & Sibling Order | Ben | MERGED | self | absorbed into contract/tab |
| UHA06 | Astrocartography Earth Map | Keşfet | MERGED | local | absorbed into contract/tab |
| UHA07 | Local Space Compass | Keşfet | KEPT | local | direct counterpart |
| UHA08 | Relocated Chart Comparison | Keşfet | MERGED | local | absorbed into contract/tab |
| UHA09 | Travel Space Variant Explorer | Keşfet | MERGED | local | absorbed into contract/tab |
| UHA10 | Places: Symbolism vs Practical Reality | Keşfet | MERGED | local | absorbed into contract/tab |
| UHA11 | Why This Insight / How Calculated | Ben | MERGED | self | absorbed into contract/tab |
| UHA12 | Mood, Relationships & Boundaries | XRAI | MERGED | guide | absorbed into contract/tab |
| UHAOPS01 | Tradition/Source/Rights Registry | Operasyon | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| UHAOPS02 | AstroLocation Numerical Reference Lab | Operasyon | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| UHAOPS03 | Sensitive Egress & App Review Lab | Operasyon | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| ST01 | Life Coherence — değer ve eylem | Ben | MERGED | self | absorbed into contract/tab |
| ST02 | Flourishing Balance & Rest | Bugün | MERGED | today | absorbed into contract/tab |
| ST03 | Independence Mode & Graduation | XRAI | MERGED | guide | absorbed into contract/tab |
| ST04 | My Relationships — boundaries | Ben | MERGED | self | absorbed into contract/tab |
| ST05 | Connection Reflection | Yolum | MERGED | path | absorbed into contract/tab |
| ST06 | My Contribution Paths | Yolum | MERGED | path | absorbed into contract/tab |
| ST07 | Contribution Evidence & Limits | Yolum | MERGED | path | absorbed into contract/tab |
| ST08 | Wisdom Conversation | XRAI | MERGED | wisdom | absorbed into contract/tab |
| ST09 | Awe & Wonder Studio | Keşfet | MERGED | wisdom | absorbed into contract/tab |
| ST10 | Life Chapters & Legacy | Ben | MERGED | self | absorbed into contract/tab |
| ST11 | Meaning Beyond Self Review | Yolum | MERGED | path | absorbed into contract/tab |
| ST12 | Your Boundaries & Why | XRAI | MERGED | guide | absorbed into contract/tab |
| STO01 | Transcendence Content Rights Studio | Operations | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |
| STO02 | Agency, Bias & Safety Evaluation | Operations | DROPPED_NOT_YET_DETAILED | - | admin/ops console; v3.2 §71 is native iOS only, no ops surface in the 12 contracts (XRAI32-MISSING-026) |

Additional contextual surfaces named in §32.13 (lines 28236–28249: Growth Compass, Learn Now Sheet, Knowledge World Portal, Mission Studio, Proof & Reflection, Independent Mode, Service Unavailable, Data Share Preview & Revoke) are not among the 148 ids and not among the 12 contracts; they are recorded here as spec-level surfaces without contracts.

## 4. Roles / agent cards

**Finding:** 43 unique `agentId`s exist across the four historical card files (48 entries; the 5 v1.1 purpose cards are repeated verbatim in the v1.2 delta-15 file): 20 (v1.0) + 5 (v1.1) + 10 new (v1.2) + 8 (v1.3) = 43, matching `XRAI_AGENT_DELTA_8_v1.3.json` `expected_total: 43`. Separately, `XRAI_AGENT_SKILL_POLICY_CARDS_v1.7.json` defines 16 logical roles (`mode: logical_roles_not_llms`, ids CORE-01..16) that re-cut the same duties; v3.1 §61 (lines 358–362) lists 19 'minimum specialists' and says 'Historical 43 roles remain in v3 registry, but not 43 running networks'; v3.2 §72 (line 31) reduces runtime to nine bounded control functions.

**Roles are review responsibilities, not 43 concurrent model calls.** Evidence: v1.7 `mode: logical_roles_not_llms`; §31.2 heading '12 competence engines: contracts, not 12 AI calls' (line 26935); §34.3 'NINE GOVERNED RESPONSIBILITIES, NOT NINE LLMS' (line 30472); GAP-011 and GAP-027 (lines 877, 906) treat 43 personas / council of 43 calls as failure modes; requirement XRAI-BRAIN_9RESP.

| agentId | first file | duty class | purpose (from card) |
|---|---|---|---|
| IntentRouter | v1.0 | EXPERIENCE/UX | user-provided request to limited relevant domain tasks |
| PrivacySecurityGuardian | v1.0 | SECURITY/PRIVACY | evaluate purpose, data class, consent, tool access |
| ClaimVerifier | v1.0 | KNOWLEDGE/SOURCE | source/method/uncertainty trace and unsupported claim rejection |
| IdentitySpecialist | v1.0 | RESEARCH | interpret self-report/validated assessments without diagnosing |
| NumerologySpecialist | v1.0 | COMPUTATION | compute compound/root/name with deterministic trace |
| AstronomySpecialist | v1.0 | COMPUTATION | historical timezone and ephemeris computation after rights check |
| HumanDesignSpecialist | v1.0 | COMPUTATION | calculate charts and explain licensed, source-tagged mechanics |
| MemoryCurator | v1.0 | SECURITY/PRIVACY | retrieve/update user-approved temporal memories |
| FutureScenarioPlanner | v1.0 | EXPERIENCE/UX | propose alternative user chosen futures and goal dependencies |
| SkillGraphPlanner | v1.0 | KNOWLEDGE/SOURCE | map goals to prerequisites and reasonable skill gaps |
| LearningResourceResearcher | v1.0 | KNOWLEDGE/SOURCE | candidate resources with rights/access/level/cost checked |
| PedagogyDesigner | v1.0 | KNOWLEDGE/SOURCE | original micro lessons, practice and rubrics |
| ProofEvaluator | v1.0 | RESEARCH | assess P0-P5 evidential levels and distinguish causality |
| SocraticMentor | v1.0 | EXPERIENCE/UX | context aware respectful questions/alternative perspectives |
| DailyAlignment | v1.0 | EXPERIENCE/UX | one actionable feasible step or rest |
| AttentionGuardian | v1.0 | EXPERIENCE/UX | limit messaging and respect quiet hours |
| CollectiveLearningEvaluator | v1.0 | RESEARCH | aggregate legitimate resource feedback and test changes |
| GrowthEthicsReviewer | v1.0 | RELEASE/OPS | evaluate paywall, referral and ASO claims |
| ReleaseIndependentReviewer | v1.0 | RELEASE/OPS | challenge builder evidence and run separate adversarial set |
| OpsFailureInvestigator | v1.0 | RELEASE/OPS | triage containment/rollback, observable actual fix |
| PurposeDiscoveryFacilitator | v1.1 | EXPERIENCE/UX | support user-authored purpose hypotheses and Socratic meaning exploration |
| HumanFlourishingResearcher | v1.1 | RESEARCH | interpret historical Maslow and limitations nonlinearly |
| HDMethodAuditor | v1.1 | COMPUTATION | audit ephemeris, gate mapping, 88deg root and independent fixtures |
| BookResearchRightsCurator | v1.1 | KNOWLEDGE/SOURCE | record book provenance, licensed facts and legal gates without copying expression |
| DevicePrivacyEgressAuditor | v1.1 | SECURITY/PRIVACY | independently test that sensitive data remain local |
| UniversalLensCurator | v1.2 | KNOWLEDGE/SOURCE | Classifies traditions, rights, epistemic families and overlapping schools |
| AstroLocationMathEngineer | v1.2 | COMPUTATION | Computes independent geometry for ACG/Local Space/relocation with reference fixtures |
| AstroLocationInterpretationSafety | v1.2 | KNOWLEDGE/SOURCE | Separates symbolic line geography from evidence-based practical travel |
| LocalSensitiveContextGovernor | v1.2 | SECURITY/PRIVACY | Purpose-scoped field access and special-category privacy firewall |
| PurposePossibilityMentor | v1.2 | EXPERIENCE/UX | Offers values-based possibility hypotheses and small voluntary experiments |
| ScientificMisuseAuditor | v1.2 | KNOWLEDGE/SOURCE | Blocks quantum double slit and E=mc2 misuse as psychology proofs |
| CulturalRespectAndRightsReviewer | v1.2 | KNOWLEDGE/SOURCE | Checks origins, indigenous/closed spiritual traditions and legal usage |
| SoftUXCompressionDesigner | v1.2 | EXPERIENCE/UX | Compresses deep system to one action and transparent progressive disclosure |
| AstroEphemerisLicensingGate | v1.2 | KNOWLEDGE/SOURCE | Checks redistributable offline ephemeris artefacts and contract compliance |
| PersonalContextPrivacyRedTeam | v1.2 | SECURITY/PRIVACY | Runs actual app tracing/storage/sync/analytics/SDK exfil tests |
| LifeCoherenceAgent | v1.3 | EXPERIENCE/UX | Link values to actual opt-in actions without judging personality |
| FlourishingBalanceGovernor | v1.3 | EXPERIENCE/UX | Reduce overburden; ensure agency and rest options |
| AutonomyGraduationGuide | v1.3 | EXPERIENCE/UX | Teach users to make plans without dependence on XRAI |
| ConnectionEthicsCoach | v1.3 | EXPERIENCE/UX | Communication role play without profiling third parties |
| ContributionOpportunityCurator | v1.3 | KNOWLEDGE/SOURCE | Suggest voluntary and safe contribution activities |
| WisdomPerspectiveFacilitator | v1.3 | EXPERIENCE/UX | Generate evidence-bound alternatives and counterarguments |
| AweCuriosityCurator | v1.3 | KNOWLEDGE/SOURCE | Offer permissioned science, art and contemplative exercises |
| LifeChapterArchivist | v1.3 | SECURITY/PRIVACY | Make reversible private stories and portable exports |

Duty-class totals (43 cards): COMPUTATION 5, EXPERIENCE/UX 13, KNOWLEDGE/SOURCE 12, RELEASE/OPS 3, RESEARCH 4, SECURITY/PRIVACY 6.

v1.7 logical roles (16): CORE-01 PrivacyGovernor → SECURITY/PRIVACY, CORE-02 VaultCustodian → SECURITY/PRIVACY, CORE-03 MethodRegistryAgent → KNOWLEDGE/SOURCE, CORE-04 AstroCalculationAgent → COMPUTATION, CORE-05 HumanDesignMethodAgent → COMPUTATION, CORE-06 ProvenanceAuditor → KNOWLEDGE/SOURCE, CORE-07 PersonalMemoryCustodian → SECURITY/PRIVACY, CORE-08 GoalPlanner → EXPERIENCE/UX, CORE-09 LearningResolver → KNOWLEDGE/SOURCE, CORE-10 ProofVerifier → RESEARCH, CORE-11 HistoricalMentorGuide → KNOWLEDGE/SOURCE, CORE-12 LocalModelRouter → COMPUTATION, CORE-13 CollectiveLearningGovernor → RESEARCH, CORE-14 AHTOVIABridgeGuard → SECURITY/PRIVACY, CORE-15 AppStoreReleaseAuditor → RELEASE/OPS, CORE-16 ModelUpdateSafetyGovernor → RELEASE/OPS.

Access responsibility note: every card carries `allowedCapabilities` / `forbidden` (v1.0–v1.3) or `typedContracts` / `hardVeto` / `localFirst` (v1.7); XRAI31-OCTOPUS-LEAST-PRIVILEGE requires scoped data per role. None of these cards is implemented (all `status: SPECIFIED_NOT_IMPLEMENTED`).

## 5. Methods (19) — ORIGINAL_MATH_METHOD_REGISTRY_v3.2.json

`independent_algorithm_specified` = the registry text (plus v3.2 §75–§79, lines 48–72) states an algorithm that can be implemented and golden-tested without copying a protected source; PARTIAL = the arithmetic is independent but an input table/dataset is not registered.

| method_id | epistemic_class | activation_gate | design_only | independent_algorithm_specified | coded | tested | reason |
|---|---|---|---|---|---|---|---|
| num.life_path.digits.v1 | EXACT_MATH | METHOD_ORIGINAL_AND_REFERENCES | YES (DESIGN_ONLY_NOT_TESTED) | YES | CODED_PENDING_TEST_EVIDENCE (see docs/status/TEST_EVIDENCE_LEDGER.json) | NOT ASSERTED HERE (ledger: run1 2/35 failed, run3 35/35 exit 0; see docs/status/TEST_EVIDENCE_LEDGER.json) | self-contained digit arithmetic; hand-derived fixtures in BOOT_01_HAND_DERIVED_FIXTURES.md |
| num.name.pythagorean.v1 | EXACT_MATH | METHOD_ORIGINAL_AND_REFERENCES | YES (DESIGN_ONLY_NOT_TESTED) | YES | NO | NO | letter map + Unicode policy is declared in the spec; Turkish mapping must be chosen explicitly (§75) |
| num.personal_cycles.v1 | EXACT_MATH | METHOD_ORIGINAL_AND_REFERENCES | YES (DESIGN_ONLY_NOT_TESTED) | YES | NO | NO | arithmetic on dates; year convention must be versioned |
| num.place_names.v1 | SYMBOLIC_ASSOCIATION | METHOD_ORIGINAL_AND_REFERENCES | YES (DESIGN_ONLY_NOT_TESTED) | PARTIAL | NO | NO | lettering arithmetic is independent; etymology sources are not |
| astro.ephemeris.position.v1 | EXACT_MATH | LICENSE_AND_CALIBRATION | YES (DESIGN_ONLY_NOT_TESTED) | NO | NO | NO | positions come from a licensed ephemeris/JPL dataset; no independent algorithm in repo (ADR-007 BLOCKED) |
| astro.natal_chart.v1 | HISTORICAL_TRADITION | LICENSE_AND_METHOD_VARIANTS | YES (DESIGN_ONLY_NOT_TESTED) | PARTIAL | NO | NO | house/aspect geometry specifiable; depends on ephemeris positions and tradition variants |
| astro.local_space.v1 | EXACT_MATH | LICENSE_AND_REFERENCE_FIXTURE | YES (DESIGN_ONLY_NOT_TESTED) | YES | NO | NO | spherical geometry (azimuth/altitude/geodesic) fully specifiable without protected sources; needs positions as input |
| astro.astrocartography.v1 | HISTORICAL_TRADITION | EPHEMERIS_RIGHTS | YES (DESIGN_ONLY_NOT_TESTED) | PARTIAL | NO | NO | angle-line geometry specifiable; requires licensed positions |
| astro.traditional_methods.v1 | HISTORICAL_TRADITION | TRANSLATION_SOURCE_REVIEW | YES (DESIGN_ONLY_NOT_TESTED) | NO | NO | NO | edition/translation-dependent rule tables not yet registered (SOURCE_RIGHTS NOT_ALL_APPROVED) |
| hd.design_sun_minus_88deg.v1 | EXACT_MATH | EPHEMERIS_AND_HD_METHOD_RIGHTS | YES (DESIGN_ONLY_NOT_TESTED) | YES | NO | NO | root-finding equation stated in §78; needs a licensed solar longitude function as input |
| hd.gate_line_map.v1 | HISTORICAL_TRADITION | BLOCKED_UNTIL_SOURCE_METHOD | YES (DESIGN_ONLY_NOT_TESTED) | NO | NO | NO | gate-wheel order/anchor not independently verified; gate BLOCKED_UNTIL_SOURCE_METHOD |
| hd.bodygraph.v1 | HISTORICAL_TRADITION | BLOCKED_UNTIL_INDEPENDENT_FIXTURE | YES (DESIGN_ONLY_NOT_TESTED) | NO | NO | NO | channel/centre/type/authority tables depend on gate map and tradition variant; BLOCKED_UNTIL_INDEPENDENT_FIXTURE |
| psych.big_five.v1 | SOURCED_EMPIRICAL | LICENSED_QUESTIONNAIRE_VALIDATION | YES (DESIGN_ONLY_NOT_TESTED) | NO | NO | NO | scoring depends on a licensed item bank that is not registered |
| psych.16_exploratory.v1 | MODEL_HYPOTHESIS | BRAND_AND_SCALE_RIGHTS | YES (DESIGN_ONLY_NOT_TESTED) | NO | NO | NO | original questionnaire not authored; brand/scale rights open (ADR-008) |
| cabala.gematria.v1 | HISTORICAL_TRADITION | TRADITION_SOURCE_RIGHTS | YES (DESIGN_ONLY_NOT_TESTED) | PARTIAL | NO | NO | alphabet arithmetic trivial once a versioned letter table is registered; table not registered |
| iching.hexagrams.v1 | HISTORICAL_TRADITION | RIGHTS_AND_SOURCED_TRADITION | YES (DESIGN_ONLY_NOT_TESTED) | PARTIAL | NO | NO | 64-binary mapping is trivial; interpretation sourcing open |
| bazi.solar_terms.v1 | HISTORICAL_TRADITION | METHOD_REFERENCE_VERIFICATION | YES (DESIGN_ONLY_NOT_TESTED) | PARTIAL | NO | NO | sexagenary arithmetic specifiable; solar-term boundaries need an astronomical method and calendar source |
| energy.physical_frequency.v1 | EXACT_MATH | REAL_SENSOR_AND_PERMISSION | YES (DESIGN_ONLY_NOT_TESTED) | YES | NO | NO | Fourier/period estimation on a measured signal; standard DSP |
| purpose.parallel_lenses.v1 | MODEL_HYPOTHESIS | EPISTEMIC_REVIEW | YES (DESIGN_ONLY_NOT_TESTED) | NO | NO | NO | policy/presentation rule, not a mathematical method; MODEL_HYPOTHESIS class |

Additional method introduced in BOOT-01 and not yet in the registry: `num.life_path.components.v1` (docs/status/BOOT_01_HAND_DERIVED_FIXTURES.md, 'Method definitions under test' and Amendment A1 / ADR-BOOT-004) — state CODED_PENDING_TEST_EVIDENCE (see docs/status/TEST_EVIDENCE_LEDGER.json); must be appended to the registry, not replace anything. Test evidence on disk at audit time (`docs/status/TEST_EVIDENCE_LEDGER.json`): BOOT01-TEST-RUN1 `swift test` failed 2 of 35 (F11, `docs/status/evidence/swift_test_run1_FAILED_2_of_35.log`); BOOT01-TEST-RUN3 `swift test` exit 0, 35 tests in 7 suites passed (`docs/status/evidence/swift_test_run3_PASS_35_of_35.log`, sha256 d2aabfdb…). The ledger's own `statuses` block marks `time.civil_date.gregorian.v1`, `num.life_path.digits.v1` and `num.life_path.components.v1` as TESTED; this audit did not execute or re-verify those runs, so it records the state string required by the BOOT-00 brief and leaves the TESTED promotion to the parent's report and the independent reviewer. The registry file itself still says DESIGN_ONLY_NOT_TESTED for all 19 and has not been updated.

Independence summary: YES 6, PARTIAL 6, NO 7; coded 1 (pending evidence); tested 0.

## 6. Human Design source coverage

Inputs: `docs/registries/historical_v3.0/HUMAN_DESIGN_SOURCE_COVERAGE_v3.json`, `HUMAN_DESIGN_298_IMAGE_PAGE_TRACKER.csv` (298 rows), `docs/audits/XRAI_HUMAN_DESIGN_DUPLICATE_AND_COVERAGE_AUDIT_2026-10-19.md`, `docs/audits/XRAI_V3_2_KAPSAM_EKSIK_VE_CLAUDE_DENETIMI_2026-10-19.md` §3, `SOURCE_AND_ARTIFACT_PROVENANCE_v3.json`, scratchpad `BATCH1_ANALYSIS_NOTES.md`. The PDFs themselves were not opened.

- Inventory: 13 unique PDFs, 298 PDF image frames (17 uploads; 4 later files byte-identical by SHA-256 to earlier ones — duplicate audit table). `all_rows_have_scan_ids: true`.
- Review level: `review_level: VISUAL_OVERVIEW`, `detailed_review_remaining: 298`. Tracker columns: overview_check {'VISUAL_OVERVIEW_COMPLETE': 298}; line_by_line_check {'PENDING_DETAILED_READING': 298}; calculation_rules_status {'NOT_VERIFIED': 298}; printed_book_page_number {'NOT_VERIFIED_PER_SCAN': 298}; commercial_reuse {'RIGHTS_REVIEW_REQUIRED': 298}.
- Image quality flags: {'UNVERIFIED_READABILITY': 291, 'CRITICAL_EDGE_ON_UNREADABLE': 3, 'DARK_LOW_CONTRAST': 4}. Frames flagged unreadable/dark: Human desing.pdf p16 (HD-B1-01-016: CRITICAL_EDGE_ON_UNREADABLE); Human desing3(1).pdf p3 (HD-B1-03-003: DARK_LOW_CONTRAST); Human desing4.pdf p3 (HD-B1-04-003: DARK_LOW_CONTRAST); Human desng9.pdf p8 (HD-B1-09-008: CRITICAL_EDGE_ON_UNREADABLE); Human desng9.pdf p17 (HD-B1-09-017: CRITICAL_EDGE_ON_UNREADABLE); Human design 12.pdf p12 (HD-B1-12-012: DARK_LOW_CONTRAST); Human design 12.pdf p20 (HD-B1-12-020: DARK_LOW_CONTRAST). These 7 flags agree with BATCH1_ANALYSIS_NOTES.md (desing.pdf 16, desng9.pdf 8/17, design 12.pdf 12/20) and add two dark frames (desing3(1).pdf 3, desing4.pdf 3); the remaining 291 rows are UNVERIFIED_READABILITY, i.e. readability has not been confirmed for any frame.
- Missing/uncertain printed pages: printed pp. 1–8 (cover, imprint, contents) are absent — first visible printed page is 9 (duplicate audit, 'Basılı sayfa aralığının sınır kontrolü'); printed p. 300 is not proven present (file 12 ends at 299, file 13 starts at 301); `known_uncertainties` in HUMAN_DESIGN_SOURCE_COVERAGE_v3.json repeat these plus 'warped/or too dark frames and facing pages' and 'full citation/copyright edition not verified'. One PDF image can hold two printed pages, so 298 frames ≠ 298 printed pages.
- Licence status: `not_licensed_for_app_corpus: True`; SOURCE_RIGHTS_AND_EVIDENCE_v3.1 HD_PARKYN_TR rights `PRIVATE_STUDY_ONLY_PENDING_RIGHTS`, status NOT_ALL_APPROVED; SOURCE_INVENTORY rows `PRIVATE_BOOK_SCAN_INDEXED_NOT_LICENSED_FOR_APP`; OPEN_DECISIONS HD_TRANSLATION_COPYRIGHT and HD_METHOD_COMPLETENESS both OPEN_UNVERIFIED; v3.2 §78 (line 66): private study/indexing, not a licensable corpus.
- **Explicit statement: the Human Design research is NOT complete.** 0 of 298 frames has a detailed (line-by-line) reading; 0 calculation rules are verified from the source; the 88° design-time method, gate-wheel order/anchor and type/authority decision tables are not confirmed from the book (BATCH1 notes S1, S6; methods hd.* all DESIGN_ONLY_NOT_TESTED; ADR-009 BLOCKED).

## 7. Tooling

Not audited in this document (parent task). See `docs/tools/` (`EXTERNAL_REPO_PINS.txt`, 11 pinned repos).

## 8. Open decisions: 16 vs 20 reconciliation

Where the '20' comes from: `CLAUDE_FIRST_SESSION_v3.2.md` line 9 ('20 open decisions'), `PHASE_EXECUTION_DAG_v3.1.json` P00 exit_evidence ('source authority and 20 blockers status') and `TASK_DEPENDENCY_GRAPH_v3.1.json` line 28. The only 20-record file is `docs/registries/historical_v3.0/OPEN_BLOCKERS_v3.json` (generated 2026-10-19, ids below). `docs/registries/OPEN_DECISIONS_v3.1.json` has 16 records. All 36 records are `OPEN_UNVERIFIED`.

| v3.0 blocker (20) | gate | v3.1 decision (16) | gate | relation |
|---|---|---|---|---|
| REPO_BASELINE | BOOT-00 | LOCAL_REPO_STATE | P00 | same topic |
| XCODE_TOOLCHAIN | BOOT-00 | — | — | no v3.1 record (IPHONE_TEST covers only the physical-phone part) |
| APP_ID_SIGNING | BOOT-00 | APPLE_ACCOUNT | P11 | merged into APPLE_ACCOUNT |
| ON_DEVICE_VAULT | P1 | JOURNAL_SECURITY | P02 | same topic (also IPHONE_TEST) |
| LOCAL_LLM_BENCH | P4 | LOCAL_ML_TURKISH | P06 | same topic |
| HD_BOOK_PARAGRAPHS | P7 | HD_METHOD_COMPLETENESS | P09 | same topic |
| HD_METHOD_RIGHTS | P7 | HD_TRANSLATION_COPYRIGHT | P09 | same topic |
| EPHEMERIS_LICENSE | P6 | EPHEMERIS_RIGHTS | P08 | same topic |
| ASTRODIEST | P6 | — | — | no v3.1 record (only SOURCE_RIGHTS_AND_EVIDENCE_v3.1 ASTROD_INFO) |
| BOOK_OF_WISDOM_COMPLETE | P8 | BOW_FULL_COVERAGE | P10 | same topic |
| ANCIENT_MODERN_EDITIONS | P6 | — | — | no v3.1 record (only SOURCE_RIGHTS_AND_EVIDENCE_v3.1 PTOLEMY/VALENS/DOROTHEUS/LILLY rows) |
| MBTI_16PSYCH_RIGHTS | P8 | PSYCHOLOGICAL_INSTRUMENT | P07 | same topic |
| MODEL_TRAINING_DATA | P4 | COLLECTIVE_RESEARCH_RIGHTS | P13 | same topic |
| AHTOVIA_TRUST | P9 | FUTURE_CHILD_SAFETY | FUTURE | partially merged (AHTOVIA boundary) |
| APP_STORE_PRICE | P3 | STOREKIT_REAL_PRICE | P11 | same topic |
| TRADEMARK | P10 | — | — | no v3.1 record (XRAI-LEGAL_IP requirement only) |
| STORE_REVIEW | P10 | APPLE_ACCOUNT | P11 | merged into APPLE_ACCOUNT |
| REPLICA_SKILL_SECURITY | BOOT-00 | — | — | no v3.1 record (only SOURCE_RIGHTS_AND_EVIDENCE_v3.1 REPLICA_SKILL) |
| DATA_RECOVERY_POLICY | P1 | DEVICE_BACKUP_POLICY | P02 | same topic |
| CHILDREN_CONSENT | P9 | FUTURE_CHILD_SAFETY | FUTURE | same topic |
| — | — | IPHONE_TEST | P02 | new in v3.1, no v3.0 blocker |
| — | — | CLOUD_CONSENT_LEGAL | P06 | new in v3.1, no v3.0 blocker |
| — | — | PARENT_NAME_SCOPE | P02 | new in v3.1, no v3.0 blocker |

Result: 20 v3.0 blockers → 12 distinct v3.1 decisions (APPLE_ACCOUNT and FUTURE_CHILD_SAFETY each absorb two); 5 v3.0 blockers have **no** v3.1 record (XCODE_TOOLCHAIN, ASTRODIEST, ANCIENT_MODERN_EDITIONS, TRADEMARK, REPLICA_SKILL_SECURITY); 3 v3.1 decisions are new (IPHONE_TEST, CLOUD_CONSENT_LEGAL, PARENT_NAME_SCOPE). Distinct open topics across both files = 16 + 5 = 21. Older lineage for reference only: 15 numbered items in `XRAI_OPEN_DECISIONS_AND_BLOCKERS_v1.0.md` and DEC-01..12 in `XRAI_EXTERNAL_DECISIONS_12_v1.6.json` (both in scratchpad pkg_v30/HISTORICAL_MACHINE_REGISTRIES).

**Recommended canonical statement:** 'The canonical open-decision register is `docs/registries/OPEN_DECISIONS_v3.1.json` (16 records). The figure 20 in `CLAUDE_FIRST_SESSION_v3.2.md` and the P00 exit evidence refers to the superseded `historical_v3.0/OPEN_BLOCKERS_v3.json` (20 records). Five v3.0 blockers (TRADEMARK, ASTRODIEST, ANCIENT_MODERN_EDITIONS, REPLICA_SKILL_SECURITY, XCODE_TOOLCHAIN) were not carried into v3.1 and remain open; they should be appended to OPEN_DECISIONS_v3.1 as new records without renumbering, giving 21 distinct open decisions. None is closed by this audit.' `docs/status/OPEN_BLOCKERS.md` (parent) marks LOCAL_REPO_STATE as RESOLVED_TODAY on the basis of `REPO_FACTS.json`; that closure is the parent's BOOT_00_REPORT decision and is not re-asserted here.

## 9. Not determined / limits of this audit

- The `swift test` runs in `docs/status/TEST_EVIDENCE_LEDGER.json` (run 1 failed 2/35, run 3 passed 35/35) were not re-executed or re-hashed by this audit; the two BOOT-01 methods therefore keep the state string CODED_PENDING_TEST_EVIDENCE here, and the TESTED promotion belongs to the parent's BOOT_00_REPORT and the independent reviewer.
- Correctness of the BOOT-01 Swift code was not reviewed here.
- Content of the HD scans, Book of Wisdom and the four classical works: NOT_AVAILABLE; statements about them are taken from the registries and audits only.
- Contents of the deleted GitHub repo and of the NUR/AUREV/AYMORA dumps: NOT_AVAILABLE.
- The v1.0–v2.0 master MD files as separate files: only their embedded copy in the constitution was checked by heading; they were not read line by line (35,131 lines).
- The MERGED/DROPPED screen classification is a reading of thin v3.2 contract text (one `user_purpose` phrase per screen); the user may reassign any row without changing counts elsewhere.

