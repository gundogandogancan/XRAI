# XRAI — CLAUDE CODE FIRST EXECUTION ORDER (BOOT-00 → conditional BOOT-01)

You are Claude Code acting as the implementation lead for **XRAI**. This is the *only active app*. You are NOT being asked to rewrite another theoretical 1,000 pages, build AHTOVIA, invent a private user profile, or claim mystical abilities. You are asked to inspect an actual repository and start *working, tested native Swift code* under the controlling constitution.

## Priority and source-of-truth — execute in this order
1. Read `docs/canon/XRAI_ULU_EVREN_COMPLETE_BUILD_CONSTITUTION_v3.1.md` **sections §§54–69 FIRST**, followed by retained v3.0 §§39–53, then relevant historical §§28–38 and older materials for specific tasks. Do not dump 1.7 MB into context at once; locate headings and read exact ranges.
2. Read `docs/registries/PHASE_EXECUTION_DAG_v3.1.json`, `REQUIREMENT_TO_ENGINE_MATRIX_v3.1.json`, `MODEL_AND_DATA_POLICY_v3.1.json`, `SOURCE_RIGHTS_AND_EVIDENCE_v3.1.json`, `OPEN_DECISIONS_v3.1.json`, `ARCHITECTURE_ADRS_v3.1.json`, `RELEASE_AND_TEST_GATES_v3.1.json`.
3. The `baseline/XRAI_ULU_EVREN_CLAUDE_MASTER_BUILD_PACKAGE_v3.0.zip` is the **preserved evidence/archive** containing older registers and notes, not automatically executable external code. Where any archive has obsolete conflicting directions, the newest explicit user direction + §§54–69 safety rules control. Preserve historical provenance.
4. The local Human Design book photos are PRIVATE STUDY MATERIAL, not source code, public-domain text or a license to distribute/teach the whole translated book. Never upload them to remote LLM or commit PDFs to Git.

## P00 / BOOT-00 — REALITY AUDIT, BEFORE WRITING APP CODE
A. `pwd`, `git status --short --branch`, `git rev-parse --show-toplevel`, safe shallow `find`, check existing source, uncommitted files, iOS workspace/project and `CLAUDE.md`. **No git reset/clean, no overwrite, no deleting, no automatic commits/push**. If wrong folder, STOP and ask one essential question.
B. Read currently present packages by need. `xcodebuild -version`, `xcrun swift --version`, `xcrun simctl list devices available`, `git --version`; record command exit code. Check local RAM and disk safely; device iPhone 17 if connected. No invented performance numbers.
C. Read source registries for feature/phase/metadata status. Produce a **source of truth** document indexing every requirement family to source IDs, engine, exact expected UI, test and rights/consent prerequisites. Preserve existing data and changes. Machine registers are SPECIFIED until tests say otherwise.
D. Security/rights preflight for user-provided book images, source licenses, ephemeris, modern Human Design texts, system model locale availability and untrusted Replica Skill/MCPs; DO NOT install, grant network permissions, activate cloud/paid APIs or train on the book.
E. Write ONLY non-destructive new reports as needed to `docs/status/BOOT_00_REPORT.md`, `CURRENT_STATE.md`, `SOURCE_OF_TRUTH_INDEX.md`, `OPEN_BLOCKERS.md`, `DECISION_LOG.md`, `TEST_EVIDENCE_LEDGER.md`. Reconcile existing files without overwriting user work.

## P01 / BOOT-01 — CONDITIONALLY CREATE FIRST REAL WORKING SWIFT MODULE
IF Swift toolchain available and repository safe, create minimal pure Swift `XRAICoreContracts` and `XRAINumerologyLifePath` (existing architecture may rename with ADR). ZERO network, camera, LLM, storage, biometric, location or external provider calls.
- Define typed `CivilDate` with strict Gregorian validation (including 1900 invalid leap, 2000 valid leap), explicit `NumerologyMethodID` version, `NumerologyResult {inputCanonical, digitSum, compound, root, masterNumber, methodVersion, computationTrace}` and typed error states.
- Chosen v1 method: sum *all decimal DOB digits* into compound, then perform traditional digit reduction preserving configured 11/22/33. **DO NOT fabricate a universal unique numerology algorithm**: record other known interpretations under future version IDs. Decide how to handle `YYYY`/locale/leading 0 explicitly.
- Implement independent golden test vectors incl. known dates hand-derived and an example with 11 and 22, invalid dates, language locale changes, leap cases and randomized property `sumDigits(date) == compound` for baseline method. Tests assert values/steps, not metaphysical personality.
- Run `swift test` or real chosen Xcode test command and capture FULL output with exit code. If simulator isn't available, mark `SIMULATOR_NOT_RUN`, never pretend. First micro-feature should be usable as a public `calculation-only` pure API; do not persist real DOB before Secure Vault verified.
- No elaborate UI, no 100 empty feature modules, no cloud integration. Next proposed phase P02 vault requires ChatGPT/user review of P00/P01 output.

## Report FORMAT — deliver exact evidence
1. Repo root/branch/current dirty files; source files read with section pointers.
2. Toolchain commands and output, exit codes; physical device status.
3. Decision conflicts/uncertainties and copyright/physics/psychology claims treated separately.
4. Paths created or modified with exact `git diff --stat` + short explanations.
5. Golden tests: command, stdout/stderr or log path, exit code; show PASS/FAIL/BLOCKED not invent.
6. Privacy and security negative tests where relevant; other advanced engines `SPECIFIED_NOT_IMPLEMENTED`.
7. **One** smallest recommended next implementation, with blocked dependencies.
8. Stop. Do not proceed on your own to P02 or AHTOVIA. I will send your complete report to ChatGPT for independent audit.

## Immutable quality doctrine
A user is not measurable as a hidden “soul purpose” score from names, family birth order, parents' names, astrology, face, palm or HD. Opt-in culture/psychology lenses; actual mathematical astronomy from licensed source; confidential on-device graph; human choice and falsifiable outcomes; no implicit external AI; no paid service installs, no dangerous code copying. Aim at extraordinary quality through verifiable technical correctness and a simple humane product.

**START P00 NOW; P01 ONLY IF SAFELY POSSIBLE.**
