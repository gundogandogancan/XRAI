# XRAI v3.2 — Kapsam, Eksik ve Claude BOOT-00 Denetimi

**Tarih:** 2026-10-19  
**Durum:** Gerçek dosyalar üzerinden şartname denetimi; iOS kod/çalıştırma doğrulaması DEĞİL.  
**Ana kaynak:** `XRAI_ULU_EVREN_CANONICAL_EXECUTION_v3.2/docs/canon/XRAI_ULU_EVREN_COMPLETE_BUILD_CONSTITUTION_v3.2.md` (35.131 satır) ve `CLAUDE_FIRST_SESSION_v3.2.md` (29 satır).  
**Sınır:** Erişilebilir XRAI konuşma bağlamı, özetler, mevcut arşivler ve ilgili dosyalar incelendi. Tüm geçmiş sohbetlerin kelimesi kelimesine eksiksiz arşivi mevcut değil; tamamı okundu iddiası yapılmaz.

## 1. Doğrulanmış kapsam

- Misyon: local-first, native iOS, insanın kendini ve mümkün geleceklerini keşfi; değişmez kader veya klinik tanı iddiası yok.
- UX: beş sekme (Bugün, Ben, Keşfet, Yolum, XRAI), gerçek ücretsiz Life Path, StoreKit, kaynak ve gizlilik kontrolleri.
- Matematik: sürümlü numeroloji, doğum/isim/tarih/takvim, astroloji/Local Space/astrocartography, HD Design −88° Güneş boylamı, gate/line/channel, BaZi, Gematria, I Ching; gerçek matematik ile sembolik yorum ayrı.
- Bağlamsal katman: isteğe bağlı ebeveyn isimleri/doğum sırası, psikometri ve 16 keşif yaklaşımı, Big Five, Jung, Maslow, Future Self; üçüncü kişilerin verileri korumalı.
- Güvenlik: cihaz içi kişisel kasa hedefi, dışarı veri çıkışı varsayılan reddi, açık izinli provider çağrıları, kontrollü kolektif bilgi gelişimi.
- Araştırma: 298 Human Design fotoğrafı envanteri; Book of Wisdom ve dört astroloji eseri için hak/kaynak/bağımsız uygulama kuralları.
- Görev modeli: tek aktif XRAI repo; AHTOVIA sadece gelecekte izinli sözleşme; Claude P00 repo audit, P01 testli saf Swift ilk matematik çekirdeği, P02 öncesi dur.

## 2. Kaynaklardaki doğrulanmış sayılar

| Kayıt | Gerçek durum |
|---|---|
| v3.2 kanonik anayasa | 35.131 satır |
| `REQUIREMENT_TO_ENGINE_MATRIX_v3.1.json` | 100 gereksinim aile kaydı (uygulama kanıtı değil) |
| `ORIGINAL_MATH_METHOD_REGISTRY_v3.2.json` | 19 yöntem sözleşmesi (tam matematik implementasyonu değil) |
| `PHASE_EXECUTION_DAG_v3.1.json` | 14 faz (durum NOT_VERIFIED) |
| `EXECUTION_OVERLAY_TASKS_v3.2.json` | 18 ek görev (NOT_STARTED) |
| `NEW_ACCEPTANCE_TESTS_v3.2.json` | 98 yeni kabul testi (NOT_RUN) |
| `RELEASE_AND_TEST_GATES_v3.1.json` | 86 v3.1 kabul testi (NOT_RUN) |
| `UX_PIXEL_SCREEN_CONTRACTS_v3.2.json` | 12 detay seviyesi sınırlı ekran/surface sözleşmesi (148 adayın tamamı değil) |
| `OPEN_DECISIONS_v3.1.json` | **16** açık karar; ilk promptun “20” ifadesi ile TUTARSIZ |
| Paket validator | PASS yalnız JSON/ZIP/şartname yapısı, **Xcode/iOS testi değil** |

## 3. Henüz kapanmamış gerçek blokörler

**P0 — Kodlamadan önce:** Kullanıcının gerçek XRAI repo ve mevcut kod durumu bilinmiyor. Tam önceki sohbet arşivi indirgenmiş özetlerle eşdeğer değil. Eski req/phase ID’leri ve tüm özellikler için `traceability` crosswalk kanıtı henüz oluşturulmadı. 20/16 açık karar tutarsızlığı var.

**P1 — Matematik:** 19 üst-seviye yöntem taslağı, numeroloji ekollerinin ve HD gate sıralamasının gerçek testli uygulaması değildir. Tarihsel timezone, yüksek enlem, doğum saati belirsizliği, −88° kök bulma, Local Space, eski astroloji ekol varyantları ve özel edge case fixture'ları gerçek kodla sınanmalı.

