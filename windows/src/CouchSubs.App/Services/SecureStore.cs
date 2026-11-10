// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CouchSubs.App.Services;

/// <summary>
/// Hesap kimliği, PS5 anahtarları ve TV anahtarı. Windows'un veri koruması (DPAPI, yalnız bu kullanıcı)
/// ile şifrelenmiş tek bir dosyada tutulur.
/// </summary>
public sealed class SecureStore(string path)
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("couchsubs-secure-store");
    private readonly object gate = new();

    public static SecureStore Default { get; } = new(Path.Combine(AppPaths.Data, "secure.dat"));

    public void Save<T>(string key, T value)
    {
        lock (gate)
        {
            var all = ReadAll();
            all[key] = JsonSerializer.SerializeToNode(value);
            WriteAll(all);
        }
    }

    public T? Load<T>(string key)
    {
        lock (gate)
        {
            var node = ReadAll()[key];
            if (node is null) return default;
            try { return node.Deserialize<T>(); } catch (JsonException) { return default; }
        }
    }

    public void Remove(string key)
    {
        lock (gate)
        {
            var all = ReadAll();
            if (all.Remove(key)) WriteAll(all);
        }
    }

    private JsonObject ReadAll()
    {
        if (!File.Exists(path)) return [];
        try
        {
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
            return JsonNode.Parse(plain) as JsonObject ?? [];
        }
        catch (Exception error) when (error is CryptographicException or JsonException)
        {
            // Başka kullanıcıdan kopyalanmış ya da bozulmuş dosya: kurulum baştan yapılır.
            return [];
        }
    }

    private void WriteAll(JsonObject all)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var cipher = ProtectedData.Protect(Encoding.UTF8.GetBytes(all.ToJsonString()), Entropy, DataProtectionScope.CurrentUser);
        var temporary = path + ".tmp";
        File.WriteAllBytes(temporary, cipher);
        File.Move(temporary, path, overwrite: true);
    }
}

/// <summary>Uygulamanın kullanıcıya özel klasörü (%LOCALAPPDATA%\CouchSubs).</summary>
public static class AppPaths
{
    public static string Data { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CouchSubs");
    public static string Models { get; } = Path.Combine(Data, "models");
    /// <summary>Kalıcı çeviri önbellekleri (motor ve dil çifti başına bir dosya).</summary>
    public static string Translations { get; } = Path.Combine(Data, "translations");
}
