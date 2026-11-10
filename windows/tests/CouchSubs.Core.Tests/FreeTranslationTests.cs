// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Türkçe düzeltmeler (Mac: TurkishPostEditTests).</summary>
public class TurkishPostEditTests
{
    [Theory]
    [InlineData("Run!", "Koş.", "Koş!")]
    [InlineData("Run!", "Koş", "Koş!")]
    [InlineData("What?!", "Ne?", "Ne?!")]
    [InlineData("Wait…", "Bekle.", "Bekle…")]
    [InlineData("Wait...", "Bekle.", "Bekle...")]
    [InlineData("Where is he?", "O nerede.", "O nerede?")]
    [InlineData("He said \"Run!\"", "\"Koş.\" dedi.", "\"Koş.\" dedi.")]
    [InlineData("He said \"Run!\"", "\"Koş\" dedi", "\"Koş\" dedi")]
    [InlineData("\"Run!\"", "\"Koş.\"", "\"Koş!\"")]
    [InlineData("We go.", "Gidiyoruz!", "Gidiyoruz!")]
    [InlineData("We go.", "Gidiyoruz", "Gidiyoruz")]
    [InlineData("Boy!", "Evlat!", "Evlat!")]
    public void SourceEndingIsKept(string source, string translation, string expected) =>
        Assert.Equal(expected, TurkishPostEdit.Apply(source, translation));

    [Theory]
    [InlineData("Dur , bekle !", "Dur, bekle!")]
    [InlineData("Ne  oldu ?", "Ne oldu?")]
    [InlineData("Peki ... gidelim .", "Peki... gidelim.")]
    public void SpaceBeforePunctuationIsRemoved(string translation, string expected) =>
        Assert.Equal(expected, TurkishPostEdit.Apply("Okay. Go.", translation));

    [Fact]
    public void QuotesFollowTheSource()
    {
        Assert.Equal("\"Koş\" dedi, Kratos'un oğlu.", TurkishPostEdit.Apply("He said \"run\", Kratos's son.", "“Koş” dedi, Kratos’un oğlu."));
        Assert.Equal("“Koş” dedi, Kratos’un oğlu.", TurkishPostEdit.Apply("He said “run”, Kratos’s son.", "\"Koş\" dedi, Kratos'un oğlu."));
    }

    [Fact]
    public void ImperativesFollowAnInformalLine()
    {
        Assert.Equal(["Sana söyledim.", "Bekle!", "Dikkat et, evlat."],
            TurkishPostEdit.Register(["Sana söyledim.", "Bekleyin!", "Dikkat edin, evlat."]));
        Assert.Equal(["Seni gördüm. Hemen gel!"], TurkishPostEdit.Register(["Seni gördüm. Hemen gelin!"]));
    }

    [Theory]
    // "Sen" yoksa hitap belirsizdir; dokunulmaz.
    [InlineData("Bekleyin!")]
    // Cümlede "siz" varsa kibar/çoğul hitap bilerek seçilmiştir.
    [InlineData("Siz bekleyin, sana sonra bakarım!")]
    // Emir yerinde değil (ardından noktalama yok): "Gelin misin" gibi başka anlam olabilir.
    [InlineData("Sen gelin misin?")]
    public void OtherLinesKeepTheirRegister(string sentence) =>
        Assert.Equal([sentence], TurkishPostEdit.Register([sentence]));

    [Fact]
    public void NullPiecesStayNull() =>
        Assert.Equal([null, "Sana söyledim.", null, "Dur!"], TurkishPostEdit.Register([null, "Sana söyledim.", null, "Durun!"]));
}

/// <summary>Ücretsiz çevirinin metin hattı (Mac: FreeTranslationTests).</summary>
public class FreeTranslationTests
{
    private static readonly Glossary Gow = Glossary.Parse("""
        { "terms": { "Leviathan Axe": "Leviathan Baltası" }, "keep": ["Kratos", "Atreus"] }
        """);

    [Fact]
    public void PipelineVersionIsBumped() => Assert.True(FreeTranslation.PipelineVersion >= 2);

    [Theory]
    [InlineData("Boy!", true)]
    [InlineData("Do it.", true)]
    [InlineData("Not you, boy.", true)]
    [InlineData("We go to the mountain.", false)]
    [InlineData("...", false)]
    public void ShortLinesHaveFewerThanFourWords(string sentence, bool expected) =>
        Assert.Equal(expected, FreeTranslation.IsShort(sentence));

    [Theory]
    [InlineData("Annen nerede? *** Sen değil.", "Sen değil.")]
    [InlineData("Annen nerede?***Sen değil.", "Sen değil.")]
    [InlineData("ANNEN NEREDE? *** SEN DEĞİL.", "SEN DEĞİL.")]
    [InlineData("Annen nerede? Sen değil.", null)]
    [InlineData("Annen *** nerede? *** Sen değil.", null)]
    [InlineData("Annen nerede? **** Sen değil.", null)]
    [InlineData("*** Sen değil.", null)]
    [InlineData("Annen nerede? ***", null)]
    [InlineData("Annen nerede? *** Sen değil, sen değil, sen değil, sen değil, sen değil, sen değil, sen değil.", null)]
    public void PartAfterTheSeparatorOnlyWhenUnambiguous(string output, string? expected) =>
        Assert.Equal(expected, FreeTranslation.AfterSeparator(output, "Not you."));

