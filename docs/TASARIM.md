# CouchSubs tasarım standardı

Mac ve Windows uygulamaları aynı görünür. Bu belge neyin nasıl göründüğünü, `design/tokens.json`
ise sayısal değerleri tanımlar. Değer değişecekse yalnız `tokens.json` düzenlenir; uygulamalar onu
doğrudan okur. Belge ile kod çelişirse `tokens.json` geçerlidir.

## İlke

Sade ve klas. Tek vurgu rengi (altyazı sarısı), sakin zemin, bol boşluk, büyük ve okunaklı yazı.
Süs yok: gölge, degrade, cam efekti, animasyonlu arka plan kullanılmaz. Uygulama TV karşısında,
biraz uzaktan bakılarak kullanılır; her şey bir bakışta okunmalı.

## Logo

- Kaynak: `design/logo.svg` (vektör). Arkalığı ekran gibi duran, üstünde iki sarı altyazı satırı
  olan bir kanepe; koyu grafit zemin.
- Simgeler `swift scripts/make-icons.swift` ile üretilir (macOS simge seti, uygulama içi logo,
  TV uygulaması simgeleri, `design/logo-1024.png`). Windows için `.ico` aynı SVG'den üretilir.
- Logo değiştirilmez, yeniden renklendirilmez, gölge eklenmez. Uygulama içinde en az 32 pt.

## Renk

Her renk açık ve koyu görünüm için ayrı tanımlıdır; uygulama sistemin görünümünü izler.

| Ad | Kullanım |
|---|---|
| `background` | Pencere zemini |
| `surface` | Kartlar, alt düğme çubuğu |
| `border` | Kart çerçevesi, ayraçlar, ilerleme çubuğu zemini |
| `textPrimary` | Ana metin |
| `textSecondary` | Açıklamalar, ikincil bilgiler |
| `accent` | Birincil düğme, ilerleme, seçili bölge (yalnız dolgu olarak; metin rengi değildir) |
| `onAccent` | Sarı düğme üstündeki yazı |
| `accentText` | Sarı tonda metin ve simgeler (açık görünümde koyulaştırılmış) |
| `accentSoft` | Simge rozeti ve numara dairesi zemini |
| `success` / `warning` / `danger` | Durum: bağlı / dikkat / hata ve "Durdur" |
| `onDanger` | Kırmızı düğme üstündeki yazı |

Okunaklılık kuralı (Mac'te `ThemeTests` ile denetlenir; Windows'ta da aynı test yazılır):
ana metin zeminlere karşı en az 7:1, diğer tüm metinler en az 4,5:1 kontrastta olur.

## Yazı

Sistem yazı tipi: Mac'te SF Pro, Windows'ta Segoe UI Variable. Boyutlar nokta (pt) cinsinden;
Windows'ta aynı sayılar efektif piksel (epx) olarak kullanılır.

| Ad | Boyut | Kalınlık | Kullanım |
|---|---|---|---|
| `display` | 30 | yarı kalın | Sihirbaz adım başlığı |
| `title` | 22 | yarı kalın | Ekran başlığı, son altyazının çevirisi |
| `headline` | 17 | yarı kalın | Kart başlığı |
| `body` | 15 | normal | Tüm metinler (varsayılan) |
| `callout` | 14 | normal | Açıklama ve ipuçları |
| `caption` | 12 | normal | Yasal notlar gibi küçük metinler |
| `button` | 15 | yarı kalın | Düğme yazısı |
| `code` | 22 | yarı kalın, eş genişlikli rakam | PS5 eşleme kodu |

Paragraflarda satır arası yazı boyutunun yaklaşık 1,3 katıdır. 12 pt'nin altı kullanılmaz.

## Boşluk ve biçim

- Boşluk ölçeği: `xs` 4, `s` 8, `m` 12, `l` 16, `xl` 24, `xxl` 32.
- Pencere kenar boşluğu `xxl`, kartlar arası `l`–`xl`, kart iç boşluğu `xl`.
- Köşe: denetimler (düğme, alan, rozet) `control` 10, kartlar `card` 14.
- Pencere 640 × 720; Ayarlar penceresi 600 × 720.

## Bileşenler

Her iki platformda aynı adla bulunur.

- **LogoView** – logo, kenar boşluğu kırpılmış hâliyle; koyu temada kenarı seçilsin diye 1 pt `border` çerçeve.
- **Düğme** – yükseklik 44 (`buttonHeight`), ana ekrandaki "Çeviriyi başlat/durdur" 52 (`primaryActionHeight`), yatay iç boşluk `xl`.
  - *Birincil*: `accent` dolgu, `onAccent` yazı. Ekranda en fazla bir tane.
  - *İkincil*: `surface` dolgu, `border` çerçeve, `textPrimary` yazı.
  - *Tehlikeli*: `danger` dolgu, `onDanger` yazı (yalnız "Çeviriyi durdur").
  - Devre dışı: %45 saydamlık.
- **Card** – `surface` zemin, 1 pt `border` çerçeve, `card` köşe, isteğe bağlı `headline` başlık.
- **IconBadge** – 48 × 48, `accentSoft` zemin, `accentText` simge.
- **StepLayout** – sihirbaz adımı: IconBadge, `display` başlık, `body`/`textSecondary` açıklama, içerik.
- **NumberedRow** – 26 pt `accentSoft` dairede numara, yanında `body` metin.
- **StatusRow** – 10 pt durum noktası, kalın ad, sağda değer. Nokta: bağlı `success`, çeviri sürerken
  bağlantı yok `warning`, çeviri başlamamışken `textSecondary` (boşta olmak uyarı değildir).
