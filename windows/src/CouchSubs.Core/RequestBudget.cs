// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections.Concurrent;

namespace CouchSubs.Core;

/// <summary>
/// Kayan bir dakikalık pencerede en çok <c>perMinute</c> istek hakkı (Mac'teki CouchSubsCore/RequestBudget.swift ile aynı).
/// Gemini'nin ücretsiz katmanı dakikadaki istek sayısını sınırlar; sınırın üstüne çıkan istek 429 alır ve beklemek gerekir.
/// Hak önceden sayılınca istek hiç gönderilmez, o satır hemen yerel çeviriyle çevrilir; böylece hem gecikme hem hata
/// uyarısı olmaz ve pencere boşaldıkça hizmete kendiliğinden dönülür.
/// </summary>
public sealed class RequestBudget
{
    /// <summary>Pencerenin uzunluğu.</summary>
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(1);

    private static readonly ConcurrentDictionary<string, RequestBudget> Registry = new(StringComparer.Ordinal);

    private readonly object gate = new();
    private readonly Func<DateTimeOffset> now;
    /// <summary>Penceredeki isteklerin zamanları, eskiden yeniye.</summary>
    private readonly Queue<DateTimeOffset> sent = new();
    private int limit;

    public RequestBudget(int perMinute, Func<DateTimeOffset>? now = null)
    {
        limit = Math.Max(1, perMinute);
        this.now = now ?? (() => DateTimeOffset.UtcNow);
    }

    /// <summary>Şu anki dakikalık sınır.</summary>
    public int PerMinute
    {
        get { lock (gate) return limit; }
    }

    /// <summary>Hak varsa bir istek hakkı kullanır ve true döner; yoksa false (istek gönderilmemeli).</summary>
    public bool TryTake()
    {
        lock (gate)
        {
            var time = now();
            while (sent.Count > 0 && time - sent.Peek() >= Window) sent.Dequeue();
            if (sent.Count >= limit) return false;
            sent.Enqueue(time);
            return true;
        }
    }

    /// <summary>Hizmet daha düşük bir sınır bildirdi (429 yanıtındaki "quotaValue"); yükseltmez.</summary>
    public void Lower(int perMinute)
    {
        lock (gate) limit = Math.Max(1, Math.Min(limit, perMinute));
    }

    /// <summary>
    /// Modelin uygulama genelindeki ortak hakkı (Google sınırı proje ve model başına sayar; çeviri hattı yeniden kurulsa da
    /// hak sıfırlanmaz); modelin sınırı yoksa null.
    /// </summary>
    public static RequestBudget? Shared(AiProvider provider, AiModel model) =>
        model.RequestsPerMinute is { } perMinute
            ? Registry.GetOrAdd(provider.EngineId(model.Id), _ => new RequestBudget(perMinute))
            : null;
}
