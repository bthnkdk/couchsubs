// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Navigation;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

public partial class SettingsWindow : Window
{
    private static readonly (string Code, string Name)[] Languages =
        [("en", "English"), ("ja", "Japanese"), ("de", "German"), ("fr", "French"), ("es", "Spanish")];

    /// <summary>Ek bölgeler ilk açıldığında (sağ üst köşe, sağ alt köşe, ekranın ortası) bu alanlarla başlar.</summary>
    private static readonly CropRegion[] ExtraDefaults = [new(0.05, 0.28, 0.60, 0.97), new(0.72, 0.95, 0.60, 0.97), new(0.35, 0.65, 0.30, 0.70)];

    private readonly AppController controller;
    private bool loading = true;
    /// <summary>Çerçevesi düzenlenen bölge: 0 altyazı, 1, 2 ve 3 ek bölgeler.</summary>
    private int area;

    internal SettingsWindow(AppController controller)
    {
        this.controller = controller;
        InitializeComponent();
        var settings = controller.Settings;
        TextSize.Value = Math.Clamp(settings.Style.FontSize, TextSize.Minimum, TextSize.Maximum);
        TextSizeValue.Text = ((int)TextSize.Value).ToString();
        Position.Value = settings.Style.BottomPercent;
        Placement.SelectedItem = Placement.Items.Cast<ComboBoxItem>().First(item => (string)item.Tag == settings.Style.Placement.ToString());
        ShowPlacement(settings.Style.Placement);
        BackgroundOpacity.Value = settings.Style.Background;
        Bold.IsChecked = settings.Style.Bold;
        // Yalnız çeviri modeli olan diller listelenir; tek dil varsa seçim gösterilmez.
        foreach (var (code, name) in Languages.Where(l => controller.SupportsLanguage(l.Code)))
            GameLanguage.Items.Add(new ComboBoxItem { Content = Localizer.Current[name], Tag = code, IsSelected = code == settings.SourceLanguage });
        LanguageCard.Visibility = GameLanguage.Items.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        (settings.FreeAreaTarget switch { ResultTarget.Pc => FreePc, ResultTarget.Both => FreeBoth, _ => FreeTv }).IsChecked = true;
        Region.Frame = controller.LastFrame;
        ObsAddress.Text = $"http://localhost:{controller.ServerPort}/obs";
        ShowArea(0);
        // Num 8: oyunun o anki görüntüsü önizlemeye alınır.
        controller.SnapshotRequested += OnSnapshot;
        Closed += (_, _) => controller.SnapshotRequested -= OnSnapshot;
        Dubbing.Attach(controller);
        Engine.SelectedItem = Engine.Items.Cast<ComboBoxItem>().First(item => (string)item.Tag == settings.Engine.ToString());
        ShowEngine();
        loading = false;
    }

    /// <summary>Seçili motor (ayarlarda ücretsiz ise Free).</summary>
    private TranslationEngine SelectedEngine =>
        Engine.SelectedItem is ComboBoxItem { Tag: string tag } ? Enum.Parse<TranslationEngine>(tag) : TranslationEngine.Free;