    [Fact]
    public void CacheKeyCarriesContextAndGlossary()
    {
        Assert.Equal("We go.", FreeTranslation.CacheKey("We go.", null, Gow));
        Assert.Equal("Where?\u001FWe go.", FreeTranslation.CacheKey("We go.", "Where?", Gow));
        Assert.Equal(Gow.Fingerprint + "\u001FKratos, go.", FreeTranslation.CacheKey("Kratos, go.", null, Gow));
        Assert.StartsWith(Gow.Fingerprint, FreeTranslation.CacheKey("Go.", "Kratos!", Gow));
    }

    private static string Same(string text) => text;

    [Fact]
    public void TermsAreProtectedAndRestored()
    {
        var calls = new List<string>();
        var result = FreeTranslation.Translate("Kratos, throw the Leviathan Axe!", null, Gow, Same, input =>
        {
            calls.Add(input);
            return "Zarmon, Velkor'u fırlat.";
        });
        Assert.Equal(["Zarmon, throw the Velkor!"], calls);
        Assert.Equal("Kratos, Leviathan Baltası'nı fırlat!", result);
    }

    [Fact]
    public void LostPlaceholderFallsBackToPlainTranslation()
    {
        var calls = new List<string>();
        var result = FreeTranslation.Translate("Throw the Leviathan Axe!", null, Gow, Same, input =>
        {
            calls.Add(input);
            return input.Contains("Zarmon") ? "Baltayı fırlat!" : "Leviathan Baltasını fırlat!";
        });
        Assert.Equal(["Throw the Zarmon!", "Throw the Leviathan Axe!"], calls);
        Assert.Equal("Leviathan Baltasını fırlat!", result);
    }

    [Fact]
    public void ShortLineIsTranslatedWithItsContext()
    {
        var calls = new List<string>();
        var result = FreeTranslation.Translate("Not you.", "Where is your mother?", Gow, Same, input =>
        {
            calls.Add(input);
            return "Annen nerede? *** Sen değil.";
        });
        Assert.Equal(["Where is your mother? *** Not you."], calls);
        Assert.Equal("Sen değil.", result);
    }

    [Fact]
    public void AmbiguousContextFallsBackToTheLineAlone()
    {
        var calls = new List<string>();
        var result = FreeTranslation.Translate("Not you.", "Where is your mother?", Gow, Same, input =>
        {
            calls.Add(input);
            return input.Contains("***") ? "Annen nerede, sen değil." : "Sen değil.";
        });
        Assert.Equal(["Where is your mother? *** Not you.", "Not you."], calls);
        Assert.Equal("Sen değil.", result);
    }

    [Fact]
    public void ContextTermsDoNotLeakIntoTheLine()
    {
        // Bağlamdaki terimin yer tutucusu satıra kaydıysa ayrım güvenilmez; satır tek başına çevrilir.
        var result = FreeTranslation.Translate("Go, Atreus!", "Kratos is here.", Gow, Same, input =>
            input.Contains("***") ? "Burada. *** Git, Zarmon Velkor!" : "Git, Zarmon!");
        Assert.Equal("Git, Atreus!", result);
    }

    [Fact]
    public void ContextualLineKeepsTermsOfItsOwn()
    {
        var result = FreeTranslation.Translate("Go, Atreus!", "Kratos is here.", Gow, Same, input =>
        {
            Assert.Equal("Zarmon is here. *** Go, Velkor!", input);
            return "Zarmon burada. *** Git, Velkor!";
        });
        Assert.Equal("Git, Atreus!", result);
    }

    [Fact]
    public void NormalizeAndGameEnglishRunBeforeProtection()
    {
        string? sent = null;
        FreeTranslation.Translate("HEADS UP, KRATOS!", null, Gow, text => text == "HEADS UP, KRATOS!" ? "Heads up, kratos!" : text,
            input => { sent = input; return "Dikkat et, Zarmon!"; });
        Assert.Equal("Watch out, Zarmon!", sent);
    }
}

/// <summary>Kısa satırın bağlamı (Mac: RecentLinesTests).</summary>
public class RecentLinesTests
{
    [Fact]
    public void PreviousLineIsTheContextAndRereadsKeepIt()
    {
        var now = DateTimeOffset.UnixEpoch;
        var recent = new RecentLines(() => now);
        Assert.Null(recent.Shown("Where is your mother?"));
        Assert.Equal("Where is your mother?", recent.Shown("Not you."));
        now += TimeSpan.FromMinutes(5);
        // Aynı satır uzun süre ekranda kaldı; bağlamı değişmez, çevirisi de değişmez.
        Assert.Equal("Where is your mother?", recent.Shown("Not you."));
        Assert.Equal("Not you.", recent.Shown("Go."));
    }

    [Fact]
    public void OldLineIsNotContext()
    {
        var now = DateTimeOffset.UnixEpoch;
        var recent = new RecentLines(() => now);
        recent.Shown("Where is your mother?");
        now += TimeSpan.FromSeconds(25);
        Assert.Null(recent.Shown("Not you."));
    }
}
