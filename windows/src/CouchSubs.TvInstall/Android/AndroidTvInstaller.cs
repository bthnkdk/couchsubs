// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace CouchSubs.TvInstall.Android;

/// <summary>
/// CouchSubs'ın Android TV uygulamasını ağ üzerinden kurar. TV'de geliştirici seçenekleri ve USB hata ayıklama
/// açık olmalıdır; Android TV'lerin çoğu bu ayarla 5555 portunda ADB bekler.
/// </summary>
public sealed partial class AndroidTvInstaller(string host, string keyDirectory, int port = AndroidTvInstaller.DefaultPort)
{
    public const int DefaultPort = 5555;
    public const string PackageName = "com.couchsubs.tv";

    /// <summary>Kurulum sırasında TV'nin onay sorusunu göstermesi.</summary>
    public Action? OnApprovalNeeded { get; init; }

    /// <summary>TV'de ADB açık mı (port yanıt veriyor mu)?</summary>
    public static async Task<bool> IsReachableAsync(string host, int port = DefaultPort, TimeSpan? timeout = null)
    {
        using var tcp = new TcpClient();
        using var limit = new CancellationTokenSource(timeout ?? TimeSpan.FromSeconds(1));
        try
        {
            await tcp.ConnectAsync(host, port, limit.Token);
            return true;
        }
        catch (Exception error) when (error is SocketException or OperationCanceledException)
        {
            return false;
        }
    }

    /// <summary>Bu bilgisayarın ağlarında ADB'si açık cihazları arar (her ağın /24 bölümü).</summary>
    public static async Task<IReadOnlyList<string>> ScanAsync(int port = DefaultPort, CancellationToken cancellationToken = default)
    {
        var hosts = ScanTargets(LocalAddresses()).ToList();
        var found = new System.Collections.Concurrent.ConcurrentBag<string>();
        await Parallel.ForEachAsync(hosts, new ParallelOptions { MaxDegreeOfParallelism = 64, CancellationToken = cancellationToken },
            async (candidate, _) =>
            {
                if (await IsReachableAsync(candidate, port, TimeSpan.FromMilliseconds(700))) found.Add(candidate);
            });
        return [.. found.OrderBy(h => IPAddress.Parse(h).GetAddressBytes()[3])];
    }

    internal static IEnumerable<string> ScanTargets(IEnumerable<IPAddress> locals)
    {
        var seen = new HashSet<string>();
        foreach (var local in locals)
        {
            var bytes = local.GetAddressBytes();
            for (var last = 1; last < 255; last++)
            {
                if (last == bytes[3]) continue;
                var candidate = $"{bytes[0]}.{bytes[1]}.{bytes[2]}.{last}";
                if (seen.Add(candidate)) yield return candidate;
            }
        }
    }

    private static IEnumerable<IPAddress> LocalAddresses() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n => n.GetIPProperties().UnicastAddresses)
            .Select(a => a.Address)
            .Where(a => a.AddressFamily == AddressFamily.InterNetwork && IsPrivate(a));

    internal static bool IsPrivate(IPAddress address)
    {
        var b = address.GetAddressBytes();
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
    }

    /// <summary>
    /// Uygulama eksikse ya da eskiyse kurar ve açar; hepsi tek bağlantıda yapılır, TV onayı en çok bir kez sorulur.
    /// </summary>
    /// <returns>TV'de artık bulunan sürüm ve kurulum yapılıp yapılmadığı.</returns>
    public async Task<(string Version, bool Installed)> EnsureInstalledAsync(string apkPath, string version,
        CancellationToken cancellationToken = default)
    {
        await using var adb = await ConnectAsync(cancellationToken);
        var installed = VersionFromDumpsys(await adb.RunAsync($"shell:dumpsys package {PackageName}", cancellationToken: cancellationToken));
        if (installed is not null && !Versions.IsNewer(version, installed))
        {
            await GrantOverlayAsync(adb, cancellationToken);
            return (installed, false);
        }
        await InstallAsync(adb, apkPath, cancellationToken);
        await GrantOverlayAsync(adb, cancellationToken);
        await adb.RunAsync($"shell:am start -n {PackageName}/.MainActivity", cancellationToken: cancellationToken);
        return (version, true);
    }

    /// <summary>
    /// "Diğer uygulamaların üzerinde göster" iznini verir: overlay modunda (TCL) altyazı TV'nin kendi HDMI ekranının
    /// üstünde çizilir. Google TV'lerde bu ayar çoğu zaman menüde gizlidir; verilemezse TV uygulaması kendisi sorar.
    /// </summary>
    private static async Task GrantOverlayAsync(AdbConnection adb, CancellationToken cancellationToken)
    {
        try
        {
            await adb.RunAsync($"shell:appops set {PackageName} SYSTEM_ALERT_WINDOW allow", cancellationToken: cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            // İzin verilemedi: kurulum yine başarılı sayılır.
        }
    }

    internal static string? VersionFromDumpsys(string output) =>
        VersionName().Match(output) is { Success: true } match ? match.Groups[1].Value : null;

    /// <summary>APK'yı kurar. İmzası farklı eski bir kopya varsa önce onu kaldırır.</summary>
    private static async Task InstallAsync(AdbConnection adb, string apkPath, CancellationToken cancellationToken)
    {
        var result = await StreamInstallAsync(adb, apkPath, cancellationToken);
        if (result.Contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE") || result.Contains("INSTALL_FAILED_VERSION_DOWNGRADE"))
        {
            await adb.RunAsync($"shell:pm uninstall {PackageName}", cancellationToken: cancellationToken);
            result = await StreamInstallAsync(adb, apkPath, cancellationToken);
        }
        if (!result.Contains("Success"))
            throw new AndroidInstallException(AndroidInstallError.InstallFailed, result.Trim());
    }

    private static async Task<string> StreamInstallAsync(AdbConnection adb, string apkPath, CancellationToken cancellationToken)
    {
        await using var apk = File.OpenRead(apkPath);
        // Android 7 ve sonrası: dosyayı TV'ye ayrıca kopyalamadan doğrudan paket yöneticisine akıtır.
        return await adb.RunAsync($"exec:cmd package install -r -S {apk.Length}", apk, cancellationToken);
    }

    private Task<AdbConnection> ConnectAsync(CancellationToken cancellationToken) =>
        AdbConnection.ConnectAsync(host, port, LoadOrCreateKey(keyDirectory), OnApprovalNeeded, cancellationToken: cancellationToken);

    /// <summary>
    /// Bu bilgisayarın ADB anahtarı. TV onayı bu anahtara verilir; anahtar değişirse TV yeniden sorar.
    /// </summary>
    public static RSA LoadOrCreateKey(string directory)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "adbkey");
        var key = RSA.Create();
        if (File.Exists(path))
        {
            try
            {
                key.ImportFromPem(File.ReadAllText(path));
                if (key.KeySize == 2048) return key;
            }
            catch (CryptographicException) { /* bozuk dosya: yenisi üretilir */ }
        }
        key.Dispose();
        key = RSA.Create(2048);
        File.WriteAllText(path, key.ExportPkcs8PrivateKeyPem());
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        return key;
    }

    [GeneratedRegex(@"versionName=(\S+)")]
    private static partial Regex VersionName();
}
