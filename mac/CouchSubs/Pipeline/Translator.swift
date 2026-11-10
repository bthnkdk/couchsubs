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
/// Uygulama kalıcı önbelleği verir: önceki oturumlarda çevrilmiş satır ve cümleler hiç çevrilmeden döner.
final class Translator: TextTranslator {
    /// Kalıcı önbellek dosyasındaki motor adı.
    static let engineID = "apple"

    private let source: Locale.Language
    private let target: Locale.Language
    private var session: TranslationSession?
    private let cache: TranslationCache
    private var speech: [String: [SpokenLine]] = [:]
    private let names = SpeakerNames()

    /// `cache`: kalıcı önbellek; verilmezse yalnız bellekte tutulur.
    init(source: String = "en", target: String = "tr", cache: TranslationCache = TranslationCache()) {
        self.source = Locale.Language(identifier: source)
        self.target = Locale.Language(identifier: target)
        self.cache = cache
    }

    static func status(source: String, target: String) async -> TranslatorStatus {
        switch await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target)) {
        case .installed: .ready
        case .supported: .needsDownload
        default: .unsupported
        }
    }

    func translate(_ text: String) async throws -> String {
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
        speech[text] ?? SpeechScript.fromCache(text, cache: cache)
    }

    private func translateSentence(_ sentence: String) async throws -> String {
        if let cached = cache.value(for: sentence) { return cached }
        if session == nil {
            switch await LanguageAvailability().status(from: source, to: target) {
            case .installed: session = TranslationSession(installedSource: source, target: target)
            case .supported: throw TranslatorError.needsDownload
            default: throw TranslatorError.unsupported
            }
        }
        let result = try await session!.translate(GameEnglish.plain(SubtitleSegmenter.normalizeCase(sentence, names: names.all))).targetText
        cache.store(result, for: sentence)
        return result
    }
}
