// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Sözlük teriminin Türkçe eki (Windows: CouchSubs.Core/TurkishSuffix.cs, aynı kurallar). Çeviri motoru terimin
/// yerindeki yer tutucu ada bir ek koyar ("Zarmon'a", "Zarmon'un", "Zarmon'da"); ek, hangi hâl olduğu korunarak gerçek
/// terime göre yeniden kurulur:
/// - ünlü uyumu: Kratos'u, Midgard'ı, Freya'yı; Atreus'un, Midgard'ın
/// - kaynaştırma: ünlüyle biten terime y / n gelir (Freya'ya, Freya'nın)
/// - ünsüz benzeşmesi: sert ünsüzden sonra -da/-dan → -ta/-tan (Kratos'ta)
/// - özel ad (büyük harfle başlayan terim) kesmeyle ayrılır; cins ad bitişik yazılır, p/ç/k yumuşar (kılıcı)
/// - çok sözcüklü ve dar ünlüyle biten terim tamlama sayılır: hâl ekinden önce n gelir (Leviathan Baltası'nı)
public enum TurkishSuffix {
    static let turkish = Locale(identifier: "tr_TR")
    private static let vowels: Set<Character> = ["a", "e", "ı", "i", "o", "ö", "u", "ü"]
    private static let backVowels: Set<Character> = ["a", "ı", "o", "u"]
    private static let roundedVowels: Set<Character> = ["o", "u", "ö", "ü"]
    private static let highVowels: Set<Character> = ["ı", "i", "u", "ü"]
    private static let voiceless: Set<Character> = ["f", "s", "t", "k", "ç", "ş", "h", "p"]
    /// Daha uzun "ek" büyük olasılıkla ek değildir; dokunulmaz.
    private static let maxSuffixLength = 12

    /// `term` + ek. `suffix` motorun yer tutucuya koyduğu ektir (kesmesiz, "a", "un", "ya", "dan"); boşsa terim döner.
    public static func attach(_ term: String, suffix: String, apostrophe: Character = "'") -> String {
        guard !term.isEmpty, !suffix.isEmpty else { return term }
        var body = Array(suffix.lowercased(with: turkish))
        guard body.count <= maxSuffixLength, body.allSatisfy(\.isLetter) else { return term + String(apostrophe) + suffix }

        let proper = term.first!.isUppercase
        let lastWord = Array((term.split(separator: " ").last.map(String.init) ?? term).lowercased(with: turkish))
        let lastLetter = lastWord.last(where: \.isLetter) ?? " "
        var lastVowel = lastWord.last(where: { vowels.contains($0) })
        // Ünlüsüz kısaltma ("XP", "HP") harf adlarıyla okunur: "iks-pe" → ince, ünlüyle biter.
        let endsWithVowel = lastVowel == nil || vowels.contains(lastLetter)
        if lastVowel == nil { lastVowel = "e" }
        let compound = term.contains(" ") && highVowels.contains(lastLetter) && lastWord.count >= 3
        let isVoiceless = !endsWithVowel && voiceless.contains(lastLetter)

        // Baştaki kaynaştırma harfi yer tutucuya göreydi ("Zarmon" ünsüzle biter, çoğu zaman yoktur); atılır.
        if body.count >= 2, body[0] == "y", vowels.contains(body[1]) || body[1] == "l" {
            body.removeFirst()
        } else if body.count >= 3, body[0] == "n", highVowels.contains(body[1]), body[2] == "n" {
            body.removeFirst()
        }

        let genitive = body.count >= 2 && highVowels.contains(body[0]) && body[1] == "n" && (body.count == 2 || !vowels.contains(body[2]))
        let instrumental = body.count >= 2 && body[0] == "l" && (body[1] == "a" || body[1] == "e") && !(body.count >= 3 && body[2] == "r")
        var buffer = ""
        if vowels.contains(body[0]) {
            if compound || (endsWithVowel && genitive) { buffer = "n" } else if endsWithVowel { buffer = "y" }
        } else if body[0] == "d" || body[0] == "t" {
            if compound { buffer = "n" }
            body[0] = compound || !isVoiceless ? "d" : "t"
        } else if instrumental, endsWithVowel || compound {
            buffer = "y"
        }

        let harmonized = harmonize(body, after: lastVowel!)
        if proper { return term + String(apostrophe) + buffer + harmonized }
        let stem = buffer.isEmpty && vowels.contains(harmonized.first!) ? soften(term) : term
        return stem + buffer + harmonized
    }

    /// Ekteki a/e ve ı/i/u/ü ünlülerini önceki ünlüye uydurur; "-ki" (Midgard'daki) değişmez.
    static func harmonize(_ body: [Character], after lastVowel: Character) -> String {
        var output = ""
        var previous = lastVowel
        for (index, original) in body.enumerated() {
            var character = original
            let invariantKi = character == "i" && index > 0 && body[index - 1] == "k" && index == body.count - 1
            if !invariantKi, character == "a" || character == "e" {
                character = backVowels.contains(previous) ? "a" : "e"
            } else if !invariantKi, highVowels.contains(character) {
                let back = backVowels.contains(previous)
                let rounded = roundedVowels.contains(previous)
                character = back ? (rounded ? "u" : "ı") : (rounded ? "ü" : "i")
            }
            if vowels.contains(character) { previous = character }
            output.append(character)
        }
        return output
    }

    /// Cins adın son p/ç/k'si ünlüyle başlayan ekten önce yumuşar (kitap → kitabı, kılıç → kılıcı, bıçak → bıçağı,
    /// renk → rengi). Tek heceli sözcükler yumuşamaz (top → topu); t çoğu sözcükte yumuşamadığı için dokunulmaz.
    static func soften(_ term: String) -> String {
        guard term.count >= 2, let last = term.last else { return term }
        let word = term.lowercased(with: turkish).split(separator: " ").last.map(String.init) ?? ""
        if word.hasSuffix("nk") { return String(term.dropLast()) + "g" }
        guard word.filter({ vowels.contains($0) }).count >= 2 else { return term }
        switch last {
        case "p": return String(term.dropLast()) + "b"
        case "ç": return String(term.dropLast()) + "c"
        case "k": return String(term.dropLast()) + "ğ"
        default: return term
        }
    }
}
