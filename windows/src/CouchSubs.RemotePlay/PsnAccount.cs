// SPDX-License-Identifier: AGPL-3.0-only
// PSN girişiyle Remote Play kaydı için gereken hesap kimliğini alır.
// Akış ve istemci bilgileri chiaki-ng'den (gui/include/psnaccountid.h, gui/src/psnaccountid.cpp).

using System.Buffers.Binary;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace CouchSubs.RemotePlay;

/// <summary>PSN girişinin nerede ve neden bittiği; kullanıcıya ayrı ayrı anlatılır.</summary>
public enum PsnLoginFailure
{
    /// <summary>Yönlendirmede ne kod ne de Sony'nin hatası var.</summary>
    NoCode,
    /// <summary>Sony girişi tamamlamadı: yönlendirmede <c>error=...</c> (ör. access_denied) ya da token isteği reddedildi.</summary>
    Refused,
    /// <summary>Sony çok fazla deneme dedi (HTTP 429 ya da hata metninde "too many").</summary>
    RateLimited,
    /// <summary>Sony'nin sunucusu HTTP hata kodu döndürdü.</summary>
    Http,
    /// <summary>Sony'ye ulaşılamadı ya da yanıt zamanında gelmedi.</summary>
    Network,
    /// <summary>Yanıt anlaşılamadı (beklenen alan yok).</summary>
    BadResponse,
}

public sealed class PsnAccountException : Exception
{
    /// <summary>Sunucu hata durumu döndürdüyse HTTP kodu; yanıt anlaşılamadıysa null.</summary>
    public int? StatusCode { get; }
    public PsnLoginFailure Failure { get; }
    /// <summary>Sony'nin bildirdiği hata (ör. "invalid_grant: Invalid authorization code") ya da ağ hatası; iletiye ve günlüğe yazılır.</summary>
    public string? Detail { get; }

    public PsnAccountException(int? statusCode = null)
        : this(statusCode is null ? PsnLoginFailure.BadResponse : statusCode == 429 ? PsnLoginFailure.RateLimited : PsnLoginFailure.Http, statusCode) { }

    public PsnAccountException(PsnLoginFailure failure, int? statusCode = null, string? detail = null, Exception? inner = null)
        : base($"PSN sign-in failed: {failure}{(statusCode is { } code ? $" (HTTP {code})" : "")}{(detail is null ? "" : $" {detail}")}", inner)
    {
        Failure = failure;
        StatusCode = statusCode;
        Detail = detail;
    }
}

public static class PsnAccount
{
    internal const string ClientId = "ba495a24-818c-472b-b12d-ff231c1b5745";
    internal const string ClientSecret = "mvaiZkRsAsI1IBkY";
    internal const string TokenUrl = "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token";
    internal const string Scope = "psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update";

    public const string RedirectPrefix = "https://remoteplay.dl.playstation.net/remoteplay/redirect";

    /// <summary>Çerezsiz: varsayılan HttpClient Sony'nin çerezlerini uygulama açık kaldıkça saklardı; bağlantılar
    /// sıfırlanıp yeniden giriş yapılınca eski oturumun çerezleri gönderilmesin.</summary>
    private static readonly HttpClient SharedClient = new(new SocketsHttpHandler { UseCookies = false }) { Timeout = TimeSpan.FromSeconds(30) };

    /// <summary>Uygulama içi tarayıcıda (WebView2) açılacak Sony giriş sayfası.</summary>
    public static Uri AuthorizeUrl { get; } = new("https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?" + Query(
    [
        ("service_entity", "urn:service-entity:psn"),
        ("response_type", "code"),
        ("client_id", ClientId),
        ("redirect_uri", RedirectPrefix),
        ("scope", Scope),
        ("request_locale", "en_US"),
        ("ui", "pr"),
        ("service_logo", "ps"),
        ("layout_type", "popup"),
        ("smcid", "remoteplay"),
        ("prompt", "always"),
        ("PlatformPrivacyWs1", "minimal"),
    ]));

    /// <summary>Giriş bitince tarayıcının gittiği yönlendirme adresinden tek kullanımlık kodu çıkarır.</summary>
    public static string? CodeFromRedirect(Uri url) => IsRedirect(url) ? QueryValue(url, "code") : null;

