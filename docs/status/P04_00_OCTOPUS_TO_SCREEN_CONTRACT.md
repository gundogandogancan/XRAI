# P04_00_OCTOPUS_TO_SCREEN_CONTRACT — Input → Method → Knowledge Source → Epistemic Class → Privacy Purpose → Output → User Correction → Optional Action

**Date:** 2026-10-20 · **Branch:** `p04-00-living-experience` · **Baseline:** `4c5235f1c6e0442a1b68fad90e4594873fe46630` · The eleven stone contracts live in code (`ScreenContract` in `LivingGrammar.swift`) and are shown to the person under "Nasıl çalışır" on every stone; `NT-LX-03` asserts all eight fields are filled for every stone. The cards that are not stones are listed in §2.

Türkçe özet: Ahtapot boru hattı (F:186) bu sürümde şöyle iner: niyet → (izin: bu sürümde gerekmez, hiçbir şey kaydedilmez) → en az girdi → deterministik araç (yalnız Yaşam Yolu) → kaynaklı iddia (yalnız aritmetik) → kişisel bağlam (oturum) → anlatım (sabit Türkçe metin, model yok) → doğrulama (etiket) → tek sade ekran. İlk dakika modelsiz ve çevrimdışı çalışır; ağ yok, API yok.

## 1. The pipeline in this build (F:186 → P04-00)

| octopus step | this build |
|---|---|
| Intent | a tap on a stone or a control |
| Consent | not needed: nothing is stored; the session date stays in memory (P03 rule). When P03-05B wires the store, stone 1 maps to purpose `life_path_calculation` |
| Minimum inputs | date only (stone 1); a choice (5, 9, 10); nothing else is asked |
| Deterministic tools | `NumerologyLifePath` (BOOT-01), nothing else runs |
| Sourced claims | only arithmetic; no tradition text exists yet (stones 2/3/4/7/8 pending) |
| Contradiction check | n/a (one engine) |
| Personal context | `SessionState` (date, journey) — in memory |
| Local narration | fixed Turkish copy; no language model; `CopyLexicon` asserted |
| Response verification | the epistemic badge on every card |
| Single clear UX | one discovery, one invitation, one court |

**No-AI and offline behaviour (directive §5):** the first slice has no model and no network call anywhere (no `URLSession`, no model runtime is linked). Airplane mode changes nothing. When a model arrives (P06), its absence must still produce exactly this screen: the model is an optional narrator, never a dependency of the court.

## 2. Contracts of the non-stone cards

| card | input | method | knowledge source | class | privacy purpose | output | user correction | optional action |
|---|---|---|---|---|---|---|---|---|
| Bugün · opening | device clock | date formatting (tr_TR) | — | system invitation | none | "20 Ekim, Salı" | — | — |
| Bugün · discovery (with date) | session trace | `NumerologyLifePath` | registered method id | exact math | none in this build (`life_path_calculation` later) | root + reduction steps in words | change/forget the date on stone 1 | "Hesabın izini gör" |
| Bugün · discovery (no date) | fixed synthetic date 2000-01-01 | same engine, computed at runtime | same | exact math | none | worked example | — | "Köken taşını doldur" |
| Bugün · invitation | journey.intention | none (session choice) | static option list (`JourneyOptions`) | system invitation → user report once chosen | none (memory) | the chosen intention or the offer | change / clear | "Bir niyet seç" |
| Bugün · rhythm | — | `PendingRhythmSource` (refuses) | — | not built | — | the four-strand promise, honestly "P07" | — | — |
| Ben · security | key provider state | `SecurityStatus` (P03) | — | system report (facts of this build) | none | truthful status rows | self-test, purge cache | self-test |
| Yolum · scenario | fixed text | none | `JourneyOptions.futureSelfScenario` | system invitation | none | one labelled scenario | — | — |
| Yolum · weekly step | journey.pathStep | none (session choice) | static list | user report | none (memory) | the chosen step, P0 | "Vazgeç" | choose |
| Yolum · evidence ladder | journey.evidence | P0–P2 ladder (RWIP-01) | constitution C:3741 | user report | none (memory) | the reached tier, P2 marked unreachable | "Beyanı geri al" | "Yaptım" |

## 3. Rhythm contract (directive §4) — specified, not implemented

Code: `App/XRAI/Experience/RhythmContract.swift` (`RhythmSource` port, `RhythmReading`, `PendingRhythmSource`). Test `NT-LX-10` asserts the only implementation refuses to calculate and is deterministic.

| strand | content | class | rule |
|---|---|---|---|
| 1 exact arithmetic | a calendar-derived number for day/week/month with a method id, a version and a trace summary | exact math | deterministic: same inputs → same reading; a registered, versioned method (like `num.life_path.digits.v1`); the engine is a P07 deliverable with golden vectors |
| 2 symbolic interpretation | a tradition's theme for that number, with tradition name and source id | symbolic tradition | only from rights-clean content packs (P04/P10); always "bu geleneğe göre" |
| 3 the person's report | how the span felt, chosen by the person | user report | never inferred from any cycle; never from horoscope (LF-04); the word "enerji" may be the person's, never the system's measurement |
| 4 optional invitation | one small option or rest | system invitation | `none` is valid; no streak, no guilt after gaps (C:3676) |

The four strands are separate optional fields of one reading and are rendered as separate labelled lines; a screen must never merge them into one sentence. Daily cadence = one meaningful task + an alternative or rest; weekly = a 10–15 minute review and 1–3 priorities; monthly = a sprint review (LLE-04). Implementing strand 1 for any span is a P07 dependency change and needs an approved method registry entry; this phase adds none.

## 4. What the person can always do

Decline (every action is optional), correct (date, choices), forget (one operation clears date, draft and journey: `forgetAll`), leave (nothing is stored). These are the G5 guarantees of the slice and are asserted by `NT-LX-09` and the existing session tests.
