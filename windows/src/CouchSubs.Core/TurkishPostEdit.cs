// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// Cihaz üstü çevirinin Türkçesine yapılan güvenli düzeltmeler (Mac: TurkishPostEdit.swift, aynı kurallar). Yalnız
/// anlamı değiştirmeyen biçim kuralları ve dar bir hitap kuralı vardır:
/// <list type="bullet">
/// <item>noktalamadan önceki boşluk silinir ("Dur !" → "Dur!")</item>
/// <item>kaynağın "!", "?", "?!", "…" sonu korunur (model "Koş!"u "Koş." yapabiliyor)</item>
/// <item>tırnaklar kaynaktaki gibi düz ya da kıvrık olur</item>
/// <item>aynı satırda "sen" ile konuşulurken model emri "siz"li verdiyse ("Sana söyledim. Bekleyin!") bilinen emirler
/// "sen"li olur ("Bekle!"). Yalnız listedeki fiiller, yalnız emir yerindeyse (ardından noktalama gelir) ve cümlede "siz"
/// geçmiyorsa.</item>
/// </list>
/// </summary>
public static partial class TurkishPostEdit
{
    private static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");

    [GeneratedRegex(@"[ \t ]+(?=[,.!?;:…])")]
    private static partial Regex SpaceBeforePunctuation();

    [GeneratedRegex(@"[ \t ]{2,}")]
    private static partial Regex RepeatedSpaces();

    /// <summary>Tek cümlenin çevirisini düzeltir; <paramref name="source"/> İngilizce cümledir.</summary>
    public static string Apply(string source, string translation)
    {
        if (!translation.Any(char.IsLetter)) return translation;
        var text = Quotes(source, translation);
        text = SpaceBeforePunctuation().Replace(text, "");
        text = RepeatedSpaces().Replace(text, " ").Trim();
        return Ending(source, text);
    }

    /// <summary>Kaynağın ünlem/soru/üç nokta sonu çeviride başka bir sonla bittiyse kaynağınki konur.</summary>
    internal static string Ending(string source, string translation)
    {
        var (_, sourceEnd, sourceClosers) = SplitEnd(source);
        if (!IsExpressive(sourceEnd)) return translation;
        var (body, end, closers) = SplitEnd(translation);
        // Kaynakta son noktalama tırnağın içindeyse (He said "Run!") çeviride tırnak sonda olmayabilir; dokunulmaz.
        if ((sourceClosers.Length > 0) != (closers.Length > 0)) return translation;
        if (end == sourceEnd || !(end.Length == 0 || end == "." || IsExpressive(end))) return translation;
        if (!body.Any(char.IsLetter)) return translation;
        return body + sourceEnd + closers;
    }

    private static bool IsExpressive(string end) => end.Length > 0 && (end.Contains('!') || end.Contains('?') || end.Contains('…') || end == "...");

    /// <summary>Metin = gövde + son noktalama (. ! ? …) + kapanış tırnak/parantezleri.</summary>
    private static (string Body, string End, string Closers) SplitEnd(string text)
    {
        text = text.TrimEnd();
        var closerStart = text.Length;
        while (closerStart > 0 && "\"'”’)]»".Contains(text[closerStart - 1])) closerStart--;
        var endStart = closerStart;
        while (endStart > 0 && ".!?…".Contains(text[endStart - 1])) endStart--;
        return (text[..endStart], text[endStart..closerStart], text[closerStart..]);
    }

    /// <summary>Kaynak kıvrık tırnak kullanıyorsa çeviri de kullanır; yoksa düz tırnak.</summary>
    internal static string Quotes(string source, string translation)
    {
        var curlyDouble = source.Contains('“') || source.Contains('”');
        var curlySingle = source.Contains('’') || source.Contains('‘');
        var builder = new StringBuilder(translation.Length);
        for (var i = 0; i < translation.Length; i++)
        {
            var c = translation[i];
            var opening = i == 0 || char.IsWhiteSpace(translation[i - 1]) || "([-–—".Contains(translation[i - 1]);
            builder.Append(c switch
            {
                '“' or '”' or '„' or '‟' when !curlyDouble => '"',
                '"' when curlyDouble => opening ? '“' : '”',
                '’' or '‘' when !curlySingle => '\'',
                '\'' when curlySingle => opening ? '‘' : '’',
                _ => c,
            });
        }
        return builder.ToString();
    }

    /// <summary>Kaynakta kıvrık kesme varsa Türkçe eklerde de o kullanılır.</summary>
    public static char Apostrophe(string source) => source.Contains('’') ? '’' : '\'';

    private static readonly string[] SenWords = ["sen", "seni", "sana", "senin", "sende", "senden", "seninle", "senle"];
    private static readonly string[] SizWords = ["siz", "sizi", "size", "sizin", "sizde", "sizden", "sizinle", "sizler"];

    /// <summary>"Siz"li emir → "sen"li emir; çoğul ya da kibar anlamı da olabilen sözcükler bilerek yok ("Alın" = alın).</summary>
    private static readonly (string Polite, string Informal)[] Imperatives =
    [
        ("dikkat edin", "dikkat et"), ("acele edin", "acele et"), ("ateş edin", "ateş et"), ("yardım edin", "yardım et"),
        ("takip edin", "takip et"), ("sessiz olun", "sessiz ol"), ("hazır olun", "hazır ol"), ("sakin olun", "sakin ol"),
        ("bekleyin", "bekle"), ("durun", "dur"), ("gelin", "gel"), ("koşun", "koş"), ("gidin", "git"), ("bakın", "bak"),
        ("dinleyin", "dinle"), ("saklanın", "saklan"), ("kaçın", "kaç"), ("savaşın", "savaş"), ("dövüşün", "dövüş"),
        ("durdurun", "durdur"), ("çekilin", "çekil"), ("eğilin", "eğil"), ("atlayın", "atla"), ("tutun", "tut"),
        ("bırakın", "bırak"), ("söyleyin", "söyle"), ("gösterin", "göster"), ("getirin", "getir"), ("kalkın", "kalk"),
        ("odaklanın", "odaklan"), ("yaklaşın", "yaklaş"), ("uzaklaşın", "uzaklaş"),
    ];

    /// <summary>
    /// Bir altyazının cümle çevirileri: herhangi birinde "sen" geçiyorsa (seni, sana…), "siz" geçmeyen cümlelerdeki
    /// bilinen "siz"li emirler "sen"li olur. Başka hiçbir şeye dokunulmaz.
    /// </summary>
    public static IReadOnlyList<string?> Register(IReadOnlyList<string?> translations)
    {
        if (!translations.Any(t => t is not null && ContainsWord(t, SenWords))) return translations;
        return [.. translations.Select(t => t is null || ContainsWord(t, SizWords) ? t : Informal(t))];
    }

    private static string Informal(string sentence)
    {
        foreach (var (polite, informal) in Imperatives)
        {
            var pattern = new Regex($@"(?<!\p{{L}}){Regex.Escape(polite)}(?=\s*[!.,?…]|\s*$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            sentence = pattern.Replace(sentence, match =>
                char.IsUpper(match.Value[0]) ? char.ToUpper(informal[0], Turkish) + informal[1..] : informal);
        }
        return sentence;
    }

    private static bool ContainsWord(string text, string[] words)
    {
        foreach (var token in Regex.Split(text.ToLower(Turkish), @"[^\p{L}]+"))
            if (words.Contains(token)) return true;
        return false;
    }
}
