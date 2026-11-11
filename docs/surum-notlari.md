CouchSubs'ın yeni deneme sürümü. Türkçe dil desteği olmayan PS5 oyunlarının İngilizce altyazısını okur, Türkçesini TV'de oyunun üstünde gösterir ve isterseniz Türkçe seslendirir.

**İndir:** [Mac (DMG)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-macos.dmg) · [Windows (kurulum)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-windows-Setup.exe)

**Bu sürümde yeni**

- **Oyun çeviri paketleri:** Desteklenen oyunlarda altyazı, önceden hazırlanmış Türkçe çeviriyle anında ve internet gerekmeden gösterilir. İlk paket **Mafia: The Old Country** (18 bin satır, oyunun bütün metni Claude ile çevrildi). Pakette olmayan satırlar her zamanki çeviri motoruyla çevrilir. Ayarlar › Çeviri › Oyun paketleri.
- **Ortak altyazı havuzu:** Paketlerde bulunmayan İngilizce altyazı satırları anonim olarak ortak havuza gönderilir; biriken satırlar çevrilip yeni paketlerle herkese gelir. Yalnız oyunun İngilizce metni gider, başka hiçbir bilgi gitmez. Ayarlar › Çeviri'den kapatılabilir.
- **Altyazı bilgisayar ekranında (TV'siz kullanım):** Kurulumda "TV'm yok, bilgisayar ekranında göster" seçilebiliyor. Altyazı her zaman üstte duran saydam bir pencerede, TV'deki görünümle gösterilir; sürüklenip genişletilebilir, "Tıklamalar geçsin" ile fareyi engellemez (geri almak için Mac'te ⌥⌘L, Windows'ta Num 7). Ana ekranda ve ayarlarda "Altyazıyı göster: TV / Bilgisayar ekranı / İkisi de".
- **PS5 eşleme ve PSN girişi düzeltildi:** Eşleme kodu yazılıp Enter'a basılınca artık bağlanıyor (önceden hiçbir şey olmuyor, kodun süresi doluyordu); kod boşluklu ya da tireli yazılabiliyor. Eşleme ve giriş hataları artık sebebiyle gösteriliyor ("Kod yanlış ya da süresi dolmuş", "PS5 yanıt vermedi", "Sony çok fazla giriş denemesi aldı" gibi). Sorun sürerse ekranda gösterilen günlük dosyasını gönderebilirsiniz (Mac'te `~/Library/Logs/CouchSubs/remoteplay.log`).
- **Ücretsiz Gemini ile daha iyi çeviri:** Kurulumun sonunda isteğe bağlı "Daha iyi çeviri (ücretsiz)" adımı: bir dakikada ücretsiz Google Gemini anahtarı alıp yapıştırınca çeviri çok daha iyi olur. Ücretsiz kotanın dakikalık sınırı aşılmaz; aşılacaksa o satır ücretsiz yerel çeviriyle gösterilir.

**beta.24'te gelenler:** altyazı yazı rengi (beyaz/sarı, TV uygulaması 0.9.10, katkı: [Kadir Eker](https://github.com/kadireker)), Mac'te her açılışta güncelleme kontrolü.

**beta.23'te gelenler:** daha kararlı altyazı (tekrar eden ve kaybolan satırlar giderildi), hızlı konuşmada önceki satırların TV'de üstte kalması (TV uygulaması 0.9.9), isteğe bağlı yapay zekâ çevirisi (Gemini, OpenAI, Claude), oyun sözlüğüyle daha iyi ücretsiz çeviri, kalıcı çeviri önbelleği, TV'nin kopan bağlantıyı kendisi toparlaması, Android TV'de doğru HDMI girişi, Windows'ta LG parolası ve WebView2 düzeltmeleri.

**beta.22'de gelenler:** LG TV'de sihirli kumandanın işaretçisiyle Tamam tuşu (TV uygulaması 0.9.8).

**beta.21'de gelenler:** TV'de altyazının bir an görünüp kaybolması için düzeltme ve panelde Tanı satırı (TV uygulaması 0.9.7), Windows'ta PS5'in IP adresi değişince yeniden bulunması, PS5 eşleştirme hatalarında gerçek sebebin görünmesi, Windows dublajında Türkçe ses motoru hatasının gösterilmesi.

