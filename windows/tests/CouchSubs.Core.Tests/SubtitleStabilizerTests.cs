// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class SubtitleStabilizerTests
{
    /// Noktalamayla bitmeyen satır yazılmakta olabilir; iki kare aynı okununca gönderilir.
    [Fact]
    public void UnfinishedLineIsSentAfterTwoStableFrames()
    {
        var s = new SubtitleStabilizer();
        Assert.Equal(StabilizerAction.None, s.Feed("We do not have time"));
        Assert.Equal(StabilizerAction.Translate("We do not have time"), s.Feed("We do not have time"));
        Assert.Equal(StabilizerAction.None, s.Feed("We do not have time"));
    }

    /// Süslü yazıda aynı cümle her karede başka çöple okunur; TV'de iki çeviri olarak görünmemeli.
    [Fact]
    public void GarbledRereadOfSentLineDoesNotReemit()
    {
        var s = new SubtitleStabilizer();
        const string first = "Across the deep waters, Pbo went,\nhoping a boat would carry him home.";
        Assert.Equal(StabilizerAction.Translate(first), s.Feed(first));
        Assert.Equal(StabilizerAction.None, s.Feed("Across the deep waters O went,"));
        Assert.Equal(StabilizerAction.None, s.Feed("Across the deep waters O went,"));
        Assert.Equal(StabilizerAction.Translate("We should keep moving."), s.Feed("We should keep moving."));
    }

    /// Cümle bitmişse beklemeye gerek yok; hızlı konuşmada her kare önemli.
    [Theory]
    [InlineData("We do not have time.")]
    [InlineData("Wait!")]
    [InlineData("Who are you?")]
    [InlineData("I know…")]
    [InlineData("\"Run.\"")]
    public void FinishedSentenceIsSentOnFirstFrame(string line)
    {
        var s = new SubtitleStabilizer();
        Assert.Equal(StabilizerAction.Translate(line), s.Feed(line));
        Assert.Equal(StabilizerAction.None, s.Feed(line));
    }

    [Fact]
    public void OcrNoiseDoesNotReemit()
    {
        var s = new SubtitleStabilizer();
        s.Feed("The gate will not hold"); s.Feed("The gate will not hold");
        Assert.Equal(StabilizerAction.None, s.Feed("The gale will not hold"));
        Assert.Equal(StabilizerAction.None, s.Feed("The gale will not hold"));
    }

    [Fact]
    public void FlickeringHudDoesNotSpam()
    {
        var s = new SubtitleStabilizer();
        var sent = 0;
        for (var i = 0; i < 20; i++)
            if (s.Feed(i % 2 == 0 ? "24 / 120" : "").Kind == StabilizerKind.Translate) sent++;
        Assert.Equal(0, sent);
    }

    [Fact]
    public void TypewriterSendsCompletedLine()
    {
        var s = new SubtitleStabilizer();
        s.Feed("We do"); s.Feed("We do not have");
        Assert.Equal(StabilizerAction.Translate("We do not have time for this, boy."), s.Feed("We do not have time for this, boy."));
        Assert.Equal(StabilizerAction.None, s.Feed("We do not have time for this, boy."));
    }

    /// Altyazının kalktığına okuma sayısıyla değil süreyle karar verilir: bölge 800 ms boş kalınca silinir.
    [Fact]
    public void EmptyRegionClearsAfterClearTime()
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        s.Feed("Hello there"); s.Feed("Hello there");
        Assert.Equal(StabilizerAction.None, s.Feed(""));
        clock.Now += SubtitleStabilizer.ClearAfterMs - 1;
        Assert.Equal(StabilizerAction.None, s.Feed(""));
        clock.Now += 1;
        Assert.Equal(StabilizerAction.Clear, s.Feed(""));
        Assert.Equal(StabilizerAction.None, s.Feed(""));
    }

    /// Parlak arka planda okuma birkaç kare kaçar; 800 ms'den kısa boşluk ne siler ne yeniden gönderir.
    [Fact]
    public void ShortFlickerNeitherClearsNorResends()
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        s.Feed("Hold the gate");
        Assert.Equal(StabilizerAction.Translate("Hold the gate"), s.Feed("Hold the gate"));
        for (var i = 0; i < 3; i++)
        {
            for (var frame = 0; frame < 10; frame++) { clock.Now += 50; Assert.Equal(StabilizerAction.None, s.Feed("")); }
            for (var frame = 0; frame < 4; frame++) { clock.Now += 50; Assert.Equal(StabilizerAction.None, s.Feed("Hold the gate")); }
        }
    }

    /// Kalkan satır 1,5 sn içinde geri gelirse yeniden çevrilmez; çevirisi yeniden gösterilsin diye Restore döner.
    [Fact]
    public void LineReturningSoonAfterClearIsRestored()
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        Assert.Equal(StabilizerAction.Translate("Hold the gate."), s.Feed("Hold the gate."));
        s.Feed("");
        clock.Now += SubtitleStabilizer.ClearAfterMs;
        Assert.Equal(StabilizerAction.Clear, s.Feed(""));
        clock.Now += SubtitleStabilizer.RestoreWithinMs;
        Assert.Equal(StabilizerAction.None, s.Feed("Hold the gate"));
        Assert.Equal(StabilizerAction.Restore("Hold the gate."), s.Feed("Hold the gate"));
        Assert.Equal(StabilizerAction.None, s.Feed("Hold the gate."));
        // Geri gelen satır da kalkınca silinir.
        s.Feed("");
        clock.Now += SubtitleStabilizer.ClearAfterMs;
        Assert.Equal(StabilizerAction.Clear, s.Feed(""));
    }

    /// Daha geç gelen aynı satır gerçek bir tekrardır (oyunda aynı söz yeniden söylendi); yeniden çevrilir.
    [Fact]
    public void LineReturningLaterIsTranslatedAgain()
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        s.Feed("Hold the gate.");
        s.Feed("");
        clock.Now += SubtitleStabilizer.ClearAfterMs;
        Assert.Equal(StabilizerAction.Clear, s.Feed(""));
        clock.Now += SubtitleStabilizer.RestoreWithinMs + 1;
        Assert.Equal(StabilizerAction.Translate("Hold the gate."), s.Feed("Hold the gate."));
    }

    /// Okuma iki satır arasında gidip gelirse (yerine başkası geldi, sonra geri döndü) eski satır yeniden çevrilmez.
    [Fact]
    public void ReplacedLineComingBackIsRestored()
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        Assert.Equal(StabilizerAction.Translate("Hold the gate."), s.Feed("Hold the gate."));
        clock.Now += 100;
        Assert.Equal(StabilizerAction.Translate("Run!"), s.Feed("Run!"));
        clock.Now += 100;
        Assert.Equal(StabilizerAction.Restore("Hold the gate."), s.Feed("Hold the gate."));
        clock.Now += 100;
        Assert.Equal(StabilizerAction.Restore("Run!"), s.Feed("Run!"));
    }

    /// İki konuşmacı neredeyse aynı sözleri söylüyor; ikinci satır da çevrilmeli.
    [Theory]
    [InlineData("Where are you going?", "Where are you going, boy?")]
    [InlineData("Where are you going, boy?", "Where are you going?")]
    [InlineData("We need to leave this place before the sun goes down.", "We need to leave this place before the sun goes down, boy.")]
    public void TwoSpeakersWithOverlappingWordsAreBothTranslated(string first, string second)
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        Assert.Equal(StabilizerAction.Translate(first), s.Feed(first));
        clock.Now += 50;
        Assert.Equal(StabilizerAction.Translate(second), s.Feed(second));
    }

    [Fact]
    public void AlreadyTranslatedIsSkipped()
    {
        var s = new SubtitleStabilizer();
        Assert.False(s.ShouldSend("Kullanıcı Ekle Oturum Açtı", "Kullanıcı Ekle Oturum Açtı"));
        Assert.True(s.ShouldSend("Add user", "Kullanıcı ekle"));
    }

    [Fact]
    public void ResetClearsOnlyAfterSomethingWasSent()
    {
        var s = new SubtitleStabilizer();
        Assert.Equal(StabilizerAction.None, s.Reset());
        s.Feed("Hello there"); s.Feed("Hello there");
        Assert.Equal(StabilizerAction.Clear, s.Reset());
        Assert.Equal(StabilizerAction.None, s.Reset());
    }

    /// Çevirisi başarısız olan satır ekranda kaldıkça yeniden denenebilmeli; ama saniyede en çok bir kez.
    [Fact]
    public void ForgottenLineIsTranslatedAgainAfterBackoff()
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        s.Feed("Hold the gate");
        Assert.Equal(StabilizerAction.Translate("Hold the gate"), s.Feed("Hold the gate"));
        s.ForgetSent();
        for (var frame = 0; frame < 19; frame++) { clock.Now += 50; Assert.Equal(StabilizerAction.None, s.Feed("Hold the gate")); }
        clock.Now += 50;
        Assert.Equal(StabilizerAction.Translate("Hold the gate"), s.Feed("Hold the gate"));
    }

    /// Bekleme yalnız başarısız satır için: başka bir satır hemen çevrilir.
    [Fact]
    public void BackoffDoesNotDelayANewLine()
    {
        var clock = new TestClock();
        var s = new SubtitleStabilizer(clock: clock.Read);
        s.Feed("Hold the gate"); s.Feed("Hold the gate");
        s.ForgetSent();
        Assert.Equal(StabilizerAction.Translate("Run!"), s.Feed("Run!"));
    }
}

internal sealed class TestClock
{
    public long Now { get; set; } = 1_000_000;
    public long Read() => Now;
}
