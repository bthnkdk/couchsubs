// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

public enum StabilizerKind { None, Translate, Clear, Restore }

/// <summary>Okuma hattının bir kareye vereceği tepki.</summary>
public readonly record struct StabilizerAction(StabilizerKind Kind, string? Text = null)
{
    public static readonly StabilizerAction None = new(StabilizerKind.None);
    public static readonly StabilizerAction Clear = new(StabilizerKind.Clear);
    public static StabilizerAction Translate(string text) => new(StabilizerKind.Translate, text);
    /// <summary>Az önce kalkan satır geri geldi; çevirisi yeniden gösterilir, yeniden çevrilmez (metin: ilk gönderilen hali).</summary>
    public static StabilizerAction Restore(string text) => new(StabilizerKind.Restore, text);
}

/// <summary>
/// Kare kare gelen OCR çıktısını izler; altyazı kararlı hale gelince çevrilmesini,
/// ekrandan kalkınca TV'den temizlenmesini ister. Aynı altyazıyı tekrar göndermez.
/// Kararlar okuma hızına değil saate bağlıdır (<paramref name="clock"/>: milisaniye; testlerde sahtesi verilir).
/// </summary>
public sealed class SubtitleStabilizer(double similarity = 0.85, int stableFrames = 2,
    int clearAfterMs = SubtitleStabilizer.ClearAfterMs, Func<long>? clock = null)
{
    /// <summary>Bölge bu kadar boş kalırsa altyazı kalkmış sayılır; parlak arka planda kaçan birkaç okuma silmez.</summary>
    public const int ClearAfterMs = 800;
    /// <summary>Kalkan satır bu süre içinde geri gelirse aynı satırdır (okuma kaçmıştı); yeniden çevrilmez.</summary>
    public const int RestoreWithinMs = 1500;
    /// <summary>Çevirisi başarısız olan satır en erken bu kadar sonra yeniden denenir.</summary>
    public const int RetryAfterMs = 1000;
    private const int HistorySize = 5;

    private readonly Func<long> now = clock ?? (() => Environment.TickCount64);
    private string candidate = "";
    private int candidateCount;
    /// <summary>Ekrandaki (gönderilmiş) satır: sadeleştirilmiş satırlar alt alta, ve ilk okunduğu hali.</summary>
    private string sent = "";
    private string sentRaw = "";
    private long? emptySince;
    /// <summary>Son kalkan satırlar ve kalktıkları an.</summary>
    private readonly List<(string Rows, string Raw, long LeftAt)> history = [];
    /// <summary>Çevirisi başarısız olan satır ve en erken yeniden deneneceği an.</summary>
    private string forgotten = "";
    private long retryAt;

    public StabilizerAction Feed(string rawText)
    {
        var time = now();
        var text = TextMatch.Normalize(rawText);
        // 3 karakterden kısa okumalar (gürültü, tek simge) boş kare sayılır.
        if (text.Length < 3)
        {
            candidate = "";
            candidateCount = 0;
            emptySince ??= time;
            if (sent.Length > 0 && time - emptySince >= clearAfterMs)
            {
                LeaveScreen(time);
                return StabilizerAction.Clear;
            }
            return StabilizerAction.None;
        }

        emptySince = null;
        if (TextMatch.IsSimilar(text, candidate, similarity))
        {
            candidateCount++;
        }
        else
        {
            candidate = text;
            candidateCount = 1;
        }
        // Daktilo efektinde metin büyürken aday değişir; tamamlanıp kararlı olunca gider.
        // Noktalamayla biten satır zaten tamamdır; hızlı konuşmada beklemeden ilk karede gider.
        var ready = candidateCount >= stableFrames || EndsSentence(rawText);
        // Gönderilenin gürültülü yeniden okuması yeni satır değildir; TV'de aynı cümle iki kez görünmesin.
        if (!ready || IsSame(text, sent)) return StabilizerAction.None;

        // Az önce kalkan satır geri geldiyse okuma birkaç kare kaçmıştır: çevirisi yeniden gösterilir, yeniden çevrilmez.
        var index = history.FindLastIndex(h => time - h.LeftAt <= RestoreWithinMs && IsSame(text, h.Rows));
        if (index >= 0)
        {
            var back = history[index];
            history.RemoveAt(index);
            LeaveScreen(time);
            (sent, sentRaw) = (back.Rows, back.Raw);
            return StabilizerAction.Restore(back.Raw);
        }
        // Çevirisi az önce başarısız olan satır her karede yeniden istenmez.
        if (forgotten.Length > 0 && time < retryAt && IsSame(text, forgotten)) return StabilizerAction.None;

        LeaveScreen(time);
        forgotten = "";
        sentRaw = rawText.Trim();
        sent = TextMatch.NormalizeRows(sentRaw);
        return StabilizerAction.Translate(sentRaw);
    }

    /// <summary>Okuma, bu satırların (gürültülü) yeniden okuması mı; sonuna sözcük eklenmiş hali yenidir.</summary>
    private static bool IsSame(string text, string rows) => rows.Length > 0 && TextMatch.IsSameSubtitle(text, rows);

    /// <summary>Ekrandaki satırı geçmişe yazar (kalktı ya da yerine başkası geldi).</summary>
    private void LeaveScreen(long time)
    {
        if (sent.Length == 0) return;
        history.Add((sent, sentRaw, time));
        if (history.Count > HistorySize) history.RemoveAt(0);
        sent = "";
        sentRaw = "";
    }

    /// <summary>Satır nokta, ünlem, soru ya da üç noktayla bitiyor mu (kapanan tırnak ve parantezler yok sayılır).</summary>
    public static bool EndsSentence(string raw)
    {
        var text = raw.Trim().TrimEnd('"', '\'', '”', '’', '»', ')', ']');
        return text.Length > 0 && ".!?…".Contains(text[^1]);
    }

    /// <summary>Çeviri kaynağıyla neredeyse aynıysa metin zaten hedef dildedir (ör. konsolun Türkçe menüleri).</summary>
    public bool ShouldSend(string source, string translation) =>
        !TextMatch.IsSimilar(TextMatch.Normalize(source), TextMatch.Normalize(translation), 0.90);

    /// <summary>
    /// Son gönderilen satırı unutur (ör. çevirisi başarısız oldu); satır ekranda kaldıkça yeniden kararlı sayılıp çevrilir,
    /// ama en erken <see cref="RetryAfterMs"/> sonra: kalıcı hatada (model eksik) her karede çevirmene gidilmez.
    /// </summary>
    public void ForgetSent()
    {
        if (sent.Length > 0) forgotten = sent;
        retryAt = now() + RetryAfterMs;
        sent = "";
        sentRaw = "";
        candidate = "";
        candidateCount = 0;
    }

    public StabilizerAction Reset()
    {
        candidate = "";
        candidateCount = 0;
        emptySince = null;
        history.Clear();
        forgotten = "";
        if (sent.Length == 0) return StabilizerAction.None;
        sent = "";
        sentRaw = "";
        return StabilizerAction.Clear;
    }
}
