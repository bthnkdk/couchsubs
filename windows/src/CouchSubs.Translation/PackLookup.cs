// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Translation;

/// <summary>
/// Satırı oyun paketinde arar (Mac: CouchSubsCore/GamePacks.swift, PackLookup). Sırayla: satırın tamamı; konuşmacı
/// etiketi ("ENZO: ") ya da diyalog tiresi varsa onsuz hâli (etiket çeviriye eklenir); birden çok satırsa her satır ayrı
/// ayrı; birden çok cümleyse her cümle ayrı ayrı. Parçalı aramada parçaların hepsi bulunmalıdır, yoksa satır motorla
/// çevrilir. Etiket ve ayraçlar ücretli motorlardaki gibi korunur (<see cref="SubtitleSegmenter"/>).
/// </summary>
public static class PackLookup
{
    /// <summary>Kütüphanedeki paketlerde arar.</summary>
    public static PackMatch? Match(GamePackLibrary library, string text) => Match(text, library.Find);

    /// <param name="find">Tek bir metnin (tamamının) paketteki Türkçesi.</param>
    public static PackMatch? Match(string text, Func<string, string?> find)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return null;
        if (Single(trimmed, find) is { } whole) return Result(whole.Pieces, whole.Translations);

        // Her satır ayrı bir altyazı olabilir (iki konuşmacı alt alta).
        var lines = trimmed.Replace("\r\n", "\n").Split('\n').Select(line => line.Trim()).Where(line => line.Length > 0).ToList();
        if (lines.Count > 1)
        {
            var pieces = new List<SubtitleSegmenter.Piece>();
            var translations = new List<string?>();
            var all = true;
            foreach (var line in lines)
            {
                if (Single(line, find) is not { } found) { all = false; break; }
                if (pieces.Count > 0)
                {
                    pieces.Add(new SubtitleSegmenter.Piece("\n", false));
                    translations.Add(null);
                }
                pieces.AddRange(found.Pieces);
                translations.AddRange(found.Translations);
            }
            if (all) return Result(pieces, translations);
        }

        // Cümle cümle (etiket, tire ve ayraçlar olduğu gibi kalır).
        var split = SubtitleSegmenter.Split(trimmed);
        if (split.Count(piece => piece.Translate) <= 1) return null;
        var sentences = new List<string?>(split.Count);
        foreach (var piece in split)
        {
            if (!piece.Translate) { sentences.Add(null); continue; }
            if (find(piece.Text) is not { } turkish) return null;
            sentences.Add(turkish);
        }
        return Result(split, sentences);
    }

    /// <summary>Tek satır: başında konuşmacı etiketi ya da diyalog tiresi varsa önce onsuz hâli, sonra tamamı.</summary>
    private static (List<SubtitleSegmenter.Piece> Pieces, List<string?> Translations)? Single(string line, Func<string, string?> find)
    {
        var split = SubtitleSegmenter.Split(line);
        if (split.Count > 1 && !split[0].Translate && !split.Any(piece => piece.Text == "\n"))
        {
            var body = string.Concat(split.Skip(1).Select(piece => piece.Text));
            if (find(body) is { } turkish)
                return (new List<SubtitleSegmenter.Piece> { split[0], new(body, true) }, new List<string?> { null, turkish });
        }
        if (find(line) is not { } whole) return null;
        return (new List<SubtitleSegmenter.Piece> { new(line, true) }, new List<string?> { whole });
    }

    private static PackMatch Result(IReadOnlyList<SubtitleSegmenter.Piece> pieces, IReadOnlyList<string?> translations)
    {
        var text = string.Concat(pieces.Select((piece, index) => translations[index] ?? piece.Text));
        return new PackMatch(text, SpeechScript.Lines(pieces, translations));
    }
}
