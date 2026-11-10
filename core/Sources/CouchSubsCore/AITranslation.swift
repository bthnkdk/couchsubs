// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Kullanıcının kendi anahtarıyla çalışan yapay zekâ çeviri hizmetleri (Windows'taki CouchSubs.Core/AiProvider.cs ile aynı).
public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case gemini
    case openAI = "openai"
    case claude

    /// Hızlı ve ucuz varsayılan model; kullanıcı ayarlarda değiştirebilir (Kasım 2026'da belgelerden denetlendi).
    public var defaultModel: String {
        switch self {
        // "Our fastest, most cost-effective 3.5 model", düşünmesi varsayılan olarak en az düzeyde
        // (aistudio.google.com/docs/models, aistudio.google.com/docs/thinking).
        case .gemini: "gemini-3.5-flash-lite"
        // "Our most efficient model for focused, high-volume tasks", reasoning_effort "none" destekler
        // (developers.openai.com/api/docs/models).
        case .openAI: "gpt-6-luna"
        // "Fastest", gecikmeye duyarlı işler için (platform.claude.com/docs/en/about-claude/models/overview).
        case .claude: "claude-haiku-5-5"
        }
    }

    /// Marka adı; çevrilmez.
    public var displayName: String {
        switch self {
        case .gemini: "Gemini"
        case .openAI: "OpenAI"
        case .claude: "Claude"
        }
    }

    /// Anahtarın alındığı resmî sayfa.
    public var keyPage: URL {
        switch self {
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .claude: URL(string: "https://platform.claude.com/settings/keys")!
        }
    }

    /// Kalıcı önbellek dosyasındaki motor adı: model değişince eski modelin çevirileri karışmaz.
    public func engineID(model: String) -> String { "\(rawValue):\(model)" }

    /// Boş ya da yalnız boşluk olan model adı varsayılana döner.
    public func model(_ custom: String?) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultModel : trimmed
    }
}

/// Yapay zekâ hizmeti neden çeviremedi. Hata yalnız durum taşır: anahtar ve hizmetin yanıt metni hiçbir yere yazılmaz.
public enum AIFailure: Error, Equatable, Sendable {
    /// Anahtar reddedildi (401/403 ya da Gemini'de "API key not valid").
    case invalidKey
    /// Bakiye bitti, aylık sınır ya da dakikalık istek sınırı aşıldı (429, 402, Claude'da "credit balance").
    case quotaExceeded
    /// Model adı tanınmadı ya da istek kabul edilmedi (400, 404).
    case modelRejected
    /// Ağ hatası, zaman aşımı, hizmet arızası ya da anlaşılmayan yanıt.
    case unreachable
}

/// Bağlam olarak giden, daha önce gösterilmiş satır ve (biliniyorsa) çevirisi.
public struct AIContextLine: Equatable, Sendable {
    public var source: String
    public var translation: String?

    public init(source: String, translation: String? = nil) {
        self.source = source
        self.translation = translation
    }
}

/// Üç hizmet için istek kurma ve yanıt okuma. Cümleler bir JSON dizisi olarak gider, aynı sırada JSON dizisi beklenir;
/// böylece cümle cümle önbelleğe yazılır ve dublaj konuşmacıyı bilir (DeepL ile aynı düzen).
public enum AIRequest {
    /// Bir altyazı satırına yeten çıktı sınırı; düşünen modellere de pay bırakır.
    public static let maxOutputTokens = 1024

    public static let systemPrompt = """
        You translate English video game subtitles into natural, spoken Turkish, the way people really talk. \
        Characters address each other informally (use "sen", not "siz") unless the line is clearly formal. \
        Keep character names, place names and speaker labels such as "ATREUS:" exactly as they are. \
        Keep line breaks. Keep the meaning and tone; do not add or leave out anything. \
        Reply with only the translation, no explanations, notes or quotes.
        """

