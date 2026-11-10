// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import Darwin
import Observation
import RemotePlay

enum StoreKey {
    static let accountId = "accountId"
    static let console = "console"
    static let tv = "tv"
    static let tvKey = "tvKey"
    static let tvDevKey = "tvDevKey"
    /// Samsung ve Android TV'ye CouchSubs'ın kurduğu sürüm (LG'de sürüm TV'den okunur).
    static let tvAppVersion = "tvAppVersion"
    /// LG geliştirici modu süresinin son uzatıldığı an.
    static let devSessionRenewed = "devSessionRenewed"
    static let settings = "settings"
    /// Kullanıcının DeepL anahtarı (isteğe bağlı çevrimiçi çeviri).
    static let deepLKey = "deepLKey"
    /// Kullanıcının yapay zekâ anahtarları (isteğe bağlı çevrimiçi çeviri).
    static let geminiKey = "geminiKey"
    static let openAIKey = "openAIKey"
    static let claudeKey = "claudeKey"
}

/// Ayarlardaki çeviri motoru seçimi. Ücretsiz olan cihaz üstü çeviridir; diğerleri kullanıcının kendi anahtarıyla
/// çalışır (Windows'taki `TranslationEngine` ile aynı).
enum TranslationEngine: String, Codable, CaseIterable {
    case free, deepL = "deepl", gemini, openAI = "openai", claude

    var aiProvider: AIProvider? {
        switch self {
        case .gemini: .gemini
        case .openAI: .openAI
        case .claude: .claude
        case .free, .deepL: nil
        }
    }

    init(_ provider: AIProvider) {
        switch provider {
        case .gemini: self = .gemini
        case .openAI: self = .openAI
        case .claude: self = .claude
        }
    }

    /// Hizmetin adı (marka adı; çevrilmez).
    var displayName: String { aiProvider?.displayName ?? "DeepL" }

    /// Anahtarlık'taki anahtar adı.
    var storeKey: String? {
        switch self {
        case .free: nil
        case .deepL: StoreKey.deepLKey
        case .gemini: StoreKey.geminiKey
        case .openAI: StoreKey.openAIKey
        case .claude: StoreKey.claudeKey
        }
    }
}

/// Kalıcı ayarlar (Anahtarlık değil, sıradan tercihler).
struct UserSettings: Codable, Equatable {
    var region = CropRegion()
    var style = SubtitleStyle()
    var sourceLanguage = "en"
    var targetLanguage = "tr"
    var dubbing = DubbingSettings()
    /// Açıksa çeviri `onlineEngine` ile yapılır (anahtarı kayıtlıysa); kapalıysa ya da hizmete ulaşılamazsa Apple'ın
    /// cihaz üstü çevirisi. Eski sürümlerde yalnız DeepL vardı; o kayıtlar DeepL ile açılır.
    var onlineTranslation = false
    /// Seçili çevrimiçi motor (hiçbir zaman `.free` değildir).
    var onlineEngine = TranslationEngine.deepL
    /// Seçili yapay zekâ modelleri (listedeki kimlikler; bkz. `AIProvider.models`).
    var geminiModel = AIProvider.gemini.defaultModel.id
    var openAIModel = AIProvider.openAI.defaultModel.id
    var claudeModel = AIProvider.claude.defaultModel.id

    init() {}

    /// Yeni eklenen ayarlar eski kayıtta yoktur; varsayılanla açılır, eski ayarlar kaybolmaz.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserSettings()
        region = try values.decodeIfPresent(CropRegion.self, forKey: .region) ?? defaults.region
        style = try values.decodeIfPresent(SubtitleStyle.self, forKey: .style) ?? defaults.style
        sourceLanguage = try values.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? defaults.sourceLanguage
        targetLanguage = try values.decodeIfPresent(String.self, forKey: .targetLanguage) ?? defaults.targetLanguage
        dubbing = (try? values.decodeIfPresent(DubbingSettings.self, forKey: .dubbing)) ?? defaults.dubbing
        onlineTranslation = try values.decodeIfPresent(Bool.self, forKey: .onlineTranslation) ?? defaults.onlineTranslation
        let engine = (try? values.decodeIfPresent(TranslationEngine.self, forKey: .onlineEngine)) ?? defaults.onlineEngine
        onlineEngine = engine == .free ? defaults.onlineEngine : engine
        geminiModel = try values.decodeIfPresent(String.self, forKey: .geminiModel) ?? defaults.geminiModel
        openAIModel = try values.decodeIfPresent(String.self, forKey: .openAIModel) ?? defaults.openAIModel
        claudeModel = try values.decodeIfPresent(String.self, forKey: .claudeModel) ?? defaults.claudeModel
    }

    /// Listede olmayan kayıtlı modeller (eski ayar ya da listeden çıkarılan model) varsayılana döner.
    func withCuratedModels() -> UserSettings {
        var settings = self
        for provider in AIProvider.allCases { settings.setModel(provider.model(model(for: provider)).id, for: provider) }
        return settings
    }

    /// Yapay zekâ hizmetinin seçili model kimliği.
    func model(for provider: AIProvider) -> String {
        switch provider {
        case .gemini: geminiModel
        case .openAI: openAIModel
        case .claude: claudeModel
        }
    }

    mutating func setModel(_ id: String, for provider: AIProvider) {
        switch provider {
        case .gemini: geminiModel = id
        case .openAI: openAIModel = id
        case .claude: claudeModel = id
        }
    }

    /// Ayarlarda seçili motor: çevrimiçi çeviri kapalıysa ücretsiz olan.
    var translationEngine: TranslationEngine {
        get { onlineTranslation ? onlineEngine : .free }
        set {
            onlineTranslation = newValue != .free
            if newValue != .free { onlineEngine = newValue }
        }
    }
}

protocol AppStore: AnyObject {
    func save<T: Encodable>(_ value: T, for key: String)
    func load<T: Decodable>(_ type: T.Type, for key: String) -> T?
    func remove(_ key: String)
}

final class KeychainStore: AppStore {
    func save<T: Encodable>(_ value: T, for key: String) { SecureStore.save(value, for: key) }
    func load<T: Decodable>(_ type: T.Type, for key: String) -> T? { SecureStore.load(type, for: key) }
    func remove(_ key: String) { SecureStore.remove(key) }
}

/// Hiçbir şey kalıcı olmaz.
final class EphemeralStore: AppStore {
    private var values: [String: Data] = [:]
    func save<T: Encodable>(_ value: T, for key: String) { values[key] = try? JSONEncoder().encode(value) }
    func load<T: Decodable>(_ type: T.Type, for key: String) -> T? { values[key].flatMap { try? JSONDecoder().decode(type, from: $0) } }
    func remove(_ key: String) { values[key] = nil }
}

