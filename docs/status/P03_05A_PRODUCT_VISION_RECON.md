# P03_05A_PRODUCT_VISION_RECON — lawful UX recon of the Human Design App and alignment of the founder's vision with the constitution

**Date:** 2026-10-20 · **Requested by the founder** (not by the reviewer) · **Scope:** public App Store listing only (`apps.apple.com/tr/app/human-design-app/id862678884`), no app binary, no copyrighted content, no scraping — "replica skills = lawful UX recon only" (CLAUDE.md §3).

Türkçe özet: Kurucu, Human Design App'ten daha iyi bir ürün istiyor ve vizyonu özetledi: isim/numeroloji/gematria/ebced analizleri, astrokartografi, kişiye özel mühür/sembol (duvar kâğıdı), kabala/sefirot ve Human Design mantığının görsel "seksek" (0→10) versiyonu, her çizginin anlamı olan canlı/animasyonlu, ansiklopedi olmayan bir deneyim. Bu belge (1) rakibin herkese açık listeden görülebilen yapısını, (2) bizim nerede olduğumuzu ve neden "yavaş" göründüğünü, (3) vizyonun anayasa fazlarına nasıl bağlandığını, (4) tasarım araçları için kurucunun yetkilendirmesini dürüstçe kaydeder. Hiçbir ürün özelliği bu belgede "yapıldı" sayılmaz.

## 1. What the public listing shows (facts only)
- Developer: Healing Shore LLC · version 5.8.6 ("Arayüz iyileştirmeleri ve hata düzeltmeleri", 1 week before 2026-10-20).
- Monetisation: subscription "Human Design Premium – Annual" ₺899,99 ("full access to all charts and descriptions"); in-app purchase "Composite Charts" ₺2.499,99 (unlimited composite charts and explanations).
- Reviews visible in the screenshot: a user asking for Turkish language support ("Türkçe dil desteği istiyoruz", 8 years ago) with a thumbs-up developer reply — Turkish localisation is a visible gap.
- Positioning: chart + descriptions ("charts and descriptions"), composite (relationship) charts as the premium add-on.

## 2. Where XRAI stands and why the pace looks slow (honest)
- Constitution order (§89 P01 → P03): real-environment audit → deterministic math core → secure persistence → consent → features. We are at P03-05A: the vault, deletion invariant, backups, attachments, consent and interaction foundations exist and are tested on three hosts; the app still persists nothing personal and shows honest empty states for astrology/Human Design/name analysis (RootTabView "Keşfet": P07–P09).
- Every phase costs three host runs plus an independent review round; ten phases happened in two days. The slowness is in *visible product*, not in engineering throughput — and it is the price of "no silent resurrection, no false guarantees". A Human Design app that stores birth data without this foundation would be exactly what the constitution forbids.
- What has NOT started: the visual system of the product (the "seksek" journey), content engines (name/numerology beyond Life Path, gematria/ebced, astrocartography, Human Design math), the seal/symbol generator, animation. These are registry items for P04–P09 and need the rights audit (`rights-auditor`) and the epistemic reviewers before any claim ships.

## 3. The founder's vision mapped to constitution phases (no promise, a map)
| vision element | constitution home | precondition | epistemic class on screen |
|---|---|---|---|
| name / numerology / Pythagorean / gematria / ebced analyses | P07 (independent engines; §73 claim graph) | rights-clean method sources; `math-verifier` review; BOOT-01 style traces | exact math (the arithmetic) + symbolic tradition (meanings), never blended |
| origin / city / place / astrocartography | P08 (ephemeris packs, §82 model neutrality) | signed content packs; ephemeris licence; birth place/time classes under consent purposes (`birthPlace`, `birthTime`) | exact math (positions) + symbolic tradition (interpretations) |
| past / present / future, partner analysis, life turning points | P07–P09 + P05 (Future Self is a user-edited hypothesis, §72) | consent purposes for partner data (third-party rules: no suspension, delete now) | symbolic tradition / system invitation / user report |
| personal seal / symbol (wallpaper, poster) | P04 design system + P09 (generated artefacts) | design system in Figma (authorised below); generator is deterministic from the user's data classes; export is user-initiated (`userEncryptedBackup`-class destination for the image is NOT needed: the seal is a derived, non-personal-looking artefact — classify at P09 with the privacy guardian) | derived result + symbolic tradition |
| Kabbalah / sefirot / Human Design logic as the "hopscotch 0→10" visual system | P04 (interaction model, §88 design direction) | a documented, versioned mapping (which square = which concept, which connector = which transition), reviewed by `claim-epistemic-reviewer`; no "crown/higher consciousness" claim is presented as fact | symbolic tradition, explicitly framed as a lens |
| chakras, hermeticism, micro/macrocosm, yin-yang, Jung, 16 types, "energy/frequency" | P07–P10 content packs | each tradition sourced and labelled; 16 types and psychology non-diagnostic (§85); "frequency/energy" claims are symbolic, never physics | symbolic tradition; never exact math |
| animated, living, no visible machinery, natural language | P04 design system + P06 guide | Reduce Motion first-class (exists); on-device only; every sentence labelled by class (exists as badges) | — |

Rule carried into every phase: the "seksek" is a **presentation grammar**, the math behind each square is a separately tested, traceable engine (like `NumerologyLifePath`), and the mapping between them is a versioned registry entry with a rights and epistemic review — this is how the product becomes more than a chart-and-descriptions app without becoming an unsourced one.

## 4. Design tools — founder authorisation recorded (2026-10-20)
The founder authorised Figma (the claude.ai Figma connector) and Claude design skills for the product design phases. Constitution rule: tools only from `docs/tools/TOOLS_AND_SKILLS_INSTALL_LEDGER.md`, no MCP without an ADR. Action taken in P03-05A: the authorisation is recorded in the ledger as `FOUNDER_AUTHORIZED — design phases (P04+)`; it is **not used in P03-05A** (consent/risk screens use the existing SwiftUI design system). An ADR-BOOT-011 "Design tooling" is proposed for P04 start: what is exported to Figma (tokens, components, no personal data), what comes back (design specs), and the rule that Figma never holds user data.

## 5. Immediate recommendation to the founder (decision, not action)
1. Approve a **P04 design-system gate** to run *in parallel* with P03-05B (they do not share files): the hopscotch grammar, the seal generator's visual language, motion rules — in Figma under ADR-BOOT-011, with the existing token system as the seed.
2. Keep the security track as is; it is what makes a Human Design competitor trustworthy in Turkey's market (birth data is sensitive by law; local-first + user-held recovery is the differentiator the competitor's listing does not show).
3. Decide the subscription model (open decision `SUBSCRIPTION_MODEL`): the competitor's annual ₺899,99 + ₺2.499,99 composite add-on is one data point; XRAI's pricing stays an open decision until App Store Connect data exists.
