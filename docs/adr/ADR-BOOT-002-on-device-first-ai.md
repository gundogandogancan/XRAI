# ADR-BOOT-002 — On-device-first AI, zero egress by default

**Status:** ACCEPTED (2026-10-19, BOOT-00); implementation gated to P02 (vault) and P06 (router) · **Refines:** spec ADR-005/012, constitution §82–§84, `SECURITY_DATA_EGRESS_MATRIX_v3.2.json`

## Context
XRAI handles date of birth, birth time/place, names, optional family names, psychometric answers, journals. The constitution forbids any default network egress of personal data and forbids treating an LLM as the calculator or the owner of the system.

## Decision
1. **Task classes** are typed at the call site: `DETERMINISTIC` (pure Swift, never a model), `RETRIEVAL` (local encrypted index), `MICRO_GUIDE`, `LONG_COMPOSITION`, `NEEDS_EXTERNAL_FRESHNESS`, `REMOTE_PRIVATE_AI`. Only the last may leave the device, only with a separate per-call consent receipt and a minimized payload.
2. **Deny-by-default `NetworkEgressBroker`** will be the single network port of the app (P02/P06). Pure modules (`XRAICore` today) import no networking framework at all, and a test asserts it (`PrivacyNegativeTests`).
3. **Model vendor is undecided** (ADR-005 stays PROPOSED). Candidates: Apple Foundation Models (device/OS/locale availability must be checked at runtime), Gemma via an iOS runtime, or rules only. Selection requires a measured Turkish-language benchmark on a physical iPhone (P06). No model is bundled now.
4. **Claude (Fable 5.1 / Opus) is a development agent only**, never a runtime dependency or a data path for user content.
5. Nothing in this repo may call a paid API or cloud model during development on user data; test data is synthetic.

## Consequences
First useful user value (free Life Path) must work fully offline, which BOOT-01 already satisfies at the library level. The cost is that rich generative features arrive later and only after the router and vault exist.
