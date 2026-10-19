# XRAI — KANONİK KODLAMA DEVİR NOTU v0.2
**Sürüm:** 2026-10-12 v0.2 — kullanıcı onaylı ÜCRETSİZ ÖNİZLEME → PREMIUM yapısı, global büyüme ve milyon kullanıcılık kapasite planı.
**İlk kodlama haftası:** 19–23 Ekim 2026 (plan).
**Durum:** MİMARİ TASLAK; çalışan XRAI kodu, milyon ölçeğinde load testi, Apple onayı, içerik lisansı ve gerçek monetizasyon kanıtı YOK.

**Otorite:** Bu dokümanın 'Yeni iş modeli' ve 'Growth & Scale' bölümleri, eski v0.1 belgesindeki doğrudan ücretli indirme/abonelik kararlarını ve ilk ödeme akışını günceller. Diğer güvenlik, özerklik, sembolik/ampirik ayrımı ve cihaz içi gizlilik koşulları geçerliliğini sürdürür.

# XRAI — ÖNCEKİ ANA SİSTEM NOTLARI
**Sürüm:** 2026-10-12 / planning v0.1  
**Planlanan ilk kodlama haftası:** 19–23 Ekim 2026  
**Durum:** Ürün tasarımı ve karar derlemesi. Çalışan XRAI kodu, güvenlik testi, lisans izni ve Apple onayı henüz doğrulanmadı.  
**Öncelik:** Minimum sürdürülebilir maliyet + maksimum ölçülebilir kalite + privacy/local-first + kanıt temelli yayımlama.  

> Bu dosya, XRAI konuşmalarındaki ana ürün, güvenlik, ödeme ve mühendislik kararlarının **kodlamaya geçiş için kullanışlı özeti**dir. 'Tam teknik spesifikasyon' değildir. `XRAI_Screen_Registry_v0_1.json` 83 aday ekranı ve eksik sözleşmelerini içerir.

## 0. Ürün kimliği ve tek cümlelik vaat
**XRAI — Personal Life Intelligence / Future Self Digital Twin.** Kullanıcı kendi kimliğini, değerlerini, ilgi ve yeteneklerini keşfeder; gelecekte olmak istediği kişinin varsayımsal rehberini oluşturur; uygun içerik, uygulamalı mikro öğrenme, günlük hedef ve yansıtma aracılığıyla kendi seçtiği yönde ilerler. AI kader, sağlık veya psikolojik teşhis iddiasında bulunmaz; kullanıcı yerine hayatını yönetmez.

**Tasarım felsefesi:** Steve Jobs (kullanıcıya karmaşıklık taşımama), Wozniak (denetlenebilir sade mühendislik), NASA (sistematik hata analizi, regresyon, kanıt), 'arkada evren, önde tek kumanda'.

## 1. Kesinleşmiş ürün doktrini
- Kullanıcı egemendir: yüksek riskli dış eylemler açık onay gerektirir; sessize alma, reddetme, düzeltme, silme ve alternatif gelecek mümkündür.
- Kaynak ayrımı: deterministik hesap; bilimsel/psikometrik ölçüm; kullanıcı öz bildirimi; sembolik gelenek; AI hipotezi. Bunlar birbirinin bilimsel kanıtı sayılamaz.
- Sembolik Human Design/astroloji/numeroloji/avuç içi/fizyonomi tarihi, 'doğru kişilik/kader/x-ray teşhisi' olarak pazarlanmaz.
- Ürün ilerlemesi: seçilen hedef -> uygun eğitim kaynağı -> ilk anlamlı deney -> geri bildirim -> ölçülebilen beceri/gelişim -> yeni adım.
- Özel günlük, kimlik, dijital ikiz, yüz/el ham görüntüsü ve hassas bilgiler varsayılan cihaz içidir. Bulut açık amaç/sağlayıcı izni olmadan kullanılamaz.
- Her kullanıcının özel zekâsı ayrı; kolektif katkı ayrı, isteğe bağlı ve veri minimizasyonlu. Gönüllü kaynak değerlendirmesinden bilimsel doğruluk türetilmez.
- 'BUILD -> TEST -> INDEPENDENT REVIEW -> EVIDENCE -> VERIFIED' olmadan tamamlandı denmez.
- Özel kriptografi icat edilmez. Güçlü Apple veri koruması, anahtar yönetimi, bağımsız test ve ihtiyaca göre post-quantum readiness tercih edilir; 'kırılamaz' iddia edilmez.

