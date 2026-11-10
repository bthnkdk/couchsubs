// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// Sözlük terimlerini çeviriden korur (Mac: TermProtection.swift, aynı kurallar). Terim, çeviri öncesinde uydurma bir
/// özel adla ("Zarmon", "Velkor") değiştirilir. Neden ad: OPUS-MT de Apple Translation da özel adı olduğu gibi
/// bırakıp Türkçe ekini kesmeyle ekler ("Zarmon'u al"); "[[1]]", "__T1__" gibi işaretleri ise model sözlüğünde olmadığı
/// için düşürebilir ya da bozabilir (OPUS-MT sözlüğünde "|", "[[" gibi parçalar yok). Çeviriden sonra ad, büyük/küçük
/// harf, boşluk ve kesme farkına bakılmadan bulunur, yerine Türkçe terim konur ve ek terime göre yeniden kurulur
/// (<see cref="TurkishSuffix"/>). Bir ad çeviride yoksa sonuç güvenilmez sayılır (null), çağıran korumasız çeviriye döner.
/// </summary>
public sealed class TermProtector
{
    /// <summary>
    /// Yer tutucu adlar: Türkçe ve İngilizcede sözcük değil, birbirinin başı değil, i/I içermez (Türkçe büyük/küçük harf
    /// dönüşümü bozmasın), ünsüzle biter (yumuşamaz) ve kalın ünlülüdür.
    /// </summary>
    internal static readonly string[] Placeholders = ["Zarmon", "Velkor", "Dorvan", "Kelmar", "Tolvar", "Brandur", "Halvor", "Feldor"];

    private static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");

    private readonly Glossary _glossary;
    private readonly List<string> _free;
    private readonly Dictionary<string, Slot> _byTerm = new(StringComparer.Ordinal);

    /// <summary>Korunan terim: yer tutucusu ve yerine konacak Türkçe.</summary>
    public sealed record Slot(string Placeholder, string English, string Turkish);

    /// <param name="sources">Kaynak metinler; içlerinde geçen yer tutucu ad kullanılmaz.</param>
    public TermProtector(Glossary glossary, params string[] sources)
    {
        _glossary = glossary;
        _free = [.. Placeholders.Where(p => !sources.Any(s => s.Contains(p, StringComparison.OrdinalIgnoreCase)))];
    }

    /// <summary>Bütün yer tutucular (bağlamdakiler dahil); çıktıda beklenmeyen ad kalmasın diye.</summary>
    public IReadOnlyCollection<Slot> AllSlots => _byTerm.Values;

    /// <summary>Terimleri yer tutucularla değiştirir; bu metinde kullanılan yer tutucular döner.</summary>
    public (string Text, IReadOnlyList<Slot> Slots) Protect(string text)
    {
        var matches = _glossary.Find(text);
        if (matches.Count == 0) return (text, []);
        var builder = new StringBuilder(text.Length);
        var used = new List<Slot>();
        var position = 0;
        foreach (var match in matches)
        {
            var key = match.English.ToLowerInvariant();
            if (!_byTerm.TryGetValue(key, out var slot))
            {
                // Ad kalmadıysa geri kalan terimler korunmaz; model onları kendi çevirir.
                if (_free.Count == 0) continue;
                slot = new Slot(_free[0], match.English, match.Turkish);
                _free.RemoveAt(0);
                _byTerm[key] = slot;
            }
            builder.Append(text, position, match.Start - position).Append(slot.Placeholder);
            position = match.Start + match.Length;
            if (!used.Contains(slot)) used.Add(slot);
        }
        builder.Append(text, position, text.Length - position);
        return (builder.ToString(), used);
    }

    /// <summary>
    /// Yer tutucuları Türkçe terimle değiştirir. <paramref name="expected"/> çıktıda en az bir kez geçmeli,
    /// <paramref name="all"/> içindeki diğer adlar hiç geçmemeli; yoksa null.
    /// </summary>
    public static string? Restore(string output, IReadOnlyList<Slot> expected, IReadOnlyCollection<Slot>? all = null,
        char apostrophe = '\'')
    {
        if (expected.Count == 0 && (all is null || all.Count == 0)) return output;
        foreach (var slot in all ?? [])
            if (!expected.Contains(slot) && PlaceholderPattern(slot.Placeholder).IsMatch(output)) return null;
        foreach (var slot in expected)
        {
            var pattern = PlaceholderPattern(slot.Placeholder);
            if (!pattern.IsMatch(output)) return null;
            output = pattern.Replace(output, match =>
            {
                var suffix = match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value;
                var term = TurkishSuffix.Attach(slot.Turkish, suffix, apostrophe);
                return StartsSentence(output, match.Index) ? Capitalize(term) : term;
            });
        }
        return output;
    }

    /// <summary>Yer tutucu ve ardındaki ek: kesmeyle ("Zarmon'a", "Zarmon 'a") ya da bitişik ("Zarmona").</summary>
    private static Regex PlaceholderPattern(string placeholder) =>
        new($@"(?<![\p{{L}}\p{{N}}]){placeholder}(?:\s?['’`´](\p{{L}}+)|(\p{{L}}+))?(?![\p{{L}}\p{{N}}])",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>Metnin ya da cümlenin başı mı (önünde yalnız boşluk, tırnak, tire ya da cümle sonu var).</summary>
    private static bool StartsSentence(string text, int index)
    {
        for (var i = index - 1; i >= 0; i--)
        {
            var c = text[i];
            if (char.IsWhiteSpace(c) || c is '"' or '“' or '\'' or '‘' or '(' or '-' or '–' or '—' or '¡' or '¿') continue;
            return c is '.' or '!' or '?' or '…';
        }
        return true;
    }

    private static string Capitalize(string term) =>
        term.Length == 0 || !char.IsLower(term[0]) ? term : char.ToUpper(term[0], Turkish) + term[1..];
}
