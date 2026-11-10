// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import XCTest
@testable import CouchSubs

/// Her isteği 429 ile geri çeviren sahte hizmet; gerçek hizmete gidilmez.
private final class QuotaAI: URLProtocol {
    nonisolated(unsafe) static var count = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.count += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":{"message":"quota"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuotaAI.self]
        return URLSession(configuration: configuration)
    }
}

private final class FakeLocal: TextTranslator {
    func translate(_ text: String) async throws -> String { "yerel: " + text }
}

/// İstek ve yanıtın ayrıntısı CouchSubsCore'daki AITranslationTests'te; burada uygulamaya bağlanışı sınanır.
final class AITranslatorTests: XCTestCase {
    func testQuotaFallsBackToAppleTranslationAndReportsIt() async throws {
        QuotaAI.count = 0
        let translator = AITranslator(provider: .claude, key: "k", model: nil, fallback: FakeLocal(), session: QuotaAI.session())
        var reported: [OnlineKeyState?] = []
        translator.onFailureChanged = { reported.append($0) }
        let first = try await translator.translate("Run!")
        let second = try await translator.translate("Hide!")
        XCTAssertEqual(first, "yerel: Run!")
        XCTAssertEqual(second, "yerel: Hide!")
        XCTAssertEqual(QuotaAI.count, 1)
        XCTAssertEqual(reported, [.quotaExceeded])
    }

    /// Eski sürümlerin ayarı (yalnız DeepL açık/kapalı) DeepL olarak açılır; yeni alanlar varsayılanla gelir.
    func testOldSettingsOpenWithDeepL() throws {
        let old = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"onlineTranslation":true}"#.utf8))
        XCTAssertEqual(old.translationEngine, .deepL)
        XCTAssertEqual(AIProvider.gemini.model(old.model(for: .gemini)), "gemini-3.5-flash-lite")

        var settings = UserSettings()
        XCTAssertEqual(settings.translationEngine, .free)
        settings.translationEngine = .claude
        settings.setModel("claude-sonnet-5-5", for: .claude)
        settings.setModel(AIProvider.openAI.defaultModel, for: .openAI)
        let again = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(again.translationEngine, .claude)
        XCTAssertEqual(again.claudeModel, "claude-sonnet-5-5")
        XCTAssertEqual(again.openAIModel, "")
        settings.translationEngine = .free
        XCTAssertEqual(settings.onlineEngine, .claude)
    }
}