## 2. Ürün ana yüzeyleri (5 sekme)
1. **Bugün:** Günlük gerçek enerji check-in, ayrı sembolik gün teması, tek anlamlı adım, plan, bildirim, akşam yansıtma.
2. **Ben:** Değerler, kişilik öz değerlendirmesi (uygun kamu malı/izinli ölçek), beceriler, ilgi alanları, kimlik atlası ve düzeltilebilir hafıza.
3. **Keşfet:** Numeroloji, astroloji, lisansı çözülmüş Human Design, tarihsel el/yüz sembolizmi ve ev/yer numerolojisi.
4. **Yolum:** Future Self, alternatif gelecek senaryoları, hedefler, öğrenme kaynakları, mikrodersler, gerçek dünya görevleri ve beceri kanıtı.
5. **XRAI:** Sokratik rehber, Future Self Mentor, karar keşfi ve kaynaklı açıklamalar.

**Aday ekran envanteri:** 73 kullanıcı/onboarding yüzeyi + 10 operasyon paneli = **83 aday ekran/akış**. Sadece isim envanteri mevcut; her ekranın input/action/state/a11y/test sözleşmesi ayrı tamamlanmalı. JSON dosyasında statüler NOT_STARTED.

## 3. 12 ürün uzmanlığı (modüller, bağımsız lisans kapıları)
Self Identity, Human Design Universe, Astrology Universe, Numerology Universe, Palm Discovery, Face/Physiognomy History, Place/Home Numerology, Daily Energy, Life Journey, Personality Explorer, Personal AI Guide, Self Actualization.

- Human Design: 9 merkez, 64 kapı, 36 kanal, tip/otorite/strateji/profil/definition/cross, Personality+Design (güneş 88° farkı), Color/Tone/Base, Variable, transit, ilişkiler, ileri modüller; ancak ticari hak denetimi zorunlu.
- Astroloji: tarihsel saat dilimleri, konum, ephemeris lisansı, gezegen konumları, evler/açılar/transit; belirsizlik ve sürümlenmiş yöntem.
- Numeroloji: compound/root/master, Türkçe karakter politikası, tam hesap adımları, kişisel yıl/ay/gün ve isim/yer hesapları.
- El/yüz: yerel görüntü işleme, kullanıcı düzeltmesi, tarihsel sembolik yorum; yüzden zekâ/ahlak/karakter/sağlık çıkarılmaz, avuç içinden ömür/sağlık kehaneti yok.
- 'Günlük enerji' gerçek öz bildirim + ayrı sembolik gün yorumu + kullanıcı hedefi olarak ayrılır.

## 4. Dokuz mimari katman
L0 Constitution Kernel; L1 Reality & Evidence; L2 Personal Identity; L3 Life Memory Graph; L4 Future Self; L5 Learning & Action; L6 Daily Guidance; L7 Intelligence Orchestrator; L8 Evolution & Verification. Bunlar ardışık her istekte çalışacak bir pipeline değil, sorumluluk katmanlarıdır.

### Çekirdek varlıklar
`BirthContext`, `UserIdentity`, `ConsentGrant`, `Claim`, `SourceRecord`, `SymbolicChart`, `LifeEvent`, `MemoryItem`, `Goal`, `FutureSelfScenario`, `Skill`, `SkillEvidence`, `LearningMission`, `LearningResource`, `Recommendation`, `Feedback`, `NotificationDecision`, `IntelligenceContribution`, `ModelVersion`, `AuditRecord`.

### İddia/veri standardı
`sourceType, provenance, epistemicClass, validAt, recordedAt, uncertainty, confirmedByUser, methodVersion, rightsStatus, supersededBy, deletionStatus`. Örnek 'astronomiyi seviyorum' öz bildirim; 'yaşam yolu 9' aritmetik+sembolik; 'bilim insanı olmalı' bilimsel çıkarım değil ve zorlayıcı öneriye dönüştürülemez.