**beta.20'de gelenler:** LG TV'de "TV uygulaması kurulamadı" hatasının düzeltilmesi (bildiren: [yag_ats](https://x.com/yag_ats)).

**beta.19'da gelenler:** Samsung ve Android TV'de görünmeyen altyazının düzeltilmesi (TV uygulaması 0.9.6), Windows Güvenlik Duvarı izni, GTA V ve renkli zeminlerde daha düzgün çeviri (Windows), ortalı altyazının kutusunun ortada durması (Mac ve Windows).

**beta.18'de gelenler:** OBS katmanı (Mac ve Windows), altyazı geçmişi (Mac, katkı: [rumpony](https://github.com/rumpony)).

**beta.17'de gelenler:** Mac uygulamasının macOS 26'da yeniden açılması, kapanıştaki Remote Play çökmesinin giderilmesi (Mac ve Windows), Mac'te disk dolu uyarısı.

**beta.16'da gelenler:** Ekranı çevir (Windows'ta Num 9, Mac'te ⌥⌘T: menüler, görev paneli ve bilgi kutuları TV'de kendi yerinde Türkçe), TV uygulaması 0.9.5, Windows'ta aynı hizadaki uzak yazıların ayrılması.

**beta.15'te gelenler:** birkaç çeviriyi deneyip en iyisini seçen Windows çevirisi, oyun ifadelerinin ("friendlies", "got your six") anlamıyla çevrilmesi, isteğe bağlı DeepL çevirisi (Mac ve Windows), Windows'ta indirmesiz hızlı Türkçe ses.

**beta.14'te gelenler:** Windows'ta İngilizce yazı tanıma paketi uyarısı ve tek düğmeyle kurulumu, menü/gösterge/kumanda ipuçlarının altyazıya karışmaması, yeni altyazı gelince eski dublaj cümlesinin kesilmesi, fareyle çizilen alan ve Num 1/2/3 ek bölgeler (katkı: [sadumqn](https://github.com/sadumqn)), Samsung'da eski kurulumun yeni sürümü engellememesi.

**İndirme**

| Dosya | Ne için |
|---|---|
| `CouchSubs-macos.dmg` | Mac kurulumu (Apple Silicon, macOS 26+) |
| `CouchSubs-windows-Setup.exe` | Windows 10 (2004) / 11 kurulumu, 64 bit |
| `CouchSubs-macos.zip`, `CouchSubs-windows-x64.zip` | Kurulumsuz kullanmak isteyenler için |
| `com.couchsubs.tv_…_all.ipk` | LG TV uygulaması, elle kurmak isteyenler için |
| `CouchSubs-samsung-kaynak.zip` | Samsung TV uygulaması, Tizen Studio ile elle kurmak isteyenler için |
| `CouchSubs-androidtv.apk` | Android TV / Google TV uygulaması, USB bellekle kurmak isteyenler için |
| `appcast.xml`, `releases.win.json`, `*.nupkg` | Uygulama içi güncelleme dosyaları (elle indirmeyin) |
| `SHA256SUMS.txt` | Dosyaların doğrulama özetleri |

**Bilinen durumlar**

- Windows kurulum dosyası imzasız: "Windows bilgisayarınızı korudu" uyarısında **Ek bilgi › Yine de çalıştır**. Uyarı yalnız ilk kurulumda çıkar; güncellemelerde çıkmaz.
- Dublaj yeni: sesin TV'den oyunun sesiyle birlikte çalması her TV'de henüz denenmedi. TV'den ses gelmezse ayarlardan sesi bilgisayara alın ve modelinizi yazın. Oyunun ses ayarlarından konuşma (diyalog) sesini kısın.
- Sesler yapaydır, gerçek kişilere ait değildir: Pocket TTS Turkish (wite-tech, CC BY 4.0), Kyutai'nin pocket-tts programıyla.
- Samsung ve Android TV kurulumu gerçek TV'de henüz az denendi. Sorun olursa TV modelinizle birlikte [Issues](https://github.com/yorulmazsinan/couchsubs/issues) sayfasından yazın; Windows'ta günlükler `%LOCALAPPDATA%\CouchSubs` klasöründe (`hata.log`, `remoteplay.log`).
- PS5 aynı anda tek Remote Play bağlantısına izin verdiği için oyun PS Remote Play uygulamasıyla oynanırken CouchSubs kullanılamaz; PS5'in TV'ye HDMI ile bağlı olması gerekir.
- Mağaza sürümleri henüz yok. Vestel, Arçelik, Beko ve Grundig'in Linux modelleri ile Philips Saphi ve Titan OS desteklenmiyor.

---

New beta. Game translation packs: supported games show a ready-made Turkish translation instantly and offline; the first pack is Mafia: The Old Country (the whole game text translated with Claude). Shared subtitle pool: English lines missing from the packs are sent anonymously so they can be translated for everyone (can be turned off in Settings). Subtitles on the computer screen: a no-TV setup option and an always-on-top, click-through subtitle window. Free Gemini key step for much better free translation. PS5 pairing and PSN sign-in fixed: Enter now connects and every failure shows its reason. Also includes beta.24: subtitle text colour (TV app 0.9.10, contributed by Kadir Eker) and update checks on every Mac launch. Download: [Mac (DMG)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-macos.dmg) · [Windows (installer)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-windows-Setup.exe).