    /// <summary>Sony girişi tamamlamadıysa yönlendirmedeki hata (ör. "access_denied: ..."); yoksa null.</summary>
    public static string? ErrorFromRedirect(Uri url)
    {
        if (!IsRedirect(url) || QueryValue(url, "error") is not { Length: > 0 } error) return null;
        // Sony açıklamadaki boşlukları "+" ile yazar.
        var description = QueryValue(url, "error_description")?.Replace('+', ' ');
        var code = QueryValue(url, "error_code");
        return error + (string.IsNullOrEmpty(description) ? "" : $": {description}") + (string.IsNullOrEmpty(code) ? "" : $" ({code})");
    }

    private static bool IsRedirect(Uri url) => url.IsAbsoluteUri && url.AbsoluteUri.StartsWith(RedirectPrefix, StringComparison.Ordinal);

    private static string? QueryValue(Uri url, string wanted)
    {
        foreach (var pair in url.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var separator = pair.IndexOf('=');
            var name = Uri.UnescapeDataString(separator < 0 ? pair : pair[..separator]);
            if (name == wanted) return separator < 0 ? "" : Uri.UnescapeDataString(pair[(separator + 1)..]);
        }
        return null;
    }

    private static bool LooksRateLimited(string? text) =>
        text is not null && (text.Contains("too many", StringComparison.OrdinalIgnoreCase) || text.Contains("too_many", StringComparison.OrdinalIgnoreCase)
                             || text.Contains("rate limit", StringComparison.OrdinalIgnoreCase));

    /// <summary>Giriş penceresinin yakaladığı yönlendirmeden hesap kimliği. Sony'nin hatası, HTTP hatası, ağ hatası ve
    /// anlaşılamayan yanıt ayrı ayrı <see cref="PsnAccountException"/> olur (eskiden hepsi "Giriş tamamlanmadı"ydı).</summary>
    public static Task<byte[]> AccountIdFromRedirectAsync(Uri redirect, CancellationToken ct = default) =>
        AccountIdFromRedirectAsync(redirect, SharedClient, ct);

    internal static async Task<byte[]> AccountIdFromRedirectAsync(Uri redirect, HttpClient client, CancellationToken ct)
    {
        if (CodeFromRedirect(redirect) is { Length: > 0 } code) return await AccountIdAsync(code, client, ct).ConfigureAwait(false);
        var error = ErrorFromRedirect(redirect);
        if (error is null) throw new PsnAccountException(PsnLoginFailure.NoCode);
        throw new PsnAccountException(LooksRateLimited(error) ? PsnLoginFailure.RateLimited : PsnLoginFailure.Refused, detail: error);
    }

    /// <summary>Kodu token'a, token'ı hesap kimliğine (8 bayt) çevirir. Token saklanmaz.</summary>
    public static Task<byte[]> AccountIdAsync(string code, CancellationToken ct = default) => AccountIdAsync(code, SharedClient, ct);

    internal static async Task<byte[]> AccountIdAsync(string code, HttpClient client, CancellationToken ct)
    {
        try
        {
            return await ExchangeAsync(code, client, ct).ConfigureAwait(false);
        }
        catch (HttpRequestException error)
        {
            throw new PsnAccountException(PsnLoginFailure.Network, detail: error.Message, inner: error);
        }
        catch (TaskCanceledException error) when (!ct.IsCancellationRequested)
        {
            // HttpClient zaman aşımı TaskCanceledException olarak gelir.
            throw new PsnAccountException(PsnLoginFailure.Network, detail: "timeout", inner: error);
        }
    }

    private static async Task<byte[]> ExchangeAsync(string code, HttpClient client, CancellationToken ct)
    {
        using var tokenRequest = new HttpRequestMessage(HttpMethod.Post, TokenUrl);
        tokenRequest.Headers.Authorization = BasicAuth;
        tokenRequest.Content = new StringContent(Query(
        [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("scope", Scope),
            ("redirect_uri", RedirectPrefix),
        ]), Encoding.UTF8);
        tokenRequest.Content.Headers.ContentType = new MediaTypeHeaderValue("application/x-www-form-urlencoded");
        using var token = await Json(client, tokenRequest, ct).ConfigureAwait(false);
        if (!token.RootElement.TryGetProperty("access_token", out var accessToken) || accessToken.ValueKind != JsonValueKind.String)
        {
            var error = SonyError(token.RootElement);
            throw error is null ? new PsnAccountException()
                : new PsnAccountException(LooksRateLimited(error) ? PsnLoginFailure.RateLimited : PsnLoginFailure.Refused, detail: error);
        }

        using var infoRequest = new HttpRequestMessage(HttpMethod.Get, TokenUrl + "/" + Uri.EscapeDataString(accessToken.GetString()!));
        infoRequest.Headers.Authorization = BasicAuth;
        using var info = await Json(client, infoRequest, ct).ConfigureAwait(false);
        if (!info.RootElement.TryGetProperty("user_id", out var userId)) throw new PsnAccountException();
        var text = userId.ValueKind switch
        {
            JsonValueKind.String => userId.GetString(),
            JsonValueKind.Number => userId.GetRawText(),
            _ => null,
        };
        return (text is null ? null : AccountIdBytes(text)) ?? throw new PsnAccountException();
    }

