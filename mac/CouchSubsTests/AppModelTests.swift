// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import RemotePlay
import XCTest
@testable import CouchSubs

final class MemoryStore: AppStore {
    var values: [String: Data] = [:]
    func save<T: Encodable>(_ value: T, for key: String) { values[key] = try? JSONEncoder().encode(value) }
    func load<T: Decodable>(_ type: T.Type, for key: String) -> T? { values[key].flatMap { try? JSONDecoder().decode(type, from: $0) } }
    func remove(_ key: String) { values[key] = nil }
}

extension UserDefaults {
    /// Testler gerçek uygulamanın tercihlerine yazmasın diye her model ayrı bir alan kullanır.
    static func isolated() -> UserDefaults { UserDefaults(suiteName: "couchsubs-test-\(UUID())")! }
}

final class FakeServices: AppServices {
    var consoles = [ConsoleInfo(host: "192.168.1.253", name: "PS5-789", isAwake: true)]
    var tvs = [LGTV(name: "LG TV", host: "192.168.1.153")]
    var registered: RegisteredConsole?
    var registerError: Error?
    var launchedServer: String?
    var streams: [FakeStream] = []
    var keepers: [FakeKeeper] = []
    var appOnTV: String? = "0.6.1"
    var devMode = false
    var keyServer = true
    var refuseKey = false
    var installs = 0
    var pairCount = 0
    var onMoved: ((LGTV) -> Void)?

    /// "Kaydet ve dene"nin sonucu; gerçek hizmete gidilmez.
    var aiResult: Result<String, AIFailure> = .success("KRATOS: Gidiyoruz.")
    var aiTests: [(provider: AIProvider, key: String, model: String?)] = []
    func testAIKey(provider: AIProvider, key: String, model: String?) async -> Result<String, AIFailure> {
        aiTests.append((provider, key, model))
        return aiResult
    }

    func discoverConsoles() async -> [ConsoleInfo] { consoles }
    var loginError: Error?
    func accountId(fromRedirect url: URL) async throws -> Data {
        if let loginError { throw loginError }
        return Data(repeating: 1, count: 8)
    }
    var registeredPin: UInt32?
    func register(host: String, accountId: Data, pin: UInt32) async throws -> RegisteredConsole {
        registeredPin = pin
        if let registerError { throw registerError }
        let console = RegisteredConsole(host: host, name: "PS5-789", registKey: Data(repeating: 0x31, count: 16), morning: Data(repeating: 2, count: 16))
        registered = console
        return console
    }
    func discoverTVs() async -> [LGTV] { tvs }
    func pairTV(_ tv: LGTV, key: String?, server: String) async throws -> TVPairing {
        launchedServer = server
        pairCount += 1
        return TVPairing(key: "tv-key", launched: appOnTV != nil)
    }
    func makeStream(console: RegisteredConsole, accountId: Data) -> StreamControlling {
        let stream = FakeStream()
        streams.append(stream)
        return stream
    }
    func makeKeeper(tv: LGTV, key: String?, params: [String: Any], appConnected: @escaping @Sendable () -> Bool,
                    onMoved: @escaping (LGTV) -> Void) -> KeeperControlling {
        let keeper = FakeKeeper()
        keepers.append(keeper)
        self.onMoved = onMoved
        return keeper
    }
    var bundledTVAppVersion: String? = "0.6.1"
    func isDevModeOn(host: String) async -> Bool { devMode }
    func fetchDevKey(host: String, passphrase: String) async throws -> String {
        guard keyServer else { throw DevModeError.keyServerOff }
        guard passphrase == "ABC123" else { throw DevModeError.wrongPassphrase }
        return "dev-key"
    }
    func installedTVAppVersion(host: String, devKey: String) async throws -> String? {
        if refuseKey { throw DevModeError.keyRefused }
        return appOnTV
    }
    var lgInstallError: Error?
    func installTVApp(host: String, devKey: String) async throws {
        installs += 1
        if let lgInstallError { throw lgInstallError }
        appOnTV = bundledTVAppVersion
    }
    var renewedHours: Int? = 999
    var renewals = 0
    func renewDevSession(host: String, devKey: String) async -> Int? {
        renewals += 1
        return renewedHours
    }

