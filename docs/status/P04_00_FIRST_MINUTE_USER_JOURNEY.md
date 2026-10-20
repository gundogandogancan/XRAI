# P04_00_FIRST_MINUTE_USER_JOURNEY — what a person sees and can do in the first sixty seconds, without an account, a model, a network or a stored record

**Date:** 2026-10-20 · **Branch:** `p04-00-living-experience` · Screens: `TodayLivingView` (Bugün), `SelfMapView` (Ben), `PathPreviewView` (Yolum). Evidence: screenshots under `docs/status/evidence/p04_00_screens/` (`before_sim/` = baseline `4c5235f`, `after_sim/` and `after_device/` = this branch), captured by the UI tests, exported from the xcresult bundles.

Türkçe özet: İlk dakika: tanıtımı atla → Bugün'de tarih, bir keşif (motorun hesapladığı örnek), harita, bir davet. Köken taşına dokun → tarihini gir (yalnız bellekte) → keşif senin kök sayın olur, haritada 1→0 çizgisi canlanır. Bir niyet seç ya da dinlen. Yolum'da bir haftalık adım seç, "yaptım" de: P1 öz bildirim; P2 bu sürümde ulaşılamaz ve öyle yazar. Hiçbir ekran ansiklopedi değildir: Bugün 4 kart, Ben harita + 1 panel + 1 kart, Yolum 4 kart.

## 1. The minute

| t | screen | what the person sees | what the person can do | what is NOT asked or claimed |
|---|---|---|---|---|
| 0–5 s | onboarding (unchanged, P03-01) | three short steps or "Şimdilik atla" | skip | no account, no date required |
| 5–15 s | **Bugün** | the day in words; one discovery (a Life Path worked example computed live by the engine on 2000-01-01, badge "Kesin matematik"); the court with stone 0 breathing and stone 1 dashed "ready"; one invitation card | tap "Köken taşını doldur", tap any stone, tap "Bir niyet seç", or nothing | no result about the person; no "your number is"; no tradition text; no energy |
| 15–35 s | **Köken** (stone 1 panel, pushed) | the question "Nereden başladım?", the meaning ("a sum and a reduction, not an interpretation"), the date fields, method and master-number rule, "Nasıl çalışır" collapsed | enter a date, compute, read the full trace, forget | the date is never written; the panel says so |
| 35–45 s | **Bugün** (back) | the discovery is now the person's exact root with its reduction steps; connector 1→0 flows; stone 1 active | "Hesabın izini gör", choose an intention | still no interpretation ("anlamı henüz eklenmedi") |
| 45–60 s | **Durum** (stone 5) or **Yolum** | rest or one small step; or a labelled scenario + one weekly step + the P0–P2 ladder | choose, undo, "Yaptım (öz bildirim)" | "Yaptım" is P1 (a statement), never a skill; P2 is shown as unreachable |

At any point: "Tarihi unut" clears the date, the draft and every choice in one operation; closing the app clears everything.

## 2. Card counts (no encyclopedia)

| screen | cards above the fold (iPhone 17, default size) | total cards |
|---|---|---|
| Bugün | opening + discovery + court + (invitation header) | 5 (opening, discovery, court, invitation, rhythm) |
| Ben | court | court + one panel (the selected stone) + one "Güvenlik ve gizlilik" card; the security status moved one level down |
| Yolum | scenario + weekly step | 4 (scenario, weekly step, evidence ladder, how it proceeds) |

Baseline comparison (`before_sim/`): Bugün had a full Life Path card with five technical rows and a "Günlük içerik" empty state; Ben was a vertical list of the feature, two links, the security card, the self-test card and preferences; Yolum was two empty states. After: the technical rows are one tap down, the map is the organising surface, the empty states became the court's planned stones with their phases.

## 3. Honesty rules applied in the minute

- Every card has exactly one epistemic badge; the court's ring is a state, not a claim.
- The discovery without a date is **computed**, not typed (`NT-LX-08`), so it can never drift from the engine.
- "Bugünün daveti" is a system invitation until chosen, then the person's report; rest is a first-class option (LLE-04, no streak).
- Future Self is "Örnek senaryo", "tahmin değil", with a sentence that it will be the person's own vision in P05.
- Evidence: P0 when a step is chosen, P1 on "Yaptım", P2 "bu sürümde eser eklenemez (P05)". No P3–P5.
- No forbidden words anywhere on these screens (`NT-LX-04`, `CopyLexicon`).

## 4. Navigation map (no dead ends)

Bugün → stone panel (push) → back. Bugün → "Bir niyet seç" → stone 5 panel. Ben → tap stone → inline panel (no modal). Ben → Güvenlik durumu / Gizlilik ve izinler / Yedekten geri yükleme (push). Yolum → choices inline; the weekly step appears on Bugün. Keşfet and XRAI tabs are unchanged honest empty states (P04/P06). Every pushed screen has the system back button; nothing opens a sheet.

## 5. MANUAL_PENDING (not claimed)

Human VoiceOver pass; a native English pass (titles exist as `titleEN`, screens are Turkish-first); SE-class width; Reduce Motion visual confirmation on a device; the founder's own first-minute impression (the point of this phase).
