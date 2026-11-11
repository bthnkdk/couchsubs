// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell.Tests;

/// <summary>Altyazının bilgisayar ekranında gösterilmesi: ayar, TV'siz kurulum ve pencereye giden olaylar (Mac ile aynı testler).</summary>
public class ComputerScreenTests
{
    private static readonly RegisteredConsole Console =
        new("192.168.1.253", "PS5", Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray());

    /// <summary>PS5 kurulu, TV yok.</summary>
    private static MemoryStore StoreWithoutTv()
    {
        var store = new MemoryStore();
        store.Save(StoreKeys.AccountId, Enumerable.Repeat((byte)1, 8).ToArray());
        store.Save(StoreKeys.Console, Console);
        return store;
    }

    private static AppController Make(FakeServices? services = null, MemoryStore? store = null, MemorySettings? settings = null) =>
        AppControllerTests.Make(services, store ?? StoreWithoutTv(), settings);

    [Fact]
    public void ExistingSettingsDefaultToTv()
    {
        var old = JsonSerializer.Deserialize<UserSettings>("""{"SourceLanguage":"en","Style":{"FontSize":58}}""")!;
        Assert.Equal(SubtitleOutput.Tv, old.Output);
        Assert.False(old.OverlayClickThrough);
        Assert.Null(old.Overlay);
        Assert.Equal(58, old.Style.FontSize);
    }

    [Fact]
    public void OutputAndWindowAreSavedAsText()
    {
        var settings = new UserSettings { Output = SubtitleOutput.Both, OverlayClickThrough = true, Overlay = new OverlayBounds(100, 800, 1200) };
        var json = JsonSerializer.Serialize(settings);
        Assert.Contains("\"Output\":\"Both\"", json);
        var loaded = JsonSerializer.Deserialize<UserSettings>(json)!;
        Assert.Equal(SubtitleOutput.Both, loaded.Output);
        Assert.True(loaded.OverlayClickThrough);
        Assert.Equal(new OverlayBounds(100, 800, 1200), loaded.Overlay);
    }

    [Fact]
    public void NoTvChoiceSkipsTvSetup()
    {
        var services = new FakeServices();
        var controller = Make(services);
        controller.Step = OnboardingStep.Tv;
        Assert.False(controller.CanAdvance);
        controller.UseComputerScreen();
        // Windows'ta TV'den sonra çeviri modeli adımı gelir.
        Assert.Equal(OnboardingStep.Translation, controller.Step);
        Assert.Equal(SubtitleOutput.Computer, controller.Settings.Output);
        Assert.Equal(0, services.PairCount);
        Assert.Null(controller.Tv);
    }

    [Fact]
    public void SetupWithoutTvOpensMainScreenNextLaunch()
    {
        var store = StoreWithoutTv();
        var settings = new MemorySettings();
        var controller = Make(store: store, settings: settings);
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        controller.Step = OnboardingStep.Tv;
        controller.UseComputerScreen();
        controller.Advance();
        controller.Advance();
        Assert.Equal(OnboardingStep.Done, controller.Step);
        Assert.Equal(OnboardingStep.Done, Make(store: store, settings: settings).Step);
    }

    [Fact]
    public void SetupAgainForgetsCompletedSetup()
    {
        var store = StoreWithoutTv();
        var controller = Make(store: store);
        controller.Step = OnboardingStep.Done;
        controller.ResetSetup();
        Assert.Equal(OnboardingStep.Welcome, Make(store: store).Step);
    }

    [Fact]
    public async Task StartWithoutTvShowsOnComputerOnly()
    {
        var services = new FakeServices();
        var controller = Make(services);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        Assert.True(controller.CanStart);
        Assert.False(controller.ShowsOnTv);
        await controller.StartAsync();
        Assert.True(controller.IsRunning);
        Assert.Single(services.Streams);
        // TV aranmaz, açık tutulmaz.
        Assert.Empty(services.Keepers);
        controller.Stop();
    }

    [Fact]
    public async Task TvOnlyWithoutTvCannotStart()
    {
        var services = new FakeServices();
        var controller = Make(services);
        Assert.False(controller.CanStart);
        Assert.True(controller.NeedsTv);
        Assert.Equal("Not set up", controller.TvStatusText);
        await controller.StartAsync();
        Assert.False(controller.IsRunning);
        Assert.Empty(services.Streams);
    }

    [Fact]
    public async Task ChoosingTvWhileRunningStartsKeeper()
    {
        var services = new FakeServices();
        var store = StoreWithoutTv();
        store.Save(StoreKeys.Tv, new LgTv("LG TV", "127.0.0.1"));
        store.Save(StoreKeys.TvKey, "tv-key");
        var controller = Make(services, store);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        await controller.StartAsync();
        Assert.Empty(services.Keepers);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Both };
        Assert.True(Assert.Single(services.Keepers).Running);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        Assert.False(services.Keepers[0].Running);
        controller.Stop();
    }

    [Fact]
    public async Task PairingTvAfterNoTvChoiceSendsSubtitlesToTv()
    {
        var controller = Make();
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        await controller.PairAsync(new LgTv("LG TV", "192.168.1.153"));
        Assert.Equal(SubtitleOutput.Tv, controller.Settings.Output);
        controller.Dispose();
    }

    [Fact]
    public void TestSubtitleGoesToComputerWindow()
    {
        var controller = Make();
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        var received = new List<SubtitleEvent>();
        controller.OverlayEvent += received.Add;
        controller.SendTestSubtitle();
        var shown = Assert.Single(received);
        Assert.Equal(SubtitleEventKind.Subtitle, shown.Kind);
        Assert.Equal("This is a test subtitle. Can you see it on top of the game?", shown.Text);
        Assert.Equal(8000, shown.DurationMs);
    }

    [Fact]
    public void TvOnlyKeepsComputerWindowEmpty()
    {
        var controller = Make();
        var received = new List<SubtitleEvent>();
        controller.OverlayEvent += received.Add;
        controller.SendTestSubtitle();
        Assert.Empty(received);
    }

    [Fact]
    public async Task StopHidesComputerWindow()
    {
        var controller = Make();
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Both };
        await controller.StartAsync();
        var hidden = 0;
        controller.OverlayHidden += () => hidden++;
        controller.Stop();
        Assert.Equal(1, hidden);
    }

    [Fact]
    public void ClickThroughToggles()
    {
        var controller = Make();
        controller.ToggleClickThrough();
        Assert.True(controller.Settings.OverlayClickThrough);
        controller.ToggleClickThrough();
        Assert.False(controller.Settings.OverlayClickThrough);
    }

    /// <summary>Altyazı TV'ye gitmiyorsa TV'nin bağlanmaması güvenlik duvarı önerisine yol açmaz.</summary>
    [Fact]
    public async Task ComputerOnlyNeverWaitsForTv()
    {
        var firewall = new FakeFirewall { Rule = false };
        var services = new FakeServices { Firewall = firewall };
        var store = StoreWithoutTv();
        store.Save(StoreKeys.Tv, new LgTv("LG TV", "127.0.0.1"));
        store.Save(StoreKeys.TvKey, "tv-key");
        var controller = Make(services, store);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        var now = DateTime.UtcNow;
        controller.Clock = () => now;
        await controller.StartAsync();
        services.Streams[0].Emit(SessionState.Streaming);
        now += TimeSpan.FromMinutes(5);
        await controller.CheckConnectionsAsync();
        Assert.Equal(FirewallPrompt.None, controller.FirewallPrompt);
        controller.Stop();
    }
}
