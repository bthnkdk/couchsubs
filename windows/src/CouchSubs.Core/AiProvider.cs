// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json.Serialization;

namespace CouchSubs.Core;

/// <summary>Kullanıcının kendi anahtarıyla çalışan yapay zekâ çeviri hizmetleri (Mac'teki AIProvider ile aynı).</summary>
[JsonConverter(typeof(JsonStringEnumConverter<AiProvider>))]
public enum AiProvider { Gemini, OpenAi, Claude }

public static class AiProviders
{
    /// <summary>Hızlı ve ucuz varsayılan model; kullanıcı ayarlarda değiştirebilir (Kasım 2026'da belgelerden denetlendi).</summary>
    public static string DefaultModel(this AiProvider provider) => provider switch
    {
        // "Our fastest, most cost-effective 3.5 model", düşünmesi varsayılan olarak en az düzeyde
        // (aistudio.google.com/docs/models, aistudio.google.com/docs/thinking).
        AiProvider.Gemini => "gemini-3.5-flash-lite",
        // "Our most efficient model for focused, high-volume tasks", reasoning_effort "none" destekler
        // (developers.openai.com/api/docs/models).
        AiProvider.OpenAi => "gpt-6-luna",
        // "Fastest", gecikmeye duyarlı işler için (platform.claude.com/docs/en/about-claude/models/overview).
        _ => "claude-haiku-5-5",
    };

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

    /// <summary>Boş ya da yalnız boşluk olan model adı varsayılana döner.</summary>
    public static string Model(this AiProvider provider, string? custom) =>
        string.IsNullOrWhiteSpace(custom) ? provider.DefaultModel() : custom.Trim();
}

/// <summary>Çevrimiçi çevirmen hatasını bildirir; ana ekran "şu an çevirmiyor" uyarısını bundan gösterir.</summary>
public interface IOnlineTranslator
{
    /// <summary>Hata başlayınca durumla, düzelince null ile çağrılır (yalnız değişince).</summary>
    event Action<OnlineKeyState?>? FailureChanged;
}

/// <summary>Ayarlardaki "Dene": örnek satırın çevirisi ya da hatanın türü.</summary>
public sealed record AiTestResult(OnlineKeyState State, string? Sample = null);
