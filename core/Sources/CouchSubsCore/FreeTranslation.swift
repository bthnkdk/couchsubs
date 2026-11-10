// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Ücretsiz (cihaz üstü) çevirinin ortak metin hattı (Windows: CouchSubs.Core/FreeTranslation.cs, aynı adımlar ve
/// sabitler): büyük harf düzeni → oyun deyimleri → terim koruma → çeviri → terim ve ekleri → Türkçe düzeltmeler.
/// Kısa satır (3 sözcük ve altı: "Boy!", "Do it.", "Not you.") önceki cümleyle birlikte çevrilir; tek başına
/// çevrilince hitap (sen/siz) ve zamirler kayıyordu. Ayraçtan sonrası alınır, ayrım belirsizse satır tek başına çevrilir.
public enum FreeTranslation {
    /// Çeviri öncesi/sonrası kuralların sürümü; kalıcı önbelleğin motor adına girer. Bu dosyadaki ya da
    /// GameEnglish/SubtitleSegmenter/Glossary/TermProtection/TurkishSuffix/TurkishPostEdit'teki kurallar değişince bir
    /// artırılır: eski kurallarla çevrilmiş satırlar yeniden çevrilir. (1: sürüm yokken.)
    public static let pipelineVersion = 2

    /// Bu sözcük sayısının altındaki cümle önceki cümleyle birlikte çevrilir.
    public static let shortLineWords = 4

    /// Bağlam ile kısa satır arasındaki ayraç. OPUS-MT sözlüğünde "▁***" tek parça (altyazılarda sahne ayracı), "|"
    /// ve "||" hiç yok, satır sonu da SentencePiece'te boşluğa döner; bu yüzden "***". Apple'da da aynı ayraç: iki
    /// platform aynı davransın, ayraç kaybolursa satır zaten tek başına çevrilir.
    public static let separator = " *** "
    private static let separatorCore = "***"

    /// Önbellek anahtarında bağlam ile satırı ayıran karakter (dosya biçimi değişmez; JSON metni).
    private static let keyJoin = "\u{1F}"

    public static func isShort(_ sentence: String) -> Bool {
        let words = sentence.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }.count
        return words > 0 && words < shortLineWords
    }

    /// Cümlenin önbellek anahtarı: bağlamla çevrildiyse bağlam da, sözlük terimi içeriyorsa sözlüğün izi de girer.
    public static func cacheKey(_ sentence: String, context: String?, glossary: Glossary) -> String {
        let basis = context.map { $0 + keyJoin + sentence } ?? sentence
        return glossary.matches(basis) ? glossary.fingerprint + keyJoin + basis : basis
    }

    /// Ayraçtan sonraki kısım; ayraç tam bir kez geçmiyorsa, iki yan da harf içermiyorsa ya da kısım akla yatmayacak
    /// kadar uzunsa nil.
    public static func afterSeparator(_ output: String, source: String) -> String? {
        guard let first = output.range(of: separatorCore),
              output.range(of: separatorCore, range: first.upperBound..<output.endIndex) == nil else { return nil }
        let before = output[..<first.lowerBound]
        let after = output[first.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        // "****" gibi yapışık yıldızlar da belirsizdir.
        if after.hasPrefix("*") || before.hasSuffix("*") { return nil }
        guard before.contains(where: \.isLetter), after.contains(where: \.isLetter) else { return nil }
        guard after.utf16.count <= 3 * source.utf16.count + 20 else { return nil }
        return after
    }

    /// Tek cümleyi çevirir. `normalize` büyük harf düzenini yapar (öğrenilen adlarla), `engine` çeviri motorudur.
    /// Önce bağlamla (verildiyse), olmazsa tek başına, terimler korunamadıysa korumasız çevrilir.
    public static func translate(_ sentence: String, context: String?, glossary: Glossary,
                                 normalize: (String) -> String,
                                 engine: (String) async throws -> String) async rethrows -> String {
        let apostrophe = TurkishPostEdit.apostrophe(for: sentence)
        func prepare(_ text: String) -> String { GameEnglish.plain(normalize(text)) }

        if let context {
            let protector = TermProtector(glossary: glossary, sources: [sentence, context])
            let contextText = protector.protect(prepare(context)).text
            let (sentenceText, slots) = protector.protect(prepare(sentence))
            let output = try await engine(contextText + separator + sentenceText)
            if let after = afterSeparator(output, source: sentence),
               let restored = TermProtector.restore(after, expected: slots, all: protector.allSlots, apostrophe: apostrophe) {
                return TurkishPostEdit.apply(source: sentence, translation: restored)
            }
        }

        let single = TermProtector(glossary: glossary, sources: [sentence])
        let (input, used) = single.protect(prepare(sentence))
        let translated = try await engine(input)
        if used.isEmpty { return TurkishPostEdit.apply(source: sentence, translation: translated) }
        if let done = TermProtector.restore(translated, expected: used, all: single.allSlots, apostrophe: apostrophe) {
            return TurkishPostEdit.apply(source: sentence, translation: done)
        }
        // Model bir yer tutucuyu düşürdü: terimsiz ama eksiksiz çeviri, eksik terimli çeviriden iyidir.
        return TurkishPostEdit.apply(source: sentence, translation: try await engine(prepare(sentence)))
    }
}

