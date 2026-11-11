// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Translation.Tests;

/// <summary>Mac'teki PackLookupTests ile aynı durumlar.</summary>
public class PackLookupTests
{
    private static readonly Dictionary<string, string> Pack = new()
    {
        [PackKey.Key("Get Down!")!] = "Yere yat!",
        [PackKey.Key("Who is that?")!] = "O da kim?",
        [PackKey.Key("Don Torrisi wants you.")!] = "Don Torrisi seni istiyor.",
        [PackKey.Key("Get back!")!] = "Geri çekil!",
    };

    private static PackMatch? Match(string text) =>
        PackLookup.Match(text, line => PackKey.Key(line) is { } key ? Pack.GetValueOrDefault(key) : null);

    [Fact]
    public void WholeLineIgnoresCaseSpacingAndPunctuation()
    {
        Assert.Equal("Yere yat!", Match("GET DOWN!!")?.Text);
        Assert.Equal("O da kim?", Match("  Who   is\nthat?  ")?.Text);
        Assert.Null(Match("Get out!"));
        Assert.Null(Match(""));
    }

    [Fact]
    public void SpeakerLabelIsKeptAndVoiced()
    {
        var found = Match("ENZO: Don Torrisi wants you.");
        Assert.Equal("ENZO: Don Torrisi seni istiyor.", found?.Text);
        Assert.Equal([new SpokenLine("Don Torrisi wants you.", "Don Torrisi seni istiyor.", "ENZO")], found!.Spoken);
        Assert.Equal("Cesare: Yere yat!", Match("Cesare: Get down!")?.Text);
        Assert.Null(Match("ENZO: Get out!"));
    }

    [Fact]
    public void EachLineIsLookedUpWhenTheWholeIsMissing()
    {
        Assert.Equal("ENZO: Yere yat!\nMARIA: O da kim?", Match("ENZO: Get down!\nMARIA: Who is that?")?.Text);
        Assert.Equal("- Yere yat!\n- O da kim?", Match("- Get down!\n- Who is that?")?.Text);
        // Bir satır bile eksikse paket kullanılmaz.
        Assert.Null(Match("Get down!\nWho are you?"));
    }

    [Fact]
    public void EachSentenceIsLookedUpWhenTheLineIsMissing()
    {
        var found = Match("ENZO: Get down! Who is that?");
        Assert.Equal("ENZO: Yere yat! O da kim?", found?.Text);
        Assert.Equal(["ENZO", "ENZO"], found!.Spoken.Select(line => line.Speaker));
        Assert.Equal("Yere yat! Geri çekil!", Match("Get down! Get back!")?.Text);
        Assert.Null(Match("Get down! Who are you?"));
    }

    [Fact]
    public void WholeLineWinsOverParts()
    {
        var custom = new Dictionary<string, string> { [PackKey.Key("Get down! Get back!")!] = "Eğil ve geri çekil!", [PackKey.Key("Get Down!")!] = "Yere yat!" };
        var found = PackLookup.Match("Get down! Get back!", line => PackKey.Key(line) is { } key ? custom.GetValueOrDefault(key) : null);
        Assert.Equal("Eğil ve geri çekil!", found?.Text);
    }

    /// <summary>Uygulamayla gelen Mafia paketinde konuşmacılı ve iki satırlı arama.</summary>
    [Fact]
    public void BundledPackIsSearched()
    {
        var library = new GamePackLibrary(GamePackLibrary.EmbeddedPacks, null);
        Assert.Equal("MARIA: Yere yat!", PackLookup.Match(library, "MARIA: Get Down!")?.Text);
        Assert.Equal("Yere yat!\nMinchia! Sana at sürmeyi yasaklamak lazım!",
            PackLookup.Match(library, "Get Down!\nMinchia! You shouldn't be allowed to ride!")?.Text);
    }
}