/// Dış dünyayla (PS5, PSN, TV) konuşan her şey; testlerde sahtesi kullanılır.
extension AppServices {
    /// DeepL anahtarını dener (ayarlardaki "Kaydet ve dene").
    func checkOnlineKey(_ key: String) async -> OnlineKeyCheck { await DeepLTranslator.check(key: key) }
    /// Yapay zekâ anahtarını örnek bir satırı çevirerek dener.
    func testAIKey(provider: AIProvider, key: String, model: String?) async -> Result<String, AIFailure> {
        await AITranslationCore.test(provider: provider, key: key, model: model)
    }
}

protocol AppServices: AnyObject {
    func discoverConsoles() async -> [ConsoleInfo]
    func accountId(fromRedirect url: URL) async throws -> Data
    func register(host: String, accountId: Data, pin: UInt32) async throws -> RegisteredConsole
    func discoverTVs() async -> [LGTV]
    /// TV ile eşleşir ve TV uygulamasını sunucu adresiyle başlatmayı dener.
    func pairTV(_ tv: LGTV, key: String?, server: String) async throws -> TVPairing
    func makeStream(console: RegisteredConsole, accountId: Data) -> StreamControlling
    /// `onMoved`: TV ağda yeni bir adreste bulununca çağrılır.
    /// `appConnected`: TV uygulaması bilgisayara bağlı mı (Samsung'da bağlıyken TV'ye dokunulmaz).
    func makeKeeper(tv: LGTV, key: String?, params: [String: Any], appConnected: @escaping @Sendable () -> Bool,
                    onMoved: @escaping (LGTV) -> Void) -> KeeperControlling
    /// Uygulamayla gelen TV paketinin sürümü (geliştirici derlemesinde paket olmayabilir).
    var bundledTVAppVersion: String? { get }
    func isDevModeOn(host: String) async -> Bool
    func fetchDevKey(host: String, passphrase: String) async throws -> String
    func installedTVAppVersion(host: String, devKey: String) async throws -> String?
    func installTVApp(host: String, devKey: String) async throws
    /// LG geliştirici modunun süresini baştan başlatır; kalan saati döner (bilinmiyorsa nil).
    func renewDevSession(host: String, devKey: String) async -> Int?

    /// Samsung ve Android TV için uygulamayla gelen paket (geliştirici derlemesinde olmayabilir).
    func bundledApp(for brand: TVBrand) -> BundledTVApp?
    func isSamsungDevModeOn(host: String) async -> Bool
    func installSamsungApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws
    func isAndroidDebugOn(host: String) async -> Bool
    /// Ağda ADB'si açık cihazlar.
    func scanAndroidTVs() async -> [String]
    /// Eksikse ya da eskiyse kurar; TV'deki sürümü döner.
    func installAndroidApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws -> String
}

struct BundledTVApp: Equatable {
    let url: URL
    let version: String

    /// `couchsubs-androidtv_0.7.0.apk` → `0.7.0`
    static func version(ofFile name: String) -> String? {
        let stem = (name as NSString).deletingPathExtension
        guard let underscore = stem.lastIndex(of: "_"), underscore < stem.index(before: stem.endIndex) else { return nil }
        return String(stem[stem.index(after: underscore)...])
    }
}

/// Denetlenemeyen TV'ler için: TV uygulaması kendisi bağlanır.
final class IdleKeeper: KeeperControlling {
    func start(interval: Duration) {}
    func stop() {}
    func reconnect() {}
}

struct TVPairing: Equatable {
    let key: String
    /// false ise TV uygulaması açılamadı; büyük olasılıkla TV'de kurulu değil.
    let launched: Bool
}

/// PS5 bağlantısı (gerçekte `StreamSession`).
protocol StreamControlling: AnyObject {
    var onFrame: ((CGImage) -> Void)? { get set }
    var onState: ((SessionState) -> Void)? { get set }
    func start()
    func stop()
    func reconnectNow()
}

/// TV uygulamasını açık tutan görevli (gerçekte `TVKeeper`).
protocol KeeperControlling: AnyObject {
    func start(interval: Duration)
    func stop()
    func reconnect()
}

extension StreamSession: StreamControlling {}
extension TVKeeper: KeeperControlling {}

final class LiveServices: AppServices {
    func discoverConsoles() async -> [ConsoleInfo] { await Console.discover() }

    func accountId(fromRedirect url: URL) async throws -> Data {
        guard let code = PSNAccount.code(fromRedirect: url) else { throw AppError.invalidLogin }
        return try await PSNAccount.accountId(code: code)
    }

    func register(host: String, accountId: Data, pin: UInt32) async throws -> RegisteredConsole {
        try await Registration.register(host: host, accountId: accountId, pin: pin)
    }

    func discoverTVs() async -> [LGTV] {
        async let lg = LGDiscovery.search()
        async let samsung = SamsungDiscovery.search()
        return await lg + samsung
    }

    func pairTV(_ tv: LGTV, key: String?, server: String) async throws -> TVPairing {
        switch tv.brand {
        case .androidTV:
            // Bilgisayar bu TV'yi denetlemez; TV uygulaması bilgisayarı kendisi bulur.
            return TVPairing(key: "", launched: true)
        case .samsung:
            let client = SamsungClient(tv: tv, token: key)
            defer { client.close() }
            let token = try await client.connect()
            try? await client.launch(appId: AppIdentity.samsungAppId, params: ["server": server])
            return TVPairing(key: token, launched: true)
        case .lg:
            break
        }
        let client = SSAPClient(tv: tv, clientKey: key)
        defer { client.close() }
        let newKey = try await client.connect()
        let launched = (try? await client.launch(appId: AppIdentity.tvAppId, params: ["server": server])) != nil
        return TVPairing(key: newKey, launched: launched)
    }

    func makeStream(console: RegisteredConsole, accountId: Data) -> StreamControlling {
        StreamSession(console: console, accountId: accountId)
    }