    /// Kullanıcı iletisi: önceki satırlar (yalnız bağlam) ve çevrilecek cümleler.
    public static func userMessage(sentences: [String], context: [AIContextLine], game: String? = nil) -> String {
        var parts: [String] = []
        if let game, !game.isEmpty { parts.append("Game: \(game)") }
        if !context.isEmpty {
            var lines = ["Previous subtitles, for context only (do not translate them again):"]
            for line in context {
                lines.append("English: \(line.source)")
                if let translation = line.translation { lines.append("Turkish: \(translation)") }
            }
            parts.append(lines.joined(separator: "\n"))
        }
        let list = (try? JSONSerialization.data(withJSONObject: sentences, options: [.withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        parts.append("Translate each string in this JSON array into Turkish. Reply with only a JSON array of \(sentences.count) "
            + "Turkish strings in the same order.\n\(list)")
        return parts.joined(separator: "\n\n")
    }

    /// Hizmete giden HTTP isteği.
    public static func make(provider: AIProvider, key: String, model: String, sentences: [String],
                            context: [AIContextLine], game: String? = nil) -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userMessage(sentences: sentences, context: context, game: game)
        var request: URLRequest
        var body: [String: Any]
        switch provider {
        case .gemini:
            // https://ai.google.dev/api/generate-content (aistudio.google.com/api-reference/generate-content):
            // POST /v1beta/models/{model}:generateContent, anahtar "x-goog-api-key" başlığında.
            // Gemini 3.6 Flash ve sonrası temperature'ı yok sayıyor; Flash-Lite zaten en az düşünmeyle çalışıyor.
            let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):generateContent")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": [["role": "user", "parts": [["text": user]]]],
                "generationConfig": ["maxOutputTokens": maxOutputTokens],
            ]
        case .openAI:
            // https://platform.openai.com/docs/api-reference/chat/create (developers.openai.com/api/reference):
            // POST /v1/chat/completions, "Authorization: Bearer"; "developer" iletisi yönergedir.
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": model,
                "messages": [["role": "developer", "content": systemPrompt], ["role": "user", "content": user]],
                "max_completion_tokens": maxOutputTokens,
                "reasoning_effort": openAIEffort(model),
            ]
        case .claude:
            // https://docs.anthropic.com/en/api/messages (platform.claude.com/docs/en/api/messages): POST /v1/messages,
            // "x-api-key" ve "anthropic-version". Yeni modellerde temperature gönderilmez; hız için effort "low",
            // Haiku 5.5'te düşünme kapalı (platform.claude.com/docs/en/build-with-claude/effort).
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": maxOutputTokens,
                "system": systemPrompt,
                "messages": [["role": "user", "content": user]],
                "output_config": ["effort": "low"],
            ]
            if model.hasPrefix("claude-haiku-5") { body["thinking"] = ["type": "disabled"] }
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// "none" yalnız hızlı modellerde var; diğerlerinde en düşük ortak düzey "low".
    static func openAIEffort(_ model: String) -> String {
        model.contains("luna") || model.contains("terra") ? "none" : "low"
    }

