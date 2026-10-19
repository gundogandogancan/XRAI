# ADR-BOOT-003 — IP / book clean-room gate

**Status:** ACCEPTED (2026-10-19, BOOT-00) · **Refines:** spec ADR-007/008/009/014, constitution §40, §57C–E, §78, §91, `SOURCE_RIGHTS_AND_EVIDENCE_v3.1.json`

## Context
Research inputs include a Turkish Human Design book scanned by the user (13 unique PDFs, 298 frames; present in `~/Downloads`, not fully read, printed pages 1–8 and 300 unverified), publisher screenshots of "Book of Wisdom", four classical astrology works in modern translations, competitor apps, and Swiss Ephemeris (AGPL or paid). Ownership of a copy grants no right to redistribute, embed, train on or paraphrase at scale.

## Decision
1. **No scan, PDF or book text enters this repository or any build artifact.** `.gitignore` blocks `*.pdf`, `scans/`, `private/`. Research notes may cite page/frame IDs and describe *methods in original words* only.
2. **Clean-room method rule:** every symbolic/computational method (HD gate wheel order and anchor, −88° design-epoch root, channel/center tables, type/authority precedence, classical dignities/terms, 16-type items) must be reconstructed from at least one independently citable, rights-clear source and registered with `method_id`, version and `activation_gate`. Until then its state is `BLOCKED_METHOD_NOT_VERIFIED` and the feature degrades gracefully with a user-visible reason.
3. **Competitor observation** (Jovian Archive, Astrodienst, 16Personalities, etc.) is limited to lawful public UX observation under `xrai-replica-recon-legal`; no scraping, no login/paywall/DRM bypass, no protected API use, no copied copy/assets/diagrams.
4. **Ephemeris:** no Swiss Ephemeris code or data is added until the licence decision (AGPL vs professional licence vs alternative) is recorded in a dedicated ADR (spec ADR-007 remains BLOCKED).
5. **Psychometrics:** no MBTI/16Personalities items or branding; any 16-approach exploration must be original and labelled non-diagnostic (spec ADR-008 remains BLOCKED).
6. **Mentor personas** are clearly labelled simulations with sourced public knowledge; no fabricated quotes.

## Consequences
Human Design, astrology and psychology engines cannot be "finished" from the material at hand; they need sourcing work first. This is recorded as the honest state, not as a delay to hide.
