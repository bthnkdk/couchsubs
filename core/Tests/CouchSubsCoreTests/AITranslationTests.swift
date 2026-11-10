// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Yapay zekâ hizmetlerinin yerine geçen sahte sunucu: istekleri saklar, cümleleri "[tr] cümle" diye çevirir.
/// Gerçek hizmetlere hiç gidilmez.
private final class FakeAI: URLProtocol {
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: [String: Any])] = []
    /// Verilirse bu durum koduyla ve gövdeyle yanıt verir.
    nonisolated(unsafe) static var failure: (status: Int, body: String)?
    /// Verilirse yanıt gelmez, istek zaman aşımına düşer.
    nonisolated(unsafe) static var timeout = false
    /// Verilirse hizmetin döndüğü metin bu olur.
    nonisolated(unsafe) static var replyText: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
        }
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        Self.requests.append((request, body))
        if Self.timeout {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let status = Self.failure?.status ?? 200
        let reply: Data
        if let failure = Self.failure {
            reply = Data(failure.body.utf8)
        } else {
            let text = Self.replyText ?? Self.echo(Self.userText(body, url: request.url!))
            reply = try! JSONSerialization.data(withJSONObject: Self.wrap(text, url: request.url!))
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func userText(_ body: [String: Any], url: URL) -> String {
        if url.host == "generativelanguage.googleapis.com" {
            let content = (body["contents"] as? [[String: Any]])?.first
            return ((content?["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        }
        let messages = body["messages"] as? [[String: Any]] ?? []
        return messages.last?["content"] as? String ?? ""
    }

    /// İletinin son satırındaki JSON dizisini "[tr] …" diye çevirir.
    static func echo(_ user: String) -> String {
        let list = user.split(separator: "\n").last.map(String.init) ?? "[]"
        let sentences = (try? JSONSerialization.jsonObject(with: Data(list.utf8)) as? [String]) ?? []
        let data = try! JSONSerialization.data(withJSONObject: sentences.map { "[tr] " + $0 })
        return String(data: data, encoding: .utf8)!
    }

    /// Hizmetin kendi yanıt biçimi.
    static func wrap(_ text: String, url: URL) -> [String: Any] {
        switch url.host {
        case "generativelanguage.googleapis.com":
            ["candidates": [["content": ["role": "model", "parts": [["text": "thinking…", "thought": true], ["text": text]]]]]]
        case "api.openai.com":
            ["choices": [["index": 0, "message": ["role": "assistant", "content": text], "finish_reason": "stop"]]]
        default:
            ["content": [["type": "thinking", "thinking": "…"], ["type": "text", "text": text]], "stop_reason": "end_turn"]
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeAI.self]
        return URLSession(configuration: configuration)
    }
}

/// Windows'taki AiTranslatorTests ile aynı durumlar.
final class AITranslationTests: XCTestCase {
    private let secret = "sk-SECRET-123"

    override func setUp() {
        FakeAI.requests = []
        FakeAI.failure = nil
        FakeAI.timeout = false
        FakeAI.replyText = nil
    }

    private func make(_ provider: AIProvider, cache: TranslationCache = TranslationCache(), model: String? = nil) -> AITranslationCore {
        AITranslationCore(provider: provider, key: "  \(secret) ", model: model, session: FakeAI.session(), cache: cache)
    }

    private func local(_ text: String) async throws -> String { "yerel: " + text }

    private func user(_ index: Int) -> String { FakeAI.userText(FakeAI.requests[index].body, url: FakeAI.requests[index].request.url!) }

    // MARK: - İstek

    func testGeminiRequest() async throws {
        let translator = make(.gemini)
        let result = try await translator.translate("KRATOS: We go now.", fallback: local)
        XCTAssertEqual(result, "KRATOS: [tr] We go now.")
        let (request, body) = FakeAI.requests[0]
        XCTAssertEqual(request.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), secret)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let system = ((body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String
        XCTAssertEqual(system, AIRequest.systemPrompt)
        XCTAssertEqual((body["generationConfig"] as? [String: Any])?["maxOutputTokens"] as? Int, AIRequest.maxOutputTokens)
        // Flash-Lite zaten en az düşünmeyle çalışır; düşünme ayarı gönderilmez.
        XCTAssertNil((body["generationConfig"] as? [String: Any])?["thinkingConfig"])
        // Konuşmacı etiketi gönderilmez; yalnız cümle gider.
        XCTAssertTrue(user(0).hasSuffix("[\"We go now.\"]"))
        XCTAssertFalse(user(0).contains("KRATOS"))
    }

    func testOpenAIRequest() async throws {
        _ = try await make(.openAI).translate("Run!", fallback: local)
        let (request, body) = FakeAI.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(secret)")
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertEqual(body["max_completion_tokens"] as? Int, AIRequest.maxOutputTokens)
        let messages = body["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["developer", "user"])
        XCTAssertEqual(messages[0]["content"] as? String, AIRequest.systemPrompt)
    }

    func testClaudeRequest() async throws {
        _ = try await make(.claude).translate("Run!", fallback: local)
        let (request, body) = FakeAI.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), secret)
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(body["max_tokens"] as? Int, AIRequest.maxOutputTokens)
        XCTAssertEqual(body["system"] as? String, AIRequest.systemPrompt)
        XCTAssertNil(body["temperature"])
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
    }

    /// Effort ve düşünme ayarı listedeki modelden gelir, adından tahmin edilmez.
    func testPerModelParametersAreSent() async throws {
        _ = try await make(.openAI, model: "gpt-6.1-terra").translate("Run!", fallback: local)
        XCTAssertEqual(FakeAI.requests[0].body["model"] as? String, "gpt-6.1-terra")
        XCTAssertEqual(FakeAI.requests[0].body["reasoning_effort"] as? String, "none")

        _ = try await make(.claude, model: "claude-sonnet-5-5").translate("Run!", fallback: local)
        XCTAssertEqual(FakeAI.requests[1].body["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual((FakeAI.requests[1].body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual((FakeAI.requests[1].body["thinking"] as? [String: Any])?["type"] as? String, "between_tools")

        _ = try await make(.gemini, model: "gemini-3.6-flash").translate("Run!", fallback: local)
        XCTAssertTrue(FakeAI.requests[2].request.url!.absoluteString.contains("/models/gemini-3.6-flash:generateContent"))
        let config = FakeAI.requests[2].body["generationConfig"] as? [String: Any]
        XCTAssertEqual((config?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "LOW")
    }

    /// Listede olmayan kayıtlı model (eski ayar, elle yazılmış ad, listeden çıkarılan model) varsayılana döner.
    func testUnknownModelFallsBackToDefault() async throws {
        _ = try await make(.openAI, model: "gpt-4o").translate("Run!", fallback: local)
        XCTAssertEqual(FakeAI.requests[0].body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(AIProvider.gemini.model("").id, "gemini-3.5-flash-lite")
        XCTAssertEqual(AIProvider.claude.model(nil).id, "claude-haiku-5-5")
        XCTAssertEqual(AIProvider.gemini.engineID(model: "gemini-3.5-flash-lite"), "gemini:gemini-3.5-flash-lite")
        XCTAssertEqual(AIProvider.openAI.engineID(model: AIProvider.openAI.defaultModel.id), "openai:gpt-6-luna")
    }

    /// Liste Windows ile ortak dosyadan okunur; her hizmette önerilen hızlı model ilk sıradadır.
    func testCatalogIsTheSharedFile() throws {
        for provider in AIProvider.allCases {
            XCTAssertGreaterThanOrEqual(provider.models.count, 2, provider.rawValue)
            XCTAssertEqual(provider.defaultModel.label, "Fast and cheap (recommended)")
            XCTAssertEqual(Set(provider.models.map(\.id)).count, provider.models.count)
        }
        XCTAssertEqual(AIProvider.gemini.defaultModel, AIModel(id: "gemini-3.5-flash-lite", label: "Fast and cheap (recommended)"))
        XCTAssertEqual(AIProvider.claude.defaultModel.thinking, "disabled")
        // Depodaki dosya, uygulamaya giden kopyayla aynıdır; Windows da bu dosyayı gömer.
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CouchSubsCore/Resources/ai-models.json")
        let parsed = AIModel.parse(try Data(contentsOf: file))
        XCTAssertEqual(parsed, AIModel.catalog)
        XCTAssertEqual(Set(parsed.keys), Set(AIProvider.allCases.map(\.rawValue)))
    }

    /// Son gösterilen 3 satır ve çevirileri bağlam olarak gider; satırın kendisi ve tekrar okunan satır girmez.
    func testContextIsTheLastThreeShownLinesWithTranslations() async throws {
        let translator = make(.claude)
        for line in ["One.", "Two.", "Two.", "Three.", "Four.", "Five."] { _ = try await translator.translate(line, fallback: local) }
        XCTAssertEqual(FakeAI.requests.count, 5)
        XCTAssertFalse(user(0).contains("Previous subtitles"))
        XCTAssertTrue(user(1).contains("English: One.\nTurkish: [tr] One."))
        XCTAssertTrue(user(4).contains("English: Two.\nTurkish: [tr] Two.\nEnglish: Three.\nTurkish: [tr] Three.\nEnglish: Four.\nTurkish: [tr] Four."))
        XCTAssertFalse(user(4).contains("English: One."))
        XCTAssertFalse(user(4).contains("English: Five."))
    }

    func testSeveralSentencesGoAsOneArray() async throws {
        let translator = make(.gemini)
        let result = try await translator.translate("We go now. Stay close.\nATREUS: Yes, father.", fallback: local)
        XCTAssertEqual(result, "[tr] We go now. [tr] Stay close.\nATREUS: [tr] Yes, father.")
        XCTAssertEqual(FakeAI.requests.count, 1)
        XCTAssertTrue(user(0).hasSuffix("[\"We go now.\",\"Stay close.\",\"Yes, father.\"]"))
        XCTAssertEqual(translator.spokenLines(for: "We go now. Stay close.\nATREUS: Yes, father.") { _ in [] }.last?.speaker, "ATREUS")
    }

    // MARK: - Yanıt

    func testReplyParsing() throws {
        XCTAssertEqual(try AIRequest.translations(from: "```json\n[\"Gidelim.\", \"Yakın dur.\"]\n```", count: 2), ["Gidelim.", "Yakın dur."])
        XCTAssertEqual(try AIRequest.translations(from: "“Gidelim.”", count: 1), ["Gidelim."])
        XCTAssertThrowsError(try AIRequest.translations(from: "[\"Tek\"]", count: 2))
        XCTAssertThrowsError(try AIRequest.translations(from: "Gidelim. Yakın dur.", count: 2))
        XCTAssertThrowsError(try AIRequest.text(provider: .gemini, from: Data(#"{"promptFeedback":{"blockReason":"OTHER"}}"#.utf8)))
        XCTAssertEqual(try AIRequest.text(provider: .openAI, from: Data(#"{"choices":[{"message":{"content":"Koş!"}}]}"#.utf8)), "Koş!")
    }

    func testPlainTextReplyForOneSentence() async throws {
        FakeAI.replyText = "Koş!"
        let result = try await make(.openAI).translate("Run!", fallback: local)
        XCTAssertEqual(result, "Koş!")
    }

    func testFailureMapping() {
        let empty = Data()
        XCTAssertEqual(AIRequest.failure(status: 401, body: empty), .invalidKey)
        XCTAssertEqual(AIRequest.failure(status: 403, body: empty), .invalidKey)
        XCTAssertEqual(AIRequest.failure(status: 400, body: Data(#"{"error":{"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"#.utf8)), .invalidKey)
        XCTAssertEqual(AIRequest.failure(status: 429, body: Data(#"{"error":{"code":"insufficient_quota"}}"#.utf8)), .quotaExceeded)
        XCTAssertEqual(AIRequest.failure(status: 400, body: Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low"}}"#.utf8)), .quotaExceeded)
        XCTAssertEqual(AIRequest.failure(status: 404, body: empty), .modelRejected)
        XCTAssertEqual(AIRequest.failure(status: 400, body: Data("unknown model".utf8)), .modelRejected)
        XCTAssertEqual(AIRequest.failure(status: 529, body: empty), .unreachable)
        XCTAssertEqual(AIRequest.failure(status: 500, body: empty), .unreachable)
    }

    // MARK: - Hata ve yerel çeviri

    /// Kota biterse o satır yerel motorla çevrilir, bir süre hizmet denenmez, hata durumu bildirilir.
    func testFallsBackAndPausesOnError() async throws {
        FakeAI.failure = (429, #"{"error":{"message":"quota"}}"#)
        let cache = TranslationCache()
        let translator = make(.gemini, cache: cache)
        var reported: [AIFailure?] = []
        translator.onFailureChanged = { reported.append($0) }
        let first = try await translator.translate("Run!", fallback: local)
        let second = try await translator.translate("Hide!", fallback: local)
        XCTAssertEqual(first, "yerel: Run!")
        XCTAssertEqual(second, "yerel: Hide!")
        XCTAssertEqual(FakeAI.requests.count, 1)
        XCTAssertEqual(translator.lastFailure, .quotaExceeded)
        XCTAssertEqual(reported, [.quotaExceeded])
        // Yerel çeviri bu motorun önbelleğine yazılmaz.
        XCTAssertNil(cache.value(for: "Run!"))
    }

    func testTimeoutFallsBack() async throws {
        FakeAI.timeout = true
        let translator = make(.claude)
        let result = try await translator.translate("Run!", fallback: local)
        XCTAssertEqual(result, "yerel: Run!")
        XCTAssertEqual(translator.lastFailure, .unreachable)
    }

    // MARK: - Önbellek

    /// Önceki oturumda çevrilen satır ve cümleler hizmete hiç gitmez; yalnız yeni cümle gönderilir.
    func testPersistentCacheAcrossSessions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("couchsubs-ai-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("cache.jsonl")
        _ = try await make(.openAI, cache: TranslationCache(file: file)).translate("KRATOS: We go now. Stay close.", fallback: local)
        FakeAI.requests = []

        let translator = make(.openAI, cache: TranslationCache(file: file))
        let again = try await translator.translate("KRATOS: We go now. Stay close.", fallback: local)
        XCTAssertEqual(again, "KRATOS: [tr] We go now. [tr] Stay close.")
        XCTAssertTrue(FakeAI.requests.isEmpty)
        let mixed = try await translator.translate("Stay close. Run!", fallback: local)
        XCTAssertEqual(mixed, "[tr] Stay close. [tr] Run!")
        XCTAssertEqual(FakeAI.requests.count, 1)
        XCTAssertTrue(user(0).hasSuffix("[\"Run!\"]"))
    }

    // MARK: - Deneme ve anahtarın gizliliği

    func testTestTranslatesTheSample() async {
        let result = await AITranslationCore.test(provider: .gemini, key: secret, model: nil, session: FakeAI.session())
        XCTAssertEqual(result, .success("KRATOS: [tr] We go now. [tr] Stay close, boy."))
    }

    /// Anahtar hiçbir hata metninde ya da durumda görünmez.
    func testKeyNeverAppearsInErrors() async {
        FakeAI.failure = (401, #"{"error":{"message":"Incorrect API key provided: \#(secret)"}}"#)
        for provider in AIProvider.allCases {
            let result = await AITranslationCore.test(provider: provider, key: secret, model: nil, session: FakeAI.session())
            XCTAssertEqual(result, .failure(.invalidKey))
            if case .failure(let error) = result {
                XCTAssertFalse(String(describing: error).contains(secret))
                XCTAssertFalse(error.localizedDescription.contains(secret))
            }
        }
        FakeAI.failure = nil
        FakeAI.timeout = true
        let result = await AITranslationCore.test(provider: .openAI, key: secret, model: nil, session: FakeAI.session())
        XCTAssertEqual(result, .failure(.unreachable))
        let empty = await AITranslationCore.test(provider: .claude, key: "  ", model: nil, session: FakeAI.session())
        XCTAssertEqual(empty, .failure(.invalidKey))
    }
}