### Olay sistemi
`USER_GOAL_CREATED/CHANGED`, `DAILY_CHECKIN_RECORDED`, `LEARNING_MISSION_STARTED/ASSESSED`, `CONSENT_REVOKED`, `MEMORY_CLAIM_DISPUTED`, `RESOURCE_BECAME_UNAVAILABLE`, `FUTURE_SCENARIO_REVISED`, `RECOMMENDATION_REJECTED`, `MODEL_EVALUATION_FAILED`. Olaylar şema versiyonlu, idempotent, yetki kontrollü; kullanıcı silme işlemlerine saygı gösterir.

## 5. Gelecekteki benlik ve eğitim motoru
- Present Self: beyanlar, gözlenen beceriler, koşullar, belirsizlik.
- Desired Future: kullanıcı seçimi; birden fazla senaryo ve hedef değişimi mümkün.
- Gap: bilgi, beceri, zaman, bütçe, dil, erişilebilirlik.
- Experience: özgün mikroders, makale/kitap/video için doğrulanmış kaynak, küçük pratik, gerçek dünya görevi, Sokratik soru.
- Evidence: `DISCOVERED`, `STARTED`, `SELF_REPORTED_PRACTICE`, `ASSESSED`, `DEMONSTRATED`, `TRANSFER_EVIDENCE`. Video izlemek beceri kazanmak değildir.
- Resource Passport: sağlayıcı, kanonik URL, tür, zorluk, önkoşul, dil, erişilebilirlik, ücret/birim, lisans, doğrulama tarihi, geçerlilik ve fallback.
- Eğitim bilgi kaynakları adayları: IPIP (uygun kişilik maddeleri), O*NET, ESCO, OpenAlex, Open Library (ticari kullanım/kota hassas), YouTube Data API, MIT OCW, Khan Academy (hak ve erişim kontrolü).
- Einstein veya başka kişiyle sembolik numeroloji eşleşmesi, meslek, zeka veya bilim başarısının kanıtı değildir; merak uyandırıcı keşif başlangıcı olabilir.

## 6. Ajan ve evrim politikası
Orkestratör en küçük yeterli aracı seçer: NO_AI / deterministik / local / small model / high reasoning / human review.
Uzmanlar: identity, symbolic, memory, future planner, learning, skill evaluator, Socratic, daily, resource auditor, notification guardian, privacy/security, evolution evaluator.
Her ajan için Agent Card + domain/tool manuals + golden/adversarial eval + policy + scoring + budget + runbook zorunlu.
Kişisel uyarlama (tercihler) ile platform modelinin güncellenmesi ayrı hatlardır. Otomatik kod/policy değiştirmek yasak. Evolution: observation -> hypothesis -> offline eval -> review -> canary -> rollback.

## 7. Özel veri, kuantum ve maliyet
- Hassas kullanıcı verisi cihazda şifreli vault; kilitli ekran koruması, uygun iOS Data Protection, Keychain, Secure Enclave destekli anahtar politikası.
- Yüz/el ham görüntüleri varsayılan sunucuya gönderilmez; hafıza ve indeksler kullanıcı kontrolündedir.
- Kurtarma/backup ayrı tasarım: cihaz-bağımlı anahtar kaybı = kurtarılabilirlik sorunu. İsteğe bağlı E2EE recovery ayrı izin ve test ister.
- Uyumlu Apple cihazında yerel AI; olmayan cihazda kurallara dayalı alternatif, kullanıcı izin verirse bulut.
- Post-quantum crypto agility: Apple/platform standart desteği + hibrit PQ TLS uygunluk testi; AES-256-GCM yerel veri; özel protokol icat edilmez; kırılamaz iddiası yok.
- Kolektif zekâ: kaynak yararlılığı/öğrenme kanıtı/güvenlik hataları için izinli veri minimizasyonu, istatistiksel gizlilik, sahte katkı denetimi. Ham özel günlükler varsayılan model eğitiminden dışarıda.
- Ekonomik optimizasyon: birime düşen yararlı aksiyon maliyeti; deterministik önce; cache ve kota; performans/gizlilik/güvenlik floor'u geçilmeden maliyet optimizasyonu yok.

