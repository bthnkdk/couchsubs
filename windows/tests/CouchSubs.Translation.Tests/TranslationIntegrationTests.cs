// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using CouchSubs.Core;
using Xunit.Abstractions;

namespace CouchSubs.Translation.Tests;

/// <summary>Gerçek modeli bir kez yükler; yükleme süresi ve bellek raporlanır.</summary>
public sealed class LoadedTranslator : IDisposable
{
    public MarianTranslator? Translator { get; }
    public TimeSpan LoadTime { get; }
    public long WorkingSetBytes { get; }

    public LoadedTranslator()
    {
        if (!TestModels.ModelAvailable) return;
        var watch = Stopwatch.StartNew();
        Translator = new MarianTranslator(TestModels.Directory);
        Translator.WarmUpAsync().GetAwaiter().GetResult();
        LoadTime = watch.Elapsed;
        WorkingSetBytes = Process.GetCurrentProcess().WorkingSet64;
    }

    public void Dispose() => Translator?.Dispose();
}

public sealed class TranslationIntegrationTests(LoadedTranslator loaded, ITestOutputHelper output)
    : IClassFixture<LoadedTranslator>
{
    private MarianTranslator Translator => loaded.Translator!;

    public static TheoryData<string, string> GameLines => new()
    {
        // Girdi, çevirinin içermesi gereken parça (birebir eşitlik, ORT sürümü/işlemci farkında kırılgan olurdu).
        { "We do not have time for this, boy.", "zaman" },
        { "Wait!", "!" },
        { "Who are you?", "Kim" },
        { "The gate will not hold much longer.", "dayan" },
        { "ATREUS: Father, look over there!", "ATREUS: Baba" },
        { "I know…", "Biliyorum" },
        { "Kratos.", "Kratos." },
        { "Boy! Focus. The draugr are still coming.", "Evlat!" },
        { "Mimir, how much farther?\nNot far now, brother.", "kardeş" },
        { "What is that? It looks like a door.", "Kapı" },
        { "THE GATE WILL NOT HOLD MUCH LONGER.", "dayan" },
        // Oyun ifadeleri (GameEnglish) ve ışın araması: açgözlü çözme bunları "dost canlısı", "Altını aldım" diye çeviriyordu.
        { "Hold your fire! They're friendlies!", "müttefik" },
        { "I've got your six.", "Arka" },
        { "Stay close. Something's not right about this place.", "terslik" },
    };

    [ModelTheory]
    [MemberData(nameof(GameLines))]
    public async Task TranslatesGameLines(string source, string expectedFragment)
    {
        var watch = Stopwatch.StartNew();
        var translated = await Translator.TranslateAsync(source);
        var elapsed = watch.Elapsed.TotalMilliseconds;
        output.WriteLine($"{elapsed,6:F0} ms  {source.Replace("\n", " / ")}  =>  {translated.Replace("\n", " / ")}");
        Assert.Contains(expectedFragment, translated);
    }

    [ModelFact]
    public async Task TypicalLineIsFastAfterWarmUp()
    {
        string[] lines =
        [
            "We do not have time for this, boy.", "Wait!", "Who are you?", "The gate will not hold much longer.",
            "ATREUS: Father, look over there!", "I know…", "Kratos.", "Stay close. The path ahead is dangerous.",
            "You should not have come here.", "I can't let you do that. Not again.",
        ];
        // Ortak çeviricinin önbelleği ölçümü bozmasın diye ayrı örnek.
        var load = Stopwatch.StartNew();
        using var translator = new MarianTranslator(TestModels.Directory);
        await translator.WarmUpAsync();
        var loadTime = load.Elapsed.TotalMilliseconds;

        var timings = new List<double>();
        foreach (var line in lines)
        {
            var watch = Stopwatch.StartNew();
            var translated = await translator.TranslateAsync(line);
            timings.Add(watch.Elapsed.TotalMilliseconds);
            output.WriteLine($"{timings[^1],6:F0} ms  {line}  =>  {translated}");
        }
        timings.Sort();
        var median = timings[timings.Count / 2];
        output.WriteLine($"median {median:F0} ms, max {timings[^1]:F0} ms; load+warm-up {loadTime:F0} ms; " +
                         $"working set {Process.GetCurrentProcess().WorkingSet64 / 1_048_576} MB " +
                         $"(fixture: load {loaded.LoadTime.TotalMilliseconds:F0} ms, {loaded.WorkingSetBytes / 1_048_576} MB)");
        // Hedef 300 ms; yavaş CI makinesine pay bırakılır, gerçek değer çıktıda.
        Assert.InRange(median, 0, 1000);
    }

    /// <summary>Terim yer tutucusu ve kısa satır ayracı gerçek modelden geçer (model yoksa atlanır).</summary>
    [ModelFact]
    public async Task GlossaryTermsAndShortLineContextSurviveTheModel()
    {
        var directory = Path.Combine(Path.GetTempPath(), "couchsubs-glossary-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            File.WriteAllText(Path.Combine(directory, "gow.json"),
                """{ "terms": { "Leviathan Axe": "Leviathan Baltası" }, "keep": ["Kratos", "Atreus"] }""");
            using var translator = new MarianTranslator(TestModels.Directory, glossary: new GlossaryStore(directory));
            var axe = await translator.TranslateAsync("Kratos, throw the Leviathan Axe!");
            output.WriteLine(axe);
            Assert.Contains("Leviathan Baltası", axe);
            Assert.Contains("Kratos", axe);
            await translator.TranslateAsync("Where is your mother, Atreus?");
            var shortLine = await translator.TranslateAsync("Not you.");
            output.WriteLine(shortLine);
            Assert.DoesNotContain("*", shortLine);
            Assert.DoesNotContain("Zarmon", shortLine);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [ModelFact]
    public async Task CachedLineReturnsImmediately()
    {
        var first = await Translator.TranslateAsync("The gate will not hold much longer!");
        // Önbellekteki satır modele hiç gitmez, sonuç çağrı döndüğünde hazırdır (süre ölçümü yoğun makinede yanıltıyordu).
        var cached = Translator.TranslateAsync("The gate will not hold much longer!");
        Assert.True(cached.IsCompletedSuccessfully);
        Assert.Equal(first, await cached);
    }

    [ModelFact]
    public async Task ConcurrentCallsMatchSequentialResults()
    {
        // Dört sözcük ve üstü: kısa satır önceki satırla çevrilir, paralel sırada bağlamı değişirdi.
        string[] lines = ["Run, now, run now!", "Where is the boat?", "Follow me now, brother.", "This is not over.",
            "Hold the line, everyone!", "Over here, quickly, come!"];
        var parallel = await Task.WhenAll(lines.Select(l => Task.Run(() => Translator.TranslateAsync(l))));

        using var fresh = new MarianTranslator(TestModels.Directory);
        foreach (var (line, result) in lines.Zip(parallel))
            Assert.Equal(await fresh.TranslateAsync(line), result);
    }
}

public sealed class ModelTheoryAttribute : TheoryAttribute
{
    public ModelTheoryAttribute()
    {
        if (!TestModels.ModelAvailable)
            Skip = $"Translation model not found in {TestModels.Directory} (set COUCHSUBS_DOWNLOAD_TEST_MODELS=1)";
    }
}
