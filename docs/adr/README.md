# Architecture Decision Records

Spec-level ADR-001…ADR-015 live in `docs/registries/ARCHITECTURE_ADRS_v3.1.json` (states ACCEPTED_IN_SPEC / PROPOSED / BLOCKED). The records below are **repo-level** decisions made during BOOT-00/BOOT-01 against the real environment. They never override a spec ADR; where they refine one they say so.

| id | title | status |
|---|---|---|
| [ADR-BOOT-001](ADR-BOOT-001-source-of-truth.md) | Source of truth and version precedence in this repo | ACCEPTED (BOOT-00) |
| [ADR-BOOT-002](ADR-BOOT-002-on-device-first-ai.md) | On-device-first AI, zero egress by default | ACCEPTED (BOOT-00), implementation gated to P06 |
| [ADR-BOOT-003](ADR-BOOT-003-ip-book-clean-room-gate.md) | IP / book clean-room gate | ACCEPTED (BOOT-00) |
| [ADR-BOOT-004](ADR-BOOT-004-civil-date-and-life-path-contracts.md) | CivilDate and Life Path method contracts (BOOT-01) | ACCEPTED, TESTED |
| [ADR-BOOT-005](ADR-BOOT-005-vault-envelope-and-recovery.md) | Vault envelope encryption, key lifecycle, user-held recovery (P02, V32-02-01 + H1 + H2) | ACCEPTED, library TESTED, not SECURITY_REVIEWED |
| [ADR-BOOT-006](ADR-BOOT-006-keychain-secure-enclave-key-provider.md) | Production key provider on Keychain with Secure Enclave wrapping (P02-02) | ACCEPTED, macOS-host + Simulator-host TESTED, DEVICE_VERIFIED: NO |
| [ADR-BOOT-007](ADR-BOOT-007-ios-host-key-cache-and-rotation-safety.md) | Native iOS host, key-cache policy, rotation/forgetting safety (P03-00, Amendment F) | ACCEPTED, device 24/24, DEVICE_VERIFIED: PARTIAL |
| [ADR-BOOT-008](ADR-BOOT-008-design-system-and-onboarding.md) | Design system, onboarding and first user flow (P03-01) | ACCEPTED, Simulator 38/38, device 38/38 |
| [ADR-BOOT-009](ADR-BOOT-009-secure-persistence-architecture.md) | Secure persistence architecture: file-based envelope store, derived-data graph, tombstones, consent authority persistence, store proof for key forgetting (P03-03) | ACCEPTED for library scope (P03-04 CONDITIONAL GO); `XRAIVaultStore` CODED + TESTED (macOS 36/36 store tests, hosted runs in the ledger); app wiring, backup v3, attachments pending; not SECURITY_REVIEWED |
- ADR-BOOT-010 — Consent and interaction authority (PROPOSED, P03-05A)