## 8. Ekim 2026 gelir modeli: YENİ / KESİNLEŞMEMİŞ KARAR
- Kullanıcı **aylık $5.55** öneriyor. Bu hedef fiyat, App Store Connect uygun fiyat noktası açısından doğrulanmalı. Standart USD 10 sent basamaklarının yanında Apple özel fiyat seçeneğini açıklıyor; kesin kullanılabilirlik doğrudan konsolda kontrol edilmeli. Yakın seçenekler $5.49 / $5.59.
- Öneri: yıllık **$49.99** alternatif. Bir yıllık $5.55 aylık karşısında yaklaşık %25 indirim. Hâlâ test hipotezi.
- Önceden tek seferlik indirme bedeli düşünülmüştü; aylık ücret istenmesi nedeniyle **ücretsiz indirme + sınırlı önizleme + StoreKit 2 premium abonelik** öneriliyor. Kullanıcı onayı bekleniyor; iki kez zorunlu ödeme alınmamalı.
- Apple 3.1.2: abonelik süreklilik arz eden gerçek değer sağlamalı. Restore, cancel, billing grace, refund, entitlements, aile paylaşımı (uygun olduğunda), paywall açıklamaları tasarlanmalı.
- Small Business Program'a kabul edilirse uygun bölgelerde %15 komisyon varsayımsal ekonomi modeli; vergi/iadeler/ülke koşulları ve yüksek maliyetli AI ayrıca değerlendirilmeli.

## 9. App Store ve fikrî hak kapanış kapıları
- 4.3(b) fal/astroloji kategori doygunluğu; gerçek kişisel gelişim/öğrenme akışı ile anlamlı farklılaşma kanıtı.
- 1.1.6 yanıltıcı tahmin, 1.4 tıbbi iddialar, 5.1 gizlilik, 5.2 hak ve lisans, 3.1 ödeme, 2.1 tamamlanmış ürün.
- XRAI markasının ad çakışması (XRAI Glass vb.) için tescil/ülke/sınıf araştırması P0.
- Human Design'ın kaynak grafik, marka, ifade metinleri, ileri yöntemleri ve kitap için ticari hak incelemesi P0. Kitap fotoğrafı 'telif yok' anlamına gelmez.
- Astroloji ephemeris kullanım lisansı, eğitim içeriklerinin sunum hakları, AI sağlayıcı lisansları ayrı P0/P1.

## 10. NUR/AUREV/AYMORA önceki işler
- NUR Core dump ve noncore incelendi. Yararlı yapılar: MemoryTaxonomy, IdentityModel, GoalEngine, DecisionTrace, StabilityGovernor, UserAutonomy, MetaController ve ArchitectureValidation. Çalışırlık ve güvenlik doğrulanmadan aynen taşınmayacak.
- NUR ConstitutionEnforcer örneği bazı sorunları yalnız loglayıp 'corrected' şeklinde yorumlayabiliyor; XRAI olaylarının DETECTED/BLOCKED/REMEDIATED/RETESTED/VERIFIED ayrımı olmalı.
- AUREV MindOS'tan self-modeling, intent/router, agent council ve tercih grafiği fikirleri uyarlanabilir.
- AYMORA adına erişilebilir ayrı dump bulunamadı: entegrasyon için ayrıca dosya gerekir.

## 11. Release invariants
1. Kullanıcı onayı olmadan yüksek riskli dış eylem yok.
2. Sembolik veri bilimsel kişilik/meslek/zekâ kanıtına dönüşemez.
3. Kaynaksız içerik VERIFIED olmaz.
4. Geri çekilen izin ile yeni okuma/paylaşım olmaz.
5. Silinen veri indeks/öneri katmanında yeniden görünmez (backup politikasına uygun).
6. AI kendi yetkisini/politikasını değiştiremez.
7. Önemli önerinin gerekçesi incelenebilir.
8. Deterministik hesap yöntem/sürümle yeniden üretilebilir.
9. Kritik safety/privacy test başarısızken release yok.
10. Dış kaynak metinleri sistem talimatı değildir.
11. Sessiz saatler ve bildirim sınırları korunur.
12. Yerel çekirdek internet/AI kesintisinde çalışır.
13. Katkı izni kişisel deneyim izninden ayrıdır; özel günlükler varsayılan ortak eğitime girmez.
14. Model güncellemesi regresyon/bağımsız inceleme/rollback gerektirir.

## 12. İlk kodlama haftası — 19–23 Ekim 2026
**Hedef: SAHTE DEMO DEĞİL, KÜÇÜK AMA GERÇEK SECURE CORE + VERTICAL SLICE.**