    // Samsung ve Android TV
    var bundled: [TVBrand: BundledTVApp] = [:]
    var samsungDevMode = false
    var androidHosts: [String] = []
    var installError: DevModeError?
    var events: [TVInstallEvent] = []
    var brandInstalls: [(brand: TVBrand, host: String)] = []
    func bundledApp(for brand: TVBrand) -> BundledTVApp? { bundled[brand] }
    func isSamsungDevModeOn(host: String) async -> Bool { samsungDevMode }
    func installSamsungApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws {
        events.forEach(onEvent)
        if let installError { throw installError }
        brandInstalls.append((.samsung, host))
    }
    func isAndroidDebugOn(host: String) async -> Bool { androidHosts.contains(host) }
    func scanAndroidTVs() async -> [String] { androidHosts }
    func installAndroidApp(host: String, app: BundledTVApp, onEvent: @escaping @Sendable (TVInstallEvent) -> Void) async throws -> String {
        events.forEach(onEvent)
        if let installError { throw installError }
        brandInstalls.append((.androidTV, host))
        return app.version
    }
}

final class FakeStream: StreamControlling {
    var onFrame: ((CGImage) -> Void)?
    var onState: ((SessionState) -> Void)?
    var started = false
    func start() { started = true }
    func stop() { started = false }
    func reconnectNow() {}
}

final class FakeKeeper: KeeperControlling {
    var running = false
    func start(interval: Duration) { running = true }
    func stop() { running = false }
    func reconnect() {}
}

@MainActor
final class AppModelTests: XCTestCase {
    private let console = RegisteredConsole(host: "192.168.1.253", name: "PS5", registKey: Data(repeating: 0x31, count: 16), morning: Data(repeating: 2, count: 16))

