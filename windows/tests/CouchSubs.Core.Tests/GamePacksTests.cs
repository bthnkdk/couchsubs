// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace CouchSubs.Core.Tests;

/// <summary>Mac ile ortak deneme dosyaları: core/Tests/CouchSubsCoreTests/Fixtures.</summary>
internal static class PackFixtures
{
    public static string Path(string name, [CallerFilePath] string source = "") =>
        System.IO.Path.GetFullPath(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(source)!, "..", "..", "..",
            "core", "Tests", "CouchSubsCoreTests", "Fixtures", name));

    public static string TemporaryDirectory()
    {
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "packs-" + Guid.NewGuid());
        Directory.CreateDirectory(path);
        return path;
    }
}

public class PackKeyTests
{
    private sealed record Vector(string input, string canon, string key);

    /// <summary>Mac ve paket hazırlayan Python betiği (canon.py) ile aynı sonuç: Fixtures/golden-vectors.json.</summary>
    [Fact]
    public void GoldenVectors()
    {
        var vectors = JsonSerializer.Deserialize<List<Vector>>(File.ReadAllText(PackFixtures.Path("golden-vectors.json")))!;
        Assert.Equal(15, vectors.Count);
        foreach (var vector in vectors)
        {
            Assert.Equal(vector.canon, PackKey.Canon(vector.input));
            Assert.Equal(vector.key, PackKey.Key(vector.input) ?? "");
        }
    }

    [Fact]
    public void TagsLongerThanFortyCharactersStay()
    {
        Assert.Equal("a   c", PackKey.StripTags("a <b> c"));
        var tooLong = "<" + new string('x', 41) + ">";
        Assert.Equal(tooLong, PackKey.StripTags(tooLong));
        Assert.Equal(" ", PackKey.StripTags("<" + new string('x', 40) + ">"));
        Assert.Equal("a < b   c", PackKey.StripTags("a < b <i> c"));
        Assert.Equal("< >", PackKey.StripTags("<<b>>"));
    }
}

public class GamePackTests
{
    private static GamePack Load(string name) => GamePack.Decode(File.ReadAllBytes(PackFixtures.Path(name)), name.Replace(".json.gz", ""));

    [Fact]
    public void WrappedAndBareFormatsLoad()
    {
        var wrapped = Load("pack-wrapped.json.gz");
        Assert.Equal("test-game", wrapped.Id);
        Assert.Equal("Test Game", wrapped.Title);
        Assert.Equal(5, wrapped.Entries.Count);
        var bare = Load("pack-bare.json.gz");
        Assert.Equal("pack-bare", bare.Id);
        Assert.Equal("pack-bare", bare.Title);
        Assert.Equal(2, bare.Entries.Count);
    }

    [Fact]
    public void PlainJsonIsAccepted()
    {
        var key = PackKey.Key("Get back!")!;
        var pack = GamePack.Decode(Encoding.UTF8.GetBytes($"{{\"{key}\": \"Geri çekil!\"}}"), "plain");
        Assert.Equal("Geri çekil!", pack.Entries[PackKey.Number(key)!.Value]);
    }

    [Fact]
    public void BrokenFilesAreRejected()
    {
        Assert.Throws<InvalidDataException>(() => GamePack.Decode(Encoding.UTF8.GetBytes("not json"), "x"));
        Assert.Throws<InvalidDataException>(() => GamePack.Decode([0x1f, 0x8b, 8, 0, .. Enumerable.Repeat((byte)7, 30)], "x"));
        Assert.Throws<InvalidDataException>(() => GamePack.Decode(Encoding.UTF8.GetBytes("{\"format\":2,\"entries\":{\"0123456789abcdef\":\"x\"}}"), "x"));
        Assert.Throws<InvalidDataException>(() => GamePack.Decode(Encoding.UTF8.GetBytes("{\"bad\":\"x\"}"), "x"));
    }

    /// <summary>Paketteki Türkçede kalan biçim etiketleri TV'ye gitmez.</summary>
    [Fact]
    public void TagsAreRemovedFromTurkish()
    {
        var pack = Load("pack-wrapped.json.gz");
        var key = PackKey.Number(PackKey.Key("<b><h>SCANNATURI SPECIALE</></> KNIFE")!)!.Value;
        Assert.Equal("SCANNATURI SPECIALE BIÇAĞI", pack.Entries[key]);
    }

    [Fact]
    public void LibraryMergesBundledAndUserPacks()
    {
        var user = PackFixtures.TemporaryDirectory();
        IEnumerable<(string, byte[])> Bundled() =>
        [
            ("a.json.gz", File.ReadAllBytes(PackFixtures.Path("pack-bare.json.gz"))),
            ("b.json.gz", File.ReadAllBytes(PackFixtures.Path("pack-wrapped.json.gz"))),
            ("c.json.gz", Encoding.UTF8.GetBytes("bozuk")),
        ];
        var library = new GamePackLibrary(Bundled, user);
        Assert.Equal(["a", "Test Game"], library.Packs.Select(p => p.Title));
        Assert.Equal([2, 5], library.Packs.Select(p => p.Entries));
        // Aynı anahtarda sonraki paket kazanır.
        Assert.Equal("Yere yat!", library.Find("Get Down!"));
        Assert.Equal("Geri çekil!", library.Find("Get back!"));

        // Kullanıcının klasöründeki aynı kimlikli paket uygulamanınkinin yerine geçer ve sonra okunur.
        var key = PackKey.Key("Get Down!");
        File.WriteAllText(Path.Combine(user, "test.json"), $"{{\"format\":1,\"id\":\"test-game\",\"title\":\"Test Game 2\",\"entries\":{{\"{key}\":\"Yat yere!\"}}}}");
        library.Reload();
        Assert.Equal(["a", "Test Game 2"], library.Packs.Select(p => p.Title));
        Assert.Equal([true, false], library.Packs.Select(p => p.BuiltIn));
        Assert.Equal("Yat yere!", library.Find("Get Down!"));
        Assert.Null(library.Find("Who is that?"));
    }

    [Fact]
    public void MissingDirectoriesGiveAnEmptyLibrary()
    {
        var library = new GamePackLibrary(null, Path.Combine(Path.GetTempPath(), "yok-" + Guid.NewGuid()));
        Assert.Empty(library.Packs);
        Assert.Null(library.Find("Get Down!"));
    }

    /// <summary>Uygulamaya gömülü paketler (ilki Mafia: The Old Country, 18 binden çok satır) yüklenir ve hızlı aranır.</summary>
    [Fact]
    public void EmbeddedPacksLoad()
    {
        var before = GC.GetTotalMemory(true);
        var watch = Stopwatch.StartNew();
        var library = new GamePackLibrary(GamePackLibrary.EmbeddedPacks, null);
        var mafia = library.Packs.Single(pack => pack.Id == "mafia-the-old-country");
        watch.Stop();
        var memory = GC.GetTotalMemory(true) - before;
        Console.WriteLine($"paket yükleme: {watch.ElapsedMilliseconds} ms, bellek: {memory / 1024} KB");
        Assert.Equal("Mafia: The Old Country", mafia.Title);
        Assert.True(mafia.Entries > 18000);
        Assert.True(mafia.BuiltIn);
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(2));
        Assert.Equal("Şimdi ayvayı yedin, evlat!", library.Find("You fucked up now, boy!"));
        Assert.Equal("Annesi vefat etti.", library.Find("It’s his mother, she passed."));
        Assert.Equal("Yere yat!", library.Find("Get Down!"));
        GC.KeepAlive(library);
    }
}
