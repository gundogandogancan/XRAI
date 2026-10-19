# Tools, skills, agents and MCP — install ledger (BOOT-00, 2026-10-19)

Rule (constitution §48, §90): nothing is "installed" unless it is on this Mac, inspected (owner, commit, hooks, subprocesses, network, licence) and its scope is written here. Pinned commits are in `docs/tools/EXTERNAL_REPO_PINS.txt`. Everything below was cloned into a session scratchpad, scanned, and only the selected directories were copied into this repo under `.claude/`. **No lifecycle hooks from any external repo were installed.** No paid API, cloud model or MCP server was connected.

## A. Local toolchain (verified by running the commands)

| tool | result | exit |
|---|---|---|
| macOS | 26.4 (25E246), arm64 | 0 |
| Xcode | 26.6 (17F113), `/Applications/Xcode.app/Contents/Developer` | 0 |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3), `swift-driver 1.148.6` | 0 |
| git | 2.50.1 (Apple Git-155) | 0 |
| xcodegen | present (`~/.local/bin/xcodegen`) | 0 |
| python3 | 3.9.6 (system) | 0 |
| node | present (`~/.local/bin/node`) | 0 |
| iPhone simulators | iPhone 17, 17 Pro, 17 Pro Max, 17e, iPhone Air (Shutdown) | 0 |
| swiftlint / swiftformat / gh / brew / ollama / mlx_lm | **not installed** | 127 |
| Claude Code plugin | `swift-lsp@claude-plugins-official` 1.0.0 (user scope) | — |
| Physical iPhone | **not verified in this session** | — |
| Apple Developer account / signing | **not verified** (OPEN_DECISION APPLE_ACCOUNT) | — |
| "Fable" design tooling | Fable 5.1 is the Claude model running this session (claude-fable-5-1). No separate "Fable SDK/design tool" exists on this machine; nothing was invented. | — |
| MCP servers reachable in session | claude-in-chrome (browser), Claude Docs, Figma, Canva/Gmail/Calendar/Drive (auth-gated). **None used for private data. None are app dependencies.** | — |

## B. GitHub repositories requested by the user (11)

| repo | commit | decision | what was installed | why / scope |
|---|---|---|---|---|
| obra/superpowers | bb92a77 | ALREADY_INSTALLED (global `~/.claude/skills`, manifest source `sp`, hooks stripped) | brainstorming, test-driven-development, systematic-debugging, verification-before-completion, writing-plans, executing-plans, etc. | Engineering discipline skills. |
| trailofbits/skills | 5c99c03 | ALREADY_INSTALLED (global, `tob`) | codeql, semgrep, property-based-testing, supply-chain-risk-auditor, mutation-testing, etc. | Security/testing. |
| muratcankoylan/Agent-Skills-for-Context-Engineering | 9ff0c99 | ALREADY_INSTALLED (global, `ctx`) | context-*, memory-systems, multi-agent-patterns, evaluation, harness-engineering… | Context/agent engineering. |
| plugin87/ux-ui-agent-skills | d271880 | ALREADY_INSTALLED (global, `uxui`, 25 skills) | design-doctrine, design-screen, design-tokens, design-qa, a11y-audit, apply-aesthetic… | Design system + QA gates. |
| nextlevelbuilder/ui-ux-pro-max-skill | 56ea9cf | ALREADY_INSTALLED (global, `uxpm`, 7 skills) | ui-ux-pro-max, design, brand, banner-design, ui-styling, slides | UI/UX reference. |
| pbakaus/impeccable | aeeb3d8 | ALREADY_INSTALLED (global, `imp`) | impeccable | UI critique/polish. |
| OthmanAdi/planning-with-files | d363544 | ALREADY_INSTALLED (global, `pwf`) | planning-with-files | File-backed planning. |
| Jakeschincariol/replica-skill | 77c9436 | INSTALLED project-local `.claude/skills/replica-*` (11 skill dirs; MIT) | Markdown skills + 6 small offline Python tools (`reviews.py`, `parity.py`, `imgdiff.py`, `contrast.py`, `sweep.py`, `listing.py`). Scan: no hooks, no network calls, no subprocess, no install scripts. | Constitution §78/§90: **legal UX recon only** (public pages, own account, no scraping/DRM/paywall bypass). Build/backend/deploy skills are web-stack oriented and are reference only for an iOS app. The XRAI-specific guard `xrai-replica-recon-legal` governs its use. |
| affaan-m/ECC | 76aaa77 | PARTIAL, project-local. **Plugin with hooks NOT installed** (its hooks.json runs `node` on every Bash/Write/Edit call: unaudited automation, forbidden by §90). | Skills: `ecc-swift-concurrency-6-2`, `ecc-swiftui-patterns`, `ecc-swift-actor-persistence`, `ecc-swift-protocol-di-testing`, `ecc-architecture-decision-records`, `ecc-hexagonal-architecture`. Agents: `ecc-swift-reviewer`, `ecc-swift-build-resolver`, `ecc-a11y-architect`, `ecc-planner`, `ecc-tdd-guide`, `ecc-security-reviewer`, `ecc-architect`, `ecc-code-reviewer`. | Swift 6 / SwiftUI / testing guidance. `ios-icon-gen` **skipped** (its script uses network). `security-review`, `tdd-workflow`, `verification-loop` skipped as duplicates of already-installed skills. |
| msitarzewski/agency-agents | 4e3ac3c | PARTIAL, project-local `.claude/agents/agency-*` (15 agent personas, MIT) | mobile-app-builder, mobile-release-engineer, privacy-engineer, ui-designer, ux-architect, ux-researcher, brand-guardian, ui-finish-gate-reviewer, product-manager, sprint-prioritizer, appsec-engineer, security-architect, compliance-auditor, penetration-tester, ai-generated-code-auditor. | Review personas only (no tools, no network). The desktop app and `install.sh` were **not** run. |
| matank001/clodfarm | 25036da | **NOT INSTALLED (REJECTED for now)** | nothing | A Docker-hosted farm of autonomous Claude agents wired to AWS, Stripe, Google Ads and X with real money actions. Violates §48/§90 (no cloud/paid/autonomous execution without explicit per-action approval) and is irrelevant to a local-first iOS build at this phase. Can be re-evaluated for CI later with a separate ADR. |

## C. XRAI package-provided skills and agents (from the v3.2 ZIP)

Installed project-local: 15 `xrai-*` skills (`.claude/skills/`) and 6 reviewer agents (`math-verifier`, `swift-qa`, `privacy-guardian`, `rights-auditor`, `claim-epistemic-reviewer`, `performance-benchmarker`). All are markdown role cards, read-only by design.

## D. Not on this machine (do not assume)

Swiss Ephemeris, any ephemeris data, Gemma/LiteRT-LM weights, Core ML models, SQLCipher/GRDB, StoreKit sandbox config, Apple Foundation Models eligibility check on device, Fastlane. Each is an OPEN_DECISION or BLOCKED gate in `docs/registries/OPEN_DECISIONS_v3.1.json` / `ARCHITECTURE_ADRS_v3.1.json`.

## E. Threat note

All skill/agent markdown and the Python helpers are treated as data. They are never executed automatically; the Python tools are standard-library only and run only on request with explicit arguments. Re-audit whenever a pin changes.