    func testFreshInstallStartsAtWelcome() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        XCTAssertEqual(model.step, .welcome)
    }

    func testCompleteSetupOpensMainScreen() {
        let store = MemoryStore()
        store.save(Data(repeating: 1, count: 8), for: StoreKey.accountId)
        store.save(console, for: StoreKey.console)
        store.save(LGTV(name: "LG TV", host: "192.168.1.153"), for: StoreKey.tv)
        store.save("tv-key", for: StoreKey.tvKey)
        XCTAssertEqual(AppModel(services: FakeServices(), store: store, defaults: .isolated()).step, .done)
    }

    func testPsnStepNeedsAccountId() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.step = .psnLogin
        XCTAssertFalse(model.canAdvance)
        model.accountId = Data(repeating: 1, count: 8)
        XCTAssertTrue(model.canAdvance)
    }

    func testConsoleStepNeedsRegistration() async throws {
        let services = FakeServices()
        let model = AppModel(services: services, store: MemoryStore(), defaults: .isolated())
        model.accountId = Data(repeating: 1, count: 8)
        model.step = .console
        XCTAssertFalse(model.canAdvance)
        try await model.register(host: "192.168.1.253", pin: "12345678")
        XCTAssertTrue(model.canAdvance)
        XCTAssertEqual(services.registered?.host, "192.168.1.253")
    }

    /// PS5 hesabı tanımazsa kullanıcıya kodu hangi kullanıcıdan alacağı söylenmeli.
    func testWrongAccountRegistrationExplainsWhatToDo() async {
        let error = await registrationError(Registration.RegistrationError(.wrongAccount, reason: 0x80108b02))
        XCTAssertEqual((error as? DetailedError)?.error, .wrongAccount)
    }

    func testOtherRegistrationFailureSuggestsNewCode() async {
        let error = await registrationError(Registration.RegistrationError(.failed))
        XCTAssertEqual((error as? DetailedError)?.error, .registrationFailed)
    }

    /// Her eşleştirme sonucu kendi iletisini alır; hiçbiri sessiz kalmaz ve genel "kodu kabul etmedi"ye düşmez.
    func testEveryRegistrationFailureHasItsOwnMessage() async {
        let cases: [(Registration.RegistrationError.Kind, AppError)] = [
            (.wrongCode, .wrongCode), (.noAnswer, .consoleNoAnswer), (.noReply, .consoleNoReply), (.canceled, .consoleNoReply),
            (.inUse, .consoleInUse), (.consoleCrashed, .consoleCrashed), (.versionMismatch, .consoleVersion),
            (.badAddress, .badAddress), (.localNetworkBlocked, .localNetworkBlocked),
        ]
        for (kind, expected) in cases {
            let error = await registrationError(Registration.RegistrationError(kind))
            XCTAssertEqual((error as? DetailedError)?.error, expected, "\(kind)")
            XCTAssertFalse(error?.localizedDescription.isEmpty ?? true)
        }
    }

    /// İletide PS5'in kodu ve gönderilecek günlük dosyası yazar.
    func testRegistrationErrorShowsThePs5CodeAndLogFile() async {
        let error = await registrationError(Registration.RegistrationError(.wrongCode, reason: 0x80108b09,
                                                                            detail: "0x80108b09 (Regist failed, probably invalid PIN)"))
        let text = error?.localizedDescription ?? ""
        XCTAssertTrue(text.contains("0x80108b09"))
        XCTAssertTrue(text.contains(RemotePlayLog.displayPath))
    }

    /// libchiaki dışı bir hata da (ör. kayıt başlatılamadı) iletiye dönüşür.
    func testUnexpectedRegistrationErrorIsStillExplained() async {
        struct Boom: Error {}
        let error = await registrationError(Boom())
        XCTAssertEqual((error as? DetailedError)?.error, .registrationFailed)
    }

    func testPinMustBeEightDigits() async {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.accountId = Data(repeating: 1, count: 8)
        for pin in ["1234", "", "123456789", "1234567a"] {
            do {
                try await model.register(host: "192.168.1.253", pin: pin)
                XCTFail("Geçersiz kod kabul edilmemeli: \(pin)")
            } catch {
                XCTAssertEqual(error as? AppError, .invalidPin)
                XCTAssertNil(model.console)
            }
        }
    }

    /// PS5'in ekranındaki gibi boşluklu ya da tireli yazılan kod da kabul edilir.
    func testPinWithSpacesIsAccepted() async throws {
        let services = FakeServices()
        let model = AppModel(services: services, store: MemoryStore(), defaults: .isolated())
        model.accountId = Data(repeating: 1, count: 8)
        try await model.register(host: " 192.168.1.253 ", pin: " 1234 5678 ")
        XCTAssertEqual(services.registered?.host, "192.168.1.253")
        XCTAssertEqual(services.registeredPin, 12345678)
    }

    /// PSN girişinin her hatası kendi iletisini alır (eskiden ham Swift hatası ya da "Giriş tamamlanmadı" idi);
    /// Sony'nin hatası ve HTTP kodu iletide yazar, hesap kaydedilmez.
    func testEveryLoginFailureHasItsOwnMessage() async {
        let cases: [(PSNAccount.PSNError, AppError, String?)] = [
            (.refused(status: 400, detail: "invalid_grant: Invalid authorization code"), .loginRefused, "HTTP 400, invalid_grant"),
            (.rateLimited(status: 429, detail: nil), .loginRateLimited, "HTTP 429"),
            (.http(503, detail: nil), .loginServer, "HTTP 503"),
            (.network("The Internet connection appears to be offline."), .loginNetwork, "offline"),
            (.badResponse, .loginBadResponse, nil),
            (.noCode, .invalidLogin, nil),
        ]
        for (thrown, expected, detail) in cases {
            let services = FakeServices()
            services.loginError = thrown
            let model = AppModel(services: services, store: MemoryStore(), defaults: .isolated())
            do {
                try await model.completePSNLogin(redirect: URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?code=x")!)
                XCTFail("Giriş başarısız olmalı: \(thrown)")
            } catch {
                XCTAssertEqual((error as? DetailedError)?.error, expected, "\(thrown)")
                if let detail { XCTAssertTrue(error.localizedDescription.contains(detail), error.localizedDescription) }
                XCTAssertTrue(error.localizedDescription.contains(RemotePlayLog.displayPath))
                XCTAssertNil(model.accountId)
            }
        }
    }

    /// Giriş penceresi yönlendirmesiz kapanırsa sessiz kalınmaz; sayfanın sorunu varsa o söylenir.
    func testClosedLoginWindowIsExplained() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        XCTAssertEqual(model.loginWindowError(problem: nil) as? AppError, .loginWindowClosed)
        XCTAssertEqual((model.loginWindowError(problem: "HTTP 429") as? DetailedError)?.error, .loginRateLimited)
        let failed = model.loginWindowError(problem: "The Internet connection appears to be offline.")
        XCTAssertEqual((failed as? DetailedError)?.error, .loginPageFailed)
        XCTAssertTrue(failed.localizedDescription.contains("offline"))
    }

    /// PS5 seçilmeden ya da adres yazılmadan bağlanılırsa "PS5 bulunamadı" denir.
    func testMissingConsoleIsExplained() async {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.accountId = Data(repeating: 1, count: 8)
        do {
            try await model.register(host: "  ", pin: "12345678")
            XCTFail("Adressiz kayıt başlamamalı")
        } catch {
            XCTAssertEqual(error as? AppError, .missingConsole)
        }
    }

    private func registrationError(_ thrown: Error) async -> Error? {
        let services = FakeServices()
        services.registerError = thrown
        let model = AppModel(services: services, store: MemoryStore(), defaults: .isolated())
        model.accountId = Data(repeating: 1, count: 8)
        do {
            try await model.register(host: "192.168.1.253", pin: "12345678")
            XCTFail("Kayıt başarısız olmalı")
            return nil
        } catch {
            XCTAssertNil(model.console)
            return error
        }
    }

    func testPairingTvPassesServerAddressAndStoresKey() async throws {
        let services = FakeServices()
        let store = MemoryStore()
        let model = AppModel(services: services, store: store, defaults: .isolated())
        try await model.pair(LGTV(name: "LG TV", host: "192.168.1.153"))
        XCTAssertTrue(services.launchedServer?.hasPrefix("http://") == true)
        XCTAssertTrue(services.launchedServer?.hasSuffix(":\(model.serverPort)") == true)
        XCTAssertEqual(store.load(String.self, for: StoreKey.tvKey), "tv-key")
    }

    func testOnboardingWalksAllStepsInOrder() async throws {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        XCTAssertEqual(model.step, .welcome); model.advance()
        XCTAssertEqual(model.step, .secondAccount); model.advance()
        XCTAssertEqual(model.step, .psnLogin)
        try await model.completePSNLogin(redirect: URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?code=x")!)
        model.advance()
        XCTAssertEqual(model.step, .console)
        try await model.register(host: "192.168.1.253", pin: "12345678"); model.advance()
        XCTAssertEqual(model.step, .tv)
        try await model.pair(LGTV(name: "LG TV", host: "192.168.1.153")); model.advance()
        XCTAssertEqual(model.step, .test); model.advance()
        XCTAssertEqual(model.step, .betterTranslation)
        XCTAssertTrue(model.canAdvance)
        model.advance()
        XCTAssertEqual(model.step, .done)
    }

    /// "Daha iyi çeviri" adımı isteğe bağlıdır: geçilirse ücretsiz çeviri kalır; anahtar kabul edilirse Gemini seçilir.
    func testBetterTranslationStepCanBeSkipped() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.step = .betterTranslation
        XCTAssertFalse(model.usesFreeGemini)
        XCTAssertTrue(model.canAdvance)
        model.advance()
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.settings.translationEngine, .free)
        model.back()
        XCTAssertEqual(model.step, .betterTranslation)
        model.back()
        XCTAssertEqual(model.step, .test)
    }

    func testBetterTranslationStepSavesTheKeyAndSelectsGemini() async {
        let services = FakeServices()
        let store = MemoryStore()
        let model = AppModel(services: services, store: store, defaults: .isolated())
        model.step = .betterTranslation
        let result = await model.setAIKey("  AIza-free  ", for: .gemini)
        XCTAssertEqual(result, .success("KRATOS: Gidiyoruz."))
        XCTAssertEqual(services.aiTests.first?.provider, .gemini)
        XCTAssertEqual(services.aiTests.first?.key, "AIza-free")
        // Ücretsiz katmandaki varsayılan model denenir.
        XCTAssertEqual(services.aiTests.first?.model, AIProvider.gemini.defaultModel.id)
        XCTAssertTrue(AIProvider.gemini.defaultModel.freeTier)
        XCTAssertEqual(store.load(String.self, for: StoreKey.geminiKey), "AIza-free")
        XCTAssertEqual(model.settings.translationEngine, .gemini)
        XCTAssertTrue(model.usesFreeGemini)
        model.advance()
        XCTAssertEqual(model.step, .done)
    }

    /// Yanlış anahtar kaydedilmez, motor değişmez; dakikalık sınıra takılan anahtar geçerlidir ve kaydedilir.
    func testBetterTranslationStepRejectsAWrongKey() async {
        let services = FakeServices()
        services.aiResult = .failure(.invalidKey)
        let model = AppModel(services: services, store: MemoryStore(), defaults: .isolated())
        model.step = .betterTranslation
        let result = await model.setAIKey("wrong", for: .gemini)
        XCTAssertEqual(result, .failure(.invalidKey))
        XCTAssertFalse(model.hasKey(.gemini))
        XCTAssertEqual(model.settings.translationEngine, .free)
        XCTAssertFalse(model.usesFreeGemini)

        services.aiResult = .failure(.quotaExceeded)
        _ = await model.setAIKey("AIza-busy", for: .gemini)
        XCTAssertTrue(model.usesFreeGemini)
    }

    /// Ayarlardaki "Ücretsiz anahtar al" Gemini'yi seçer; anahtar gelene dek ücretsiz çeviri sürer.
    func testChooseFreeGeminiSelectsGeminiWithoutAKey() {
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.chooseFreeGemini()
        XCTAssertEqual(model.settings.translationEngine, .gemini)
        XCTAssertFalse(model.onlineTranslationActive)
        XCTAssertFalse(model.usesFreeGemini)
    }

    /// Yeni metinler ortak metin dosyasında Türkçesiyle durur (Windows da aynı dosyayı okur).
    func testFreeGeminiStringsAreTranslated() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CouchSubs/Resources/Localizable.xcstrings")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let strings = root?["strings"] as? [String: Any] ?? [:]
        for key in ["Better translation (free)", "Get a free key", "Skip for now", "For better translation, get a free Gemini key.",
                    "Gemini is ready. Subtitles will be translated with Gemini.",
                    "Press Get a free key and sign in with your Google account.", "Press Create API key and copy the key.",
                    "Paste the key here and press Save and test.",
                    "The free translation works without the internet but often sounds stiff. Google's Gemini translates much more naturally, and a free Google key is enough.",
                    "Subtitle text is sent to Google. With a free key, Google may use it to improve its products, and people at Google may read it. Only the game's subtitles are sent.",
                    "The free key has a per-minute limit. When it is reached, that line is translated by the free translation."] {
            let entry = strings[key] as? [String: Any]
            let tr = ((entry?["localizations"] as? [String: Any])?["tr"] as? [String: Any])?["stringUnit"] as? [String: Any]
            XCTAssertNotNil(tr?["value"] as? String, key)
        }
    }
}