**P1 — Kaynak:** 13 benzersiz HD PDF'deki 298 taramanın tamamı sayfa/paragraf ve hesap kuralı bazında doğrulanmadı. Book of Wisdom tüm ciltleri ve Lilly/Dorotheus/Valens/Ptolemaios'un kullanılan modern baskıları tam araştırma/hak sürecini bitirmedi. Astro.com/Jovian Archive kaynaklarının izinsiz kazınması veya kapalı sistemlerinin kopyalanması yok.

**P1 — Gizlilik/AI:** iPhone Secure Enclave/Keychain/şifreli DB/kurtarma politikası gerçek cihazda çalıştırılmadı. Lokal Türkçe model kalitesi, RAM/ısı/pil ölçümü yapılmadı; Fable, Replica Skill ve diğer MCP'lerin kurulu/yetkili/yararlı olduğu kanıtlanmadı. Aynı SDK'nın bulut modeli seçmediği ayrıca sınanmalı. Kullanıcı ve üçüncü kişi verileri örtük toplanmamalı.

**P2 — UX/ürün:** 148 aday ekran/akış, 43 uzman rolü, 7 yaşam gelişim boyutu, gerçek eğitim hizmetleri ve kanıt basamakları eski metinde var; 12 ekran sözleşmesi tüm durum/senaryo, piksel, erişilebilirlik, performans, animasyon, lokalizasyon ve fiyatlandırma davranışlarının implementasyon kanıtı değildir. Her ekrana `requirement→UI state→data permission→implementation→test` bağlamak gerekir.

**P2 — Hukuk/yayın:** Swiss Ephemeris ve Human Design içerik/method hakları, psikometrik ölçek/marka lisansları, üçüncü kişi ve çocuk mahremiyeti, Apple IAP SKU fiyat/StoreKit, App Store güvenlik/metadata değerlendirmeleri açık. Kolektif model öğrenmesi için açık izinli hakları temiz bir eğitim seti mevcut değil.

**P3 — Başarı ölçümü:** Gerçek öğrenme içeriği, beceri rubriği, P0–P5 kanıtları, edinim/retention/fayda ölçümleri ve geri alınabilir güvenli kullanıcı hafızası canlıda doğrulanmadı. Sembolik “ruh amacı” önerisinin gerçek kişilik veya kader kanıtı olduğu ileri sürülmemeli.

## 4. Claude'a eklenecek kısa BOOT-00 görevi (eski promptu DEĞİŞTİRMEZ)

> Önceki `CLAUDE_FIRST_SESSION_v3.2.md` görevini aynen uygula. BOOT-00 raporuna **SOURCE_COVERAGE_AND_TRACEABILITY_AUDIT** bölümü ekle. `v3.2` dosyalarını ve `baseline/` arşivini hash'leriyle aç, 100 gereksinim ve bütün tarihsel faz/modül/özellik kaynaklarını tek tek req ID'ye eşleştir. Her kaynak/konuşma için `FULL_TEXT_AVAILABLE | SUMMARY_ONLY | NOT_AVAILABLE`, her özellik için `SPECIFIED | SOURCE_UNVERIFIED | RIGHTS_BLOCKED | CODED | TESTED` durumunu tut. 148 eski aday ekran/akıştan 12 v3.2 ekran sözleşmesine düşen kapsama farkını (tutulan, birleştirilen, düşen) kaydet; 43 rolün gerekli çalışma ve erişim sorumluluğunu ayrı incele. 19 yöntem kaydının bağımsız doğru matematik/golden fixture durumunu göster. `OPEN_DECISIONS_v3.1.json` fiilen 16 kayıt içerirken dokümandaki 20 açık karar iddiasını düzeltmek için kayıtlar üzerinden fark analizi yap. HD PDF envanterini tam metin denetimiyle karıştırma. Fable/Replica/MCP kurulu değilse uydurma. Yeni/eksik gereksinimleri yalnız ek kayıtla koru, mevcut kodu/planı ezme. Çalışmayanı DONE deme. P00 ve güvenliyse P01 sonrası DUR, raporu ChatGPT denetimine ver.

## 5. Nihai karar

Bu sürüm **ciddi ve kapsamlı bir tasarım/uygulama şartnamesidir**, ancak “tüm geçmiş konuşmalar eksiksiz okundu ve hiçbir eksik yok” garantisi değildir. **İlk doğru hareket:** Claude BOOT-00 ile gerçek repo + kapsam çapraz kontrolü, sonra saf Swift LifePath testleri, sonra durup kanıt denetimi. Bunun ardından şifreli kasa ve diğer uzman çekirdekler faz sırasıyla yapılır.
