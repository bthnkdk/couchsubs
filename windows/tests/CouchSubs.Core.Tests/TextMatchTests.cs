// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class TextMatchTests
{
    [Fact]
    public void NormalizeStripsPunctuationAndCase() =>
        Assert.Equal("kratos we do not have time boy", TextMatch.Normalize("Kratos: We do NOT have time, boy."));

    [Fact]
    public void SimilarToleratesOcrNoise() => Assert.True(TextMatch.IsSimilar("the gate will not hold", "the gale will not hold"));

    [Fact]
    public void DifferentLinesAreNotSimilar() => Assert.False(TextMatch.IsSimilar("we do not have time", "the gate will not hold"));

    [Fact]
    public void EmptyIsNeverSimilarToText() => Assert.False(TextMatch.IsSimilar("", "abc"));

    [Fact]
    public void SameSubtitleIgnoresGarbledWords()
    {
        var sent = TextMatch.Normalize("Across the deep waters, Pbo ou$3e went, hoping a boat would carry him home.");
        var wordSwap = TextMatch.Normalize("Across the deep waters, 2aljd Pbo went, Hoping 3e boat would carry him home now.");
        Assert.False(TextMatch.IsSimilar(wordSwap, sent));
        Assert.True(TextMatch.IsSameSubtitle(wordSwap, sent));
    }

    /// İki satırlık altyazı solarken alt satır kaçırıldı: yeni satır değil. Uzayan metin ise yenidir.
    [Fact]
    public void RereadMissingALineIsSameSubtitle()
    {
        const string twoRows = "Across the deep waters, Pbo went,\nhoping a boat would carry him home.";
        var sent = TextMatch.NormalizeRows(twoRows);
        Assert.True(TextMatch.IsSameSubtitle(TextMatch.Normalize(OcrNoise.Clean("Across the deep waters2aljd O went,")), sent));
        Assert.True(TextMatch.IsSameSubtitle(TextMatch.Normalize("Across the deep waters, Pbo went,"), sent));
        Assert.True(TextMatch.IsSameSubtitle(TextMatch.Normalize("hoping a boat would carry him home."), sent));
        Assert.False(TextMatch.IsSameSubtitle(TextMatch.Normalize(twoRows), TextMatch.Normalize("Across the deep waters, Pbo went,")));
    }

    /// İki konuşmacı aynı sözlerle konuşuyor: sözcüklerin çoğu ortak olsa da ikisi de ayrı çevrilmeli.
    [Theory]
    [InlineData("Where are you going?", "Where are you going, boy?")]
    [InlineData("Where are you going, boy?", "Where are you going?")]
    [InlineData("We need to leave this place before the sun goes down, boy.", "We need to leave this place before the sun goes down.")]
    [InlineData("Boy, we need to leave this place before the sun goes down.", "We need to leave this place before the sun goes down.")]
    public void LineSharingMostWordsIsANewSubtitle(string reread, string sent) =>
        Assert.False(TextMatch.IsSameSubtitle(TextMatch.Normalize(reread), TextMatch.NormalizeRows(sent)));

    /// Tek satırlık altyazının başı kesildiyse satır kaçırılmış sayılmaz; tam satırlar eksikse sayılır.
    [Fact]
    public void ShortenedSingleRowIsNotAMissingRow()
    {
        Assert.False(TextMatch.IsSameSubtitle("we have to cross the river", TextMatch.NormalizeRows("We have to cross the river before the sun goes down")));
        Assert.True(TextMatch.IsSameSubtitle("we have to cross the river", TextMatch.NormalizeRows("We have to cross the river\nbefore the sun goes down")));
    }

    [Theory]
    [InlineData("we do not have time", "the gate will not hold")]
    [InlineData("we do not have time for this boy and you know it", "we do not have time")]
    [InlineData("where is the boy", "where is the ship")]
    [InlineData("you should not be here", "i told you to stay with your mother")]
    [InlineData("we have to cross the river before the sun goes down", "the river is too deep for us to cross today")]
    public void SameSubtitleKeepsDistinctLinesApart(string reread, string sent) =>
        Assert.False(TextMatch.IsSameSubtitle(reread, sent));
}