@MainActor
final class AppModelRunTests: XCTestCase {
    private func readyModel(_ services: FakeServices) -> AppModel {
        let store = MemoryStore()
        store.save(Data(repeating: 1, count: 8), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.253", name: "PS5", registKey: Data(repeating: 0x31, count: 16), morning: Data(repeating: 2, count: 16)), for: StoreKey.console)
        store.save(LGTV(name: "LG TV", host: "127.0.0.1"), for: StoreKey.tv)
        store.save("tv-key", for: StoreKey.tvKey)
        return AppModel(services: services, store: store, defaults: .isolated())
    }

    func testDoubleStartCreatesOneSession() async {
        let services = FakeServices()
        let model = readyModel(services)
        async let first: Void = model.start()
        async let second: Void = model.start()
        _ = await (first, second)
        XCTAssertEqual(services.streams.count, 1)
        XCTAssertEqual(services.keepers.count, 1)
        XCTAssertTrue(model.isRunning)
        model.stop()
    }

    func testRunningPreventsIdleSleep() async {
        let model = readyModel(FakeServices())
        await model.start()
        XCTAssertTrue(model.isPreventingSleep)
        model.stop()
        XCTAssertFalse(model.isPreventingSleep)
    }

    func testDisconnectClearsSubtitleOnTV() async throws {
        let services = FakeServices()
        let model = readyModel(services)
        await model.start()
        defer { model.stop() }
        let (bytes, _) = try await URLSession.shared.bytes(from: URL(string: "http://127.0.0.1:\(model.serverPort)/events")!)
        try await Task.sleep(nanoseconds: 200_000_000)
        services.streams[0].onState?(.disconnected(.network))
        var sawClear = false
        for try await line in bytes.lines where line == "event: clear" { sawClear = true; break }
        XCTAssertTrue(sawClear)
    }

    func testTranslatorStatusFollowsPipeline() {
        XCTAssertEqual(AppModel.translatorStatus(after: nil), .ready)
        XCTAssertEqual(AppModel.translatorStatus(after: .needsDownload), .needsDownload)
        XCTAssertEqual(AppModel.translatorStatus(after: .unsupported), .unsupported)
    }

    func testSettingsGoToPreferencesNotKeychain() {
        let store = MemoryStore()
        let defaults = UserDefaults(suiteName: "couchsubs-test-\(UUID())")!
        let model = AppModel(services: FakeServices(), store: store, defaults: defaults)
        model.settings.style.fontSize = 58
        XCTAssertNil(store.values[StoreKey.settings])
        XCTAssertEqual(AppModel(services: FakeServices(), store: store, defaults: defaults).settings.style.fontSize, 58)
    }

    func testChangingLanguageWhileRunningRebuildsPipeline() async {
        let model = readyModel(FakeServices())
        await model.start()
        defer { model.stop() }
        XCTAssertEqual(model.activeLanguages?.source, "en")
        model.settings.sourceLanguage = "ja"
        XCTAssertEqual(model.activeLanguages?.source, "ja")
    }

    /// Çeviri başlamamışken bağlı olmamak bir uyarı değildir; nokta gri kalır.
    func testStatusToneIsIdleUntilTranslationStarts() {
        XCTAssertEqual(AppModel.ps5Tone(.disconnected(.stopped), running: false), .idle)
        XCTAssertEqual(AppModel.ps5Tone(.disconnected(.network), running: true), .warning)
        XCTAssertEqual(AppModel.ps5Tone(.connecting, running: true), .warning)
        XCTAssertEqual(AppModel.ps5Tone(.streaming, running: true), .good)
        XCTAssertEqual(AppModel.tvTone(clients: 0, running: false), .idle)
        XCTAssertEqual(AppModel.tvTone(clients: 0, running: true), .warning)
        XCTAssertEqual(AppModel.tvTone(clients: 1, running: false), .good)
    }

    func testLoginPasscodeIsExplained() {
        XCTAssertEqual(AppModel.statusText(.disconnected(.loginPasscode), running: true),
                       String(localized: "The second user has a login passcode on the PS5. Turn it off in Settings › Users and Accounts."))
    }

    func testDisconnectReasonsAreExplained() {
        XCTAssertEqual(AppModel.statusText(.disconnected(.consoleAsleep), running: true), String(localized: "Turn on your PS5"))
        XCTAssertEqual(AppModel.statusText(.disconnected(.inUse), running: true), String(localized: "Remote Play is in use on another device"))
        XCTAssertEqual(AppModel.statusText(.disconnected(.refused), running: true), String(localized: "The PS5 refused the connection. Set up the PS5 again."))
        XCTAssertEqual(AppModel.statusText(.disconnected(.network), running: true), String(localized: "Reconnecting…"))
        XCTAssertEqual(AppModel.statusText(.disconnected(.stopped), running: false), String(localized: "Not connected"))
    }
}

final class LocalizationTests: XCTestCase {
    private func strings(_ language: String) throws -> [String: String] {
        let bundle = Bundle(for: AppModel.self)
        let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language), language)
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testTurkishCoversEveryEnglishKey() throws {
        let english = try strings("en"), turkish = try strings("tr")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys).subtracting(turkish.keys), [])
        XCTAssertTrue(turkish.values.allSatisfy { !$0.isEmpty })
    }
}

