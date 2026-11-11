# Gizlilik / Privacy

*Son güncelleme / Last updated: 2026-11-11*

## Türkçe

CouchSubs, Enmera tarafından yayınlanan açık kaynaklı bir uygulamadır. Hiçbir kişisel veriyi toplamaz.
Kendi sunucumuza giden tek şey, kapatabileceğiniz ortak havuzdaki İngilizce oyun metnidir (aşağıya bakın).
Reklam, analiz ya da izleme kodu içermez.

**Bilgisayarda kalanlar**

- PS5'ten gelen oyun görüntüsü yalnız altyazıyı okumak için bellekte işlenir; kaydedilmez, hiçbir yere
  gönderilmez.
- Okunan altyazılar ve çevirileri bilgisayarda üretilir ve yalnız ev ağınızdaki TV'ye gönderilir (çevrimiçi çeviriyi
  açarsanız İngilizce metin DeepL'e de gider; aşağıya bakın).
- PlayStation Network hesap kimliği (sayısal), PS5 eşleme anahtarı ve TV eşleme anahtarı bilgisayarda
  saklanır: Mac'te Anahtar Zinciri'nde, Windows'ta yalnız sizin kullanıcı hesabınızın açabileceği
  şifreli bir dosyada (DPAPI).

**Dışarıyla kurulan bağlantılar**

- **Sony:** PlayStation Network girişi doğrudan Sony'nin sayfasında yapılır; şifrenizi CouchSubs görmez.
  Girişten sonra Sony'den yalnız hesap kimliği alınır, oturum anahtarı saklanmaz.
- **Hugging Face (yalnız Windows):** ilk açılışta çeviri modeli `huggingface.co` adresinden bir kez indirilir.
- **Apple (yalnız Mac):** çeviri dilleri macOS tarafından indirilir ve yönetilir.
- **DeepL (yalnız siz açarsanız):** ayarlarda kendi DeepL anahtarınızı girip çevrimiçi çeviriyi açarsanız okunan
  İngilizce altyazı metni çeviri için DeepL'e (`api.deepl.com` ya da `api-free.deepl.com`) gönderilir. Görüntü,
  ses ve hesap bilgisi gönderilmez. DeepL'in kendi gizlilik koşulları geçerlidir. Anahtar Mac'te Anahtar
  Zinciri'nde, Windows'ta DPAPI ile şifreli dosyada saklanır. Açmazsanız DeepL'e hiçbir şey gönderilmez.
- **Ortak havuz (Ayarlar › Çeviri'den kapatılabilir):** hiçbir oyun paketinde bulunmayan, okunan İngilizce altyazı
  satırları herkes için daha iyi Türkçe çeviriler hazırlamak üzere `couchsubs-pool.enmera.workers.dev` adresine
  gönderilir. Giden yalnız satırın metni, ondan üretilen anahtar, ilk görüldüğü an, uygulama sürümü, işletim sistemi
  (mac/windows) ve kuruluma özgü rastgele bir kimliktir. Görüntü, ses, kullanıcı adı, PSN ya da hesap bilgisi gönderilmez.
  Kapatınca gönderim hemen durur ve bekleyen satırlar silinir.
- **Ev ağı:** PS5 ve LG TV'yi bulmak ve onlarla eşleşmek için yalnız yerel ağ kullanılır.

TV uygulaması altyazıları yalnız ev ağındaki CouchSubs bilgisayarından alır ve internete bağlanmaz.

Sorularınız için: https://github.com/yorulmazsinan/couchsubs/issues

## English

CouchSubs is open-source software published by Enmera. It does not collect personal data. The only thing
sent to a server of ours is English game text for the shared pool, which you can turn off (see below). It
contains no advertising, analytics or tracking code.

**Stays on your computer:** the game picture received from the PS5 is processed in memory only to read
subtitles and is never stored or uploaded. Subtitles and translations are produced on your computer and
sent only to the TV on your home network. Your numeric PlayStation Network account ID and the PS5 and TV
pairing keys are stored locally (Keychain on Mac; a file encrypted for your Windows user account with
DPAPI on Windows).

**External connections:** PlayStation Network sign-in happens on Sony's own page, and CouchSubs never sees
your password; afterwards only the account ID is requested from Sony, and no session token is kept. On
Windows, the translation model is downloaded once from `huggingface.co`. On Mac, translation languages are
downloaded and managed by macOS. If you enter your own DeepL key in settings and turn on online
translation, the English subtitle text that was read is sent to DeepL (`api.deepl.com` or
`api-free.deepl.com`) to be translated; no picture, audio or account data is sent, and DeepL's own privacy
terms apply. The key is stored in the Keychain on Mac and in the DPAPI-encrypted file on Windows. Nothing is
sent to DeepL unless you turn this on. PS5 and TV discovery and pairing use your local network only.

**Shared pool (can be turned off in Settings › Translation):** English subtitle lines that were read and are not
in any game pack are sent to `couchsubs-pool.enmera.workers.dev` to make better Turkish translations for
everyone. Only the line's text, a key derived from it, when it was first seen, the app version, the operating
system (mac/windows) and a random ID made for this installation are sent; no picture, audio, user name, PSN or
account data. Turning it off stops sending at once and deletes lines waiting to be sent.

The TV app receives subtitles only from the CouchSubs computer on your home network and does not connect
to the internet.

Contact: https://github.com/yorulmazsinan/couchsubs/issues