    func makeKeeper(tv: LGTV, key: String?, params: [String: Any], appConnected: @escaping @Sendable () -> Bool,
                    onMoved: @escaping (LGTV) -> Void) -> KeeperControlling {
        switch tv.brand {
        case .androidTV:
            return IdleKeeper()
        case .samsung:
            let locator = TVLocator(tv: tv, connect: { tv in
                let client = SamsungClient(tv: tv, token: key)
                do {
                    _ = try await client.connect()
                } catch {
                    client.close()
                    throw error
                }
                return client
            }, search: { await SamsungDiscovery.search() }, onMoved: onMoved)
            return TVKeeper(connect: { try await locator.connect() }, appId: AppIdentity.samsungAppId, params: params,
                            appConnected: appConnected)
        case .lg:
            break
        }
        let locator = TVLocator(tv: tv, connect: { tv in
            let client = SSAPClient(tv: tv, clientKey: key)
            do {
                _ = try await client.connect()
            } catch {
                client.close()
                throw error
            }
            return client
        }, search: { await LGDiscovery.search() }, onMoved: onMoved)
        return TVKeeper(connect: { try await locator.connect() }, appId: AppIdentity.tvAppId, params: params)
    }

    // MARK: - TV uygulamasını kurma

    private var bundledTVPackage: URL? {
        Bundle.main.urls(forResourcesWithExtension: "ipk", subdirectory: "tv-app")?.first
    }

    var bundledTVAppVersion: String? {
        bundledTVPackage.flatMap { DevModeInstaller.version(ofPackage: $0.lastPathComponent) }
    }

    func isDevModeOn(host: String) async -> Bool { await DevModeInstaller.isDevModeOn(host: host) }

    func fetchDevKey(host: String, passphrase: String) async throws -> String {
        try await DevModeInstaller.fetchKey(host: host, passphrase: passphrase, runner: ProcessRunner())
    }

    func installedTVAppVersion(host: String, devKey: String) async throws -> String? {
        try await withKeyFile(devKey) { file in
            try await DevModeInstaller(host: host, keyFile: file, runner: ProcessRunner()).installedVersion()
        }
    }

    func installTVApp(host: String, devKey: String) async throws {
        guard let package = bundledTVPackage, let version = bundledTVAppVersion else { throw DevModeError.installFailed }
        try await withKeyFile(devKey) { file in
            try await DevModeInstaller(host: host, keyFile: file, runner: ProcessRunner()).install(package: package, version: version)
        }
    }

    func renewDevSession(host: String, devKey: String) async -> Int? {
        try? await withKeyFile(devKey) { file in
            try await DevModeInstaller(host: host, keyFile: file, runner: ProcessRunner()).renewSession()
        }
    }

    // MARK: Samsung ve Android TV (gömülü yardımcıyla)

    func bundledApp(for brand: TVBrand) -> BundledTVApp? {
        let ext = switch brand {
        case .samsung: "wgt"
        case .androidTV: "apk"
        case .lg: "ipk"
        }
        guard brand != .lg, TVHelper.executable != nil,
              let url = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "tv-app")?.first,
              let version = BundledTVApp.version(ofFile: url.lastPathComponent) else { return nil }
        return BundledTVApp(url: url, version: version)
    }

    func isSamsungDevModeOn(host: String) async -> Bool { await Self.isPortOpen(host: host, port: 26101) }

    func installSamsungApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws {
        _ = try await TVHelper.run(["samsung-install", "--host", host, "--package", app.url.path, "--version", app.version,
                                    "--profiles", TVHelper.dataDirectory.appendingPathComponent("samsung").path], onEvent: onEvent)
    }

    func isAndroidDebugOn(host: String) async -> Bool { await Self.isPortOpen(host: host, port: 5555) }

    func scanAndroidTVs() async -> [String] {
        (try? await TVHelper.run(["android-scan"]).hosts) ?? []
    }

    func installAndroidApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws -> String {
        let result = try await TVHelper.run(["android-install", "--host", host, "--package", app.url.path, "--version", app.version,
                                             "--key-dir", TVHelper.dataDirectory.appendingPathComponent("adb").path], onEvent: onEvent)
        return result.version ?? app.version
    }

    static func isPortOpen(host: String, port: UInt16) async -> Bool {
        await DevModeInstaller.isPortOpen(host: host, port: port)
    }

    /// ssh anahtarı dosyadan okur; dosya yalnız komut süresince durur.
    private func withKeyFile<T>(_ key: String, _ body: (URL) async throws -> T) async throws -> T {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: file.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw DevModeError.installFailed
        }
        defer { try? FileManager.default.removeItem(at: file) }
        return try await body(file)
    }
}

enum AppError: LocalizedError, Equatable {
    case invalidPin, invalidLogin, missingAccount, wrongAccount, registrationFailed

    var errorDescription: String? {
        switch self {
        case .invalidPin: String(localized: "The code must be 8 digits.")
        case .invalidLogin: String(localized: "Sign-in did not complete. Please try again.")
        case .missingAccount: String(localized: "Sign in to PlayStation Network first.")
        case .wrongAccount: String(localized: "The PS5 did not recognise this account. Get the code from the PS5 user signed in with the account you used in CouchSubs, or sign in again with that user's account.")
        case .registrationFailed: String(localized: "The PS5 refused the code. Open Pair Device again on the PS5 and enter the new code.")
        }
    }
}

/// TV uygulamasının kurulum durumu.
enum TVAppState: Equatable {
    /// Bilinmiyor ya da yapılacak bir şey yok (ör. uygulama açılıyor ama anahtar yok).
    case unknown
    case working
    case upToDate(String)
    /// TV uygulaması açılamadı ve geliştirici modu kapalı.
    case devModeOff
    /// Geliştirici modu açık; Key Server parolası gerekiyor. `error` son denemenin sonucu.
    case needsPassphrase(error: DevModeError?)
    /// `reason`: TV'nin verdiği sebep (LG kurulumunda luna yanıtındaki errorText/reason); kullanıcıya da gösterilir.
    case failed(DevModeError, reason: String? = nil)
    /// Samsung: sertifika için tarayıcıda Samsung hesabıyla giriş bekleniyor.
    case signIn(URL)
    /// Android TV: TV ekranında hata ayıklama izni bekleniyor.
    case approveOnTV
}

@MainActor
@Observable
final class AppModel {
    enum Step: Int, CaseIterable {
        case welcome, secondAccount, psnLogin, console, tv, test, done
    }