@MainActor
final class TVAppInstallTests: XCTestCase {
    private let tv = LGTV(name: "LG TV", host: "192.168.1.153")

    private func model(_ services: FakeServices, store: MemoryStore = MemoryStore()) -> AppModel {
        AppModel(services: services, store: store, defaults: .isolated())
    }

    func testMissingAppWithDevModeOffShowsTheSteps() async throws {
        let services = FakeServices()
        services.appOnTV = nil
        let model = model(services)
        try await model.pair(tv)
        XCTAssertEqual(model.tvApp, .devModeOff)
        XCTAssertNotNil(model.tv, "Eşleşme uygulama olmadan da kaydedilir")
    }

    func testTurningDevModeOnAsksForThePassphrase() async throws {
        let services = FakeServices()
        services.appOnTV = nil
        let model = model(services)
        try await model.pair(tv)
        services.devMode = true
        await model.refreshTVApp()
        XCTAssertEqual(model.tvApp, .needsPassphrase(error: nil))
    }

    func testPassphraseInstallsAndOpensTheApp() async throws {
        let services = FakeServices()
        services.appOnTV = nil
        services.devMode = true
        let store = MemoryStore()
        let model = model(services, store: store)
        try await model.pair(tv)
        let pairs = services.pairCount
        await model.installTVApp(passphrase: " ABC123 ")
        XCTAssertEqual(model.tvApp, .upToDate("0.6.1"))
        XCTAssertEqual(services.installs, 1)
        XCTAssertEqual(store.load(String.self, for: StoreKey.tvDevKey), "dev-key")
        XCTAssertEqual(services.pairCount, pairs + 1, "Kurulumdan sonra TV uygulaması açılır")
    }

