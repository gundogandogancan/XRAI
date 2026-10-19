# BOOT-01 — Hand-derived golden fixtures (written BEFORE production code)

**Date:** 2026-10-19 · **Author:** Claude Fable 5.1 (implementation agent) · **Rule:** CLAUDE_FIRST_SESSION_v3.2 P01 — "Hand-derive independent expected outputs BEFORE letting production code calculate them."

These values were computed by hand (digit-by-digit arithmetic shown) and recorded before `Packages/XRAICore` sources existed. The Swift tests in `Packages/XRAICore/Tests` must reproduce exactly these numbers. If code and this table disagree, the code is wrong until a reviewer proves otherwise.

Epistemic class of every value here: `EXACT_MATH`. A Life Path number has **no proven personality or fate meaning**; it is a deterministic function of decimal digits under a named method.

## Method definitions under test (versioned, original wording)

| method_id | algorithm | master policy variants |
|---|---|---|
| `num.life_path.digits.v1` | Take the eight decimal digits of `YYYYMMDD` in literal order. `compound` = sum of all eight digits. Reduce by repeated digit-sum until a single digit, producing `reductions[]` and `root`. | `reduce_all`: always reduce to 1–9. `preserve_11_22_33`: stop reducing when the compound or any intermediate equals 11, 22 or 33; that value is `root` and `masterNumber`. |
| `num.life_path.components.v1` | Reduce year, month and day **separately** (same master policy), `compound` = sum of the three reduced components, then reduce `compound` under the same policy. Recorded as a distinct method so the two schools are never conflated. | same two policies |

Registry note: both are `DESIGN_ONLY_NOT_TESTED` in `docs/registries/ORIGINAL_MATH_METHOD_REGISTRY_v3.2.json` (`num.life_path.digits.v1`). The components variant is an additional registry candidate introduced in BOOT-01 and must be appended to the registry, not replace anything.

## Civil date validity fixtures (proleptic Gregorian, supported years 1583…9999)

| input | expected | reasoning |
|---|---|---|
| 2000-02-29 | VALID | 2000 % 400 == 0 → leap |
| 1900-02-29 | INVALID `invalidDay(daysInMonth: 28)` | 1900 % 100 == 0 and 1900 % 400 != 0 → not leap |
| 2024-02-29 | VALID | 2024 % 4 == 0, not century |
| 2023-02-29 | INVALID | 2023 % 4 != 0 |
| 2023-04-31 | INVALID | April has 30 days |
| 2023-13-01 | INVALID `invalidMonth` | |
| 2023-00-10 | INVALID `invalidMonth` | |
| 2023-01-00 | INVALID `invalidDay` | |
| 2023-01-32 | INVALID `invalidDay` | |
| 1582-10-04 | INVALID `yearOutOfSupportedRange` | pre-reform date; policy: first fully Gregorian year 1583 |
| 10000-01-01 | INVALID `yearOutOfSupportedRange` | eight-digit `YYYYMMDD` contract |
| 1583-01-01 | VALID | lower bound inclusive |
| 9999-12-31 | VALID | upper bound inclusive |

## Life Path fixtures — `num.life_path.digits.v1`

| id | date | literal digits | compound (hand sum) | `preserve_11_22_33` reductions → root (master) | `reduce_all` reductions → root |
|---|---|---|---|---|---|
| F1 | 1998-06-30 | 1,9,9,8,0,6,3,0 | 1+9+9+8=27; 0+6+3+0=9; **36** | [9] → **9** (nil) | [9] → 9 |
| F2 | 2000-02-29 | 2,0,0,0,0,2,2,9 | 2+0+0+0=2; 0+2+2+9=13; **15** | [6] → **6** (nil) | [6] → 6 |
| F4 | 2000-01-08 | 2,0,0,0,0,1,0,8 | 2; 0+1+0+8=9; **11** | [] → **11** (11) | [2] → 2 |
| F5 | 1955-01-01 | 1,9,5,5,0,1,0,1 | 1+9+5+5=20; 0+1+0+1=2; **22** | [] → **22** (22) | [4] → 4 |
| F6 | 1969-05-21 | 1,9,6,9,0,5,2,1 | 1+9+6+9=25; 0+5+2+1=8; **33** | [] → **33** (33) | [6] → 6 |
| F7 | 1999-07-03 | 1,9,9,9,0,7,0,3 | 1+9+9+9=28; 0+7+0+3=10; **38** | [11] → **11** (11) — master reached at a reduction step, not at compound | [11, 2] → 2 |
| F10 | 1998-03-06 | 1,9,9,8,0,3,0,6 | **36** (same multiset as F1, different order) | [9] → 9 | [9] → 9 |

