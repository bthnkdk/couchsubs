// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core.Dubbing;

namespace CouchSubs.Core.Tests;

/// <summary>Oyun paketindeki satır çeviri motoruna gitmeden gösterilir (Mac: SubtitlePipelineTests, paket testleri).</summary>
public class PackPipelineTests
{
    private static readonly Frame Image = Frame.Blank(64, 64);

    private static PackMatch? Lookup(string text) => PackKey.Canon(text) == "get down"
        ? new PackMatch("Yere yat!", [new SpokenLine("Get down!", "Yere yat!")])
        : null;

    private static async Task Run(SubtitlePipeline pipeline, int frames)
    {
        for (var i = 0; i < frames; i++)
        {
            await pipeline.ProcessAsync(Image, new CropRegion());
            await pipeline.WaitForTranslationsAsync();
        }
    }

    [Fact]
    public async Task PackHitSkipsTheEngine()
    {
        var sender = new FakeSender();
        var translator = new FakeTranslator();
        var pipeline = new SubtitlePipeline(new FakeReader("Get down!", "Get down!", "Get down!"), translator, sender) { PackLookup = Lookup };
        var shown = new List<(string, string)>();
        var spoken = new List<IReadOnlyList<SpokenLine>>();
        var missed = new List<string>();
        pipeline.PairShown += (source, translation) => shown.Add((source, translation));
        pipeline.SpeechReady += spoken.Add;
        pipeline.PackMissed += missed.Add;
        await Run(pipeline, 3);
        Assert.Equal(["Yere yat!"], sender.Sent);
        Assert.Empty(translator.Requested);
        Assert.Equal([("Get down!", "Yere yat!")], shown);
        Assert.Equal("Yere yat!", Assert.Single(spoken).Single().Turkish);
        Assert.Empty(missed);
        Assert.Equal("paket", pipeline.LastOrigin);
        Assert.Equal(1, pipeline.PackHits);
    }

    [Fact]
    public async Task PackMissUsesTheEngineAndIsReported()
    {
        var sender = new FakeSender();
        var translator = new FakeTranslator();
        var pipeline = new SubtitlePipeline(new FakeReader("Hold the gate", "Hold the gate"), translator, sender) { PackLookup = Lookup };
        var missed = new List<string>();
        pipeline.PackMissed += missed.Add;
        await Run(pipeline, 2);
        Assert.Equal(["TR: Hold the gate"], sender.Sent);
        Assert.Equal(["Hold the gate"], translator.Requested);
        Assert.Equal(["Hold the gate"], missed);
        Assert.Equal("motor", pipeline.LastOrigin);
    }

    /// <summary>Paket kapalıyken (PackLookup yok) her satır motora gider ve havuz için bildirilir.</summary>
    [Fact]
    public async Task WithoutPacksEveryLineGoesToTheEngine()
    {
        var sender = new FakeSender();
        var translator = new FakeTranslator();
        var pipeline = new SubtitlePipeline(new FakeReader("Get down!", "Get down!"), translator, sender);
        var missed = new List<string>();
        pipeline.PackMissed += missed.Add;
        await Run(pipeline, 2);
        Assert.Equal(["TR: Get down!"], sender.Sent);
        Assert.Equal(["Get down!"], missed);
    }

    /// <summary>Önceki satırın çevirisi sürerken gelen paket satırı beklemeden gösterilir; geç gelen eski çeviri üstüne yazmaz.</summary>
    [Fact]
    public async Task PackLineDoesNotWaitForASlowTranslation()
    {
        var sender = new FakeSender();
        var translator = new GatedTranslator();
        var pipeline = new SubtitlePipeline(new FakeReader("Hold the gate", "Hold the gate", "Get down!", "Get down!"), translator, sender)
            { PackLookup = Lookup };
        for (var i = 0; i < 4; i++) await pipeline.ProcessAsync(Image, new CropRegion());
        Assert.Equal(["Yere yat!"], sender.Sent);
        translator.Open();
        await pipeline.WaitForTranslationsAsync();
        Assert.Equal(["Yere yat!"], sender.Sent);
    }
}