    func testWrongPassphraseAsksAgain() async throws {
        let services = FakeServices()
        services.appOnTV = nil
        services.devMode = true
        let model = model(services)
        try await model.pair(tv)
        await model.installTVApp(passphrase: "WRONG")
        XCTAssertEqual(model.tvApp, .needsPassphrase(error: .wrongPassphrase))
        XCTAssertEqual(services.installs, 0)
    }

    func testClosedKeyServerIsExplained() async throws {
        let services = FakeServices()
        services.appOnTV = nil
        services.devMode = true
        services.keyServer = false
        let model = model(services)
        try await model.pair(tv)
        await model.installTVApp(passphrase: "ABC123")
        XCTAssertEqual(model.tvApp, .needsPassphrase(error: .keyServerOff))
    }

    func testFailedInstallShowsTheTVsReason() async throws {
        let services = FakeServices()
        services.appOnTV = nil
        services.devMode = true
        services.lgInstallError = DevModeFailure(.installFailed, detail: "Invalid package (errorCode -5)")
        let model = model(services)
        try await model.pair(tv)
        await model.installTVApp(passphrase: "ABC123")
        XCTAssertEqual(model.tvApp, .failed(.installFailed, reason: "Invalid package (errorCode -5)"))
        // Boş alan yalnız TV öyle dediğinde suçlanır.
        XCTAssertFalse(TVAppCard.message(for: .installFailed, brand: .lg, reason: "Invalid package").contains("free space"))
        XCTAssertTrue(TVAppCard.message(for: .installFailed, brand: .lg, reason: "Invalid package").hasSuffix("Invalid package"))
    }

