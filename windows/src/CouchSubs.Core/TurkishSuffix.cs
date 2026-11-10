// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Text;

namespace CouchSubs.Core;

/// <summary>
/// Sözlük teriminin Türkçe eki (Mac: TurkishSuffix.swift, aynı kurallar). Çeviri motoru terimin yerindeki yer tutucu
/// ada bir ek koyar ("Zarmon'a", "Zarmon'un", "Zarmon'da"); ek, hangi hâl olduğu korunarak gerçek terime göre
/// yeniden kurulur:
/// <list type="bullet">
/// <item>ünlü uyumu: Kratos'u, Midgard'ı, Freya'yı; Atreus'un, Midgard'ın</item>
/// <item>kaynaştırma: ünlüyle biten terime y / n gelir (Freya'ya, Freya'nın)</item>
/// <item>ünsüz benzeşmesi: sert ünsüzden sonra -da/-dan → -ta/-tan (Kratos'ta)</item>
/// <item>özel ad (büyük harfle başlayan terim) kesmeyle ayrılır; cins ad bitişik yazılır, p/ç/k yumuşar (kılıcı)</item>
/// <item>çok sözcüklü ve dar ünlüyle biten terim tamlama sayılır: hâl ekinden önce n gelir (Leviathan Baltası'nı)</item>
/// </list>
/// </summary>
public static class TurkishSuffix
{
    private static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");
    private const string Vowels = "aeıioöuü";
    private const string BackVowels = "aıou";
    private const string RoundedVowels = "ouöü";
    private const string HighVowels = "ıiuü";
    private const string VoicelessConsonants = "fstkçşhp";
    /// <summary>Daha uzun "ek" büyük olasılıkla ek değildir; dokunulmaz.</summary>
    private const int MaxSuffixLength = 12;

    /// <summary>
    /// <paramref name="term"/> + ek. <paramref name="suffix"/> motorun yer tutucuya koyduğu ektir (kesmesiz, "a", "un",
    /// "ya", "dan"); boşsa terim döner.
    /// </summary>
    public static string Attach(string term, string suffix, char apostrophe = '\'')
    {
        if (term.Length == 0 || suffix.Length == 0) return term;
        var body = suffix.ToLower(Turkish);
        if (body.Length > MaxSuffixLength || !body.All(c => char.IsLetter(c))) return term + apostrophe + suffix;

        var proper = char.IsUpper(term[0]);
        var lastWord = term[(term.LastIndexOf(' ') + 1)..].ToLower(Turkish);
        var lastLetter = lastWord.LastOrDefault(char.IsLetter);
        var lastVowel = lastWord.LastOrDefault(IsVowel);
        // Ünlüsüz kısaltma ("XP", "HP") harf adlarıyla okunur: "iks-pe" → ince, ünlüyle biter.
        var endsWithVowel = lastVowel == default || IsVowel(lastLetter);
        if (lastVowel == default) lastVowel = 'e';
        var compound = term.Contains(' ') && HighVowels.Contains(lastLetter) && lastWord.Length >= 3;
        var voiceless = !endsWithVowel && VoicelessConsonants.Contains(lastLetter);

        // Baştaki kaynaştırma harfi yer tutucuya göreydi ("Zarmon" ünsüzle biter, çoğu zaman yoktur); atılır.
        if (body.Length >= 2 && body[0] == 'y' && (IsVowel(body[1]) || body[1] == 'l')) body = body[1..];
        else if (body.Length >= 3 && body[0] == 'n' && HighVowels.Contains(body[1]) && body[2] == 'n') body = body[1..];

        var genitive = body.Length >= 2 && HighVowels.Contains(body[0]) && body[1] == 'n' && (body.Length == 2 || !IsVowel(body[2]));
        var instrumental = body.Length >= 2 && body[0] == 'l' && body[1] is 'a' or 'e' && !(body.Length >= 3 && body[2] == 'r');
        var buffer = "";
        if (IsVowel(body[0]))
        {
            if (compound || (endsWithVowel && genitive)) buffer = "n";
            else if (endsWithVowel) buffer = "y";
        }
        else if (body[0] is 'd' or 't')
        {
            if (compound) buffer = "n";
            body = ((compound || !voiceless) ? 'd' : 't') + body[1..];
        }
        else if (instrumental && (endsWithVowel || compound))
        {
            buffer = "y";
        }

        var harmonized = Harmonize(body, lastVowel);
        if (proper) return term + apostrophe + buffer + harmonized;
        var stem = buffer.Length == 0 && IsVowel(harmonized[0]) ? Soften(term) : term;
        return stem + buffer + harmonized;
    }

    /// <summary>Ekteki a/e ve ı/i/u/ü ünlülerini önceki ünlüye uydurur; "-ki" (Midgard'daki) değişmez.</summary>
    internal static string Harmonize(string body, char lastVowel)
    {
        var output = new StringBuilder(body.Length);
        var previous = lastVowel;
        for (var i = 0; i < body.Length; i++)
        {
            var c = body[i];
            var invariantKi = c == 'i' && i > 0 && body[i - 1] == 'k' && i == body.Length - 1;
            if (!invariantKi && "ae".Contains(c)) c = BackVowels.Contains(previous) ? 'a' : 'e';
            else if (!invariantKi && HighVowels.Contains(c))
            {
                var back = BackVowels.Contains(previous);
                var rounded = RoundedVowels.Contains(previous);
                c = back ? (rounded ? 'u' : 'ı') : (rounded ? 'ü' : 'i');
            }
            if (IsVowel(c)) previous = c;
            output.Append(c);
        }
        return output.ToString();
    }

    /// <summary>
    /// Cins adın son p/ç/k'si ünlüyle başlayan ekten önce yumuşar (kitap → kitabı, kılıç → kılıcı, bıçak → bıçağı,
    /// renk → rengi). Tek heceli sözcükler yumuşamaz (top → topu); t çoğu sözcükte yumuşamadığı için dokunulmaz.
    /// </summary>
    internal static string Soften(string term)
    {
        if (term.Length < 2) return term;
        var last = term[^1];
        var lower = term.ToLower(Turkish);
        var word = lower[(lower.LastIndexOf(' ') + 1)..];
        if (word.EndsWith("nk", StringComparison.Ordinal)) return term[..^1] + "g";
        if (word.Count(IsVowel) < 2) return term;
        return last switch
        {
            'p' => term[..^1] + "b",
            'ç' => term[..^1] + "c",
            'k' => term[..^1] + "ğ",
            _ => term,
        };
    }

    internal static bool IsVowel(char c) => Vowels.Contains(c);
}
