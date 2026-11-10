// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json.Serialization;

namespace CouchSubs.Core;

/// <summary>Kullanıcının kendi anahtarıyla çalışan yapay zekâ çeviri hizmetleri (Mac'teki AIProvider ile aynı).</summary>
[JsonConverter(typeof(JsonStringEnumConverter<AiProvider>))]
public enum AiProvider { Gemini, OpenAi, Claude }

public static class AiProviders
{
    /// <summary>
    /// Seçilebilen modeller; ilki varsayılandır (hızlı ve ucuz). Liste Mac ile ortak <c>ai-models.json</c> dosyasından
    /// gelir (core/Sources/CouchSubsCore/Resources, gömülü kaynak).
    /// </summary>
    public static IReadOnlyList<AiModel> Models(this AiProvider provider) =>
        AiModel.Catalog.TryGetValue(provider.Id(), out var models) ? models : [];

    /// <summary>Hızlı ve ucuz varsayılan model.</summary>
    public static AiModel DefaultModel(this AiProvider provider) => provider.Models()[0];

    /// <summary>Marka adı; çevrilmez.</summary>
    public static string DisplayName(this AiProvider provider) => provider switch
    {
        AiProvider.Gemini => "Gemini",
        AiProvider.OpenAi => "OpenAI",
        _ => "Claude",
    };

    /// <summary>Anahtarın alındığı resmî sayfa.</summary>
    public static Uri KeyPage(this AiProvider provider) => new(provider switch
    {
        AiProvider.Gemini => "https://aistudio.google.com/apikey",
        AiProvider.OpenAi => "https://platform.openai.com/api-keys",
        _ => "https://platform.claude.com/settings/keys",
    });

    /// <summary>Kalıcı önbellek dosyasındaki ve Mac'teki ad: "gemini", "openai", "claude".</summary>
    public static string Id(this AiProvider provider) => provider switch
    {
        AiProvider.Gemini => "gemini",
        AiProvider.OpenAi => "openai",
        _ => "claude",
    };

    /// <summary>Önbellekteki motor adı: model değişince eski modelin çevirileri karışmaz ("gemini:gemini-3.5-flash-lite").</summary>
    public static string EngineId(this AiProvider provider, string model) => $"{provider.Id()}:{model}";

    /// <summary>Kayıtlı model listede yoksa (eski ayar ya da listeden çıkarılan model) varsayılan model.</summary>
    public static AiModel Model(this AiProvider provider, string? id) =>
        provider.Models().FirstOrDefault(m => m.Id == id) ?? provider.DefaultModel();
}

/// <summary>
/// Listedeki bir model ve onunla gönderilen ayarlar (Mac'teki AIModel ile aynı). Kullanıcı model adı yazamaz; yalnız bu
/// listeden seçer.
/// </summary>
/// <param name="Label">Ayarlarda görünen ad (Localizable.xcstrings anahtarı).</param>
/// <param name="Effort">OpenAI'da <c>reasoning_effort</c>, Claude'da <c>output_config.effort</c>; null ise gönderilmez.</param>
/// <param name="Thinking">Gemini'de <c>thinkingConfig.thinkingLevel</c>, Claude'da <c>thinking.type</c>; null ise gönderilmez.</param>
public sealed record AiModel(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("effort")] string? Effort = null,
    [property: JsonPropertyName("thinking")] string? Thinking = null)
{
    /// <summary><c>ai-models.json</c>: hizmet adı → modeller.</summary>
    internal static readonly IReadOnlyDictionary<string, IReadOnlyList<AiModel>> Catalog = Load();

    private static IReadOnlyDictionary<string, IReadOnlyList<AiModel>> Load()
    {
        using var stream = typeof(AiModel).Assembly.GetManifestResourceStream("ai-models.json")
            ?? throw new InvalidOperationException("ai-models.json uygulamaya gömülmemiş");
        using var reader = new StreamReader(stream);
        return Parse(reader.ReadToEnd());
    }

    /// <summary>"_comment" gibi dizi olmayan alanlar atlanır.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<AiModel>> Parse(string json)
    {
        var result = new Dictionary<string, IReadOnlyList<AiModel>>(StringComparer.Ordinal);
        using var document = System.Text.Json.JsonDocument.Parse(json);
        foreach (var property in document.RootElement.EnumerateObject())
        {
            if (property.Value.ValueKind != System.Text.Json.JsonValueKind.Array) continue;
            var models = property.Value.EnumerateArray().Select(item => new AiModel(
                item.GetProperty("id").GetString()!, item.GetProperty("label").GetString()!,
                item.TryGetProperty("effort", out var effort) ? effort.GetString() : null,
                item.TryGetProperty("thinking", out var thinking) ? thinking.GetString() : null)).ToList();
            if (models.Count > 0) result[property.Name] = models;
        }
        return result;
    }
}

/// <summary>Çevrimiçi çevirmen hatasını bildirir; ana ekran "şu an çevirmiyor" uyarısını bundan gösterir.</summary>
public interface IOnlineTranslator
{
    /// <summary>Hata başlayınca durumla, düzelince null ile çağrılır (yalnız değişince).</summary>
    event Action<OnlineKeyState?>? FailureChanged;
}

/// <summary>Ayarlardaki "Dene": örnek satırın çevirisi ya da hatanın türü.</summary>
public sealed record AiTestResult(OnlineKeyState State, string? Sample = null);