    var step: Step
    var accountId: Data?
    var console: RegisteredConsole?
    var tv: LGTV?
    var tvApp = TVAppState.unknown
    /// LG geliştirici modunun kalan süresi (saat); CouchSubs uzattıktan sonra bilinir.
    var devModeHoursLeft: Int?
    /// Son eşleşmede TV uygulaması açılamadı.
    private var tvAppMissing = false
    /// TV uygulaması denetimi sürüyor (bekleme ekranı ve çeviri başlangıcı aynı anda çağırabilir).
    private var refreshingTVApp = false
    var settings: UserSettings {
        didSet {
            // Sıradan tercih; her kaydırıcı hareketinde Anahtarlık'a yazılmasın.
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: StoreKey.settings) }
            server.sendStyle(settings.style)
            if settings.dubbing != oldValue.dubbing { dubbingSettingsChanged(from: oldValue.dubbing) }
            let translationChanged = settings.onlineTranslation != oldValue.onlineTranslation
                || settings.onlineEngine != oldValue.onlineEngine || settings.geminiModel != oldValue.geminiModel
                || settings.openAIModel != oldValue.openAIModel || settings.claudeModel != oldValue.claudeModel
            if translationChanged { Task { await refreshTranslatorStatus() } }
            if isRunning, settings.sourceLanguage != oldValue.sourceLanguage || settings.targetLanguage != oldValue.targetLanguage
                || translationChanged {
                Task { await refreshTranslatorStatus() }
                makePipeline()
            }
        }
    }

    // Çalışma durumu
    var isRunning = false
    var isStarting = false
    var sessionState: SessionState = .disconnected(.stopped)
    /// Çeviri sürerken Mac'in boşta uykuya geçmesi engellenir (kullanıcı TV'de oynuyor, Mac'e dokunmuyor).
    var isPreventingSleep: Bool { sleepActivity != nil }
    var tvClients = 0
    var lastSource = ""
    var lastTranslation = ""
    /// Bu oturumda çevrilen altyazılar; kaçırılan satır ana pencereden yeniden okunur.
    var history = SubtitleHistory()
    var translatorStatus: TranslatorStatus = .ready
    /// Çevrimiçi çeviri (DeepL ya da yapay zekâ) şu an çeviremiyor; o satırlar cihaz üstü çeviriyle çevriliyor.
    var onlineIssue: OnlineKeyState?
    /// Yazı tanıma art arda hata veriyor; değeri diskteki boş yer (GB). macOS, diskte yer kalmayınca okuma modelini
    /// diske yazamaz ve her okumayı hata ile bitirir; altyazı sessizce hiç gelmez.
    var readingFailedFreeGB: Double?
    private var readFailures = 0
    var lastFrame: CGImage?
    var showAbout = false
    var showSettings = false

    private let services: AppServices
    private let store: AppStore
    private let defaults: UserDefaults
    /// Çalışan okuma hattının dilleri.
    private(set) var activeLanguages: (source: String, target: String)?
    private var server = SubtitleServer(port: AppIdentity.serverPort)
    private var serverStarted = false
    /// Sunucunun gerçekten dinlediği port (8787 doluysa rastgele bir port).
    private(set) var serverPort: UInt16 = AppIdentity.serverPort
    private var session: StreamControlling?
    private var keeper: KeeperControlling?
    private var sleepActivity: NSObjectProtocol?
    private var pipeline: SubtitlePipeline?
    /// Oyundaki altyazının son görüldüğü yer; deneme altyazısı TV'de oraya yerleşir.
    private var lastSubtitleBox: TextBox?
    private var processing = false
    private var wakeObserver: NSObjectProtocol?

    // Dublaj
    private var dubber: Dubber?
    /// Model indiriliyorsa ilerleme (0…1).
    var dubbingDownload: Double?
    var dubbingError: String?
    var dubbingModelReady = DubbingModelStore.isReady

    init(services: AppServices = LiveServices(), store: AppStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.services = services
        self.store = store
        self.defaults = defaults
        let accountId = store.load(Data.self, for: StoreKey.accountId)
        let console = store.load(RegisteredConsole.self, for: StoreKey.console)
        let tv = store.load(LGTV.self, for: StoreKey.tv)
        let ready = accountId != nil && console != nil && tv != nil && store.load(String.self, for: StoreKey.tvKey) != nil
        self.accountId = accountId
        self.console = console
        self.tv = tv
        let loaded = defaults.data(forKey: StoreKey.settings).flatMap { try? JSONDecoder().decode(UserSettings.self, from: $0) } ?? UserSettings()
        let curated = loaded.withCuratedModels()
        settings = curated
        // Listede olmayan model varsayılana döndüyse ayar hemen kaydedilir.
        if curated != loaded, let data = try? JSONEncoder().encode(curated) { defaults.set(data, forKey: StoreKey.settings) }
        step = ready ? .done : .welcome
        savedKeys = Set(TranslationEngine.allCases.filter { engine in
            engine.storeKey.flatMap { store.load(String.self, for: $0) }?.isEmpty == false
        })
        server.onClientsChanged = { [weak self] count in self?.tvClients = count }
    }

    // MARK: - Sihirbaz

    var canAdvance: Bool {
        switch step {
        case .welcome, .secondAccount, .test: true
        case .psnLogin: accountId != nil
        case .console: console != nil
        case .tv: tv != nil && store.load(String.self, for: StoreKey.tvKey) != nil
        case .done: false
        }
    }

    func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func completePSNLogin(redirect: URL) async throws {
        let id = try await services.accountId(fromRedirect: redirect)
        accountId = id
        store.save(id, for: StoreKey.accountId)
    }

    func discoverConsoles() async -> [ConsoleInfo] { await services.discoverConsoles() }

    func register(host: String, pin: String) async throws {
        let digits = pin.filter(\.isNumber)
        guard digits.count == 8, let value = UInt32(digits) else { throw AppError.invalidPin }
        guard let accountId else { throw AppError.missingAccount }
        let registered: RegisteredConsole
        do {
            registered = try await services.register(host: host, accountId: accountId, pin: value)
        } catch Registration.RegistrationError.wrongAccount {
            throw AppError.wrongAccount
        } catch is Registration.RegistrationError {
            throw AppError.registrationFailed
        }
        console = registered
        store.save(registered, for: StoreKey.console)
    }

    func discoverTVs() async -> [LGTV] { await services.discoverTVs() }

    func pair(_ tv: LGTV) async throws {
        try await startServer()
        let pairing = try await services.pairTV(tv, key: store.load(String.self, for: StoreKey.tvKey), server: serverAddress(for: tv))
        if self.tv?.brand != tv.brand || (tv.brand != .androidTV && self.tv?.host != tv.host) {
            store.remove(StoreKey.tvAppVersion)
        }
        self.tv = tv
        store.save(tv, for: StoreKey.tv)
        store.save(pairing.key, for: StoreKey.tvKey)
        tvAppMissing = !pairing.launched
        if tv.brand == .lg {
            await refreshTVApp()
        } else {
            // Samsung girişi ya da Android onayı dakikalar sürebilir; eşleşme beklemesin.
            Task { await refreshTVApp() }
        }
    }

    // MARK: - TV uygulamasını kurma

    /// Geliştirici modu açık TV'de uygulamayı eksikse kurar, eskiyse günceller.
    /// Anahtar yoksa ve uygulama çalışıyorsa kullanıcıdan bir şey istenmez.
    func refreshTVApp() async {
        guard let tv, !refreshingTVApp else { return }
        refreshingTVApp = true
        defer { refreshingTVApp = false }
        switch tv.brand {
        case .lg: await refreshLGApp(tv)
        case .samsung: await refreshSamsungApp(tv)
        case .androidTV: await refreshAndroidApp(tv)
        }
    }

    /// Samsung ya da Android TV'ye daha önce CouchSubs'ın kurduğu sürüm.
    private var installedAppVersion: String? { store.load(String.self, for: StoreKey.tvAppVersion) }

    private func needsInstall(_ bundled: BundledTVApp) -> Bool {
        guard let installed = installedAppVersion else { return true }
        return DevModeInstaller.isNewer(bundled.version, than: installed)
    }

    private func refreshLGApp(_ tv: LGTV) async {
        guard let bundled = services.bundledTVAppVersion else { return }
        guard await services.isDevModeOn(host: tv.host) else {
            tvApp = tvAppMissing ? .devModeOff : .unknown
            return
        }
        guard let devKey = store.load(String.self, for: StoreKey.tvDevKey) else {
            tvApp = tvAppMissing ? .needsPassphrase(error: nil) : .unknown
            return
        }
        await install(tv: tv, devKey: devKey, bundled: bundled)
    }

    /// Samsung: geliştirici modu açıksa uygulamayı imzalayıp kurar. Sertifika yoksa Samsung girişi istenir.
    private func refreshSamsungApp(_ tv: LGTV) async {
        guard let bundled = services.bundledApp(for: .samsung) else { return }
        guard needsInstall(bundled) else {
            tvApp = .upToDate(installedAppVersion ?? bundled.version)
            return
        }
        guard await services.isSamsungDevModeOn(host: tv.host) else {
            tvApp = .devModeOff
            return
        }
        tvApp = .working
        do {
            try await services.installSamsungApp(host: tv.host, app: bundled) { [weak self] event in
                Task { @MainActor in self?.installEvent(event) }
            }
            store.save(bundled.version, for: StoreKey.tvAppVersion)
            tvApp = .upToDate(bundled.version)
            await openTVAppAfterInstall(tv)
        } catch {
            tvApp = .failed(error as? DevModeError ?? .installFailed)
        }
    }

    /// Android TV: ağda ADB'si açık TV'yi bulur, uygulamayı kurar ve açar.
    private func refreshAndroidApp(_ tv: LGTV) async {
        guard let bundled = services.bundledApp(for: .androidTV) else { return }
        var host = tv.host
        let reachable = host.isEmpty ? false : await services.isAndroidDebugOn(host: host)
        if !reachable {
            // Uygulama kuruluysa ve TV'de hata ayıklama kapalıysa yapılacak bir şey yok.
            if !needsInstall(bundled) {
                tvApp = .upToDate(installedAppVersion ?? bundled.version)
                return
            }
            guard let found = await services.scanAndroidTVs().first else {
                tvApp = .devModeOff
                return
            }
            host = found
        }
        tvApp = .working
        do {
            let version = try await services.installAndroidApp(host: host, app: bundled) { [weak self] event in
                Task { @MainActor in self?.installEvent(event) }
            }
            // TV'nin adresi bundan sonra sürüm denetimi için kullanılır.
            let located = LGTV(name: tv.name, host: host, brand: .androidTV)
            self.tv = located
            store.save(located, for: StoreKey.tv)
            store.save(version, for: StoreKey.tvAppVersion)
            tvApp = .upToDate(version)
        } catch {
            tvApp = .failed(error as? DevModeError ?? .installFailed)
        }
    }

    private func installEvent(_ event: TVInstallEvent) {
        // Kurulum bittikten sonra gelen geç olay sonucu ezmesin.
        switch tvApp {
        case .working, .signIn, .approveOnTV: break
        default: return
        }
        switch event {
        case .signIn(let url):
            tvApp = .signIn(url)
            openInBrowser(url)
        case .approveOnTV:
            tvApp = .approveOnTV
        case .progress:
            if case .signIn = tvApp { tvApp = .working }
        }
    }

    /// Seçili TV'ye uygulamayı CouchSubs kurabilir mi (paket uygulamayla geldi mi)?
    var canInstallTVApp: Bool {
        guard let tv else { return false }
        return tv.brand == .lg ? services.bundledTVAppVersion != nil : services.bundledApp(for: tv.brand) != nil
    }

    /// Testlerde tarayıcı açılmasın diye değiştirilebilir.
    var openInBrowser: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }

    /// Samsung'da geliştirici modunda "Host PC IP" olarak yazılacak bu Mac'in adresi.
    var computerAddress: String? {
        Self.localAddress(near: tv?.host.isEmpty == false ? tv!.host : "192.168.1.1")
    }

    /// Key Server'dan anahtarı alır (TV ekranındaki parolayla) ve uygulamayı kurar.
    func installTVApp(passphrase: String) async {
        guard let tv, let bundled = services.bundledTVAppVersion else { return }
        tvApp = .working
        do {
            let devKey = try await services.fetchDevKey(host: tv.host, passphrase: passphrase.trimmingCharacters(in: .whitespacesAndNewlines))
            store.save(devKey, for: StoreKey.tvDevKey)
            await install(tv: tv, devKey: devKey, bundled: bundled)
        } catch {
            tvApp = .needsPassphrase(error: error as? DevModeError ?? .installFailed)
        }
    }

    private func install(tv: LGTV, devKey: String, bundled: String) async {
        tvApp = .working
        do {
            let installed = try await services.installedTVAppVersion(host: tv.host, devKey: devKey)
            if let installed, !DevModeInstaller.isNewer(bundled, than: installed) {
                tvApp = .upToDate(installed)
                await renewDevSessionIfDue(tv: tv, devKey: devKey)
                return
            }
            try await services.installTVApp(host: tv.host, devKey: devKey)
            tvApp = .upToDate(bundled)
            tvAppMissing = false
            await renewDevSessionIfDue(tv: tv, devKey: devKey)
            await openTVAppAfterInstall(tv)
        } catch DevModeError.keyRefused {
            // Geliştirici modu yeniden açılınca TV yeni anahtar üretir; eskisi işe yaramaz.
            store.remove(StoreKey.tvDevKey)
            tvApp = .needsPassphrase(error: nil)
        } catch let failure as DevModeFailure {
            // Genel mesaj tek başına sorunu bulmaya yetmiyordu; TV'nin verdiği sebep de gösterilir.
            let reason = failure.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            tvApp = .failed(failure.error, reason: reason.isEmpty ? nil : reason)
        } catch {
            tvApp = .failed(error as? DevModeError ?? .installFailed)
        }
    }

    /// LG geliştirici modunun 1000 saatlik süresini günde en çok bir kez baştan başlatır; kullanıcı TV'den uzatmak
    /// zorunda kalmaz.
    private func renewDevSessionIfDue(tv: LGTV, devKey: String) async {
        let last = defaults.object(forKey: StoreKey.devSessionRenewed) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        if let hours = await services.renewDevSession(host: tv.host, devKey: devKey) {
            devModeHoursLeft = hours
            defaults.set(Date(), forKey: StoreKey.devSessionRenewed)
        }
    }

    private func openTVAppAfterInstall(_ tv: LGTV) async {
        if let keeper {
            keeper.reconnect()
        } else {
            _ = try? await services.pairTV(tv, key: store.load(String.self, for: StoreKey.tvKey), server: serverAddress(for: tv))
        }
    }

    func sendTestSubtitle() {
        server.sendStyle(settings.style)
        // Oyunda henüz altyazı görülmediyse altyazı bölgesinin altına yakın tipik bir yer kullanılır.
        let region = settings.region
        let box = lastSubtitleBox ?? TextBox(left: 0.3, top: region.bottom - 0.1, right: 0.7, bottom: region.bottom - 0.03)
        server.sendSubtitle(String(localized: "This is a test subtitle. Can you see it on top of the game?"), durationMs: 8000, box: box)
    }

    /// Kurulumu baştan başlatır (kayıtlı her şeyi siler).
    func resetSetup() {
        stop()
        [StoreKey.accountId, StoreKey.console, StoreKey.tv, StoreKey.tvKey, StoreKey.tvDevKey, StoreKey.tvAppVersion].forEach(store.remove)
        accountId = nil
        console = nil
        tv = nil
        tvApp = .unknown
        tvAppMissing = false
        step = .welcome
    }

    // MARK: - Çeviri

    func start() async {
        // Düğmeye iki kez basılması ya da beklerken tekrar çağrılması ikinci bir oturum açmaz.
        guard !isRunning, !isStarting, let console, let accountId, let tv else { return }
        isStarting = true
        defer { isStarting = false }

        translatorStatus = await Translator.status(source: settings.sourceLanguage, target: settings.targetLanguage)
        try? await startServer()
        server.sendStyle(settings.style)

        makePipeline()
        if settings.dubbing.enabled, dubbingModelReady { makeDubber().prepare() }

        let session = services.makeStream(console: console, accountId: accountId)
        session.onState = { [weak self] state in Task { @MainActor in self?.sessionStateChanged(state) } }
        session.onFrame = { [weak self] frame in Task { @MainActor in await self?.handle(frame) } }
        session.start()
        self.session = session

        // TV uygulamasını başlat ve açık tut; TV kapalıysa açıldığında bağlanır.
        let server = self.server
        let keeper = services.makeKeeper(tv: tv, key: store.load(String.self, for: StoreKey.tvKey), params: ["server": serverAddress(for: tv)],
                                         appConnected: { server.connectedClients > 0 }) { [weak self] moved in
            Task { @MainActor in self?.tvMoved(to: moved) }
        }
        keeper.start(interval: .seconds(5))
        self.keeper = keeper
        Task { await refreshTVApp() }

        // Mac uykudan uyanınca bağlantıları hemen yenile.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.session?.reconnectNow()
                self?.keeper?.reconnect()
            }
        }
        sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                              reason: "Translating game subtitles")
        isRunning = true
        if screenHotkey == nil { screenHotkey = ScreenHotkey { [weak self] in self?.translateScreen() } }
        screenHotkey?.enabled = true
    }

    // MARK: - Ekranı çevir

    /// ⌥⌘T yalnız çeviri sürerken tutulur.
    @ObservationIgnored private var screenHotkey: ScreenHotkey?
    /// Süren "ekranı çevir" işi; yeniden basılınca iptal edilir.
    @ObservationIgnored private var screenTask: Task<Void, Never>?
    /// TV'deki ekran çevirilerinin kalkacağı an; bu andan önce yeniden basmak onları kaldırır.
    @ObservationIgnored private var screenShownUntil = Date.distantPast

    /// ⌥⌘T: oyunun şu anki karesinin tamamını bir kez okur, her yazı grubunu ayrı çevirip TV'de kendi yerine koyar.
    /// Çeviriler hazırlandıkça TV'ye gider. Çeviri sürerken ya da çeviriler TV'deyken yeniden basmak onları kaldırır.
    func translateScreen() {
        guard isRunning, let frame = lastFrame else { return }
        if let task = screenTask {
            task.cancel()
            screenTask = nil
            hideScreen()
            return
        }
        if Date() < screenShownUntil {
            hideScreen()
            return
        }
        server.sendStyle(settings.style)
        server.sendSubtitle(String(localized: "Translating the screen…"), durationMs: 2500)
        let reader = VisionReader(language: settings.sourceLanguage)
        let translator = makeTranslator()
        let server = self.server
        screenTask = Task { [weak self] in
            do {
                let reading = try await Task.detached(priority: .userInitiated) { try reader.readLines(frame, deep: false) }.value
                let items = try await ScreenTranslation.translate(reading, using: { try await translator.translate($0) }) { shown in
                    guard !Task.isCancelled else { return }
                    let milliseconds = ScreenTranslation.displayMilliseconds(shown)
                    server.sendScreen(shown, durationMs: milliseconds)
                    self?.screenShownUntil = Date().addingTimeInterval(Double(milliseconds) / 1000)
                }
                server.clear()
                if items.isEmpty { server.sendSubtitle(String(localized: "No text found on the screen."), durationMs: 2500) }
            } catch is CancellationError {
                return
            } catch let error as TranslatorError {
                server.clear()
                self?.translatorStatus = Self.translatorStatus(after: error)
            } catch {
                server.clear()
            }
            if !Task.isCancelled { self?.screenTask = nil }
        }
    }

    private func hideScreen() {
        screenShownUntil = .distantPast
        server.clearScreen()
        server.clear()
    }

    func tvMoved(to moved: LGTV) {
        tv = moved
        store.save(moved, for: StoreKey.tv)
    }

    /// Okuma hattını güncel dillerle (yeniden) kurar.
    private func makePipeline() {
        pipeline?.reset()
        let pipeline = SubtitlePipeline(reader: VisionReader(language: settings.sourceLanguage),
                                        translator: makeTranslator(),
                                        server: server, scheduler: ReadScheduler())
        pipeline.onPair = { [weak self, weak pipeline] source, translation in
            self?.lastSource = source
            self?.lastTranslation = translation
            self?.history.add(source: source, translation: translation)
            if let box = pipeline?.lastBox { self?.lastSubtitleBox = box }
        }
        // Dil paketi bu arada indirilmiş olabilir; her çeviri sonucu durumu günceller.
        pipeline.onTranslationResult = { [weak self] error in
            self?.translatorStatus = Self.translatorStatus(after: error)
        }
        pipeline.onReadResult = { [weak self] error in self?.noteRead(error) }
        pipeline.onSpeech = { [weak self] lines in self?.speak(lines) }
        onlineIssue = nil
        pipeline.warmUp()
        self.pipeline = pipeline
        activeLanguages = (settings.sourceLanguage, settings.targetLanguage)
    }

    private func refreshTranslatorStatus() async {
        if onlineTranslationActive {
            translatorStatus = .ready
            return
        }
        translatorStatus = await Translator.status(source: settings.sourceLanguage, target: settings.targetLanguage)
    }

    // MARK: - Çevrimiçi çeviri (DeepL ve yapay zekâ)

    private func makeTranslator() -> TextTranslator {
        let (source, target) = (settings.sourceLanguage, settings.targetLanguage)
        // Önceki oturumların çevirileri motor ve dil çifti başına diskte durur; tekrar eden satır hemen gelir.
        let local = Translator(source: source, target: target,
                               cache: Self.translationCache(engine: Translator.engineID, source: source, target: target))
        let engine = settings.onlineEngine
        guard onlineTranslationActive, let storeKey = engine.storeKey, let key = store.load(String.self, for: storeKey) else { return local }
        let online: TextTranslator & OnlineTranslating
        if let provider = engine.aiProvider {
            let model = provider.model(settings.model(for: provider)).id
            online = AITranslator(provider: provider, key: key, model: model, fallback: local,
                                  cache: Self.translationCache(engine: provider.engineID(model: model), source: source, target: target))
        } else {
            online = DeepLTranslator(key: key, fallback: local,
                                     cache: Self.translationCache(engine: DeepLTranslator.engineID, source: source, target: target))
        }
        // Hizmet çeviremeyince ana ekranda uyarı çıkar; düzelince kalkar.
        online.onFailureChanged = { [weak self] state in
            Task { @MainActor in self?.onlineIssue = state }
        }
        return online
    }

    /// ~/Library/Application Support/CouchSubs/Translations içindeki kalıcı çeviri önbelleği.
    private static func translationCache(engine: String, source: String, target: String) -> TranslationCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(AppIdentity.name, isDirectory: true)
            .appendingPathComponent("Translations", isDirectory: true)
        return TranslationCache.shared(in: directory, engine: engine, source: source, target: target)
    }

    /// Çevrimiçi çeviri yalnız İngilizce→Türkçe için ve seçili motorun anahtarı kayıtlıysa açılır.
    var onlineTranslationActive: Bool {
        settings.onlineTranslation && settings.sourceLanguage == "en" && settings.targetLanguage == "tr" && hasKey(settings.onlineEngine)
    }

    /// Anahtarı kayıtlı motorlar (anahtarların kendisi arayüze hiç dönmez).
    private var savedKeys: Set<TranslationEngine> = []

    func hasKey(_ engine: TranslationEngine) -> Bool { savedKeys.contains(engine) }

    /// Kayıtlı bir DeepL anahtarı var mı.
    var hasDeepLKey: Bool { hasKey(.deepL) }

    /// Anahtar denenir; geçerliyse (kotası bitmiş olsa da) Anahtarlık'a yazılır ve DeepL seçilir.
    func setDeepLKey(_ key: String) async -> OnlineKeyCheck {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let check = await services.checkOnlineKey(key)
        if check.state == .valid || check.state == .quotaExceeded { saveKey(key, for: .deepL) }
        return check
    }

    /// Kayıtlı anahtarın bu ayki kullanımı.
    func deepLUsage() async -> OnlineKeyCheck {
        guard let key = store.load(String.self, for: StoreKey.deepLKey) else { return OnlineKeyCheck(state: .invalid) }
        return await services.checkOnlineKey(key)
    }

    func removeDeepLKey() { removeKey(.deepL) }

    /// Yapay zekâ anahtarı örnek bir satırla denenir. Anahtar kabul edildiyse (bakiye bitmiş ya da model adı yanlış olsa
    /// da) Anahtarlık'a yazılır ve bu motor seçilir.
    func setAIKey(_ key: String, for provider: AIProvider) async -> Result<String, AIFailure> {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await services.testAIKey(provider: provider, key: key, model: settings.model(for: provider))
        switch result {
        case .success, .failure(.quotaExceeded), .failure(.modelRejected): saveKey(key, for: TranslationEngine(provider))
        case .failure: break
        }
        return result
    }

    /// Kayıtlı anahtar ve modelle örnek satırı çevirir (ayarlardaki "Dene").
    func testAIKey(for provider: AIProvider) async -> Result<String, AIFailure> {
        guard let storeKey = TranslationEngine(provider).storeKey, let key = store.load(String.self, for: storeKey) else {
            return .failure(.invalidKey)
        }
        return await services.testAIKey(provider: provider, key: key, model: settings.model(for: provider))
    }

    func removeKey(_ engine: TranslationEngine) {
        guard let storeKey = engine.storeKey else { return }
        store.remove(storeKey)
        savedKeys.remove(engine)
        if settings.translationEngine == engine {
            settings.onlineTranslation = false
        } else {
            Task { await refreshTranslatorStatus() }
        }
    }

    private func saveKey(_ key: String, for engine: TranslationEngine) {
        guard let storeKey = engine.storeKey else { return }
        store.save(key, for: storeKey)
        savedKeys.insert(engine)
        if settings.translationEngine == engine {
            // Motor zaten seçiliydi, anahtar yeni geldi: hat yeni anahtarla kurulsun.
            if isRunning { makePipeline() }
            Task { await refreshTranslatorStatus() }
        } else {
            settings.translationEngine = engine
        }
    }

    func stop() {
        session?.stop()
        session = nil
        keeper?.stop()
        keeper = nil
        pipeline?.reset()
        pipeline = nil
        activeLanguages = nil
        screenHotkey?.enabled = false
        screenTask?.cancel()
        screenTask = nil
        if Date() < screenShownUntil { server.clearScreen() }
        screenShownUntil = .distantPast
        if let dubber {
            self.dubber = nil
            Task { await dubber.shutdown() }
        }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let sleepActivity { ProcessInfo.processInfo.endActivity(sleepActivity) }
        sleepActivity = nil
        isRunning = false
        onlineIssue = nil
        sessionState = .disconnected(.stopped)
    }

    private func sessionStateChanged(_ state: SessionState) {
        sessionState = state
        // Bağlantı koptuysa TV'de eski altyazı kalmasın.
        if case .disconnected = state {
            pipeline?.reset()
            server.clear()
            dubber?.stop()
        }
    }

    private func noteRead(_ error: Error?) {
        guard error != nil else {
            readFailures = 0
            readingFailedFreeGB = nil
            return
        }
        readFailures += 1
        if readFailures >= 10, readingFailedFreeGB == nil { readingFailedFreeGB = Self.freeDiskGB() }
    }

    static func freeDiskGB() -> Double {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let bytes = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return Double(bytes) / 1_000_000_000
    }

    static func translatorStatus(after error: TranslatorError?) -> TranslatorStatus {
        switch error {
        case nil: .ready
        case .needsDownload: .needsDownload
        case .unsupported: .unsupported
        }
    }

    /// Çeviri başlamamışken bağlı olmamak bir sorun değildir; nokta gri kalır.
    static func ps5Tone(_ state: SessionState, running: Bool) -> StatusTone {
        state == .streaming ? .good : running ? .warning : .idle
    }

    static func tvTone(clients: Int, running: Bool) -> StatusTone {
        clients > 0 ? .good : running ? .warning : .idle
    }

    /// PS5 durumunun kullanıcıya gösterilecek metni.
    static func statusText(_ state: SessionState, running: Bool) -> String {
        switch state {
        case .streaming: return String(localized: "Connected")
        case .connecting: return String(localized: "Connecting…")
        case .disconnected(let reason):
            guard running else { return String(localized: "Not connected") }
            switch reason {
            case .consoleAsleep: return String(localized: "Turn on your PS5")
            case .inUse: return String(localized: "Remote Play is in use on another device")
            case .refused: return String(localized: "The PS5 refused the connection. Set up the PS5 again.")
            case .loginPasscode: return String(localized: "The second user has a login passcode on the PS5. Turn it off in Settings › Users and Accounts.")
            default: return String(localized: "Reconnecting…")
            }
        }
    }

    private func handle(_ frame: CGImage) async {
        lastFrame = frame
        // Önceki kare hâlâ işleniyorsa bu kare atlanır; okuma kareleri biriktirmez.
        guard !processing, let pipeline else { return }
        processing = true
        await pipeline.process(frame, region: settings.region)
        processing = false
    }

    private func startServer() async throws {
        guard !serverStarted else { return }
        do {
            serverPort = try await server.start()
        } catch {
            // 8787 başka bir uygulamada; TV'ye zaten adres bildirildiği için herhangi bir boş port olur.
            server = SubtitleServer(port: 0)
            server.onClientsChanged = { [weak self] count in self?.tvClients = count }
            serverPort = try await server.start()
        }
        serverStarted = true
    }

    /// TV ile aynı ağdaki Mac adresi.
    private func serverAddress(for tv: LGTV) -> String {
        "http://\(Self.localAddress(near: tv.host) ?? "127.0.0.1"):\(serverPort)"
    }

    static func localAddress(near host: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        let target = inet_addr(host)
        var fallback: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard Int32(entry.ifa_flags) & IFF_LOOPBACK == 0, entry.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = entry.ifa_netmask else { continue }
            let address = entry.ifa_addr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let text = String(cString: inet_ntoa(address))
            if address.s_addr & netmask == target & netmask { return text }
            fallback = fallback ?? text
        }
        return fallback
    }
}

