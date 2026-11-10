// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Dublajda seslendirilecek bir cümle: kimin söylediği, İngilizcesi (duygu için) ve Türkçesi.
public struct SpokenLine: Equatable, Sendable {
    /// Altyazıdaki konuşmacı etiketi ("KRATOS: " → "KRATOS"); etiket yoksa nil.
    public var speaker: String?
    /// Diyalog tiresiyle başlayan yeni konuşma ("- Gidelim. - Bekle!"): etiketsiz satırlarda konuşan değişti demektir.
    public var newTurn: Bool
    public var english: String
    public var turkish: String

    public init(speaker: String? = nil, newTurn: Bool = false, english: String, turkish: String) {
        self.speaker = speaker
        self.newTurn = newTurn
        self.english = english
        self.turkish = turkish
    }
}

/// Çevrilen parçalardan seslendirilecek cümleleri çıkarır (bkz. `SubtitleSegmenter.split`).
public enum SpeechScript {
    /// `translations[i]`, `pieces[i]` çevrilecek bir parçaysa onun Türkçesidir; diğerleri yok sayılır.
    public static func lines(pieces: [SubtitleSegmenter.Piece], translations: [String?]) -> [SpokenLine] {
        var lines: [SpokenLine] = []
        var speaker: String?
        var newTurn = false
        for (index, piece) in pieces.enumerated() {
            if piece.translate {
                guard index < translations.count, let turkish = translations[index],
                      turkish.contains(where: \.isLetter) else { continue }
                lines.append(SpokenLine(speaker: speaker, newTurn: newTurn, english: piece.text, turkish: turkish))
                // Aynı konuşmanın sonraki cümleleri aynı sesle sürer.
                newTurn = false
            } else if piece.text == "\n" {
                speaker = nil
                newTurn = false
            } else if piece.text.hasSuffix(": ") {
                let name = SubtitleSegmenter.name(fromLabel: piece.text)
                speaker = name.isEmpty ? nil : name
                newTurn = false
            } else if let first = piece.text.first, "-–—".contains(first) {
                speaker = nil
                newTurn = true
            }
        }
        return lines
    }

    /// Önceki oturumdan önbellekte duran satır: cümleleri de önbellekteyse konuşmacılarıyla kurulur, değilse
    /// satırın tamamı tek cümle sayılır.
    public static func fromCache(_ text: String, cache: TranslationCache) -> [SpokenLine] {
        guard let whole = cache.value(for: text) else { return [] }
        let pieces = SubtitleSegmenter.split(text)
        var translations: [String?] = []
        for piece in pieces {
            guard piece.translate else { translations.append(nil); continue }
            guard let sentence = cache.value(for: piece.text) else { return [SpokenLine(english: text, turkish: whole)] }
            translations.append(sentence)
        }
        return lines(pieces: pieces, translations: translations)
    }
}
