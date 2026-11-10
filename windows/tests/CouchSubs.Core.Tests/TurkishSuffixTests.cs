// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Terim ekleri ünlü uyumu, kaynaştırma ve ünsüz benzeşmesiyle kurulur (Mac: TurkishSuffixTests).</summary>
public class TurkishSuffixTests
{
    // Motor yer tutucuya ("Zarmon": kalın, ünsüzle biten) göre ek koyar; ek terime göre yeniden kurulur.
    [Theory]
    [InlineData("Kratos", "u", "Kratos'u")]
    [InlineData("Kratos", "un", "Kratos'un")]
    [InlineData("Kratos", "a", "Kratos'a")]
    [InlineData("Kratos", "da", "Kratos'ta")]
    [InlineData("Kratos", "dan", "Kratos'tan")]
    [InlineData("Kratos", "la", "Kratos'la")]
    [InlineData("Kratos", "dur", "Kratos'tur")]
    [InlineData("Atreus", "un", "Atreus'un")]
    [InlineData("Atreus", "a", "Atreus'a")]
    [InlineData("Midgard", "a", "Midgard'a")]
    [InlineData("Midgard", "da", "Midgard'da")]
    [InlineData("Midgard", "u", "Midgard'ı")]
    [InlineData("Midgard", "un", "Midgard'ın")]
    [InlineData("Midgard", "daki", "Midgard'daki")]
    [InlineData("Freya", "u", "Freya'yı")]
    [InlineData("Freya", "a", "Freya'ya")]
    [InlineData("Freya", "un", "Freya'nın")]
    [InlineData("Freya", "la", "Freya'yla")]
    [InlineData("Freya", "da", "Freya'da")]
    [InlineData("Mimir", "a", "Mimir'e")]
    [InlineData("Mimir", "u", "Mimir'i")]
    [InlineData("Mimir", "un", "Mimir'in")]
    [InlineData("Mimir", "dan", "Mimir'den")]
    [InlineData("Brok", "da", "Brok'ta")]
    [InlineData("Brok", "u", "Brok'u")]
    [InlineData("Jötunheim", "a", "Jötunheim'e")]
    [InlineData("Jötunheim", "da", "Jötunheim'de")]
    [InlineData("Thor", "un", "Thor'un")]
    [InlineData("Baldur", "u", "Baldur'u")]
    [InlineData("Sindri", "un", "Sindri'nin")]
    [InlineData("Sindri", "u", "Sindri'yi")]
    [InlineData("Odin", "a", "Odin'e")]
    [InlineData("Odin", "ya", "Odin'e")]
    [InlineData("Freya", "nın", "Freya'nın")]
    [InlineData("Kratos", "nın", "Kratos'un")]
    [InlineData("Kratos", "", "Kratos")]
    public void ProperNounsTakeHarmonizedSuffixWithApostrophe(string term, string suffix, string expected) =>
        Assert.Equal(expected, TurkishSuffix.Attach(term, suffix));

    [Theory]
    [InlineData("Leviathan Baltası", "u", "Leviathan Baltası'nı")]
    [InlineData("Leviathan Baltası", "a", "Leviathan Baltası'na")]
    [InlineData("Leviathan Baltası", "da", "Leviathan Baltası'nda")]
    [InlineData("Leviathan Baltası", "dan", "Leviathan Baltası'ndan")]
    [InlineData("Leviathan Baltası", "un", "Leviathan Baltası'nın")]
    [InlineData("Leviathan Baltası", "la", "Leviathan Baltası'yla")]
    [InlineData("Dünya Ağacı", "a", "Dünya Ağacı'na")]
    [InlineData("Kaos Bıçakları", "u", "Kaos Bıçakları'nı")]
    public void CompoundNamesTakeTheBufferN(string term, string suffix, string expected) =>
        Assert.Equal(expected, TurkishSuffix.Attach(term, suffix));

    [Theory]
    [InlineData("can iksiri", "u", "can iksirini")]
    [InlineData("kontrol noktası", "a", "kontrol noktasına")]
    [InlineData("bekleme süresi", "da", "bekleme süresinde")]
    [InlineData("envanter", "a", "envantere")]
    [InlineData("envanter", "da", "envanterde")]
    [InlineData("kılıç", "u", "kılıcı")]
    [InlineData("kitap", "u", "kitabı")]
    [InlineData("bıçak", "u", "bıçağı")]
    [InlineData("renk", "u", "rengi")]
    [InlineData("top", "u", "topu")]
    [InlineData("balta", "u", "baltayı")]
    [InlineData("balta", "lar", "baltalar")]
    [InlineData("kalkan", "lar", "kalkanlar")]
    [InlineData("kalkan", "dan", "kalkandan")]
    [InlineData("kalkan", "la", "kalkanla")]
    public void CommonNounsAreWrittenTogether(string term, string suffix, string expected) =>
        Assert.Equal(expected, TurkishSuffix.Attach(term, suffix));

    [Fact]
    public void ApostropheStyleIsKept() => Assert.Equal("Kratos’un", TurkishSuffix.Attach("Kratos", "un", '’'));

    [Fact]
    public void AbbreviationsReadAsLetterNames() => Assert.Equal("XP'yi", TurkishSuffix.Attach("XP", "u"));

    [Fact]
    public void SuffixInCapitalsIsLowered() => Assert.Equal("Midgard'a", TurkishSuffix.Attach("Midgard", "A"));
}
