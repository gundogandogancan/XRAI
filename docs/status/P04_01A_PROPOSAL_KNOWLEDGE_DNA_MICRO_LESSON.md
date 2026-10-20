# P04_01A_PROPOSAL — the first genuine Knowledge DNA experience: one original, rights-cleared, source-backed interactive micro-lesson on the Anlam stone

**Date:** 2026-10-20 · **Status:** PROPOSAL (NOT_STARTED; separately gated; nothing implemented) · **Prerequisite:** P04-00 merged into main · **Does NOT include:** any P07–P10 calculation engine, any tradition's interpretation of the person's own number, any persistence.

Türkçe özet: İlk gerçek "Bilgi DNA'sı" deneyimi: Anlam taşından açılan tek bir özgün, hakları temiz, kaynaklı ve etkileşimli mini ders. Konu önerisi: "Bir sayı nasıl anlam kazanır? Hesap ile atfı ayırmak." Dersin aritmetik kısmı kamu malı matematik (dokuz atma / rakam kökü), atıf kısmı "modern numeroloji bu sayıya tema atfeder" cümlesinin kaynaklı ve etiketli hâli. Ders kişi hakkında hiçbir iddia üretmez; bunu test kanıtlar. Kaynaklar `rights-auditor` denetiminden geçmeden tek cümle yayınlanmaz.

## 1. Why this lesson first (G1 problem, §89 slice "free original micro-lesson")
The person already sees an exact Life Path and the sentence "anlamı henüz eklenmedi". The first honest next step is not to add a meaning but to teach, in two minutes, the difference between what the arithmetic does and what a tradition *attributes* — the one distinction the whole product rests on (§73, F §06). It needs no personal data, no engine, no model; it is original XRAI content; its sources are either public-domain mathematics or a cited historical text used only for a short attributed statement.

## 2. Lesson design (compact, interactive, not an encyclopedia)

**Title (TR):** "Bir sayı nasıl anlam kazanır?" · **Entry:** Anlam stone (8) panel → "Mini ders" (the stone stays `pending` for tradition content; the lesson is a separate, labelled surface inside the panel). · **Length:** ≤ 5 screens, ≤ 120 words each, ≤ 3 minutes.

| step | what the person does | class | source |
|---|---|---|---|
| 1 Gör | watches the digits of a date add up and reduce, one tap per step (their own session date if present, else the fixed example 2000-01-01); every step is computed by `NumerologyLifePath`/`DigitReduction` at runtime | exact math | the registered method (`num.life_path.digits.v1`); the mathematics of digital roots / casting out nines is public domain |
| 2 Dene | sorts four short statements into two baskets, "hesap" or "atıf" (e.g. "36 → 9" vs "9 tamamlanmayı temsil eder"); immediate feedback with the reason | exact math vs symbolic tradition (as labels on the cards) | XRAI original rubric |
| 3 Bil | one attributed sentence: "Modern Pisagorcu numeroloji, indirgenmiş sayıya temalar atfeder (kaynak: …, yıl, sayfa)" — shown with the badge "Sembolik gelenek" and a visible source line; NO theme for the person's number is stated | symbolic tradition (attributed statement about a tradition, not a claim about the person) | ONE public-domain early-20th-century numerology text, to be chosen and cleared by `rights-auditor` (candidates in §4) |
| 4 Ayır | the person is asked the lesson's one question: "Yaşam Yolu 9 hesabı ile '9 tamamlanmadır' cümlesi arasındaki fark nedir?" with three answers; the correct one names the two classes | system invitation → user report | XRAI original |
| 5 Yansıt (optional) | "Bu sayıya bugün sen ne anlam verirsin?" — one line, session-only, labelled "Senin beyanın"; or skip | user report | — |

Completion is recorded as P1 ("ders yapıldı", self-report) in the session journey only; never as a skill (G10).

## 3. Outputs required by the gate (directive GATE 3)
- **Source and rights evidence:** a `KnowledgeDNA` registry entry for the lesson: claim ids, each with source id, edition/year, rights status (`PUBLIC_DOMAIN` / `ORIGINAL_XRAI`), reviewer, date (`docs/registries/overlay_knowledge_dna/lesson_number_meaning_v1.json`). `rights-auditor` sign-off recorded before any text ships.
- **Method/version:** `lesson.number_meaning.v1`; arithmetic through the existing method ids; the rubric versioned with the lesson.
- **Epistemic classification:** every card carries one badge; the attributed sentence carries the source line inline; tests assert no card mixes classes.
- **Compact SwiftUI experience:** `App/XRAI/Knowledge/NumberMeaningLesson.swift` (+ a `LessonFlow` model); opened from the Anlam panel; tokens only; audits on every step.
- **Optional real-world reflection/action:** step 5 + "bir kişiye bu farkı anlat" as the one optional action (system invitation).
- **Accessibility and offline acceptance:** XCUI audit on all five steps incl. accessibility size; airplane-mode run (no network code exists; a test asserts no `URLSession` symbol in the app binary's link map, as today).
- **Tests that the lesson never makes unsupported personal claims:** `NT-KD-01` lexicon over every lesson string; `NT-KD-02` no second-person claim pattern ("sen …sın/sin", "senin … kaderin/amacın") outside the user-report step; `NT-KD-03` every statement in step 3 resolves to a registry claim id with rights status cleared; `NT-KD-04` the sorting rubric's answer key equals the registered classes; `NT-KD-05` step 1's numbers equal the engine's trace for the same date; `NT-KD-06` completion writes nothing to disk (defaults suite unchanged).

## 4. Source candidates (NOT cleared; for the rights auditor)
- Casting out nines / digital root: public-domain mathematics; reference texts in the public domain to cite for the historical note: L. E. Dickson, *History of the Theory of Numbers*, vol. 1 (1919), chapter on casting out nines; Fibonacci, *Liber Abaci* (1202) — citation only, no reproduction.
- An attributed statement that modern numerology assigns themes to reduced numbers: a public-domain early-20th-century English numerology text (e.g. L. Dow Balliett, *The Philosophy of Numbers*, 1908 — publication status to be verified by the auditor; used for ONE attributed sentence, no theme table reproduced).
- Nothing from the founder's Human Design scans; nothing from modern copyrighted numerology books.

## 5. Non-goals and boundaries
No meaning for the person's own number. No P07 engine (name, cycles), no P08/P09/P10 content. No persistence. No model. No Figma unless ADR-BOOT-011 is accepted first. The Anlam stone stays `pending` for tradition content; the lesson is labelled as a lesson, not as the stone's result.

## 6. Acceptance for the gate (what "done" means)
Registry entry cleared · lesson flow TESTED on Simulator and device · NT-KD-01…06 green · audits green · screenshots · founder's two-minute walkthrough recorded as MANUAL_PENDING until done. Estimated size: one phase (P04-01A), no dependency changes.
