// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

public partial class TestStep : UserControl
{
    public TestStep()
    {
        InitializeComponent();
        Loaded += (_, _) => ShowTarget();
    }

    private AppController Controller => (AppController)DataContext;

    /// <summary>TV seçilmediyse ("TV'm yok") örnek altyazı bu bilgisayarın ekranında görünür.</summary>
    private void ShowTarget()
    {
        if (Controller.Settings.Output != SubtitleOutput.Computer) return;
        var text = Localizer.Current;
        Layout.Message = text["CouchSubs will show a sample subtitle on this computer's screen, at the bottom."];
        Question.Title = text["Do you see it on the screen?"];
        Hint.Text = text["If you don't see it, send it again. It shows for a few seconds at the bottom of the screen."];
        Adjust.Visibility = Visibility.Visible;
    }

    private void OnSend(object sender, RoutedEventArgs e)
    {
        Controller.SendTestSubtitle();
        Send.Style = (Style)FindResource("SecondaryButton");
        Question.Visibility = Visibility.Visible;
    }

    private void OnAdjust(object sender, RoutedEventArgs e) => Controller.OverlayAdjusting = true;

    private void OnYes(object sender, RoutedEventArgs e)
    {
        Controller.OverlayAdjusting = false;
        Controller.Advance();
    }

    private void OnNo(object sender, RoutedEventArgs e) => Controller.Step = OnboardingStep.Tv;
}
