# Vendor/source references, researched 19 Oct 2026

- Apple Foundation Models overview: https://developer.apple.com/foundation-models-framework/ ; same Swift API can select local or remote; check exactly which provider runs. On-device availability, system language and `supportsLocale()` runtime must be tested.
- Apple local language support: https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models
- Apple CryptoKit: https://developer.apple.com/documentation/cryptokit ; hardware Keychain/Secure Enclave and actual SDK supported crypto algorithms must be checked.
- Swiss Ephemeris official: https://www.astro.com/swisseph/sweph_e.htm ; dual AGPL/professional-license decision before commercial redistribution. Historical mirror licenses may be stale: official current license takes precedence.
- Google mobile Gemma: https://ai.google.dev/gemma/docs/integrations/mobile ; iOS MediaPipe LLM old implementation is maintenance-only, check newer LiteRT-LM documentation for current support: https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference/ios .
- Anthropic custom skill directions: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview ; `.claude/skills/name/SKILL.md`. Skills are executable instructions and an access surface, review them.

**CAVEAT** Provider capabilities, legal terms, SDK availability and licenses are live external facts, recheck at implementation/approval. This file is research, not a provider contract or production test.