/// Son gösterilen satırlar: kısa satırın bağlamı (DeepL'in bağlam satırlarıyla aynı düzen). Aynı satır yeniden
/// okunursa aynı bağlam döner (çeviri ekranda değişmesin); bağlam satırı çok önce gösterildiyse bağlam yoktur.
public final class RecentLines: @unchecked Sendable {
    public static let maxAge: TimeInterval = 20

    private let clock: () -> Date
    private let lock = NSLock()
    private var last: (text: String, context: String?, seen: Date)?

    public init(clock: @escaping () -> Date = Date.init) { self.clock = clock }

    /// Satırın gösterildiğini kaydeder; bu satırdan önce gösterilen satırı döner (yoksa nil).
    public func shown(_ text: String) -> String? {
        lock.withLock {
            let now = clock()
            if let last, last.text == text {
                self.last = (text, last.context, now)
                return last.context
            }
            let context = last.flatMap { now.timeIntervalSince($0.seen) <= Self.maxAge ? $0.text : nil }
            last = (text, context, now)
            return context
        }
    }
}

/// Ücretsiz motorun satır düzeyi (Windows'ta MarianTranslator.TranslateAsync ile aynı akış): satırı cümlelere böler,
/// kısa cümleye bağlam seçer, cümleleri önbellekten ya da motordan alır, hitabı satır bütününe göre düzeltir.
/// Motor (Apple Translation) dışarıdan verilir; testlerde sahtesi kullanılır.
public final class FreeLineTranslator: @unchecked Sendable {
    private let cache: TranslationCache
    private let glossaryStore: GlossaryStore
    private let recent: RecentLines
    private let names = SpeakerNames()
    private let lock = NSLock()
    private var speech: [String: [SpokenLine]] = [:]

    public init(cache: TranslationCache = TranslationCache(), glossary: GlossaryStore = .builtInOnly(),
                clock: @escaping () -> Date = Date.init) {
        self.cache = cache
        glossaryStore = glossary
        recent = RecentLines(clock: clock)
    }

    /// Satırı çevirir; seslendirme cümleleri `spokenLines(for:)` ile alınır.
    public func translate(_ text: String, engine: (String) async throws -> String) async throws -> String {
        // Kısa cümlenin bağlamı: aynı satırdaki önceki cümle, yoksa bu satırdan önce gösterilen satırın son cümlesi.
        let previousLine = recent.shown(text)
        let pieces = SubtitleSegmenter.split(text)
        names.learn(from: pieces)
        var previous = previousLine.flatMap { SubtitleSegmenter.split($0).last(where: \.translate)?.text }
        var translations: [String?] = []
        for piece in pieces {
            guard piece.translate else { translations.append(nil); continue }
            let context = FreeTranslation.isShort(piece.text) ? previous : nil
            translations.append(try await translateSentence(piece.text, context: context, engine: engine))
            previous = piece.text
        }
        // Hitap satırın bütününe bakar ("Sana söyledim. Bekleyin!"); önbellekteki cümle çevirileri değişmez.
        let final = TurkishPostEdit.register(translations)
        var result = ""
        for (index, piece) in pieces.enumerated() { result += final[index] ?? piece.text }
        lock.withLock {
            if speech.count >= 512 { speech.removeAll() }
            speech[text] = SpeechScript.lines(pieces: pieces, translations: final)
        }
        return result
    }

    public func spokenLines(for text: String) -> [SpokenLine] {
        lock.withLock { speech[text] } ?? SpeechScript.fromCache(text, cache: cache)
    }

    private func translateSentence(_ sentence: String, context: String?, engine: (String) async throws -> String) async throws -> String {
        let glossary = glossaryStore.glossary
        let key = FreeTranslation.cacheKey(sentence, context: context, glossary: glossary)
        if let cached = cache.value(for: key) { return cached }
        let known = names.all.union(glossary.capitalWords)
        let result = try await FreeTranslation.translate(sentence, context: context, glossary: glossary,
                                                         normalize: { SubtitleSegmenter.normalizeCase($0, names: known) },
                                                         engine: engine)
        cache.store(result, for: key)
        return result
    }
}
