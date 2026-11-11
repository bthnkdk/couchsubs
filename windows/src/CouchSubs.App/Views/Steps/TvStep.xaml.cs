// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

public partial class TvStep : UserControl
{
    public TvStep()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            ShowDone();
            await SearchAsync();
        };
    }

    private AppController Controller => (AppController)DataContext;

    private void ShowDone()
    {
        Done.Text = Controller.Tv?.Name ?? "";
        Done.Visibility = Controller.Tv is null ? Visibility.Collapsed : Visibility.Visible;
        // Uygulamayla TV paketi gelmediyse (geliştirici derlemesi) rehber gösterilir.
        ManualInstall.Visibility = Controller.Tv is null or { Brand: TvBrand.Lg } || Controller.CanInstallTvApp
            ? Visibility.Collapsed : Visibility.Visible;
    }

    private async Task SearchAsync()
    {
        Search.IsEnabled = false;
        Tvs.Children.Clear();
        var found = await Controller.DiscoverTvsAsync();
        foreach (var tv in found)
        {
            var row = new Grid { Margin = new Thickness(0, 4, 0, 4) };
            row.Children.Add(new TextBlock { Text = $"{tv.Name} — {tv.Host}", VerticalAlignment = VerticalAlignment.Center });
            var connect = new Button { Content = Localizer.Current["Connect"], Style = (Style)FindResource("PrimaryButton"), HorizontalAlignment = HorizontalAlignment.Right };
            connect.Click += async (_, _) => await PairAsync(tv);
            row.Children.Add(connect);
            Tvs.Children.Add(row);
        }
        NotFound.Visibility = found.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        Search.IsEnabled = true;
    }

    private async Task PairAsync(LgTv tv)
    {
        Tvs.IsEnabled = false;
        Waiting.Visibility = Visibility.Visible;
        Error.Text = "";
        try
        {
            await Controller.PairAsync(tv);
            ShowDone();
        }
        catch (SsapException error) when (error.Reason != "cannot connect")
        {
            // TV yanıt verdi ama reddetti ya da süre doldu: gerçek nedeni göster.
            Error.Text = $"{Localizer.Current["The TV did not respond. Make sure it is on and on the same network."]} ({error.Reason})";
        }
        catch (Exception)
        {
            Error.Text = Localizer.Current["The TV did not respond. Make sure it is on and on the same network."];
        }
        Waiting.Visibility = Visibility.Collapsed;
        Tvs.IsEnabled = true;
    }

    private async void OnSearch(object sender, RoutedEventArgs e) => await SearchAsync();

    /// <summary>"TV'm yok": TV kurulmaz, altyazı bilgisayar ekranında gösterilir; sonraki adıma geçilir.</summary>
    private void OnNoTv(object sender, RoutedEventArgs e) => Controller.UseComputerScreen();

    private async void OnAndroidTv(object sender, RoutedEventArgs e) => await PairAsync(new LgTv("Android TV", "", TvBrand.AndroidTv));

    private void OnGuide(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("https://github.com/yorulmazsinan/couchsubs/blob/main/docs/tv-kurulum.md") { UseShellExecute = true });
}
