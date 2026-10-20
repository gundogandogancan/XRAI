# ADR-BOOT-011 — Design tooling (Figma connector, Claude design skills) for the product-experience phases

**Status:** PROPOSED (P04-00, 2026-10-20) · **Deciders:** founder (authorised design tools on 2026-10-20, recorded in `docs/tools/TOOLS_AND_SKILLS_INSTALL_LEDGER.md`), external reviewer · **Related:** ADR-BOOT-008 (design system), constitution §88, §90 (tool acceptance), CLAUDE.md §3 "no MCP without an ADR".

Türkçe özet: Figma bağlayıcısı ve tasarım becerileri yalnız tasarım fazlarında, yalnız kişisel olmayan içerikle (jetonlar, bileşenler, sentetik ekranlar) kullanılır. Kaynak gerçek Swift tasarım sistemi kalır; Figma bir aynadır, otorite değil. Kişisel veri, kasa modülleri ve telifli içerik Figma'ya asla gitmez. Bu kararın gerçek kullanımı ancak INSTALL ledger'da hash/sürüm kaydı ve bir "ilk dışa aktarım" raporuyla sayılır.

## Context
The founder asked for Figma and Claude design skills to raise the visible product quality ("2 zekânın birleşimi"). The constitution allows tools only through the install ledger with pinned versions, denied data classes and minimal permissions (§90), and the repo rule forbids MCP servers without an ADR. A Figma MCP connector is available in the agent environment; it is an external service: anything sent to it leaves the device and may be retained.

## Decision
1. **Scope:** design phases only (P04 and later product-experience work). Not used in vault, consent, keychain or authorization phases.
2. **What may be sent:** semantic design tokens (`Theme.swift` values), component anatomy (`Components.swift`), the court grammar's structure (stone ids, titles, relations), synthetic screen content (the fixed example date, the static option lists), screenshots of synthetic sessions. **Never:** any real personal value, any user-entered date, vault file formats, keys, consent events, copyrighted scans or their derivatives, App Store credentials.
3. **Direction of truth:** the Swift design system in the repo is the source of truth; Figma mirrors it (code → design). Changes proposed in Figma come back as reviewed edits to tokens/components with the contrast tests re-run; Figma never auto-writes code.
4. **Evidence:** every Figma export/import is a ledger row (date, file key, what was sent, by whom). A phase may claim "designed in Figma" only with that row and the file link in the phase report.
5. **Skills:** the Figma skills shipped with the connector are read on demand; no skill may run shell commands or read the vault directories (the agent reviews each skill's instructions before use, §90 prompt-injection model).
6. **Reversal:** the founder can revoke the authorisation at any time; the Swift design system keeps working without Figma.

## Consequences
- P04-00 did **not** need Figma to produce the three screens (SwiftUI prototypes on existing tokens); the first Figma use is deferred to the design-system export of `court.v1` and will be recorded as `P04-FIGMA-01` in the ledger when it happens.
- Privacy guardian review of the "what may be sent" list is required before the first export.
- The open decision `DESIGN_TOOLING_AUTHORIZATION` (OPEN_BLOCKERS, P03-05A) closes when this ADR is ACCEPTED by the reviewer.
