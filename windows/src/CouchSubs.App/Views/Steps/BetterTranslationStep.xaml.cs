// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

/// <summary>
/// "Daha iyi çeviri (ücretsiz)": "Kaydet ve dene" ayarlardaki denemeyi çalıştırır; anahtar kabul edilince Gemini seçilir.
/// Alttaki düğme anahtar yokken "Şimdilik geç", varken "Devam" olur (OnboardingView).
/// </summary>
public partial class BetterTranslationStep : UserControl
{
    public BetterTranslationStep()
    {
        InitializeComponent();
        Loaded += (_, _) => ShowState();
    }

    private AppController Controller => (AppController)DataContext;

    private void ShowState()
    {
        var ready = Controller.UsesFreeGemini;
        Ready.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
        NewKey.Visibility = ready ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnGetKey(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo(AiProvider.Gemini.KeyPage().AbsoluteUri) { UseShellExecute = true });

    private void OnKeyChanged(object sender, RoutedEventArgs e) => KeySave.IsEnabled = KeyBox.Password.Trim().Length > 0;

    private async void OnSave(object sender, RoutedEventArgs e)
    {
        KeySave.IsEnabled = false;
        KeySave.Content = Localizer.Current["Testing…"];
        KeyStatus.Visibility = Visibility.Collapsed;
        KeyError.Visibility = Visibility.Collapsed;
        try
        {
            var result = await Controller.SetAiKeyAsync(AiProvider.Gemini, KeyBox.Password);
            if (Controller.HasKey(TranslationEngine.Gemini)) KeyBox.Clear();
            var works = result.State == OnlineKeyState.Valid;
            var message = works
                ? Localizer.Current.Format("It works. Sample translation: %@", result.Sample ?? "")
                : result.State.Describe(TranslationEngine.Gemini, Localizer.Current);
            (works ? KeyStatus : KeyError).Text = message;
            (works ? KeyStatus : KeyError).Visibility = Visibility.Visible;
            ShowState();
        }
        finally
        {
            KeySave.Content = Localizer.Current["Save and test"];
            KeySave.IsEnabled = KeyBox.Password.Trim().Length > 0;
        }
    }
}
