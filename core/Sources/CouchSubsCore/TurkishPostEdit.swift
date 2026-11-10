// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Cihaz üstü çevirinin Türkçesine yapılan güvenli düzeltmeler (Windows: CouchSubs.Core/TurkishPostEdit.cs, aynı
/// kurallar). Yalnız anlamı değiştirmeyen biçim kuralları ve dar bir hitap kuralı vardır:
/// - noktalamadan önceki boşluk silinir ("Dur !" → "Dur!")
/// - kaynağın "!", "?", "?!", "…" sonu korunur (model "Koş!"u "Koş." yapabiliyor)
/// - tırnaklar kaynaktaki gibi düz ya da kıvrık olur
/// - aynı satırda "sen" ile konuşulurken model emri "siz"li verdiyse ("Sana söyledim. Bekleyin!") bilinen emirler
///   "sen"li olur ("Bekle!"). Yalnız listedeki fiiller, yalnız emir yerindeyse (ardından noktalama gelir) ve cümlede
///   "siz" geçmiyorsa.
public enum TurkishPostEdit {
    private static let spaceBeforePunctuation = try! NSRegularExpression(pattern: #"[ \t ]+(?=[,.!?;:…])"#)
    private static let repeatedSpaces = try! NSRegularExpression(pattern: #"[ \t ]{2,}"#)

    /// Tek cümlenin çevirisini düzeltir; `source` İngilizce cümledir.
    public static func apply(source: String, translation: String) -> String {
        guard translation.contains(where: \.isLetter) else { return translation }
        var text = quotes(source: source, translation: translation)
        text = replace(spaceBeforePunctuation, in: text, with: "")
        text = replace(repeatedSpaces, in: text, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return ending(source: source, translation: text)
    }

    /// Kaynağın ünlem/soru/üç nokta sonu çeviride başka bir sonla bittiyse kaynağınki konur.
    static func ending(source: String, translation: String) -> String {
        let (_, sourceEnd, sourceClosers) = splitEnd(source)
        guard isExpressive(sourceEnd) else { return translation }
        let (body, end, closers) = splitEnd(translation)
        // Kaynakta son noktalama tırnağın içindeyse (He said "Run!") çeviride tırnak sonda olmayabilir; dokunulmaz.
        guard sourceClosers.isEmpty == closers.isEmpty else { return translation }
        guard end != sourceEnd, end.isEmpty || end == "." || isExpressive(end), body.contains(where: \.isLetter) else { return translation }
        return body + sourceEnd + closers
    }

    private static func isExpressive(_ end: String) -> Bool {
        !end.isEmpty && (end.contains("!") || end.contains("?") || end.contains("…") || end == "...")
    }

    /// Metin = gövde + son noktalama (. ! ? …) + kapanış tırnak/parantezleri.
    private static func splitEnd(_ text: String) -> (body: String, end: String, closers: String) {
        var characters = Array(text)
        while let last = characters.last, last.isWhitespace { characters.removeLast() }
        var closerStart = characters.count
        while closerStart > 0, "\"'”’)]»".contains(characters[closerStart - 1]) { closerStart -= 1 }
        var endStart = closerStart
        while endStart > 0, ".!?…".contains(characters[endStart - 1]) { endStart -= 1 }
        return (String(characters[..<endStart]), String(characters[endStart..<closerStart]), String(characters[closerStart...]))
    }

    /// Kaynak kıvrık tırnak kullanıyorsa çeviri de kullanır; yoksa düz tırnak.
    static func quotes(source: String, translation: String) -> String {
        let curlyDouble = source.contains("“") || source.contains("”")
        let curlySingle = source.contains("’") || source.contains("‘")
        var output = ""
        var previous: Character?
        for character in translation {
            let opening = previous == nil || previous!.isWhitespace || "([-–—".contains(previous!)
            switch character {
            case "“", "”", "„", "‟" where !curlyDouble: output.append("\"")
            case "\"" where curlyDouble: output.append(opening ? "“" : "”")
            case "’", "‘" where !curlySingle: output.append("'")
            case "'" where curlySingle: output.append(opening ? "‘" : "’")
            default: output.append(character)
            }
            previous = character
        }
        return output
    }

    /// Kaynakta kıvrık kesme varsa Türkçe eklerde de o kullanılır.
    public static func apostrophe(for source: String) -> Character { source.contains("’") ? "’" : "'" }

    private static let senWords: Set<String> = ["sen", "seni", "sana", "senin", "sende", "senden", "seninle", "senle"]
    private static let sizWords: Set<String> = ["siz", "sizi", "size", "sizin", "sizde", "sizden", "sizinle", "sizler"]

    /// "Siz"li emir → "sen"li emir; çoğul ya da kibar anlamı da olabilen sözcükler bilerek yok ("Alın" = alın).
    private static let imperatives: [(polite: String, informal: String)] = [
        ("dikkat edin", "dikkat et"), ("acele edin", "acele et"), ("ateş edin", "ateş et"), ("yardım edin", "yardım et"),
        ("takip edin", "takip et"), ("sessiz olun", "sessiz ol"), ("hazır olun", "hazır ol"), ("sakin olun", "sakin ol"),
        ("bekleyin", "bekle"), ("durun", "dur"), ("gelin", "gel"), ("koşun", "koş"), ("gidin", "git"), ("bakın", "bak"),
        ("dinleyin", "dinle"), ("saklanın", "saklan"), ("kaçın", "kaç"), ("savaşın", "savaş"), ("dövüşün", "dövüş"),
        ("durdurun", "durdur"), ("çekilin", "çekil"), ("eğilin", "eğil"), ("atlayın", "atla"), ("tutun", "tut"),
        ("bırakın", "bırak"), ("söyleyin", "söyle"), ("gösterin", "göster"), ("getirin", "getir"), ("kalkın", "kalk"),
        ("odaklanın", "odaklan"), ("yaklaşın", "yaklaş"), ("uzaklaşın", "uzaklaş"),
    ]
    private static let imperativePatterns: [(NSRegularExpression, String)] = imperatives.map {
        (try! NSRegularExpression(pattern: #"(?<!\p{L})"# + NSRegularExpression.escapedPattern(for: $0.polite) + #"(?=\s*[!.,?…]|\s*$)"#,
                                  options: [.caseInsensitive]), $0.informal)
    }

    /// Bir altyazının cümle çevirileri: herhangi birinde "sen" geçiyorsa (seni, sana…), "siz" geçmeyen cümlelerdeki
    /// bilinen "siz"li emirler "sen"li olur. Başka hiçbir şeye dokunulmaz.
    public static func register(_ translations: [String?]) -> [String?] {
        guard translations.contains(where: { $0.map { containsWord($0, senWords) } ?? false }) else { return translations }
        return translations.map { sentence in
            guard let sentence, !containsWord(sentence, sizWords) else { return sentence }
            return informal(sentence)
        }
    }

    private static func informal(_ sentence: String) -> String {
        var text = sentence
        for (pattern, informal) in imperativePatterns {
            let string = text as NSString
            for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).reversed() {
                let found = string.substring(with: match.range)
                let replacement = found.first!.isUppercase
                    ? String(informal.first!).uppercased(with: TurkishSuffix.turkish) + informal.dropFirst() : informal
                guard let range = Range(match.range, in: text) else { continue }
                text.replaceSubrange(range, with: replacement)
            }
        }
        return text
    }

    private static func containsWord(_ text: String, _ words: Set<String>) -> Bool {
        text.lowercased(with: TurkishSuffix.turkish).split(whereSeparator: { !$0.isLetter }).contains { words.contains(String($0)) }
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}