- **Metin alanı** – `surface` zemin, 1 pt `border` çerçeve, `control` köşe, en az 40 yükseklik; PS5 kodu
  alanı 52 yükseklik ve `code` yazı. Etiketi alanın üstünde `callout`/`textSecondary`.
- **Bölmeli seçim** – yazı boyutu gibi 2–4 seçenek: `background` zeminli çerçeveli kutu, seçili parça
  `accent` dolgu ve `onAccent` yazı (Mac'te sistemin segmented denetimi).
- **Kaydırıcı** – ince ray (`border`), dolu kısım `accent`, yuvarlak tutamaç.
- **Bağlantı** – `accentText` renginde.
- **DoneLabel** – `success` renkli onay simgesi ve metin.
- **HintText** – `callout`, `textSecondary`.
- **ErrorText** – `callout`, `warning`, uyarı simgesi.
- **ProgressBar** – 6 pt yüksek, yuvarlak uçlu; zemin `border`, dolu kısım `accent`.

## Ekranlar

**Kurulum sihirbazı**: üstte küçük logo + "CouchSubs" + sağda "Adım n / 6", altında ilerleme
çubuğu; ortada kaydırılabilir StepLayout; en altta `surface` zeminli çubukta solda "Geri"
(ikincil), sağda "Devam" (birincil).

**Ana ekran** (yukarıdan aşağı): logo + "CouchSubs" + sağda ayar simgesi; tam genişlikte
"Çeviriyi başlat" (birincil) ya da "Çeviriyi durdur" (tehlikeli); PS5 ve TV durumlarını gösteren
kart; gerekiyorsa dil paketi uyarı kartı; "Son altyazı" kartında `title` boyutunda çeviri, altında
`callout` boyutunda özgün metin.

**Ayarlar**: `title` başlık; sırasıyla "TV'de" (yazı boyutu, ekrandaki konum, test altyazısı),
"Dil", "Çeviri", "Altyazı bölgesi" kartları ve Hakkında / Yeniden kur düğmeleri; altta "Bitti" (birincil).
"Çeviri" kartında motor seçimi (Ücretsiz, DeepL, Gemini, OpenAI, Claude); ücretli motorda kısa açıklama, model
seçimi, gizli anahtar alanı ve "Kaydet ve dene" (ikincil), anahtar sayfası bağlantısı, kayıtlıysa "Anahtar kayıtlı" (DoneLabel) ile
"Dene" ve "Anahtarı sil" (ikincil). Model yazılamaz; "Model" seçiminde yalnız ortak listedeki modeller
(`core/Sources/CouchSubsCore/Resources/ai-models.json`) sade adlarıyla görünür. Sonuç HintText, hata ErrorText olur.
Çevrimiçi motor çeviri sırasında hata verirse ana ekranda uyarı kartı çıkar.
"Çeviri" kartının sonunda ayraçtan sonra "Oyun paketleri" (`headline`): "Oyun paketlerini kullan" anahtarı, HintText
açıklama, kurulu paketler "Ad · n satır" (`body`); ikinci ayraçtan sonra "Okunan İngilizce altyazıları ortak havuza
gönder" anahtarı (varsayılan açık) ve tek satırlık HintText. Kurulumun son adımında havuz bir HintText ile söylenir.

**Hakkında**: 88 pt logo, ad, sürüm, lisans, teşekkür, bağlantılar, Sony ile ilişkisizlik notu.

## TV uygulaması

TV'de her zaman koyu temanın renkleri kullanılır (oyunun üstünde durur). Bilgi paneli ve "uygulamayı açın"
ekranı `background` %92–94 saydam zemin, 2 px `border` çerçeve, 24–32 px köşe; başlıkta logo. Kumanda
tuşları satır satır, tuş adı `accent` renginde. Altyazı kutusu siyah %72 saydam zemin üstünde beyaz,
yarı kalın yazı (okunaklılık için tema rengi değil). Bekleme ekranı açıkken panel kendiliğinden açılmaz.
Bekleme ekranında tek düğme "Demoyu izle"dir; seçili düğme `accent` dolgu ve beyaz çerçeveyle belli olur.
Demo sırasında sağ üstte panel biçiminde "DEMO" notu durur. Geri tuşu önce demoyu ya da paneli kapatır,
giriş ekranında TV'nin ana ekranına döner (mağaza kuralı).

## Windows'a aktarım

- `tokens.json` uygulamayla birlikte paketlenir ve açılışta okunur (Mac ile aynı yöntem);
  renkler açık/koyu tema kaynaklarına, boyutlar yazı ve boşluk kaynaklarına dönüştürülür.
- Yazı tipi Segoe UI Variable; sayılar yukarıdaki tablodakiyle aynı.
- Pencere zemini düz `background` rengidir (Mica/Acrylic gibi saydam efektler kullanılmaz).
- Bileşenler yukarıdaki adlarla kurulur; ekran düzenleri birebir aynıdır.
- Kontrast testi Windows test projesine de eklenir.
