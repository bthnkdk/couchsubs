// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using CouchSubs.App.Views.Steps;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

/// <summary>Kurulum sihirbazı: üstte adım sayacı ve ilerleme, ortada adım, altta Geri / Devam.</summary>
public partial class OnboardingView : UserControl
{
    private readonly AppController controller;

    public OnboardingView(AppController controller)
    {
        this.controller = controller;
        DataContext = controller;
        InitializeComponent();
        controller.PropertyChanged += OnChanged;
        Unloaded += (_, _) => controller.PropertyChanged -= OnChanged;
        ShowStep();
    }

    private void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppController.Step)) ShowStep();
        else if (e.PropertyName == nameof(AppController.UsesFreeGemini)) ShowContinue();
    }

    /// <summary>
    /// "Daha iyi çeviri" isteğe bağlıdır: anahtar yokken alttaki düğme ikincil "Şimdilik geç" (birincil düğme adımdaki
    /// "Ücretsiz anahtar al"), anahtar kaydedilince birincil "Devam".
    /// </summary>
    private void ShowContinue()
    {
        var skip = controller.Step == OnboardingStep.BetterTranslation && !controller.UsesFreeGemini;
        ContinueButton.Content = Localizer.Current[skip ? "Skip for now" : "Continue"];
        ContinueButton.Style = (Style)FindResource(skip ? "SecondaryButton" : "PrimaryButton");
        // Anahtar alanında Enter adımı geçmesin.
        ContinueButton.IsDefault = !skip;
    }

    private void ShowStep()
    {
        StepHost.Content = controller.Step switch
        {
            OnboardingStep.Welcome => new WelcomeStep(),
            OnboardingStep.SecondAccount => new SecondAccountStep(),
            OnboardingStep.PsnLogin => new PsnLoginStep(),
            OnboardingStep.Console => new ConsoleStep(),
            OnboardingStep.Tv => new TvStep(),
            OnboardingStep.Translation => new TranslationStep(),
            OnboardingStep.Test => new TestStep(),
            _ => new BetterTranslationStep(),
        };
        Counter.Text = Localizer.Current.Format("Step %lld of %lld", controller.StepNumber, AppController.StepCount);
        Progress.Value = (double)controller.StepNumber / AppController.StepCount;
        BackButton.Visibility = controller.Step == OnboardingStep.Welcome ? Visibility.Hidden : Visibility.Visible;
        ContinueButton.Visibility = controller.Step == OnboardingStep.Test ? Visibility.Hidden : Visibility.Visible;
        ShowContinue();
    }

    private void OnBack(object sender, RoutedEventArgs e) => controller.Back();

    private void OnContinue(object sender, RoutedEventArgs e) => controller.Advance();
}