    /// Yanıttaki düz metin (düşünme bölümleri atlanır).
    public static func text(provider: AIProvider, from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIFailure.unreachable }
        let text: String?
        switch provider {
        case .gemini:
            // candidates[0].content.parts[].text; "thought": true olan parçalar düşünmedir.
            let candidate = (root["candidates"] as? [[String: Any]])?.first
            let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        case .openAI:
            let message = ((root["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any]
            text = message?["content"] as? String
        case .claude:
            let blocks = root["content"] as? [[String: Any]] ?? []
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIFailure.unreachable }
        return text
    }

    /// Yanıttaki JSON dizisi; tek cümlede model diziyi unutup düz metin dönerse o metin alınır.
    public static func translations(from text: String, count: Int) throws -> [String] {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // ```json … ``` çitini at.
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
                .filter { !$0.hasPrefix("```") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end,
           let data = String(trimmed[start...end]).data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [String] {
            guard list.count == count else { throw AIFailure.unreachable }
            return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard count == 1 else { throw AIFailure.unreachable }
        return [trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))]
    }

    /// Başarısız HTTP yanıtının anlamı. Gövde yalnız tanınan hata kodları için okunur, hiçbir yere yazılmaz.
    public static func failure(status: Int, body: Data) -> AIFailure {
        let message = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        switch status {
        case 401, 403: return .invalidKey
        case 402, 429: return .quotaExceeded
        case 400:
            if message.contains("api_key_invalid") || message.contains("api key not valid") { return .invalidKey }
            if message.contains("credit balance") || message.contains("insufficient_quota") { return .quotaExceeded }
            return .modelRejected
        case 404: return .modelRejected
        default: return .unreachable
        }
    }
}

/// Yapay zekâ çevirisinin ortak çekirdeği: önbellek, bağlam, cümle bölme, hata sonrası bekleme ve yerel çeviriye düşme.
/// Uygulamadaki `AITranslator` bunu çeviri protokolüne bağlar. Hata olursa o satır yerel (ücretsiz) motorla çevrilir ve
/// bir dakika hizmet denenmez; her satırda zaman aşımı beklenmez. Yerel çeviriler bu motorun önbelleğine yazılmaz.
public final class AITranslationCore: @unchecked Sendable {
    /// Bağlama giden önceki satır sayısı.
    public static let contextLines = 3
    /// Hata sonrası bu süre hizmet denenmez.
    public static let retryAfter: TimeInterval = 60

    public let provider: AIProvider
    public let model: String
    private let key: String
    private let session: URLSession
    private let cache: TranslationCache
    private let names = SpeakerNames()
    private let lock = NSLock()
    private var speech: [String: [SpokenLine]] = [:]
    /// Son gösterilen satırlar, eskiden yeniye.
    private var recent: [AIContextLine] = []
    private var pausedUntil = Date.distantPast
    private var failure: AIFailure?

    /// Son hata; çeviri düzgün gidiyorsa nil. Değiştikçe `onFailureChanged` çağrılır.
    public var lastFailure: AIFailure? { lock.withLock { failure } }
    public var onFailureChanged: ((AIFailure?) -> Void)?

    public init(provider: AIProvider, key: String, model: String? = nil, session: URLSession = AITranslationCore.makeSession(),
                cache: TranslationCache = TranslationCache()) {
        self.provider = provider
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = provider.model(model)
        self.session = session
        self.cache = cache
    }

    /// Kısa zaman aşımı: altyazı birkaç saniye ekranda kalır, geç gelen çeviri işe yaramaz.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }

    public func translate(_ text: String, fallback: (String) async throws -> String) async throws -> String {
        // Bağlam, bu satırdan önce gösterilenlerdir; satırın kendisi bağlama girmez.
        let context = lock.withLock { recent }
        shown(text)
        if let cached = cache.value(for: text) { return remember(cached, for: text) }
        guard Date() >= lock.withLock({ pausedUntil }) else { return remember(try await fallback(text), for: text) }
        let pieces = SubtitleSegmenter.split(text)
        names.learn(from: pieces)
        // Önbellekte duran cümleler yeniden gönderilmez.
        var translations: [String?] = pieces.map { $0.translate ? cache.value(for: $0.text) : nil }
        let missing = pieces.indices.filter { pieces[$0].translate && translations[$0] == nil }
        let sources = missing.map { SubtitleSegmenter.normalizeCase(pieces[$0].text, names: names.all) }
        let translated: [String]
        do {
            translated = sources.isEmpty ? [] : try await request(sources, context: context)
            setFailure(nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch {
            setFailure(error as? AIFailure ?? .unreachable)
            lock.withLock { pausedUntil = Date().addingTimeInterval(Self.retryAfter) }
            return remember(try await fallback(text), for: text)
        }
        for (index, sentence) in zip(missing, translated) {
            translations[index] = sentence
            cache.store(sentence, for: pieces[index].text)
        }
        let result = zip(pieces, translations).map { $1 ?? $0.text }.joined()
        lock.withLock {
            if speech.count >= 512 { speech.removeAll() }
            speech[text] = SpeechScript.lines(pieces: pieces, translations: translations)
        }
        cache.store(result, for: text)
        return remember(result, for: text)
    }

    public func spokenLines(for text: String, fallback: (String) -> [SpokenLine]) -> [SpokenLine] {
        if let lines = lock.withLock({ speech[text] }) { return lines }
        let cached = SpeechScript.fromCache(text, cache: cache)
        return cached.isEmpty ? fallback(text) : cached
    }

    private func shown(_ text: String) {
        lock.withLock {
            // Aynı satır yeniden okunduysa bağlam tekrarla dolmasın.
            guard recent.last?.source != text else { return }
            recent.append(AIContextLine(source: text))
            if recent.count > Self.contextLines { recent.removeFirst() }
        }
    }

    /// Gösterilen satırın çevirisi sonraki satırların bağlamına girer.
    private func remember(_ translation: String, for text: String) -> String {
        lock.withLock {
            if let index = recent.lastIndex(where: { $0.source == text }) { recent[index].translation = translation }
        }
        return translation
    }

    private func setFailure(_ value: AIFailure?) {
        let changed = lock.withLock { () -> Bool in
            defer { failure = value }
            return failure != value
        }
        if changed { onFailureChanged?(value) }
    }

    private func request(_ sentences: [String], context: [AIContextLine]) async throws -> [String] {
        try await Self.send(AIRequest.make(provider: provider, key: key, model: model, sentences: sentences, context: context),
                            provider: provider, count: sentences.count, session: session)
    }

    private static func send(_ request: URLRequest, provider: AIProvider, count: Int, session: URLSession) async throws -> [String] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // URLError adresi taşır ama anahtarı taşımaz; yine de dışarı yalnız durum çıkar.
            throw AIFailure.unreachable
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIRequest.failure(status: http.statusCode, body: data)
        }
        return try AIRequest.translations(from: AIRequest.text(provider: provider, from: data), count: count)
    }

    /// Ayarlardaki "Dene": örnek bir satırı çevirir; çeviri ya da hatanın türü döner.
    public static func test(provider: AIProvider, key: String, model: String?, sample: String = AITranslationCore.sample,
                            session: URLSession = makeSession()) async -> Result<String, AIFailure> {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(.invalidKey) }
        let translator = AITranslationCore(provider: provider, key: key, model: model, session: session)
        do {
            let result = try await translator.translate(sample) { _ in throw translator.lastFailure ?? AIFailure.unreachable }
            return .success(result)
        } catch {
            return .failure(error as? AIFailure ?? .unreachable)
        }
    }

    /// Denemede çevrilen örnek satır.
    public static let sample = "KRATOS: We go now. Stay close, boy."
}