    /// <summary>Ondalık <c>user_id</c>'yi 8 baytlık little-endian dizisine çevirir.</summary>
    internal static byte[]? AccountIdBytes(string userId)
    {
        if (!ulong.TryParse(userId, NumberStyles.None, CultureInfo.InvariantCulture, out var value)) return null;
        var bytes = new byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(bytes, value);
        return bytes;
    }

    private static AuthenticationHeaderValue BasicAuth =>
        new("Basic", Convert.ToBase64String(Encoding.UTF8.GetBytes($"{ClientId}:{ClientSecret}")));

    private static async Task<JsonDocument> Json(HttpClient client, HttpRequestMessage request, CancellationToken ct)
    {
        using var response = await client.SendAsync(request, ct).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            var status = (int)response.StatusCode;
            var error = await ErrorBody(response, ct).ConfigureAwait(false);
            // 400/401/403: Sony kodu kabul etmedi (ör. invalid_grant: kod kullanılmış ya da süresi dolmuş).
            var failure = status == 429 || LooksRateLimited(error) ? PsnLoginFailure.RateLimited
                : status is 400 or 401 or 403 ? PsnLoginFailure.Refused : PsnLoginFailure.Http;
            throw new PsnAccountException(failure, status, error);
        }
        var body = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        try
        {
            var document = await JsonDocument.ParseAsync(body, cancellationToken: ct).ConfigureAwait(false);
            if (document.RootElement.ValueKind == JsonValueKind.Object) return document;
            document.Dispose();
        }
        catch (JsonException)
        {
        }
        throw new PsnAccountException();
    }

    /// <summary>Sony'nin JSON hatasından "error: error_description (error_code)"; JSON değilse metnin başı.</summary>
    private static async Task<string?> ErrorBody(HttpResponseMessage response, CancellationToken ct)
    {
        try
        {
            var text = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(text)) return null;
            try
            {
                using var document = JsonDocument.Parse(text);
                if (document.RootElement.ValueKind == JsonValueKind.Object && SonyError(document.RootElement) is { } error) return error;
            }
            catch (JsonException)
            {
            }
            var trimmed = text.Trim();
            return trimmed.Length > 200 ? trimmed[..200] : trimmed;
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        {
            return null;
        }
    }

    internal static string? SonyError(JsonElement root)
    {
        string? Text(string name) => root.TryGetProperty(name, out var value)
            ? value.ValueKind == JsonValueKind.String ? value.GetString() : value.ValueKind == JsonValueKind.Number ? value.GetRawText() : null
            : null;
        var error = Text("error");
        if (string.IsNullOrEmpty(error)) return null;
        var description = Text("error_description");
        var code = Text("error_code");
        return error + (string.IsNullOrEmpty(description) ? "" : $": {description}") + (string.IsNullOrEmpty(code) ? "" : $" ({code})");
    }

    /// <summary>Mac'teki URLComponents gibi kodlar: sorguda izinli karakterler (":" ve "/" dahil) olduğu gibi kalır.</summary>
    internal static string Query(IEnumerable<(string Name, string Value)> items) =>
        string.Join("&", items.Select(item => Encode(item.Name) + "=" + Encode(item.Value)));

    private static string Encode(string text)
    {
        var result = new StringBuilder(text.Length);
        foreach (var b in Encoding.UTF8.GetBytes(text))
        {
            var c = (char)b;
            if (char.IsAsciiLetterOrDigit(c) || "-._~:/?@!$'()*,;".Contains(c)) result.Append(c);
            else result.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return result.ToString();
    }
}