    private void ShowEngine()
    {
        var text = Localizer.Current;
        var engine = SelectedEngine;
        EngineHint.Text = text[engine switch
        {
            TranslationEngine.Free => "Free. The translation model built into CouchSubs runs on this computer; subtitle text never leaves it.",
            TranslationEngine.DeepL => "Optional. With your own free DeepL key, translations read more naturally. Subtitle text is sent to DeepL; when DeepL cannot be reached, the translation model on this computer takes over.",
            TranslationEngine.Gemini => "Google's AI translates with the game's tone and keeps names as they are. Subtitle text is sent to Google with your own key, and any cost is billed to your Google account. When Gemini cannot be reached, the free translation takes over.",
            TranslationEngine.OpenAi => "OpenAI's AI translates with the game's tone and keeps names as they are. Subtitle text is sent to OpenAI with your own key, and any cost is billed to your OpenAI account. When OpenAI cannot be reached, the free translation takes over.",
            _ => "Anthropic's Claude translates with the game's tone and keeps names as they are. Subtitle text is sent to Anthropic with your own key, and any cost is billed to your Anthropic account. When Claude cannot be reached, the free translation takes over.",
        }];
        EnglishOnlyHint.Visibility = engine != TranslationEngine.Free && controller.Settings.SourceLanguage != "en" ? Visibility.Visible : Visibility.Collapsed;
        KeyPanel.Visibility = engine == TranslationEngine.Free ? Visibility.Collapsed : Visibility.Visible;
        KeyStatus.Visibility = Visibility.Collapsed;
        KeyError.Visibility = Visibility.Collapsed;
        if (engine == TranslationEngine.Free) return;

        var saved = controller.HasKey(engine);
        NewKey.Visibility = saved ? Visibility.Collapsed : Visibility.Visible;
        SavedKey.Visibility = saved ? Visibility.Visible : Visibility.Collapsed;
        // DeepL'in denemesi bu ayki kullanımı gösterir; ayrı bir "Dene" düğmesi gerekmez.
        KeyTest.Visibility = engine == TranslationEngine.DeepL ? Visibility.Collapsed : Visibility.Visible;
        NoKeyHint.Visibility = engine == TranslationEngine.DeepL ? Visibility.Collapsed : Visibility.Visible;
        var provider = engine.Provider();
        KeyLink.NavigateUri = provider?.KeyPage() ?? new Uri("https://www.deepl.com/pro-api");
        KeyLinkText.Text = provider is { } named ? text.Format("Get a %@ API key", named.DisplayName()) : text["Get a free DeepL API key"];
        ModelPanel.Visibility = provider is null ? Visibility.Collapsed : Visibility.Visible;
        if (provider is { } p) ShowModels(p);
        if (saved && engine == TranslationEngine.DeepL) _ = ShowDeepLUsageAsync();
    }

    private void ShowStatus(string message, bool error)
    {
        KeyStatus.Visibility = error ? Visibility.Collapsed : Visibility.Visible;
        KeyError.Visibility = error ? Visibility.Visible : Visibility.Collapsed;
        (error ? KeyError : KeyStatus).Text = message;
    }

    private void ShowDeepLStatus(OnlineKeyCheck check)
    {
        var text = Localizer.Current;
        ShowStatus(check.State switch
        {
            OnlineKeyState.Valid => text.Format("This month: %1$@ of %2$@ characters used.", check.Used.ToString("N0"), check.Limit.ToString("N0")),
            OnlineKeyState.QuotaExceeded => text["This month's DeepL limit is used up. Until it renews, the translation model on this computer translates."],
            OnlineKeyState.Invalid => text["DeepL did not accept this key. Copy it again from your DeepL account page."],
            _ => text["DeepL could not be reached. Check your internet connection."],
        }, check.State is not (OnlineKeyState.Valid or OnlineKeyState.QuotaExceeded));
    }

    private void ShowAiResult(AiTestResult result, TranslationEngine engine)
    {
        if (result.State == OnlineKeyState.Valid)
            ShowStatus(Localizer.Current.Format("It works. Sample translation: %@", result.Sample ?? ""), false);
        else
            ShowStatus(result.State.Describe(engine, Localizer.Current), true);
    }

    private async Task ShowDeepLUsageAsync() => ShowDeepLStatus(await controller.CheckDeepLKeyAsync());

    private void OnEngine(object sender, SelectionChangedEventArgs e)
    {
        if (loading) return;
        Update(s => s.WithEngine(SelectedEngine));
        ShowEngine();
    }

    private async void OnKeySave(object sender, RoutedEventArgs e)
    {
        var engine = SelectedEngine;
        KeySave.IsEnabled = false;
        try
        {
            if (engine.Provider() is { } provider)
            {
                var result = await controller.SetAiKeyAsync(provider, KeyBox.Password);
                var saved = controller.HasKey(engine);
                if (saved) KeyBox.Clear();
                ShowEngine();
                ShowAiResult(result, engine);
            }
            else
            {
                var check = await controller.SetDeepLKeyAsync(KeyBox.Password);
                if (controller.HasDeepLKey) KeyBox.Clear();
                ShowEngine();
                ShowDeepLStatus(check);
            }
        }
        finally
        {
            KeySave.IsEnabled = true;
        }
    }