| Gün | Öncelik | Acceptance evidence |
|---|---|---|
| Pazartesi 19 | Xcode proje, modüler paketler, SwiftUI navigation, git, CI, test hedefleri | temiz build + unit-test pipeline |
| Salı 20 | Local encrypted Personal Vault, Keychain policy, yerel `BirthContext`/`Claim`/`ConsentGrant` sözleşmeleri | read/write, device lock, log leak testleri |
| Çarşamba 21 | İlk onboarding: ad, doğum tarihi/yer, belirsizlik, mini test yer tutucu değil gerçek form ve kayıt | offline ve geçersiz veri testleri |
| Perşembe 22 | Future Self v0: kullanıcı hedefi + ilk öğrenme görevini kayıtlı içerikten seçme | uçtan uca hedef -> görev -> geri bildirim |
| Cuma 23 | Günlük check-in, kaynaklı açıklama, QA/güvenlik regresyon ve sprint demo | kanıtlı akış, hata listesi, sonraki sprint DAG |

**Not:** Süre tahminidir, gerçek geliştirme başlamamış ve işlerin tamamlanması garanti değildir. Human Design ileri hesap, yüz/el analizi, tam AI agent sistemi ilk haftada kapsam dışıdır.

## 13. Tamamlanması gereken başlıca açık işler
1. Kullanıcının fiyat ve ödeme yapısı onayı; App Store Connect gerçek USD ve TR fiyat noktaları.
2. XRAI marka/trademark hukuki inceleme ve paket kimliği.
3. Human Design lisansı, ephemeris lisansı, kitap ve harici eğitim kaynak hakları.
4. 83 Screen Contract detayları: girdi, hata, offline, erişilebilirlik, gizlilik, test.
5. Kanonik domain/command/event/API sürümlü şemalar.
6. Güvenlik modellemesi, kurtarma/backup, kullanıcı silme kanıtı.
7. On-device AI desteği ve bulut AI veri aktarımı sınırları; latency/batarya/cost testi.
8. Kolektif katkı için hukuki dayanak, izin/denetim ve kötüye kullanım önleme.
9. Gerçek kullanıcı pilotu ve yarar/retention metrikleri.
10. TestFlight ve Apple başvurusu — henüz yok.

## 14. Kaynak/otorite sırası
1. XRAI Constitution ve kullanıcı tarafından onaylanmış ürün kararları.
2. Kaynak ve veri hakları, yasal/regülasyon koşulları, Apple App Review kuralları.
3. Kanonik ekran/domain/veri/agent registry ve ADR.
4. Test, independent review, evidence ledger.
5. Uygulama kodu ve runtime config; çelişki sessizce kapatılmaz, issue/change request açılır.

### Temel resmî referanslar
- Apple App Review: https://developer.apple.com/app-store/review/guidelines/
- Apple subscriptions: https://developer.apple.com/app-store/subscriptions/
- Apple price points: https://developer.apple.com/in-app-purchase/
- Apple Small Business Program: https://developer.apple.com/app-store/small-business-program/
- OWASP Mobile Security Testing: https://mas.owasp.org/
- NIST PQ standards: https://csrc.nist.gov/projects/post-quantum-cryptography

**Gerçek durum:** Bu belge bir release veya çalışan kod kanıtı değil; 19 Ekim'de mühendislik başlangıcında çelişkileri azaltmak için tek devir referansıdır.


# v0.2 — ÜCRETSİZ ÖNİZLEME → PREMIUM → GLOBAL ÖLÇEK

