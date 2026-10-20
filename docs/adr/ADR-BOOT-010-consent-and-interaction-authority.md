# ADR-BOOT-010 — Consent and interaction authority

**Status:** PROPOSED for the next independent review (2026-10-20, P03-05A) · **Depends on:** ADR-BOOT-005 (envelopes), 009 + Amendments H…H.4 (store, ledger binding, identity policy) · **Supersedes:** `P03_03_CONSENT_AUTHORITY_SPEC.md` §2, §4 (ring), §5, §7 — see `docs/status/P03_05A_CANONICAL_RECONCILIATION.md`.

Türkçe özet: İzin = sürümlü amaç + değişmez olay zinciri; depoda `system/consent.v1`; yetki = tek dokunuştan türeyen, kapsamı ve amacı tam token; sınır süreç içi.

## Decisions
1. **Purposes are versioned, immutable values** in a registry shipped with the app (`PurposeRegistry`). A grant records the version it was shown for. Widening classes/destinations or adding AI egress is a new version; old grants never cover it; narrowing keeps coverage.
2. **Consent is an append-only, payload-free event chain** (`ConsentEvent` granted/revoked, `ConsentLedger`). Active state is derived by replay; nothing is edited. Revocation events are appended in the SAME journaled mutation as the record consequence (`revoke(purpose:mode:)`).
3. **Persistence is store system state**: `system/consent.v1` sealed as `storeMetadata`, bound by `Manifest.consentHash` (manifest v3), announced before every write (`consentWritten`), proven at open by `LedgerBinding.verifyConsent`; rollback/missing/unreadable ⇒ read-only. This solves the bootstrap (no token needed to store a consent).
4. **Consent never leaves the device**: `mayBackup(.consentReceipts)` denies. A restored vault asks again.
5. **The only token source for app code is `InteractionGate`** (`XRAIVaultInteraction`): owns the issuer privately; mints proofs only in an active scene; proof ≤ 5 s, single use; kind per scope (tap vs confirmation dialog); purpose equal to the consent purpose; the store/vault consume through `gate.validator`. A source-scan test forbids `.issue(` and `AuthorizationIssuer(` in app code outside the gate construction.
6. **Stated limit:** the gate is an in-process misuse-prevention mechanism, not an OS security boundary and not cryptographic proof of human intent. OS-level user authentication for high-risk operations is a separate decision (OPEN_BLOCKERS `OS_USER_AUTH_HIGH_RISK`).
7. **Authorization precedes inspection (PRE-01):** every store entry point validates the token (non-consuming `AuthorizationValidator.validate`) before any state check, so unauthorized callers only ever see `authorizationInvalid`.

## Consequences
Library TESTED on macOS, Simulator and iPhone 14 Pro Max (NT-CA, NT-PR, NT-IG, NT-UX rows). The production composition root is NOT wired (P03-05B). SECURITY_REVIEWED: NO.
