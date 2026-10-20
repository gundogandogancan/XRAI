# P04_00_LIVING_EXPERIENCE_GRAMMAR — the court (seksek 0→10), grammar version `court.v1`

**Date:** 2026-10-20 · **Branch:** `p04-00-living-experience` (worktree, main untouched) · **Baseline:** `4c5235f1c6e0442a1b68fad90e4594873fe46630` · **Status:** CODED + TESTED on synthetic/session data; nothing persisted; no model; no network. **Source of the grammar in code:** `App/XRAI/Experience/LivingGrammar.swift` (the doc and the code must agree; `LivingGrammarStructureTests` asserts the structural rules below).

Türkçe özet: "Seksek" XRAI'nın kendi sunum grameridir: anayasanın iddia grafiğini (§73) on bir taş ve anlamlı bağlantılarla gösterir. Her taş bir sorudur; her bağlantı savunulabilir bir ilişkidir (hesaplar / beyan eder / yorumlar / kanıtlar / davet eder). Taş numarası yalnız yolculuktaki sıradır. Bu gramer Kabala Sefirot'u ya da Human Design bodygraph'ı DEĞİLDİR ve öyle pazarlanmaz. Sürümlüdür: anlam, taş ya da bağlantı değişirse `court.v2` olur.

## 1. Why a court

The constitution asks for an X-ray as *depth of understanding, never diagnosis* (F §04), a Personal Life Graph with edit/delete on every node (C:230), progressive disclosure (short insight → why → method → source → math, C:348) and "arkada evren, önde tek kumanda" (C:3376). A court does all four at once: the person sees eleven questions, not eleven features; each stone opens to its method and source; every stone can be revisited and corrected; and the machinery (engines, registries, consent, vault) stays behind the stones.

The founder's vision (recon doc §3) asked for a hopscotch "with meaning on every line". The rule that makes that true, and testable:

> A connector exists only when a registered method or a user action consumes the source stone's output to produce the target stone's output. A connector is drawn **solid and moving only when that path runs in this build and both ends are active in this session**. Everything else is dashed, still, and visible only when the person selects one of its stones.

## 2. The stones

| # | key | title | question (TR) | epistemic class now | runs in this build | planned phase |
|---|---|---|---|---|---|---|
| 0 | now | Şimdi | Bugün neredeyim? | system invitation | yes (calendar day, no personal data) | — |
| 1 | origin | Köken | Nereden başladım? | exact math | yes (`NumerologyLifePath`, BOOT-01 engine, session date) | — |
| 2 | name | Ad | Bana ne deniyor? | not built | no | P07 |
| 3 | place | Yer | Nereye aitim? | not built | no | P08 |
| 4 | rhythm | Ritim | Günün, haftanın, ayın düzeni ne? | not built (contract written: `RhythmContract.swift`) | no | P07 |
| 5 | state | Durum | Bugün nasılım? | user report | yes (session-only intention: rest or one small step) | — |
| 6 | bond | Bağ | Kimlerle bağlıyım? | not built | no | P07–P09 |
| 7 | pattern | Desen | Hangi desenlerle anlatılıyorum? | not built | no | P09 |
| 8 | meaning | Anlam | Gelenekler bu sayıya ne demiş? | not built | no | P04/P10 |
| 9 | direction | Yön | Nereye gitmek istiyorum? | user report | yes (session-only weekly step) | — |
| 10 | evidence | Kanıt | Gerçekten ne yaptım? | user report | yes (P0 → P1 self-report; P2 unreachable) | — |

Layout rows from the start: `[0] [1] [2,3] [4] [5,6] [7] [8,9] [10]`. **Single stones are turning points** where only one thing is possible (now, origin, time, pattern, evidence). **Paired stones are two sides of one question**: 2/3 what you are called / where you are from; 5/6 your state / your bonds; 8/9 meaning / direction.

**The return rule.** After 10 the court returns to 0: evidence feeds the next day. Nothing is ever "completed"; every stone can be revisited, changed or emptied (G5 human sovereignty, G14 correctability). The court has no score, no streak, no "level".

## 3. The connectors

