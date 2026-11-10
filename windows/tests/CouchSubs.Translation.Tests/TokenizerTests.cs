// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Translation.Tests;

/// <summary>
/// Kimlikler Hugging Face MarianTokenizer'ın aynı dosyalarla verdiği çıktıdan alındı (geliştirirken
/// 500 rastgele dizgiyle de karşılaştırıldı, hepsi aynı).
/// </summary>
public class TokenizerTests
{
    private static readonly Lazy<MarianTokenizer> Tokenizer = new(TestModels.LoadTokenizer);

    public static TheoryData<string, int[]> Reference => new()
    {
        { "We do not have time for this, boy.", [54337, 15378, 36420, 23847, 50733, 20276, 50518, 14, 8689, 33, 43741] },
        { "Wait!", [54162, 21, 43741] },
        { "I know…", [25182, 29976, 34, 43741] },
        { "Kratos.", [30576, 50847, 43740, 33, 43741] },
        { "ATREUS: Father, look over there!", [5435, 42073, 52811, 18, 19389, 14, 32605, 38502, 50436, 21, 43741] },
        { "  Multiple   spaces\tand\ttabs  ", [35372, 47425, 4138, 49058, 43740, 43741] },
        { "ＡＢＣ ½ café naïve—“quoted” 'single' don't",
            [2169, 314, 52508, 832, 9608, 52508, 35631, 52508, 53450, 52508, 58, 41715, 49816, 59, 119, 46278, 46, 15635, 46, 49045, 43741] },
        { "Line one\nLine two", [32274, 37720, 32274, 51885, 43741] },
        { "123,456.78 km/h — 50% off!", [475, 14, 1552, 33, 1914, 29939, 32, 23211, 52508, 1626, 36856, 21, 43741] },
        { "Ægir's hall: Þór & Óðinn", [90, 52508, 20789, 26995, 46, 43740, 23427, 18, 90, 52508, 41729, 151, 90, 52508, 26539, 43741] },
        { "😀 emoji test", [90, 52508, 17563, 50281, 43741] },
        { "", [43741] },
        { "Hello, World! It's 3 o'clock.", [24170, 14, 54836, 21, 27564, 46, 43740, 1227, 36614, 46, 11447, 33, 43741] },
        // Ardışık bilinmeyen karakterler tek parça olur; "ç" spm'de bilinmez ama ortak sözlükte vardır.
        { "ðð x", [90, 52508, 54951, 43741] },
        { "😀😀 test", [90, 52508, 50281, 43741] },
        { "Óðinn", [90, 52508, 26539, 43741] },
        { "ç,¥:l", [90, 9560, 14, 52508, 18, 31140, 43741] },
        { "Don’t “go” – now…", [15637, 48, 49045, 126, 22060, 59, 157, 36480, 34, 43741] },
        { "FATHER! WAIT!", [19127, 50427, 21, 54144, 27565, 21, 43741] },
        { "Tyr’s Temple — Lake of Nine", [51913, 48, 43740, 50051, 52508, 31233, 36851, 36209, 43741] },
    };

    [TokenizerTheory]
    [MemberData(nameof(Reference))]
    public void EncodeMatchesReferenceTokenizer(string text, int[] expected)
    {
        Assert.Equal(expected, Tokenizer.Value.Encode(text));
    }

    [TokenizerTheory]
    [InlineData("We do not have time for this, boy.", "We do not have time for this, boy.")]
    [InlineData("Who are you?", "Who are you?")]
    [InlineData("  The gate   will not hold. ", "The gate will not hold.")]
    // nmt_nfkc normalleştirmesi üç noktayı ayrı noktalara açar.
    [InlineData("I know…", "I know...")]
    public void DecodeRoundTripsEncodedText(string text, string expected)
    {
        var ids = Tokenizer.Value.Encode(text);
        Assert.Equal(expected, Tokenizer.Value.Decode(ids));
    }

    [TokenizerFact]
    public void DecodeSkipsSpecialTokens()
    {
        int[] ids = [MarianTokenizer.PadId, 54162, 21, MarianTokenizer.UnkId, MarianTokenizer.EosId];
        Assert.Equal("Wait!", Tokenizer.Value.Decode(ids));
    }

    [TokenizerFact]
    public void VocabularyCoversModelOutputSize()
    {
        Assert.Equal(57060, Tokenizer.Value.VocabularySize);
    }
    /// <summary>
    /// Kısa satır ayracı ve terim yer tutucuları model sözlüğünde bilinmeyen parçaya düşmemeli: bilinmeyen parça
    /// modelden geri gelmez. "|", "||", "[[" sözlükte yok; "▁***" tek parça.
    /// </summary>
    [TokenizerTheory]
    [InlineData("Where is your mother? *** Not you.")]
    [InlineData("Zarmon, take the Velkor to Dorvan.")]
    [InlineData("Kelmar, Tolvar, Brandur, Halvor and Feldor.")]
    public void SeparatorAndPlaceholdersAreKnownPieces(string text)
    {
        var ids = Tokenizer.Value.Encode(text);
        Assert.DoesNotContain(MarianTokenizer.UnkId, ids);
        Assert.Equal(text, Tokenizer.Value.Decode(ids));
    }

    [TokenizerFact]
    public void PipeWouldBeLost() => Assert.Contains(MarianTokenizer.UnkId, Tokenizer.Value.Encode("Where? | Not you."));
}
