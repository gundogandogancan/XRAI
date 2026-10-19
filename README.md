# XRAI — Original Human Intelligence (iOS)

Local-first, native iOS **Personal Life Intelligence** app: exact mathematics where mathematics applies, separately attributed symbolic traditions, consented psychological reflection, user-authored purpose and Future Self, real lessons and evidence, three privacy-preserving brains, five tabs (**Bugün · Ben · Keşfet · Yolum · XRAI**). Paid subscription product (model to be chosen). AHTOVIA (future education platform) is only a reserved interface, not built here.

**This repository was re-created from scratch on 2026-10-19.** Everything earlier lives only in the specification packages under `docs/`.

## Where things are

| path | what |
|---|---|
| `CLAUDE.md` | work contract for the implementation agent (read first) |
| `CLAUDE_FIRST_SESSION_v3.2.md` | the first-session order (BOOT-00 / BOOT-01) |
| `docs/canon/` | binding constitution v3.2 (preserves v3.1/v3.0/v2.1), founding philosophy & GOD LEVEL doctrine |
| `docs/registries/` | immutable v3.2/v3.1 registries; `historical_v3.0/`, `historical_archive/`; append-only `overlay_*/` deltas |
| `docs/status/` | BOOT reports, ledgers, blockers, next task, `evidence/` logs |
| `docs/adr/` | repo-level ADRs |
| `docs/tools/` | tool/skill/agent install ledger and pins |
| `docs/audits/` | prior audit notes |
| `App/`, `project.yml`, `XRAI.xcodeproj` | native SwiftUI iOS app: design system, onboarding, Life Path feature, five tabs, honest security status; hosted + UI tests |
| `Packages/XRAICore` | pure Swift core: `XRAIIdentityTime` (CivilDate), `XRAINumerology` (Life Path), `XRAIVaultContracts` (privacy policy, envelope/backup contracts), `XRAIVaultCryptoKit` (AES-256-GCM adapter + `SecureVault` access contract, the only production CryptoKit module), `XRAIVaultKeychain` (production KeyProvider on Keychain + Secure Enclave, the only Security module), `XRAIVaultTesting` (in-memory doubles, tests only) |
| `docs/security/` | threat models |
| `brand/` | logo source and derived PNG |
| `baseline/` | immutable v3.1 package ZIP (contains v3.0) |
| `.claude/` | project-local skills and reviewer agents (audited, pinned) |

## Build and test (what exists today)

```bash
cd Packages/XRAICore
swift build
swift test
python3 -I ../../validation/validate_package.py   # spec structure only, not an app build
```

An Xcode app target exists (`XRAI.xcodeproj`, regenerate with `xcodegen generate`); it has a real first experience (onboarding + offline Life Path) with no personal persistence; hosted and UI tests pass on the Simulator and on a real iPhone. No network, persistent storage, analytics or model code exists yet by design; the vault has a production Keychain/Secure Enclave key provider tested on a macOS host; physical-device verification is pending.

## Non-negotiables
No private book scans or PDFs in the repo. No paid API, cloud model, MCP or hook without an ADR. Deterministic results never come from an LLM. Symbolic readings are never presented as personality, health or destiny facts. Nothing is "DONE" without a test log in `docs/status/evidence/`.
