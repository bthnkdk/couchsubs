// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Ücretsiz (cihaz üstü) çevirinin ortak metin hattı (Mac: FreeTranslation.swift, aynı adımlar ve sabitler):
/// büyük harf düzeni → oyun deyimleri → terim koruma → çeviri → terim ve ekleri → Türkçe düzeltmeler.
/// Kısa satır (3 sözcük ve altı: "Boy!", "Do it.", "Not you.") önceki cümleyle birlikte çevrilir; tek başına
/// çevrilince hitap (sen/siz) ve zamirler kayıyordu. Ayraçtan sonrası alınır, ayrım belirsizse satır tek başına çevrilir.
/// </summary>
public static class FreeTranslation
{
    /// <summary>
    /// Çeviri öncesi/sonrası kuralların sürümü; kalıcı önbelleğin motor adına girer. Bu dosyadaki ya da
    /// GameEnglish/SubtitleSegmenter/Glossary/TermProtection/TurkishSuffix/TurkishPostEdit'teki kurallar değişince bir
    /// artırılır: eski kurallarla çevrilmiş satırlar yeniden çevrilir. (1: sürüm yokken.)
    /// </summary>
    public const int PipelineVersion = 2;

    /// <summary>Bu sözcük sayısının altındaki cümle önceki cümleyle birlikte çevrilir.</summary>
    public const int ShortLineWords = 4;

    /// <summary>
    /// Bağlam ile kısa satır arasındaki ayraç. OPUS-MT sözlüğünde "▁***" tek parça (altyazılarda sahne ayracı), "|"
    /// ve "||" hiç yok, satır sonu da SentencePiece'te boşluğa döner; bu yüzden "***".
    /// </summary>
    public const string Separator = " *** ";
    private const string SeparatorCore = "***";

    /// <summary>Önbellek anahtarında bağlam ile satırı ayıran karakter (dosya biçimi değişmez; JSON metni).</summary>
    private const char KeyJoin = '\u001F';

    public static bool IsShort(string sentence) =>
        sentence.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Count(w => w.Any(char.IsLetter)) is > 0 and < ShortLineWords;

    /// <summary>Cümlenin önbellek anahtarı: bağlamla çevrildiyse bağlam da, sözlük terimi içeriyorsa sözlüğün izi de girer.</summary>
    public static string CacheKey(string sentence, string? context, Glossary glossary)
    {
        var basis = context is null ? sentence : context + KeyJoin + sentence;
        return glossary.Matches(basis) ? glossary.Fingerprint + KeyJoin + basis : basis;
    }

    /// <summary>Ayraçtan sonraki kısım; ayraç tam bir kez geçmiyorsa, iki yan da harf içermiyorsa ya da kısım akla yatmayacak kadar uzunsa null.</summary>
    public static string? AfterSeparator(string output, string source)
    {
        var first = output.IndexOf(SeparatorCore, StringComparison.Ordinal);
        if (first < 0 || output.IndexOf(SeparatorCore, first + SeparatorCore.Length, StringComparison.Ordinal) >= 0) return null;
        var before = output[..first];
        var after = output[(first + SeparatorCore.Length)..].Trim();
        // "****" gibi yapışık yıldızlar da belirsizdir.
        if (after.StartsWith('*') || before.EndsWith('*')) return null;
        if (!before.Any(char.IsLetter) || !after.Any(char.IsLetter)) return null;
        if (after.Length > 3 * source.Length + 20) return null;
        return after;
    }

    /// <summary>
    /// Tek cümleyi çevirir. <paramref name="normalize"/> büyük harf düzenini yapar (öğrenilen adlarla),
    /// <paramref name="engine"/> modeldir. Önce bağlamla (verildiyse), olmazsa tek başına, terimler korunamadıysa korumasız çevrilir.
    /// </summary>
    public static string Translate(string sentence, string? context, Glossary glossary, Func<string, string> normalize,
        Func<string, string> engine)
    {
        var apostrophe = TurkishPostEdit.Apostrophe(sentence);
        string Prepare(string text) => GameEnglish.Plain(normalize(text));

        if (context is not null)
        {
            var protector = new TermProtector(glossary, sentence, context);
            var (contextText, _) = protector.Protect(Prepare(context));
            var (sentenceText, slots) = protector.Protect(Prepare(sentence));
            var output = engine(contextText + Separator + sentenceText);
            if (AfterSeparator(output, sentence) is { } after &&
                TermProtector.Restore(after, slots, protector.AllSlots, apostrophe) is { } restored)
                return TurkishPostEdit.Apply(sentence, restored);
        }

        var single = new TermProtector(glossary, sentence);
        var (input, used) = single.Protect(Prepare(sentence));
        var translated = engine(input);
        if (used.Count == 0) return TurkishPostEdit.Apply(sentence, translated);
        if (TermProtector.Restore(translated, used, single.AllSlots, apostrophe) is { } done) return TurkishPostEdit.Apply(sentence, done);
        // Model bir yer tutucuyu düşürdü: terimsiz ama eksiksiz çeviri, eksik terimli çeviriden iyidir.
        return TurkishPostEdit.Apply(sentence, engine(Prepare(sentence)));
    }
}

/// <summary>
/// Son gösterilen satırlar: kısa satırın bağlamı (DeepL'in bağlam satırlarıyla aynı düzen). Aynı satır yeniden
/// okunursa aynı bağlam döner (çeviri ekranda değişmesin); bağlam satırı çok önce gösterildiyse bağlam yoktur.
/// </summary>
public sealed class RecentLines
{
    public static readonly TimeSpan MaxAge = TimeSpan.FromSeconds(20);

    private readonly Func<DateTimeOffset> _clock;
    private readonly object _gate = new();
    private (string Text, string? Context, DateTimeOffset Seen)? _last;

    public RecentLines(Func<DateTimeOffset>? clock = null) => _clock = clock ?? (() => DateTimeOffset.UtcNow);

    /// <summary>Satırın gösterildiğini kaydeder; bu satırdan önce gösterilen satırı döner (yoksa null).</summary>
    public string? Shown(string text)
    {
        lock (_gate)
        {
            var now = _clock();
            if (_last is { } last && last.Text == text)
            {
                _last = (text, last.Context, now);
                return last.Context;
            }
            var context = _last is { } previous && now - previous.Seen <= MaxAge ? previous.Text : null;
            _last = (text, context, now);
            return context;
        }
    }
}
