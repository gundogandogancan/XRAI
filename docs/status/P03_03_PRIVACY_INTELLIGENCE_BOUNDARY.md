# P03_03_PRIVACY_INTELLIGENCE_BOUNDARY — what the intelligence layers may touch, and the AHTOVIA line

**Date:** 2026-10-20 · **Baseline:** `713468e` · Constitution §72 (three brains), §73 (claim graph), §82 (model neutrality), §85 (education), §89; ADR-BOOT-002.

Türkçe özet: Altı bilgi sınıfı birbirine karışmaz; kişisel kayıtlar izin olmadan model eğitimine, analitik servislere veya dış sağlayıcılara gitmez; Knowledge DNA yalnız hakları temiz ve kişisel olmayan bilgidir; Future Self kullanıcının düzenlediği bir varsayımdır; AHTOVIA ile otomatik kişisel veri paylaşımı yoktur, yalnız gelecekte açık izinli, tipli ve asgari bir köprü sözleşmesi olabilir.

## 1. Six classes and their homes

| class | examples | brain | storage | may leave device? | may train anything? |
|---|---|---|---|---|---|
| 1 public / rights-clear knowledge | method definitions, licensed lessons, public-domain texts | Knowledge Brain | signed content packs, app bundle | yes (it is public) | only as licensed |
| 2 deterministic results | `NumerologyTrace`, charts | Personal Brain (derived) | vault `derived_result` with `derivedFrom` | never by default | never |
| 3 symbolic/traditional interpretations | "according to the Pythagorean tradition…" | Knowledge Brain (templates) + Personal Brain (which lens the user enabled) | templates in content packs; selections in vault | templates yes; selections never | templates only |
| 4 user's own statements | journal, goals, values, answers | Personal Brain | vault | never by default; per-call explicit consent only | never |
| 5 system-generated suggestions | invitations, hypotheses ("EXPLORATION_ONLY") | Personal Brain (ephemeral unless the user keeps one) | memory; vault only if the user saves it | never | never |
| 6 personal behaviour & progress evidence | P0–P5 evidence, completed lessons | Personal Brain | vault | never by default | never |

Badges in the UI map 1:1: Kesin matematik (2), Sembolik gelenek (3), Senin beyanın (4), Sistem daveti (5), Henüz yok (not built); class 1 is shown as source citations; class 6 as evidence tier labels (P05).

## 2. Boundaries for the intelligence layers

- **Knowledge DNA** indexes class 1 and 3 templates only. It never embeds personal records. Retrieval over personal data (class 2/4/6) happens on-device in the Personal Brain index, encrypted at rest as vault attachments, keyed per user.
- **Future Self "Digital Twin"** is a user-edited scenario (class 4 + 5), not a model trained on the person. No profile vector leaves the device; no behavioural scoring is persisted without an explicit lens grant; the user can delete it like any record and the derived cascade applies.
- **Lifelong learning / Evolution Brain** receives nothing personal by default. The only inputs are: aggregate quality metrics the user explicitly opted into (separate consent purpose, separate screen), with re-identification review before any aggregation ships; never raw journals, names, dates or evidence.
- **Model routing (§82)**: `DETERMINISTIC` never touches a model; `MICRO_GUIDE`/`LONG_COMPOSITION` run on-device over a `ClaimGraph` built from classes 1–6 with their labels intact; `REMOTE_PRIVATE_AI` requires a per-call `perCallConsentedProvider` grant showing the exact payload classes, and is denied for classes 4/6 unless the user explicitly includes them for that call.
- **No cross-contamination rule:** a claim node keeps its `epistemicClass`; synthesis may juxtapose classes, never average them (§73).

## 3. AHTOVIA line
- Separate product, separate trust domain, separate app identifier; **no app group, no shared container, no shared Keychain access group** (today's entitlements: only `com.xrai.app` group). Test N20 verifies this.
- Future bridge (P09 seam): a typed, signed, minimal `LearningIntent` / `EvidenceReceipt` exported **by the user's action** through the share sheet or an explicit "AHTOVIA'ya gönder" consent purpose; never journals, birth data, names or raw evidence files; children's data domain never merges with the adult XRAI vault.
- Until that ADR exists, XRAI ships **no** AHTOVIA code path.

## 4. Verification
Static: entitlements contain no app group (checked in this phase: `keychain-access-groups` only). Policy: `hardDeniedForPersonalData` covers analytics/model training/cloud/ads/crash logs (TESTED). Planned: content-pack signature verification, Personal Brain index as encrypted attachment, per-call payload preview screen.
