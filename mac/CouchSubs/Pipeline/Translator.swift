// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import Foundation
import Translation

protocol TextTranslator {
    func translate(_ text: String) async throws -> String
    /// Son çevrilen altyazının seslendirilecek cümleleri (konuşmacısıyla); dublaj için.
    func spokenLines(for text: String) -> [SpokenLine]
}

extension TextTranslator {
    func spokenLines(for text: String) -> [SpokenLine] { [] }
}

enum TranslatorError: Error, Equatable {
    case needsDownload
    case unsupported
}

enum TranslatorStatus: Equatable {
    case ready, needsDownload, unsupported
}

/// Apple'ın cihaz üstü çevirisi. Dil paketi yüklü olmalı; değilse `needsDownload` atar.
/// Altyazı cümle cümle çevrilir: alt alta sarılmış satırlar birleşir, konuşmacı adları ("ATREUS:") çevrilmez,
/// tümü büyük harfli cümleler önce cümle düzenine getirilir (öğrenilen adlar büyük harfle kalır).
/// İngilizce→Türkçede Windows'taki OPUS-MT ile aynı metin hattı kullanılır (`FreeLineTranslator`): terim sözlüğü
/// (~/Library/Application Support/CouchSubs/Glossary/*.json), kısa satır bağlamı, Türkçe düzeltmeler.
/// Uygulama kalıcı önbelleği verir: önceki oturumlarda çevrilmiş cümleler hiç çevrilmeden döner.
final class Translator: TextTranslator {
    /// Kalıcı önbellek dosyasındaki motor adı; metin hattı değişince (`FreeTranslation.pipelineVersion`) bu da değişir.
    static let engineID = "apple-p\(FreeTranslation.pipelineVersion)"

    private let source: Locale.Language
    private let target: Locale.Language
    private var session: TranslationSession?
    private let cache: TranslationCache
    private let freeLine: FreeLineTranslator?
    private var speech: [String: [SpokenLine]] = [:]
    private let names = SpeakerNames()

    /// `cache`: kalıcı önbellek; verilmezse yalnız bellekte tutulur.
    init(source: String = "en", target: String = "tr", cache: TranslationCache = TranslationCache(),
         glossary: GlossaryStore = GlossaryStore(directory: GlossaryStore.userDirectory)) {
        self.source = Locale.Language(identifier: source)
        self.target = Locale.Language(identifier: target)
        self.cache = cache
        // Sözlük, ek kuralları ve Türkçe düzeltmeler yalnız İngilizce→Türkçe için.
        freeLine = source == "en" && target == "tr" ? FreeLineTranslator(cache: cache, glossary: glossary) : nil
    }

    static func status(source: String, target: String) async -> TranslatorStatus {
        switch await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target)) {
        case .installed: .ready
        case .supported: .needsDownload
        default: .unsupported
        }
    }

    func translate(_ text: String) async throws -> String {
        if let freeLine { return try await freeLine.translate(text) { try await self.run($0) } }
        if let cached = cache.value(for: text) { return cached }
        let pieces = SubtitleSegmenter.split(text)
        names.learn(from: pieces)
        var result = ""
        var translations: [String?] = []
        for piece in pieces {
            let translated = piece.translate ? try await translateSentence(piece.text) : nil
            translations.append(translated)
            result += translated ?? piece.text
        }
        if speech.count >= 512 { speech.removeAll() }
        speech[text] = SpeechScript.lines(pieces: pieces, translations: translations)
        cache.store(result, for: text)
        return result
    }

    func spokenLines(for text: String) -> [SpokenLine] {
        if let freeLine { return freeLine.spokenLines(for: text) }
        return speech[text] ?? SpeechScript.fromCache(text, cache: cache)
    }

    private func translateSentence(_ sentence: String) async throws -> String {
        if let cached = cache.value(for: sentence) { return cached }
        let result = try await run(GameEnglish.plain(SubtitleSegmenter.normalizeCase(sentence, names: names.all)))
        cache.store(result, for: sentence)
        return result
    }

    /// Hazır metni Apple'ın çevirisine verir; oturum ilk çağrıda açılır.
    private func run(_ input: String) async throws -> String {
        if session == nil {
            switch await LanguageAvailability().status(from: source, to: target) {
            case .installed: session = TranslationSession(installedSource: source, target: target)
            case .supported: throw TranslatorError.needsDownload
            default: throw TranslatorError.unsupported
            }
        }
        return try await session!.translate(input).targetText
    }
}
