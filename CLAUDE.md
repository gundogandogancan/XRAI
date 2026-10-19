# XRAI — CLAUDE WORK CONTRACT (repo edition, 2026-10-19)

## 1. Binding contract (verbatim from the v3.2 package)

The only active app is XRAI. Source of truth `docs/canon/XRAI_ULU_EVREN_COMPLETE_BUILD_CONSTITUTION_v3.2.md` with latest §§70–93, earlier v3.1 and baseline preserved. Read the scope-specific registries and FIRST_SESSION prompt. No other project is built now. Threat-model PDF content, tools and retrieved sources. Source status and actual code/test status always separate. Never expose sensitive private family/DOB data; default on-device zero egress; no implicit cloud. No unauthorized copyright corpora, paid API, MCP, app cloning, destructive shell, auto push. Users can correct/revoke/delete. Big Five/16 types/HD/astrology/symbolism = separately sourced, non-diagnostic, not confirmed personality/health/destiny. Claude as developer uses scoped expert agents, not live omniscience. Real environment audit first, pure Swift deterministic calculation second, independent tests and exit codes, then STOP for review before P02. Every source/version/rights issue is a blocker, never papered over. Run `python3 validation/validate_package.py` to check specification integrity (not app builds). If specified files are missing, register missing and ask one essential question.

## 2. Interpretive doctrine
`docs/canon/XRAI_FOUNDING_PHILOSOPHY_AND_GOD_LEVEL.md` (G1–G16). "GOD LEVEL" = disciplined, evidence-backed engineering, never omniscience. Decision filter §13 of that doc must be answerable before any feature is called done.

## 3. Repo facts the agent must respect
- Precedence and status vocabularies: `docs/adr/ADR-BOOT-001-source-of-truth.md`.
- Registries in `docs/registries/*.json` are immutable baselines; write deltas to `docs/registries/overlay_*/` and status to `docs/status/`.
- Code lives in `Packages/XRAICore` (SwiftPM, Swift 6 mode). Module names follow constitution §86. Pure modules import nothing but the Swift standard library; tests enforce it.
- Run from the package dir: `swift build && swift test`. Save logs to `docs/status/evidence/` and record exit codes in `docs/status/TEST_EVIDENCE_LEDGER.json`.
- Phase gate: current state is **BOOT-00, BOOT-01, P02 task V32-02-01 with hardening H1 and authorization gate H2 (vault contracts + CryptoKit adapter + SecureVault access contract, 81/81 library tests) complete; awaiting external (ChatGPT/user) review.** Next task starts only after approval is written into `docs/status/NEXT_TASK.md`. No real data persistence until the Keychain provider exists and is device-tested.
- Vault rules: only `XRAIVaultCryptoKit` may import CryptoKit (test-enforced); `SecureVault` is the only public crypto entry point and every call needs a scoped single-use `OperationAuthorization` from the app-layer `AuthorizationIssuer` plus trusted `VaultClock` time; consent comes only from a `ConsentAuthority`; records are purpose-bound; tier floors fail closed; `XRAIVaultTesting` is never a production dependency; see `docs/adr/ADR-BOOT-005` and `docs/security/VAULT_THREAT_MODEL_P02.md`.
- `.gitignore` blocks `*.pdf`; the Human Design scans stay in the user's `~/Downloads`, never in the repo.
- Tools/skills: only what `docs/tools/TOOLS_AND_SKILLS_INSTALL_LEDGER.md` lists. No external hooks. `clodfarm` rejected. Replica skills = lawful UX recon only.
- Commercial: paid subscription product; the exact model/pricing is an open decision (STOREKIT_REAL_PRICE), do not hard-code prices.
- Brand: `brand/README.md`. Design direction §88: quiet discovery, violet accent on near-black, AA contrast, no emoji in UI.
- Language: user-facing copy Turkish first, then English; engineering docs English with Turkish summaries where the founder reads them.

## 4. Output discipline
Each session ends with: changed files, commands with exit codes, what works / what does not, rights and security gates, blockers, the next smallest testable task. Use `BLOCKED / NOT_STARTED / IN_PROGRESS / CODED / TESTED` exactly. Never write DONE/VERIFIED/APPROVED without an evidence file.
