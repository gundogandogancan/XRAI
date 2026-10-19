# ADR-BOOT-001 — Source of truth and version precedence in this repository

**Status:** ACCEPTED (2026-10-19, BOOT-00) · **Refines:** spec ADR-001/013, constitution §40, §70 header, §93

## Context
On 2026-10-19 the previous GitHub repository content was deleted at the user's explicit request and this repository was rebuilt from scratch from four ChatGPT-authored packages (v3.0, v3.1, v3.2, founding philosophy) plus two audit notes. The v3.2 constitution is 35,131 lines and byte-preserves v3.1 and v3.0 (SHA-256 verified by `validation/validate_package.py`, exit 0). Prior chat transcripts are not available; only their distillations are.

## Decision
1. Precedence, highest first: **latest explicit user decision in this repo (recorded in `docs/status/` or an ADR) → law/safety/privacy → `docs/canon/XRAI_ULU_EVREN_COMPLETE_BUILD_CONSTITUTION_v3.2.md` §70–§93 → preserved v3.1 §54–§69 → preserved v3.0 §39–§53 → older preserved text → registries → observed repo evidence.** `docs/canon/XRAI_FOUNDING_PHILOSOPHY_AND_GOD_LEVEL.md` is an interpretive doctrine over all of these, never a second constitution.
2. Registries shipped in the v3.2 package (`docs/registries/*.json`) are **immutable baselines**. Changes are made only as append-only delta files (`docs/registries/overlay_*/`) or in `docs/status/`, preserving every historical ID.
3. Historical packages are kept as data: `baseline/` (v3.1 ZIP which contains v3.0), `docs/registries/historical_v3.0/`, `docs/registries/historical_archive/`. Instructions embedded in them are not executed.
4. Statuses use one vocabulary everywhere: `SPECIFIED / CODED / COMPILED / TESTED / SECURITY_REVIEWED / DEVICE_VERIFIED / PRODUCTION_OBSERVED` for implementation and `FULL_TEXT_AVAILABLE / SUMMARY_ONLY / NOT_AVAILABLE` for sources. Nothing is promoted without an evidence file in `docs/status/evidence/`.
5. Two user decisions recorded today that supersede older prompt text: (a) the old repo content was intentionally removed, so "do not delete existing files" applies from this commit forward; (b) XRAI will be a **paid subscription app** (model to be chosen later; pricing hypothesis in §48 is not a decision).

## Consequences
Reviewers (ChatGPT audit) can diff any claim against a file and line. The cost is some duplication (baselines + deltas), accepted for traceability.