Adversarial requirement for F1 vs F10: identical `compound` and `root`, but `rawDigits` differ and `formulaTraceHash` differs. The trace must carry literal digit order; a permuted date must not be indistinguishable in the trace.

## Life Path fixtures — `num.life_path.components.v1`

| id | date | year → | month → | day → | compound | `preserve` root (master) | `reduce_all` root |
|---|---|---|---|---|---|---|---|
| F8 | 1955-01-01 | 1+9+5+5=20 → 2 | 1 | 1 | 2+1+1 = **4** | **4** (nil) | 4 |
| F9 | 2000-02-29 | 2 | 2 | 2+9=11 (preserved as 11 under `preserve`; → 2 under `reduce_all`) | preserve: 2+2+11 = **15**; reduce_all: 2+2+2 = 6 | [6] → **6** (nil) | 6 |
| F11 | 1984-11-22 | 1+9+8+4=22 (preserved) | 11 (preserved) | 22 (preserved) | 22+11+22 = **55** | [10, 1] → **1** (nil) | year 22→4, 11→2, 22→4 → 10 → 1 |

Cross-method proof of non-conflation: **F5 vs F8** — same date 1955-01-01 gives root 22 under the digits method but root 4 under the components method. The product must never present these as the same "number"; the method ID is part of the result.

Cross-method invariant (property test): under `reduce_all`, both methods must produce the same root for every valid date, because digital roots are additive modulo 9. Under `preserve_11_22_33` they may legitimately differ (F5/F8).

## Typed error fixtures

| case | expected |
|---|---|
| valid date, unknown method `num.life_path.chaldean.v9` | `NumerologyError.methodUnavailable` — a date can be valid while the method is not registered (constitution §87) |
| 1900-02-29 → cannot even construct `CivilDate` | the numerology layer never sees invalid dates |

## Privacy negative fixtures (must be asserted by tests)

1. No file under `Packages/XRAICore/Sources` imports `Foundation`, `Network`, `OSLog` or references `URLSession`, `FileManager`, `UserDefaults`, `print(`, `NSLog`. Pure Swift standard library only ⇒ the module has no API through which it could make a network call or write a file.
2. `String(describing: civilDate)` and `String(describing: trace)` do **not** contain the birth date digits (redacted descriptions). The ISO string is available only through the explicit `isoString` accessor.
3. `CivilDate` and `NumerologyTrace` are not `Encodable`/`Decodable` in this module. Persistence belongs to the future vault layer (P02) behind consent and encryption.
4. `formulaTraceHash` is an integrity fingerprint, not an anonymizer: the DOB space is small (~3 million dates), so the hash is brute-forceable and must never be logged or used as a pseudonymous identifier.

## Amendment A1 (2026-10-19, after first `swift test` run) — components method definition made explicit

**Observed:** first test run: 35 tests, 33 passed, 2 failed (both in F11, `swift_test_run1.log`). The production code started each component's reduction from the component's **digit sum** (month 11 → 1+1 = 2), while the hand-derived table above treats month 11 and day 22 as master-number **values** (11, 22). The table is authoritative; the code was wrong.

**Decision (ADR-BOOT-004):** `num.life_path.components.v1` reduces each component starting from its **numeric value** (1984 → 22; 11 stays 11 under `preserve_11_22_33`; 29 → 11). A "digit-sum-first" variant would be a different method and is intentionally **not** registered. The `ComponentTrace.reduction.compound` therefore equals the component value (e.g. 1955), and `steps` shows every reduction (e.g. [20, 2]).

**Fixture rows F8/F9/F11 re-stated under the explicit definition (values unchanged, intermediate traces now precise):**

| id | year value → steps → root | month | day | compound | preserve root | reduce_all root |
|---|---|---|---|---|---|---|
| F8 1955-01-01 | 1955 → [20, 2] → 2 | 1 → [] → 1 | 1 → [] → 1 | 4 | 4 | 4 |
| F9 2000-02-29 | 2000 → [2] → 2 | 2 → [] → 2 | 29 → [11] → 11 (preserve) / [11, 2] → 2 (reduce_all) | 15 / 6 | 6 | 6 |
| F11 1984-11-22 | 1984 → [22] → 22 | 11 → [] → 11 | 22 → [] → 22 | 55 | [10, 1] → 1 | 4+2+4 = 10 → 1 |

No fixture value in the original tables changed; only the intermediate representation was made unambiguous. The failing first run is kept as evidence (`docs/status/TEST_EVIDENCE_LEDGER.json`).