## 1. Kesinleşen yeni ürün kararları
- Ücretsiz indirme, gerekli olmayan hesap oluşturmadan ücretsiz ilk keşif.
- Ücretsiz ilk keşif: ad (isteğe bağlı olarak soyad), doğum tarihi, doğum yeri (astroloji için isteğe bağlı; numerolojik hayat yolu hesaplamak için zorunlu değil), doğum saati bilinmiyorsa 'Bilmiyorum'. Kullanıcı yalnızca doğum tarihiyle numerolojik hayat yolu önizlemesini tamamlayabilir.
- Önizleme gerçek matematiksel hayat yolu hesabını ve ücretsiz kısa sembolik yorum ile bir yansıtma sorusunu içerir. Kısa numeroloji çıktısı kişilik, kader, zeka, sağlık veya meslek kanıtı değildir.
- Ayrıntılı numeroloji/astroloji/Human Design (hakları çözülmüşse)/Future Self/öğrenme/AI/günlük rehber gibi yayımlanmış Premium ürün alanları için tek abonelik. Gelecek vaatleri mevcut özellik gibi gösterilmez.
- Premium hedef aylık $5.55; App Store Connect USD fiyat noktası ve yerel para birimi mevcudiyeti doğrulanmalı. İsteğe bağlı yıllık hedef $49.99: ayrı fiyat testi gerekir. Paywall'da nihai fiyat StoreKit'in localized displayPrice değerinden gelir, hardcoded $5.55 gösterilmez.
- Reklam GÖSTERİMİ YOK (no ad network, no kişisel veri satışı). PAZARLAMA/Reklam kampanyaları VAR ve kullanıcıdan ayrı tutulur.
- Hesap oluşturma: yerel önizleme anonim olabilir; isteğe bağlı Apple sign-in/sync ayrı ihtiyaç olarak ele alınır. Sign in with Apple veya başka yöntemler gerekirse Apple login kuralına uyum incelenir.
- Ebeveyn/çocuk, yüksek hassas veri, yüz-el, işaretli sağlık vb. bilgilerin viral akışta paylaşılması yasak/özel açık onay gerektirir.

## 2. Kullanıcı edinimi ve Premium dönüşüm
Guest/Limited User state machine:
`NEW -> INTRO -> BIRTH_INPUT -> FREE_CALC -> FREE_RESULT -> {SHARE, EXPLORE_MORE, PAYWALL} -> {PREMIUM_ACTIVE, NOT_NOW} -> RETURNING_FREE -> (OPTIONAL PURCHASE) -> PREMIUM_ACTIVE -> {GRACE, RETRY, EXPIRED, REFUNDED, REVOKED} -> PREMIUM_DISABLED`.
- Kullanıcı ücretsiz sonuç ekranını görmeden zorunlu paywall yok.
- `PAYWALL_NOT_NOW` her zaman çalışır; kullanıcı tekrar ücretsiz sonucuna dönebilir. İlk 1-2 oturumda tekrarlanan paywall baskısı yok.
- Doğum tarihi dışında ekstra veri ihtiyacını gerekçelendir; şehir/saat astroloji ve HD için isteğe bağlıdır, Life Path için değil.
- Ücretsiz numeroloji kısmı için 'kader doğrulandı' ve 'gizli gerçek açıklanacak' gibi manipülatif ifadeler kullanma.
- App Store StoreKit 2 verified entitlements; olası subscription server App Store Server Notifications V2 JWS verification, reconciler ve idempotent updates. Restore/subscription management/grace/expired/refund handled.
- Ödeme akışı `FREE -> PAYWALL -> PURCHASE_PENDING -> VERIFIED -> PREMIUM_UNLOCK`, hata/iptal/ask-to-buy/connection/refund ayrı durumlar.
- Ücretli mevcut V1 özellikleri kapsamı yayımdan önce SKU entitlement haritasında yazılı: `premium.all_current_features`. Sınırsız yüksek maliyetli bulut AI sözü verilmez; adil kullanım varsa limit açıkça anlatılır.
- Trial: ücretsiz hayat yolu önizlemesi zaten var; otomatik başlayan trial yerine isteğe bağlı App Store introductory offer A/B test. Trial varsa otomatik yenileme ve zamanlaması net.

## 3. Etik viral döngüler
1. **Life Path Share Card**: Kullanıcı bilinçli seçerse paylaşılabilir kart; varsayılan olarak ad-soyad, tam doğum tarihi, konum, portre veya hassas veri YOK. Paylaşım linki deterministik / açık izinli ve önizleme güvenli. Kartta 'numeroloji geleneğine göre sembolik' etiketi.
2. **Meaningful Journey Card**: Kullanıcı isterse kendi seçtiği hedef için paylaşım kartı; mental/medical/relationship günlük bilgileri otomatik paylaşılmaz.
3. **Invite/Referral**: kullanıcının açıkça başlattığı standart Share Sheet; rehber/kontak upload yok; paylaşım yapmayı üyelik koşulu yapma; kendini davet etme/suistimal denetimi; App Store offer codes yalnızca App Store'un resmî eligibility/kota akışına göre. V1'de referral ödülsüz çalışır.
4. **Public Education Content**: İnsanların öğrenmek isteyeceği hayat yolu sembolizmi, kaynaklı mini makaleler, açıklayıcı videolar. Gerçek kullanıcı günlüğü kamu içeriği olmaz.
5. **Annual/Monthly Review**: Özel yaşam analizi paylaşılmadan önce kullanıcı tek tek dışarı çıkacak alanları seçer.
6. **Campaign + ASO**: Apple custom product pages, product page optimization, in-app events, kampanya attribution; pazarlama A/B testleri içerik ve fiyat iddiası açısından review edilir.
Growth KPI: first preview completion, preview->paywall view, paywall->verified purchase, trial->paid, qualified referrals per sharing user, invite accept, D1/D7/D30 retention, 30/60-day subscriber retention, LTV/CAC, contribution margin, refund, crash-free, privacy complaints, unsubscribe. `viral K = invites per participant × invite-to-new-user conversion`; başarı garanti edilmez.
Avoid: deceptive urgency, countdown without actual offer, misleading numerology, invite-to-unlock, fake scarcity, spam, review incentives.