    private async void OnKeyTest(object sender, RoutedEventArgs e)
    {
        var engine = SelectedEngine;
        if (engine.Provider() is not { } provider) return;
        KeyTest.IsEnabled = false;
        KeyTest.Content = Localizer.Current["Testing…"];
        try
        {
            ShowAiResult(await controller.TestAiKeyAsync(provider), engine);
        }
        finally
        {
            KeyTest.IsEnabled = true;
            KeyTest.Content = Localizer.Current["Test"];
        }
    }

    private void OnKeyRemove(object sender, RoutedEventArgs e)
    {
        var engine = SelectedEngine;
        controller.RemoveKey(engine);
        ShowEngine();
    }

    /// <summary>Hizmetin listedeki modelleri; seçili olan işaretlenir.</summary>
    private void ShowModels(AiProvider provider)
    {
        var wasLoading = loading;
        loading = true;
        ModelChoice.Items.Clear();
        var selected = provider.Model(controller.Settings.ModelFor(provider)).Id;
        foreach (var option in provider.Models())
            ModelChoice.Items.Add(new ComboBoxItem { Content = Localizer.Current[option.Label], Tag = option.Id, IsSelected = option.Id == selected });
        loading = wasLoading;
    }

    private void OnModel(object sender, SelectionChangedEventArgs e)
    {
        if (loading || SelectedEngine.Provider() is not { } provider || ModelChoice.SelectedItem is not ComboBoxItem { Tag: string id }) return;
        Update(s => s.WithModel(provider, id));
    }

