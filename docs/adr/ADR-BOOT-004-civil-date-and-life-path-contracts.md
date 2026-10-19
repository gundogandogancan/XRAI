# ADR-BOOT-004 — CivilDate and Life Path method contracts (BOOT-01)

**Status:** ACCEPTED and TESTED (2026-10-19) · **Implements:** constitution §75, §76, §87, method `num.life_path.digits.v1`; introduces `num.life_path.components.v1` · **Evidence:** `docs/status/TEST_EVIDENCE_LEDGER.json`, `docs/status/evidence/`

## Context
P01 requires the smallest executable pure Swift core with hand-derived golden tests and a negative privacy test, no UI/network/storage/model.

## Decisions
1. **Package:** `Packages/XRAICore` (SwiftPM, tools 6.0, Swift 6 language mode, iOS 17 / macOS 14) with two library targets named per §86: `XRAIIdentityTime` and `XRAINumerology`. No app target yet (§86: "do not create 18 empty targets").
2. **`CivilDate`** is immutable, validated, proleptic Gregorian, date-only, supported years **1583…9999**. Earlier dates are rejected (`yearOutOfSupportedRange`), never converted. Not `Codable`; `description` is redacted; the ISO string is an explicit accessor. Rationale: time-zone independence by construction, no DOB in logs, persistence belongs to the vault (P02).
3. **Life Path methods** are registry entries, each with a stable `method_id`; a valid date with an unregistered method throws `methodUnavailable` (§87).
   - `num.life_path.digits.v1`: sum of the eight literal `YYYYMMDD` digits, then digit-sum reduction.
   - `num.life_path.components.v1`: year, month and day each reduced **from their numeric value** (1984 → 22, 11 stays 11, 29 → 11), summed, reduced again. *Amendment A1 in the fixtures doc records that the first implementation started from digit sums (month 11 → 2), which the hand-derived fixture rejected; the numeric-value definition is the one registered. A digit-sum-first variant is deliberately not offered.*
   - `MasterNumberPolicy`: `reduce_all` or `preserve_11_22_33` (stop when compound or any intermediate equals 11/22/33). Policy is part of every trace.
4. **`NumerologyTrace`** carries `methodID`, policy, literal `rawDigits`, optional component traces, `compound`, `reductions[]`, `root`, `masterNumber?`, and `formulaTraceHash` (FNV-1a 64 over a canonical text; integrity only, brute-forceable, never to be logged or used as an identifier). `epistemicClass` is the constant `EXACT_MATH`.
5. **Privacy negative tests** scan the production sources at test time: no `Foundation`, `Network`, `OSLog`, `URLSession`, `FileManager`, `UserDefaults`, `print(` etc.; only `import XRAIIdentityTime` is allowed inside the package. Redaction and non-Codability are asserted.
6. **No interpretation text** of any number exists in this package. Symbolic meaning belongs to a later, separately sourced `XRAITraditions` lens, labelled `SYMBOLIC_ASSOCIATION`.

## Consequences
The free Life Path value (§89 first vertical slice) can be computed offline today. The method registry delta is recorded in `docs/registries/overlay_boot01/METHOD_REGISTRY_DELTA_BOOT01.json`. Name numerology, cycles and all other methods remain `DESIGN_ONLY_NOT_TESTED`.