## 4. İlk ücretli ekran kapsamı
- Guest path: intro → data entry → result → optional share → honest paywall.
- Paywall: price via StoreKit `displayPrice`, billing period, auto renewal disclosure, what is included NOW, limits, privacy/terms, Restore Purchases, Not Now, manage subscription; accessibility.
- Returning free: preview available without recreating identity.
- Returning premium: entitlement check and offline cached entitlement policy; no false unlock after revocation, grace handling per Apple and local fallback.
- Subscription lapse: private local data NEVER deleted solely due lapse; premium tools lock and free preview remains; data export and deletion available.
- Share: default private, share token no personal identifiers; links safe against enumeration and leak; revoke if personal link. For pure static cards, links contain no data.

## 5. Million-user scale engineering (target, not achieved)
Separate counts: total installs, registered users, MAU, DAU, concurrent sessions, subscribed paying users, requests/day. 1M installs ≠ 1M concurrent.
Plan capacity by measured SLO and traffic profile. **Illustrative nonforecast test scenario**: 1M DAU × 10 backend events/day = 10M events/day ≈116 events/second average; stress at 20× burst ≈2315 events/s. These are hypothetical events; local calculations produce ZERO backend events.
- Local-first: life path, numerology, checks, private graph and symbolic cache stay on-device; massively reduces backend request volume.
- Static assets: CDN, compress, versioned public knowledge packs; offline resource metadata only where rights permit.
- Stateless API horizontal scale, autoscale on queue depth/CPU/request rate; auth/rate limits; multi-region CDN, no premature multi-region database if unneeded.
- Postgres managed with indexes, limited user identifiers, strict tenant scope, connection pool, read replicas when measured, encrypted at rest; partition high volume append-only non-sensitive events after evidence.
- Queue jobs (notification decisions, resource verification, analytics batches, provider refresh), retry with backoff, dead-letter queues, idempotency.
- Subscription backend: StoreKit 2 client, Apple Server API/Notifications V2 signed payload validation, periodic reconciliation, entitlement ledger, restore, billing retry/grace/refund states.
- Daily peaks by time zone: no globally synchronized expensive cloud jobs, scheduling jitter, user quiet hours.
- Cost cap: per-user/per-feature AI usage allocation, deterministic-first router, result cache if lawful, cloud inference only after opt-in; metered resource API, provider fallback/circuit breakers.
- Rate limiting: device/service and account-aware, referral/share endpoints, fraud prevention without invasive fingerprinting; WAF, network ACL, bot throttles, anomaly response.
- Data governance: Vault local; account/payment minimal server metadata; collective aggregate opt-in separate. Per-user stored birth dates/daily logs NOT needed for marketing analytics.
- Monitoring: distributed tracing with redaction, error budgets, p95/p99 API latency, outbox queue lag, billing webhook age, referral abuse, cloud AI costs, crash-free. Zero sensitive log leakage as release gate.
- Backup/DR: RPO/RTO measurable and recovery drills, multi-AZ for payment/entitlement backend, partial outages graceful degradation, regional privacy requirements.
- DDoS, downtime, app store webhooks out of order, duplicate events, mobile offline mode, unusual peaks tested BEFORE major campaign.