// MARK: - Dublaj

extension AppModel {
    @discardableResult
    private func makeDubber() -> Dubber {
        if let dubber {
            dubber.update(serverPort: serverPort)
            return dubber
        }
        let dubber = Dubber(server: server, serverPort: serverPort, settings: settings.dubbing)
        dubber.onCastChanged = { [weak self] cast in self?.settings.dubbing.cast = cast }
        dubber.onError = { [weak self] message in self?.dubbingError = message }
        self.dubber = dubber
        return dubber
    }

    private func speak(_ lines: [SpokenLine]) {
        guard settings.dubbing.enabled, dubbingModelReady else { return }
        makeDubber().speak(lines)
    }

    private func dubbingSettingsChanged(from old: DubbingSettings) {
        guard let dubber else {
            if settings.dubbing.enabled, !old.enabled, isRunning, dubbingModelReady { makeDubber().prepare() }
            return
        }
        dubber.cast = settings.dubbing.cast
        if dubber.output != settings.dubbing.output {
            dubber.stop()
            dubber.output = settings.dubbing.output
        }
        if !settings.dubbing.enabled {
            self.dubber = nil
            Task { await dubber.shutdown() }
        }
    }

    /// Ses modelini indirir (ilk kullanımda bir kez, ~440 MB).
    func downloadDubbingModel() async {
        guard dubbingDownload == nil else { return }
        dubbingDownload = 0
        dubbingError = nil
        do {
            try await DubbingModelStore.download { [weak self] progress in self?.dubbingDownload = progress }
            dubbingModelReady = true
            if settings.dubbing.enabled, isRunning { makeDubber().prepare() }
        } catch {
            dubbingError = error.localizedDescription
        }
        dubbingDownload = nil
    }

    /// Ayarlardaki "Dinle": sesi seçilen çıkıştan çalar.
    func previewVoice(_ voice: DubbingVoice) async {
        guard dubbingModelReady else { return }
        dubbingError = nil
        try? await startServer()
        makeDubber().preview(voice)
    }

    func assignVoice(_ voice: DubbingVoice, to name: String) {
        settings.dubbing.cast.assign(voice, to: name)
    }

    func removeDubbingModel() {
        if let dubber {
            self.dubber = nil
            Task { await dubber.shutdown() }
        }
        DubbingModelStore.remove()
        dubbingModelReady = false
    }
}
