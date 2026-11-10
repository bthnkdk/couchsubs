// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Text;

namespace CouchSubs.Core;

/// <summary>OCR çıktılarını karşılaştırmak için sadeleştirme ve gürültüye dayanıklı benzerlik.</summary>
public static class TextMatch
{
    /// <summary>Küçük harf, yalnız harf/rakam, tek boşluk.</summary>
    public static string Normalize(string s)
    {
        var builder = new StringBuilder(s.Length);
        foreach (var c in s.ToLowerInvariant())
            builder.Append(IsAlphanumeric(c) ? c : ' ');
        return string.Join(' ', builder.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>Levenshtein oranı <paramref name="threshold"/> ve üstündeyse benzer sayılır. Boş metin hiçbir metne benzemez.</summary>
    public static bool IsSimilar(string a, string b, double threshold = 0.85)
    {
        if (a == b) return a.Length > 0;
        if (a.Length == 0 || b.Length == 0) return false;
        var previous = new int[b.Length + 1];
        var row = new int[b.Length + 1];
        for (var j = 0; j <= b.Length; j++) previous[j] = j;
        for (var i = 1; i <= a.Length; i++)
        {
            row[0] = i;
            for (var j = 1; j <= b.Length; j++)
                row[j] = Math.Min(Math.Min(previous[j] + 1, row[j - 1] + 1), previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
            (previous, row) = (row, previous);
        }
        return 1 - (double)previous[b.Length] / Math.Max(a.Length, b.Length) >= threshold;
    }

    /// <summary>Satırları ayrı ayrı sadeleştirip alt alta birleştirir; <see cref="IsSameSubtitle"/> kaçırılan satırı bundan anlar.</summary>
    public static string NormalizeRows(string s) =>
        string.Join('\n', s.Replace("\r\n", "\n").Split('\n').Select(Normalize).Where(row => row.Length > 0));

    /// <summary>
    /// Yeni okuma, gönderilmiş altyazının yeniden okuması mı (sadeleştirilmiş metinler; <paramref name="sent"/> satırları
    /// <see cref="NormalizeRows"/> ile alt alta verilebilir). Süslü yazı tipinde ya da solarken OCR bir iki sözcüğü her
    /// karede başka çöpe çevirir ("ou$3e", "waters2aljd") ya da iki satırlık altyazının bir satırını kaçırır; karakter
    /// benzerliği düşse de sözcükler aynı kalır. Rakam karışmış sözcükler ve tek harfler çöp sayılıp karşılaştırmaya girmez.
    /// Başına ya da sonuna sözcük eklenmiş metin (daktilo efekti, "Nereye gidiyorsun?" / "Nereye gidiyorsun evlat?") yenidir;
    /// sondan kısalmış metin ise ancak tam bir satırı eksikse aynı altyazıdır.
    /// </summary>
    public static bool IsSameSubtitle(string reread, string sent)
    {
        var rows = sent.Split('\n');
        var flat = string.Join(' ', rows);
        var x = CleanWords(reread);
        var y = CleanWords(flat);
        // Uzayan metin (daktilo efekti ya da aynı sözlerle başlayan yeni satır) karakterce benzese de yenidir.
        if (y.Count > 0 && x.Count > y.Count && (StartsWith(x, y) || EndsWith(x, y))) return false;
        if (IsSimilar(reread, flat)) return true;
        // Baştan ya da sondan kesilmiş okuma: altyazının yalnız tam satırları okunduysa aynıdır, yoksa başka bir cümledir.
        if (x.Count > 0 && x.Count < y.Count && (StartsWith(y, x) || EndsWith(y, x)))
            return IsWholeRows(x.Count, rows, StartsWith(y, x));
        var remaining = new List<string>(y);
        var sentCount = remaining.Count;
        var shared = 0;
        foreach (var word in x)
            if (remaining.Remove(word)) shared++;
        // Arasından çöp sözcükler düşmüş okuma: yeni okumanın sözcüklerinin hemen hepsi gönderilende var.
        if (x.Count >= 4 && x.Count <= sentCount && shared >= x.Count * 0.85) return true;
        // Kısa satırda tek sözcük anlamı değiştirir ("where is the boy" / "ship"); orada yalnız karakter benzerliği geçerli.
        int longer = Math.Max(x.Count, sentCount), shorter = Math.Min(x.Count, sentCount);
        if (shorter < 6 || (double)shorter / longer < 0.75) return false;
        return (double)shared / longer >= 0.75;
    }

    private static bool StartsWith(List<string> words, List<string> part) => words.Take(part.Count).SequenceEqual(part);

    private static bool EndsWith(List<string> words, List<string> part) => words.Skip(words.Count - part.Count).SequenceEqual(part);

    /// <summary>Baştan (ya da sondan) <paramref name="count"/> sözcük tam satırlara denk geliyor mu.</summary>
    private static bool IsWholeRows(int count, string[] rows, bool fromStart)
    {
        var total = 0;
        foreach (var row in fromStart ? rows : Enumerable.Reverse(rows))
        {
            total += CleanWords(row).Count;
            if (total == count) return true;
            if (total > count) return false;
        }
        return false;
    }

    // Tek harfler ("a", "I" ya da OCR'ın uydurduğu "O") karşılaştırmaya bir şey katmaz.
    private static List<string> CleanWords(string normalized) =>
        normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(w => w.Length > 1 && !w.Any(char.IsNumber)).ToList();

    private static bool IsAlphanumeric(char c) => char.GetUnicodeCategory(c) switch
    {
        UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
            or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter
            or UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark
            or UnicodeCategory.DecimalDigitNumber or UnicodeCategory.LetterNumber or UnicodeCategory.OtherNumber => true,
        _ => false,
    };
}
