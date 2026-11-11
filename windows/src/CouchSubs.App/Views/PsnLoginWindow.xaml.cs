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
    /// <summary>Pencerenin gördüğü son sorun (sayfa açılamadı, Sony'nin HTTP hatası, WebView2 çöktü); kapanınca bildirilir.</summary>
    private string? problem;

    private PsnLoginWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            try
            {
                await OpenAsync();
            }
            catch (Exception error)
            {
                // WebView2 başlatılamadı: eskiden işlenmeyen istisna olurdu.
                problem = $"WebView2: {error.Message}";
                Close();
            }
        };
    }

    /// <summary>Giriş tamamlanırsa yönlendirme adresini döner; tamamlanmadan kapanırsa adres null, <c>Problem</c> pencerenin
    /// gördüğü sorun (kullanıcı kendisi kapattıysa null).</summary>
    public static (Uri? Redirect, string? Problem) Show(Window? owner)
    {
        var window = new PsnLoginWindow { Owner = owner };
        window.ShowDialog();
        return (window.redirect, window.redirect is null ? window.problem : null);
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
        Browser.CoreWebView2.NavigationCompleted += OnNavigationCompleted;
        Browser.CoreWebView2.ProcessFailed += (_, e) =>
        {
            problem = $"WebView2 {e.ProcessFailedKind}";
            RemotePlayLog.Note($"PSN giriş penceresi: {problem}");
        };
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

    /// <summary>Sony'nin sayfası açılamadıysa ya da hata kodu döndürdüyse (ör. 429 çok fazla deneme) not edilir; giriş
    /// bitmeden pencere kapanınca kullanıcıya bu söylenir. Başarılı sayfa önceki sorunu siler.</summary>
    private void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        // Yönlendirmeyi kendimiz iptal ediyoruz; o bir sorun değildir.
        if (redirect is not null) return;
        if (!e.IsSuccess && e.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled)
            problem = e.HttpStatusCode >= 400 ? $"HTTP {e.HttpStatusCode}" : e.WebErrorStatus.ToString();
        else if (e.IsSuccess && e.HttpStatusCode >= 400)
            problem = $"HTTP {e.HttpStatusCode}";
        else if (e.IsSuccess)
            problem = null;
        if (problem is not null) RemotePlayLog.Note($"PSN giriş sayfası: {problem}");
    }

    private void OnCancel(object sender, RoutedEventArgs e) => Close();
}
