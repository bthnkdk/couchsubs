// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Kalıcı çeviri önbelleği (Mac: TranslationCacheTests ile aynı durumlar).</summary>
public sealed class TranslationCacheTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "couchsubs-cache-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { Directory.Delete(_directory, recursive: true); } catch (DirectoryNotFoundException) { }
    }

    private string FileOf(string engine = "deepl") => TranslationCache.FileFor(_directory, engine, "en", "tr");

    private static string? Get(TranslationCache cache, string key) => cache.TryGet(key, out var value) ? value : null;

    [Fact]
    public void TranslationsSurviveRestart()
    {
        var first = new TranslationCache(FileOf());
        first.Store("Close the door.", "Kapıyı kapat.");
        first.Store("ATREUS: Father!", "ATREUS: Baba!");

        var second = new TranslationCache(FileOf());
        Assert.Equal("Kapıyı kapat.", Get(second, "Close the door."));
        Assert.Equal("ATREUS: Baba!", Get(second, "ATREUS: Father!"));
        Assert.Null(Get(second, "Run!"));
    }

    [Fact]
    public void EnginesHaveSeparateFiles()
    {
        new TranslationCache(FileOf("deepl")).Store("Run!", "DeepL çevirisi");
        Assert.Null(Get(new TranslationCache(FileOf("opus-mt")), "Run!"));
        Assert.Equal("v1-opus_mt-en-tr.jsonl", Path.GetFileName(FileOf("opus-mt")));
    }

    [Fact]
    public void LinesWithQuotesAndNewlinesRoundTrip()
    {
        const string source = "KRATOS: \"Boy.\"\nATREUS: Yes?";
        new TranslationCache(FileOf()).Store(source, "KRATOS: \"Evlat.\"\nATREUS: Evet?");
        Assert.Equal("KRATOS: \"Evlat.\"\nATREUS: Evet?", Get(new TranslationCache(FileOf()), source));
    }

    [Fact]
    public void LeastRecentlyUsedEntriesAreDropped()
    {
        var cache = new TranslationCache(FileOf(), limit: 10);
        for (var i = 0; i < 10; i++) cache.Store($"s{i}", $"t{i}");
        // s0 yeni kullanıldı; atılan en eskiler s1 ve sonrası olur.
        Assert.Equal("t0", Get(cache, "s0"));
        cache.Store("s10", "t10");
        Assert.True(cache.Count <= 10);
        Assert.Equal("t0", Get(cache, "s0"));
        Assert.Null(Get(cache, "s1"));
        Assert.Equal("t10", Get(cache, "s10"));
    }

    [Fact]
    public void FileIsCompactedWhenItGrows()
    {
        var cache = new TranslationCache(FileOf(), limit: 5);
        for (var round = 0; round < 6; round++)
            for (var i = 0; i < 5; i++) cache.Store($"s{i}", $"t{i}-{round}");
        Assert.True(File.ReadAllLines(FileOf()).Length <= 10);
        Assert.Equal("t3-5", Get(new TranslationCache(FileOf(), limit: 5), "s3"));
    }

    [Fact]
    public void BrokenLinesAreSkipped()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllText(FileOf(), "[\"Run!\",\"Koş!\"]\nnot json\n[\"only one\"]\n");
        var cache = new TranslationCache(FileOf());
        Assert.Equal("Koş!", Get(cache, "Run!"));
        Assert.Equal(1, cache.Count);
    }

    /// <summary>Mac'in yazdığı (Türkçe harfleri kaçışsız) satırlar da okunur.</summary>
    [Fact]
    public void ReadsMacFormattedLines()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllText(FileOf(), "[\"Who are you?\",\"Sen de kimsin?\"]\n[\"Run!\",\"Koş!\"]\n");
        Assert.Equal("Koş!", Get(new TranslationCache(FileOf()), "Run!"));
    }

    [Fact]
    public void EmptyValuesAreNotStored()
    {
        var cache = new TranslationCache(FileOf());
        cache.Store("Run!", "");
        Assert.Null(Get(cache, "Run!"));
        Assert.False(File.Exists(FileOf()));
    }

    [Fact]
    public void MemoryOnlyCacheWorksWithoutFile()
    {
        var cache = new TranslationCache();
        cache.Store("Run!", "Koş!");
        Assert.Equal("Koş!", Get(cache, "Run!"));
    }

    [Fact]
    public void SharedReturnsOneCachePerFile()
    {
        var a = TranslationCache.Shared(_directory, "opus-mt", "en", "tr");
        Assert.Same(a, TranslationCache.Shared(_directory, "opus-mt", "en", "tr"));
        Assert.NotSame(a, TranslationCache.Shared(_directory, "deepl", "en", "tr"));
    }
}