    private void OnLink(object sender, RequestNavigateEventArgs e) =>
        Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true });

    public static void Open(Window? owner, AppController controller) =>
        new SettingsWindow(controller) { Owner = owner }.ShowDialog();

    private void Update(Func<UserSettings, UserSettings> change)
    {
        if (!loading) controller.Settings = change(controller.Settings);
    }

    private void OnTextSize(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (loading) return;
        var size = (int)Math.Round(e.NewValue);
        TextSizeValue.Text = size.ToString();
        Update(s => s with { Style = s.Style with { FontSize = size } });
    }

    private void OnFreeTarget(object sender, RoutedEventArgs e)
    {
        if (loading || sender is not RadioButton { Tag: string tag }) return;
        var target = Enum.Parse<ResultTarget>(tag);
        Update(s => s with { FreeAreaTarget = target });
    }

    /// <summary>Önizlemeyi oyunun şu anki görüntüsüyle yeniler (çerçeve olduğu gibi kalır).</summary>
    private void OnRefresh(object sender, RoutedEventArgs e) => Region.Frame = controller.LastFrame;

    private void OnSnapshot() => Dispatcher.Invoke(() => Region.Frame = controller.LastFrame);

    private void OnPosition(object sender, RoutedPropertyChangedEventArgs<double> e) =>
        Update(s => s with { Style = s.Style with { BottomPercent = (int)Math.Round(e.NewValue) } });

    private void OnPositionStart(object sender, System.Windows.Input.MouseButtonEventArgs e) => controller.SendTestSubtitle();

    private void OnPlacement(object sender, SelectionChangedEventArgs e)
    {
        if (Placement.SelectedItem is not ComboBoxItem { Tag: string tag }) return;
        var placement = Enum.Parse<SubtitlePlacement>(tag);
        ShowPlacement(placement);
        Update(s => s with { Style = s.Style with { Placement = placement } });
    }

    /// <summary>Elle ayarlanan yükseklik yalnız sabit yerleşimde anlamlıdır.</summary>
    private void ShowPlacement(SubtitlePlacement placement)
    {
        var isFixed = placement == SubtitlePlacement.Fixed;
        FixedPanel.Visibility = isFixed ? Visibility.Visible : Visibility.Collapsed;
        FollowsHint.Visibility = isFixed ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnBackground(object sender, RoutedPropertyChangedEventArgs<double> e) =>
        Update(s => s with { Style = s.Style with { Background = (int)Math.Round(e.NewValue) } });

    private void OnBold(object sender, RoutedEventArgs e) =>
        Update(s => s with { Style = s.Style with { Bold = Bold.IsChecked == true } });

    private void OnLanguage(object sender, SelectionChangedEventArgs e)
    {
        if (GameLanguage.SelectedItem is ComboBoxItem { Tag: string code }) Update(s => s with { SourceLanguage = code });
    }

    private void OnRegion(object? sender, CropRegion region)
    {
        var slot = area;
        Update(s => slot == 0 ? s with { Region = region } : s.WithExtraRegion(slot, region));
    }

    private void OnArea(object sender, RoutedEventArgs e)
    {
        if (!loading && sender is RadioButton { Tag: string tag }) ShowArea(int.Parse(tag));
    }

    /// <summary>Seçilen bölgenin çerçevesini gösterir; ek bölge kapalıysa çerçeve düzenlenemez.</summary>
    private void ShowArea(int slot)
    {
        area = slot;
        var wasLoading = loading;
        loading = true;
        var text = Localizer.Current;
        var settings = controller.Settings;
        if (slot == 0)
        {
            UseArea.Visibility = Visibility.Collapsed;
            ExtraTargetPanel.Visibility = Visibility.Collapsed;
            Region.IsEnabled = true;
            Region.DefaultRegion = new CropRegion();
            Region.ShowRegion(settings.Region);
            AreaHint.Text = text["Drag on the picture to draw the area where the game shows its subtitles. Drag the edges to resize it, or the inside to move it."];
        }
        else
        {
            var extra = settings.ExtraRegion(slot);
            UseArea.Visibility = Visibility.Visible;
            UseArea.IsChecked = extra is not null;
            ExtraTargetPanel.Visibility = Visibility.Visible;
            (settings.ExtraTarget(slot) switch { ResultTarget.Pc => ExtraPc, ResultTarget.Both => ExtraBoth, _ => ExtraTv }).IsChecked = true;
            Region.IsEnabled = extra is not null;
            Region.DefaultRegion = ExtraDefaults[slot - 1];
            Region.ShowRegion(extra ?? ExtraDefaults[slot - 1]);
            AreaHint.Text = text["Draw the area to translate, for example a quest panel. While you play, press its key (Num 1, 2 or 3) to read and translate it once. Choose where the result shows. It works even when CouchSubs is in the background."];
        }
        loading = wasLoading;
    }

    private void OnExtraTarget(object sender, RoutedEventArgs e)
    {
        if (loading || area == 0 || sender is not RadioButton { Tag: string tag }) return;
        var slot = area;
        var target = Enum.Parse<ResultTarget>(tag);
        Update(s => s.WithExtraTarget(slot, target));
    }

    private void OnUseArea(object sender, RoutedEventArgs e)
    {
        if (loading || area == 0) return;
        var on = UseArea.IsChecked == true;
        Region.IsEnabled = on;
        var slot = area;
        var region = Region.Region;
        Update(s => s.WithExtraRegion(slot, on ? region : null));
    }

    private void OnTest(object sender, RoutedEventArgs e) => controller.SendTestSubtitle();

    private void OnAbout(object sender, RoutedEventArgs e) => AboutWindow.Open(this);

    private void OnReset(object sender, RoutedEventArgs e)
    {
        var text = Localizer.Current;
        var answer = MessageBox.Show(this, text["The saved PS5, account and TV connection will be removed."], text["Set up again?"],
            MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (answer != MessageBoxResult.OK) return;
        controller.ResetSetup();
        Close();
    }

    private void OnDone(object sender, RoutedEventArgs e) => Close();

    private void OnObsCopy(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(ObsAddress.Text);
            ObsCopy.Content = Localizer.Current["Copied"];
        }
        catch (System.Runtime.InteropServices.COMException) { }
    }
}