    func testOlderAppIsUpdatedWithoutAsking() async throws {
        let services = FakeServices()
        services.appOnTV = "0.4.0"
        services.devMode = true
        let store = MemoryStore()
        store.save("dev-key", for: StoreKey.tvDevKey)
        let model = model(services, store: store)
        try await model.pair(tv)
        XCTAssertEqual(model.tvApp, .upToDate("0.6.1"))
        XCTAssertEqual(services.installs, 1)
    }

    func testCurrentAppIsNotReinstalled() async throws {
        let services = FakeServices()
        services.devMode = true
        let store = MemoryStore()
        store.save("dev-key", for: StoreKey.tvDevKey)
        let model = model(services, store: store)
        try await model.pair(tv)
        XCTAssertEqual(model.tvApp, .upToDate("0.6.1"))
        XCTAssertEqual(services.installs, 0)
    }

    func testRefusedKeyIsForgottenAndPassphraseAskedAgain() async throws {
        let services = FakeServices()
        services.devMode = true
        services.refuseKey = true
        let store = MemoryStore()
        store.save("old-key", for: StoreKey.tvDevKey)
        let model = model(services, store: store)
        try await model.pair(tv)
        XCTAssertEqual(model.tvApp, .needsPassphrase(error: nil))
        XCTAssertNil(store.load(String.self, for: StoreKey.tvDevKey))
    }

    func testWorkingAppWithoutKeyAsksNothing() async throws {
        let services = FakeServices()
        services.devMode = true
        let model = model(services)
        try await model.pair(tv)
        XCTAssertEqual(model.tvApp, .unknown)
    }

    func testOtherBrandsAreNotInstalledThroughLGDeveloperMode() async throws {
        let services = FakeServices()
        services.appOnTV = nil
        services.devMode = true
        let model = model(services)
        try await model.pair(LGTV(name: "Samsung", host: "192.168.1.20", brand: .samsung))
        XCTAssertEqual(model.tvApp, .unknown)
        XCTAssertEqual(services.installs, 0)
    }

    func testLGDeveloperModeIsExtendedOncePerDay() async throws {
        let services = FakeServices()
        services.devMode = true
        let store = MemoryStore()
        store.save("dev-key", for: StoreKey.tvDevKey)
        let model = model(services, store: store)
        try await model.pair(tv)
        XCTAssertEqual(model.devModeHoursLeft, 999)
        await model.refreshTVApp()
        XCTAssertEqual(services.renewals, 1, "Aynı gün ikinci kez uzatılmaz")
    }

