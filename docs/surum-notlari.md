CouchSubs'ın yeni deneme sürümü. Türkçe dil desteği olmayan PS5 oyunlarının İngilizce altyazısını okur, Türkçesini TV'de oyunun üstünde gösterir ve isterseniz Türkçe seslendirir.

**İndir:** [Mac (DMG)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-macos.dmg) · [Windows (kurulum)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-windows-Setup.exe)

**Bu sürümde yeni**

- **Daha kararlı altyazı.** Aynı çevirinin üst üste gelmesi ve hızlı konuşmada satırların kaybolması, karışması ve gecikmesi giderildi. Kısa süre okunamayan satır yeniden gönderilmiyor; çeviri kuyruğu birikmiyor; ekrandan kalkmış satırın çevirisi sonraki sahnenin üstüne düşmüyor.
- **Hızlı konuşmada önceki satırlar ekranda kalıyor (TV uygulaması 0.9.9).** Yeni satır gelince önceki çeviri onun üstünde küçük ve soluk olarak kısa süre daha duruyor; üç kişi art arda konuşursa üç satır görünüyor.
- **Yapay zekâ ile çeviri (isteğe bağlı).** Ayarlar › Çeviri'den Google Gemini, OpenAI ya da Anthropic Claude kendi API anahtarınızla seçilebiliyor; önceki satırları da bilerek çeviriyor. Ücret sizin hesabınızdan çıkar; sorun olursa o satır ücretsiz çeviriyle gelir.
- **Ücretsiz çeviri daha iyi.** Oyun adları ve terimleri bozulmuyor, Türkçe ekleri doğru geliyor (Kratos'u, Midgard'a); büyük harfli altyazılarda adlar korunuyor; "Boy!", "Do it." gibi kısa satırlar önceki cümleyle birlikte çevriliyor; ünlem ve soru işaretleri korunuyor. Kendi sözlük dosyanızı da ekleyebilirsiniz.
- **Çeviriler hatırlanıyor.** Bir kez çevrilen satır sonraki oyunlarda anında geliyor ve DeepL kotası harcanmıyor. DeepL'e önceki satırlar bağlam olarak gidiyor.
- **TV bağlantısı kendini toparlıyor.** Bağlantı yarı kopunca TV kendisi yeniden bağlanıyor; çeviri artık "TV'de Tamam'a basınca geri gelme" durumuna düşmemeli.
- **Android TV ve TCL:** HDMI girişi doğru seçiliyor, uygulama öne gelince görüntü yeniden açılıyor (bildiren: [onepunchmanq](https://x.com/onepunchmanq)).
- **Windows:** LG TV'de doğru girilen parolanın "yanlış" sayılması düzeltildi; kurulum PlayStation girişi için gereken WebView2'yi de kuruyor.
- **Daha hafif:** çeviri en fazla 2 işlemci çekirdeği kullanıyor.

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

New beta. Steadier subtitles: no more repeated lines, and fast dialogue no longer drops, mixes up or delays lines. On the TV (app 0.9.9) the previous one or two lines stay above the new one for a moment in fast dialogue. Optional AI translation with your own Google Gemini, OpenAI or Anthropic Claude key (Settings › Translation), with the free engine as fallback. Better free translation: game names and terms stay intact with correct Turkish suffixes, ALL CAPS lines keep names, short lines are translated with the previous sentence, and you can add your own glossary. Translations are remembered across sessions. The TV reconnects by itself after a half-open connection. Android TV picks the right HDMI input. Windows: correct LG passphrase no longer rejected; the installer adds WebView2 for the PlayStation sign-in. Download: [Mac (DMG)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-macos.dmg) · [Windows (installer)](https://github.com/yorulmazsinan/couchsubs/releases/latest/download/CouchSubs-windows-Setup.exe).
