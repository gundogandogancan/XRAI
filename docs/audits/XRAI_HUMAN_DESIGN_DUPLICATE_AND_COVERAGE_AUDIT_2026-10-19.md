# XRAI Human Design — Ek dört dosya karşılaştırması

Tarih: 2026-10-19

## Doğrulanan sonuç

Yeni gelen 4 PDF'nin **dördü de** önceki 13 PDF içindeki karşılığının byte düzeyinde aynısıdır (SHA-256 tam eşleşme). Yeni sayfa veya daha net tarama içermez. Mevcut kaynak 17 yükleme, 13 benzersiz PDF, toplam 298 PDF görüntü sayfasıdır. Bir PDF görüntüsü bazen açılmış kitabın iki basılı sayfasını içerebilir; 298 = 298 basılı kitap sayfası denemez.

| Yeni PDF | Önceki PDF | Sonuç |
|---|---|---|
| `Human desing(1).pdf` | `Human desing.pdf` | 24 PDF sayfası; SHA-256 aynı `3844444393b8bf3c…` |
| `Human desing2(1).pdf` | `Human desing2.pdf` | 24 PDF sayfası; SHA-256 aynı `8f6af3434745e0e5…` |
| `Human desing3.pdf` | `Human desing3(1).pdf` | 24 PDF sayfası; SHA-256 aynı `4b0d916de3f214c3…` |
| `Human desing4(1).pdf` | `Human desing4.pdf` | 24 PDF sayfası; SHA-256 aynı `9e5f2ae0467f5fec…` |

## Basılı sayfa aralığının sınır kontrolü

13 benzersiz PDF'nin ilk/son sayfa görsellerinden basılı sayfa aralıkları yaklaşık şu sırada gözlendi: 9–31 (2. bölüme giriş), 32–55, 56–81, 82–107, 108–132, 132–155, 154–179, 180–203, 204–225, 226–250, 250–273, 274–299, 301–310. Bazı görüntüler kitap açıklığı içerdiğinden bitişikler arasında fiziksel sayfa yinelenebilir. Bu **tam kapsam ispatı değildir**; her folionun tek tek okunaklı görüntüsünün varlığı ayrı taranmalıdır.

**İlk gerçek belge eksiklik/kalite adayları:**
- Basılı s. 1–8 (kapak, künye/telif, içindekiler vb. varsa) mevcut PDF'lerin ilk sayfasında bulunmuyor; ilk görünen basılı sayfa s. 9.
- **Basılı s. 300:** 12. dosyanın son görünür basılı sayfası 299, 13. dosyanın ilk görünür sayfası 301. s. 300'ün başka fotoğraf kadrajında bulunup bulunmadığı henüz ispatlanmadı; kontrol edilmeli.
- İlk incelemede `Human desing.pdf` PDF sayfa 16, `Human desng9.pdf` PDF sayfa 8/17, `Human design 12.pdf` PDF sayfa 12/20 eksik veya yetersiz okunaklı bulunmuştu. Yeni 4 PDF bunları değiştirmiyor.

## Analiz durumu

SHA-256, sayfa sayısı ve dosya sınırı kontrolü **doğrulandı**. 298 PDF görüntüsünün önceki görsel ön inceleme kapsamı devam ediyor. Her basılı sayfanın her paragrafı çözülmüş veya Human Design matematik modeli test edilmiş **değildir**. Kitap ekolleri ve sembolik yorumları bilimsel kişilik kanıtı olarak sunulmayacaktır; telifli çeviri metnini ticari ürün içine kopyalamıyoruz.