    private let samsung = LGTV(name: "Samsung", host: "192.168.1.20", brand: .samsung)
    private let app = BundledTVApp(url: URL(fileURLWithPath: "/tmp/couchsubs-samsung_0.7.0.wgt"), version: "0.7.0")

    func testSamsungWithDevModeOffShowsTheSteps() async {
        let services = FakeServices()
        services.bundled[.samsung] = app
        let model = model(services)
        model.tv = samsung
        await model.refreshTVApp()
        XCTAssertEqual(model.tvApp, .devModeOff)
        XCTAssertTrue(model.canInstallTVApp)
    }

    func testSamsungInstallOpensSignInAndRemembersTheVersion() async {
        let services = FakeServices()
        services.bundled[.samsung] = app
        services.samsungDevMode = true
        let page = URL(string: "https://account.samsung.com/signin")!
        services.events = [.signIn(page)]
        let store = MemoryStore()
        let model = model(services, store: store)
        model.openInBrowser = { _ in }
        model.tv = samsung
        await model.refreshTVApp()
        // Olaylar ana iş parçacığına bir sonraki turda gelir.
        await Task.yield()
        XCTAssertEqual(model.tvApp, .upToDate("0.7.0"))
        XCTAssertEqual(store.load(String.self, for: StoreKey.tvAppVersion), "0.7.0")
        XCTAssertEqual(services.brandInstalls.map { $0.host }, ["192.168.1.20"])

        await model.refreshTVApp()
        XCTAssertEqual(services.brandInstalls.count, 1, "Kurulu sürüm yeniden kurulmaz")
    }

    func testSamsungFailureIsShown() async {
        let services = FakeServices()
        services.bundled[.samsung] = app
        services.samsungDevMode = true
        services.installError = .signInFailed
        let model = model(services)
        model.tv = samsung
        await model.refreshTVApp()
        XCTAssertEqual(model.tvApp, .failed(.signInFailed))
    }

    func testAndroidTVIsFoundOnTheNetworkAndRemembered() async {
        let services = FakeServices()
        services.bundled[.androidTV] = BundledTVApp(url: URL(fileURLWithPath: "/tmp/couchsubs-androidtv_0.7.0.apk"), version: "0.7.0")
        let store = MemoryStore()
        let model = model(services, store: store)
        model.tv = LGTV(name: "Android TV", host: "", brand: .androidTV)
        await model.refreshTVApp()
        XCTAssertEqual(model.tvApp, .devModeOff, "Hata ayıklama açılana kadar adımlar görünür")

        services.androidHosts = ["192.168.1.40"]
        await model.refreshTVApp()
        XCTAssertEqual(model.tvApp, .upToDate("0.7.0"))
        XCTAssertEqual(model.tv?.host, "192.168.1.40")
        XCTAssertEqual(store.load(LGTV.self, for: StoreKey.tv)?.host, "192.168.1.40")
    }

    func testInstalledAndroidAppNeedsNothingWhenDebuggingIsOff() async {
        let services = FakeServices()
        services.bundled[.androidTV] = BundledTVApp(url: URL(fileURLWithPath: "/tmp/a_0.7.0.apk"), version: "0.7.0")
        let store = MemoryStore()
        store.save("0.7.0", for: StoreKey.tvAppVersion)
        let model = model(services, store: store)
        model.tv = LGTV(name: "Android TV", host: "192.168.1.40", brand: .androidTV)
        await model.refreshTVApp()
        XCTAssertEqual(model.tvApp, .upToDate("0.7.0"))
        XCTAssertTrue(services.brandInstalls.isEmpty)
    }

    func testBundledFileNameCarriesTheVersion() {
        XCTAssertEqual(BundledTVApp.version(ofFile: "couchsubs-androidtv_0.7.0.apk"), "0.7.0")
        XCTAssertNil(BundledTVApp.version(ofFile: "couchsubs.apk"))
    }

    func testMovedTVIsSaved() {
        let store = MemoryStore()
        let model = model(FakeServices(), store: store)
        let moved = LGTV(name: "LG TV", host: "192.168.1.230")
        model.tvMoved(to: moved)
        XCTAssertEqual(model.tv, moved)
        XCTAssertEqual(store.load(LGTV.self, for: StoreKey.tv), moved)
    }
}