## 6. Product analytics vs privacy
App Analytics/StoreKit metrics as primary; locally aggregated first party events with no raw diary/name/birth info. Consent/privacy disclosures for marketing SDKs; do not deploy invasive trackers by default.
Canonical events:
`ONBOARDING_STARTED`, `BIRTH_INPUT_COMPLETED_LOCAL`, `FREE_RESULT_SHOWN`, `FREE_RESULT_SAVED`, `SHARE_PREVIEW_OPENED`, `SHARE_COMPLETED_LOCAL` (only consent-compatible aggregate), `PAYWALL_PRESENTED`, `PURCHASE_STARTED`, `STOREKIT_VERIFIED`, `PREMIUM_GRANTED`, `SUBSCRIPTION_RENEWED`, `SUBSCRIPTION_GRACE`, `SUBSCRIPTION_EXPIRED`, `RESTORE_SUCCEEDED`, `REFERRAL_OPENED`, `FIRST_LEARNING_ACTION`, `WEEKLY_MEANINGFUL_ACTION`.
Event schema: `name,eventVersion,occurredAt,anonEphemeralId?,appBuild,campaignToken?,consentScope?`, NO name, full DOB, home address, private journal. Avoid even age cohort in tiny samples where re-identification risk.
Experiment assignment without external tracking; experiment guardrails: safety, refund rates, crash, retention, complaint and Apple review risk.

## 7. Growth governance and administration
Add Growth command center with acquisition/campaign performance, organic sharing, referral integrity, paywall A/B, subscriber health and costs. No personal raw vault access; minimum aggregate cohort thresholds.
Roles: Growth Analyst (aggregated KPIs only), Content Editor (public knowledge packs), Release Approver, Privacy Officer, Finance Admin (minimal billing metadata), Support (account state only), Security Admin. Separation of duties for production rollout & policy change.

## 8. Release stages and capacity gates
Stage 0: prototypes + price/brand/license review; 10–30 test users (hypothesis). Stage 1: 100–500 TestFlight pilot, analytics/privacy and bug checks. Stage 2: 1–10k installs staged release, load/retention/monetization. Stage 3: 10k–100k operations, predictable cost/SLO. Stage 4: 100k–1M+ installs, actual DAU-based capacity and DR tests. These are planning bands not promises.
**P0 tests**: unit determinism, birthday/calendar inputs, free paywall exits, purchase states, refunds, local data survive lapse, secure share, duplicate referral, cost runaway, 10–20x burst, notification jobs, API outage, PII exfil/leak, App Store compliant paywall.
**Go/no-go**: free preview yields real value, price/terms clear, active subscribers receive access, non-premium still has their free result, personal vault never uploaded without consent, webhook/reconciliation works, growth is ethical and lawful, independent evaluation recorded.

## 9. Screen registry v0.2 delta
Four *additional* user-facing screens (M01 Free Preview Detail, M02 Premium Paywall, M03 Share Studio, M04 Invite/Landing) and four *additional* operation consoles (H11 Acquisition Analytics, H12 Growth Experiments, H13 Campaign Studio, H14 Referral & Fraud Control). Original A/D/G screens adapted; duplicate screens unnecessary. Registry now 91 candidate surfaces (77 consumer + 14 operations), still NOT implemented.

## 10. First coding week scope adjustment
19 Mon: Xcode SwiftUI app scaffold, StoreKit configuration, offline LifePathCalculator with goldens, source+symbolism notices; privacy by design.
20 Tue: Guest input/birth date validation, encrypted local storage, free result/edge cases.
21 Wed: Transparent paywall, StoreKit sandbox purchase/restore, entitlement, error/cancel/grace/refund tests.
22 Thu: deterministic share card without personal info, optional invite link, growth event schema, privacy/analytics policies.
23 Fri: end-to-end Guest -> Free Preview -> Paywall -> Verified Premium -> Future Self starter experience; regression, evidence, next sprint. No Human Design/license gated face scan in first week.

## 11. Apple primary references (verify when implementing)
- Review: https://developer.apple.com/app-store/review/guidelines/
- StoreKit 2: https://developer.apple.com/storekit/
- Subscriptions: https://developer.apple.com/app-store/subscriptions/
- Price points: https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/in-app-purchase-and-subscriptions-pricing-and-availability/
- Custom product pages: https://developer.apple.com/app-store/custom-product-pages/
- Campaign links: https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links
- Offer codes: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/
- Server notifications V2: https://developer.apple.com/documentation/appstoreservernotifications/receiving-app-store-server-notifications