| from → to | relation | class carried | note | live rule | phase |
|---|---|---|---|---|---|
| 1 → 0 | derives | exact math | the origin's calculation is shown today | trace exists | — |
| 0 → 5 | reports | user report | today's intention is the person's statement | intention chosen | — |
| 9 → 0 | invites | system invitation | this week's step reaches today as one reminder | step chosen | — |
| 9 → 10 | evidences | user report | a direction is tested by evidence | evidence ≥ P1 | — |
| 1 → 4 | derives | exact math | cycles will be computed from the birth date | never in this build | P07 |
| 4 → 0 | invites | system invitation | the day theme will arrive as an invitation | never | P07 |
| 1 → 8 | interprets | symbolic tradition | traditions will read the root number | never | P04/P10 |
| 1 → 7 | derives | exact math | the pattern needs date, time and place | never | P09 |
| 3 → 7 | derives | exact math | place is an input of the pattern | never | P09 |
| 2 → 8 | interprets | symbolic tradition | name analyses will be read by traditions | never | P07/P10 |
| 1 → 6 | derives | exact math | a bond analysis needs two origins | never | P07–P09 |

Rules asserted by `NT-LX-02`: a connector joins two distinct existing stones; a connector without a phase joins only stones that run in this build; no planned stone is an island. Rule asserted by `NT-LX-06…09`: in an empty session no connector is live; a date makes exactly `1→0` live; choices light `0→5`, `9→0`, `9→10`.

## 4. States of a stone (and what the person sees)

| state | meaning | visual | VoiceOver |
|---|---|---|---|
| active | real data or a real choice is present in this session | accent fill, solid accent ring, accent number | "etkin: <summary>" |
| available | the person can act here now | surface fill, dashed boundary ring, secondary number | "hazır: <prompt>" |
| pending | planned for a later phase, nothing runs | secondary surface, lock glyph, phase in the panel | "planlı, P0x" |
| locked by consent | would need a consent that does not exist in this build | as pending, purpose named | "izin bekliyor" |
| error | a calculation could not run | danger ring and number, message in the panel | "hata: <message>" |

Stone 0 always carries the **current ring** (gold, one highlight per screen): the journey is always "now". A selected stone has a thicker ring and the `isSelected` trait.

## 5. Information hierarchy (progressive disclosure, C:348)

1. The court (which stones are alive, which are planned) — one glance.
2. The stone's question and one plain-language meaning (panel header).
3. The state line: what is here now, in words.
4. The stone's own feature (date entry and trace on 1; choices on 5/9; the ladder on 10).
5. "Nasıl çalışır": the eight-question contract (input, method, source, class, purpose, output, correction, action) and the stone's connectors with their phase — collapsed by default.

Nothing on level 1 or 2 ever states a result as a fact about the person; level 3 names the class every time (badge).

## 6. What this grammar is NOT (non-equivalence, recorded for the epistemic reviewer)

- **Not the Sefirot.** The Kabbalistic tree has ten emanations plus Da'at and twenty-two paths with theological and lettered meanings. The court has eleven *questions* and relationships defined by XRAI's own engines. No stone is a divine attribute; no connector is a Hebrew letter; "10" is not "Keter" and "0" is not "Malkhut". `NT-LX-05` asserts that no stone text mentions sefira/keter/crown/divine/higher consciousness.
- **Not a Human Design bodygraph.** Stone 7 is where an independent HD engine would present its result (P09, rights pending); the court is not a chart.
- **Not a score.** Numbers are ordinal positions. There is no total, no "level", no completeness bar.
- **Not a prediction.** Stone 9 holds a scenario the person chose (F:126); stone 10 holds what the person reports, on the P0–P2 ladder (C:3741).

If a later phase wants to show a tradition's own diagram (Sefirot, bodygraph, chakras), it is a separate, sourced, symbolic-tradition surface inside a stone — never the court itself.

## 7. Versioning

`LivingGrammar.version = "court.v1"`. A change to any stone's question or meaning, to any connector, or to the row layout is `court.v2` with a migration note here. Copy fixes that do not change meaning are allowed within a version. The lexicon (`CopyLexicon.forbidden`) is part of the version and is asserted over every string of the grammar (`NT-LX-04`).

## 8. Open items for the reviewer

- Stone 5 ("Durum") deliberately offers **no mood scale** and **no "energy" meter**: only rest or one small step. A richer self-report (how the day felt, in the person's words) is a P05 decision with the privacy guardian.
- Whether stone 6 ("Bağ") belongs on the court at all before third-party consent rules are implemented — it is shown as planned so the person knows it will not appear silently.
- The names of the stones are first drafts in Turkish; the native English titles exist (`titleEN`) but are not shown yet (MANUAL_PENDING native review).
