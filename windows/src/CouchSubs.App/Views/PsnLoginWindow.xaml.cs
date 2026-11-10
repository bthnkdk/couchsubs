// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Windows;
using CouchSubs.App.Services;
using CouchSubs.RemotePlay;
using Microsoft.Web.WebView2.Core;

namespace CouchSubs.App.Views;

/// <summary>Sony'nin giriş sayfasını açar; giriş bitince yönlendirme adresini yakalar. Parola yalnız Sony'ye gider.</summary>
public partial class PsnLoginWindow : Window
{
    private Uri? redirect;

    private PsnLoginWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await OpenAsync();
    }

    /// <summary>Giriş tamamlanırsa yönlendirme adresini, vazgeçilirse null döner.</summary>
    public static Uri? Show(Window? owner)
    {
        var window = new PsnLoginWindow { Owner = owner };
        window.ShowDialog();
        return window.redirect;
    }

    /// <summary>Microsoft'un WebView2 indirme sayfası (Evergreen kurulumu).</summary>
    public const string BrowserDownloadUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";

    /// <summary>WebView2 çalışma ortamı kurulu mu? Değilse pencere açılırken WebView2RuntimeNotFoundException ile çökerdi.</summary>
    public static bool IsBrowserAvailable()
    {
        try { return !string.IsNullOrEmpty(CoreWebView2Environment.GetAvailableBrowserVersionString()); }
        catch (Exception) { return false; }
    }

    // Tarayıcı süreci kapanana kadar ortam canlı kalmalı; yoksa BrowserProcessExited gelmez.
    private static CoreWebView2Environment? lastEnvironment;

    private async Task OpenAsync()
    {
        // Her girişte temiz oturum: önceki çerezler (ör. kendi hesabınız) karışmasın.
        var root = Path.Combine(AppPaths.Data, "webview");
        DeleteLeftovers(root);
        var folder = Path.Combine(root, Guid.NewGuid().ToString("N"));
        var environment = await CoreWebView2Environment.CreateAsync(null, folder);
        lastEnvironment = environment;
        // WebView2 kapanırken dosyalarını (ör. BrowserMetrics-*.pma) bir süre açık tutar. Klasör ancak tarayıcı
        // süreci bitince silinebilir; silinemeyen klasörü bir sonraki giriş temizler.
        environment.BrowserProcessExited += (_, _) => TryDelete(folder);
        await Browser.EnsureCoreWebView2Async(environment);
        Browser.CoreWebView2.NavigationStarting += OnNavigation;
        Browser.CoreWebView2.Navigate(PsnAccount.AuthorizeUrl.AbsoluteUri);
        Closed += (_, _) => Browser.Dispose();
    }

    private static void DeleteLeftovers(string root)
    {
        if (!Directory.Exists(root)) return;
        foreach (var folder in Directory.EnumerateDirectories(root)) TryDelete(folder);
    }

    private static void TryDelete(string folder)
    {
        try { Directory.Delete(folder, recursive: true); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    private void OnNavigation(object? sender, CoreWebView2NavigationStartingEventArgs e)
    {
        if (!e.Uri.StartsWith(PsnAccount.RedirectPrefix, StringComparison.Ordinal)) return;
        e.Cancel = true;
        redirect = new Uri(e.Uri);
        Close();
    }

    private void OnCancel(object sender, RoutedEventArgs e) => Close();
}
