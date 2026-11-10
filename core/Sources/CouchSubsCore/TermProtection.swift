// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Sözlük terimlerini çeviriden korur (Windows: CouchSubs.Core/TermProtection.cs, aynı kurallar). Terim, çeviri
/// öncesinde uydurma bir özel adla ("Zarmon", "Velkor") değiştirilir. Neden ad: OPUS-MT de Apple Translation da özel
/// adı olduğu gibi bırakıp Türkçe ekini kesmeyle ekler ("Zarmon'u al"); "[[1]]", "__T1__" gibi işaretleri ise model
/// sözlüğünde olmadığı için düşürebilir ya da bozabilir. Çeviriden sonra ad, büyük/küçük harf, boşluk ve kesme farkına
/// bakılmadan bulunur, yerine Türkçe terim konur ve ek terime göre yeniden kurulur (`TurkishSuffix`). Bir ad çeviride
/// yoksa sonuç güvenilmez sayılır (nil), çağıran korumasız çeviriye döner.
public final class TermProtector {
    /// Yer tutucu adlar: Türkçe ve İngilizcede sözcük değil, birbirinin başı değil, i/I içermez (Türkçe büyük/küçük harf
    /// dönüşümü bozmasın), ünsüzle biter (yumuşamaz) ve kalın ünlülüdür.
    static let placeholders = ["Zarmon", "Velkor", "Dorvan", "Kelmar", "Tolvar", "Brandur", "Halvor", "Feldor"]

    /// Korunan terim: yer tutucusu ve yerine konacak Türkçe.
    public struct Slot: Equatable, Sendable {
        public var placeholder: String
        public var english: String
        public var turkish: String
    }

    private let glossary: Glossary
    private var free: [String]
    private var byTerm: [String: Slot] = [:]
    private var order: [Slot] = []

    /// `sources`: kaynak metinler; içlerinde geçen yer tutucu ad kullanılmaz.
    public init(glossary: Glossary, sources: [String]) {
        self.glossary = glossary
        free = Self.placeholders.filter { name in !sources.contains { $0.range(of: name, options: .caseInsensitive) != nil } }
    }

    /// Bütün yer tutucular (bağlamdakiler dahil); çıktıda beklenmeyen ad kalmasın diye.
    public var allSlots: [Slot] { order }

    /// Terimleri yer tutucularla değiştirir; bu metinde kullanılan yer tutucular döner.
    public func protect(_ text: String) -> (text: String, slots: [Slot]) {
        let matches = glossary.find(text)
        guard !matches.isEmpty else { return (text, []) }
        let string = text as NSString
        var output = ""
        var used: [Slot] = []
        var position = 0
        for match in matches {
            let key = match.english.lowercased()
            var slot = byTerm[key]
            if slot == nil {
                // Ad kalmadıysa geri kalan terimler korunmaz; model onları kendi çevirir.
                guard !free.isEmpty else { continue }
                let created = Slot(placeholder: free.removeFirst(), english: match.english, turkish: match.turkish)
                byTerm[key] = created
                order.append(created)
                slot = created
            }
            output += string.substring(with: NSRange(location: position, length: match.start - position)) + slot!.placeholder
            position = match.start + match.length
            if !used.contains(slot!) { used.append(slot!) }
        }
        output += string.substring(from: position)
        return (output, used)
    }

    /// Yer tutucuları Türkçe terimle değiştirir. `expected` çıktıda en az bir kez geçmeli, `all` içindeki diğer adlar
    /// hiç geçmemeli; yoksa nil.
    public static func restore(_ output: String, expected: [Slot], all: [Slot] = [], apostrophe: Character = "'") -> String? {
        if expected.isEmpty, all.isEmpty { return output }
        for slot in all where !expected.contains(slot) {
            if pattern(slot.placeholder).firstMatch(in: output, range: NSRange(location: 0, length: (output as NSString).length)) != nil { return nil }
        }
        var text = output
        for slot in expected {
            let expression = pattern(slot.placeholder)
            let string = text as NSString
            let found = expression.matches(in: text, range: NSRange(location: 0, length: string.length))
            guard !found.isEmpty else { return nil }
            var result = text
            for match in found.reversed() {
                let suffixRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                let suffix = suffixRange.location != NSNotFound ? string.substring(with: suffixRange) : ""
                var term = TurkishSuffix.attach(slot.turkish, suffix: suffix, apostrophe: apostrophe)
                if startsSentence(string, match.range.location) { term = capitalize(term) }
                guard let range = Range(match.range, in: result) else { return nil }
                result.replaceSubrange(range, with: term)
            }
            text = result
        }
        return text
    }

    /// Yer tutucu ve ardındaki ek: kesmeyle ("Zarmon'a", "Zarmon 'a") ya da bitişik ("Zarmona").
    private static func pattern(_ placeholder: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])"# + placeholder + #"(?:\s?['’`´](\p{L}+)|(\p{L}+))?(?![\p{L}\p{N}])"#,
                                 options: [.caseInsensitive])
    }

    /// Metnin ya da cümlenin başı mı (önünde yalnız boşluk, tırnak, tire ya da cümle sonu var).
    private static func startsSentence(_ text: NSString, _ index: Int) -> Bool {
        var i = index - 1
        while i >= 0 {
            guard let scalar = UnicodeScalar(text.character(at: i)) else { return false }
            let character = Character(scalar)
            if character.isWhitespace || "\"“'‘(-–—¡¿".contains(character) { i -= 1; continue }
            return ".!?…".contains(character)
        }
        return true
    }

    private static func capitalize(_ term: String) -> String {
        guard let first = term.first, first.isLowercase else { return term }
        return String(first).uppercased(with: TurkishSuffix.turkish) + term.dropFirst()
    }
}
