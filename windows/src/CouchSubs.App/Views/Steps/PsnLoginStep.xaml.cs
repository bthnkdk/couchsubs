// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

public partial class PsnLoginStep : UserControl
{
    public PsnLoginStep()
    {
        InitializeComponent();
        Loaded += (_, _) => Refresh();
    }

    private AppController Controller => (AppController)DataContext;

    private void Refresh()
    {
        SignIn.Content = Localizer.Current[Controller.HasAccount ? "Sign in again" : "Sign in"];
        SignIn.Style = (Style)FindResource(Controller.HasAccount ? "SecondaryButton" : "PrimaryButton");
    }

    private async void OnSignIn(object sender, RoutedEventArgs e)
    {
        // Giriş penceresi WebView2 ile açılır; kurulum normalde onu da kurar, yine de eksikse çökmek yerine yol gösterilir.
        if (!PsnLoginWindow.IsBrowserAvailable())
        {
            Error.Text = Localizer.Current["The sign-in window needs Microsoft's WebView2 component, which is missing on this computer. Install it from the page that just opened, then press Sign in again."];
            try { Process.Start(new ProcessStartInfo(PsnLoginWindow.BrowserDownloadUrl) { UseShellExecute = true }); }
            catch (Exception) { }
            return;
        }
        var redirect = PsnLoginWindow.Show(Window.GetWindow(this));
        if (redirect is null) return;
        SignIn.IsEnabled = false;
        Error.Text = "";
        try
        {
            await Controller.CompletePsnLoginAsync(redirect);
        }
        catch (Exception error)
        {
            Error.Text = error is AppException ? error.Message : AppException.Describe(AppError.InvalidLogin, Localizer.Current);
        }
        SignIn.IsEnabled = true;
        Refresh();
    }
}
