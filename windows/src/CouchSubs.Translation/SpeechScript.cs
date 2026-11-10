// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Translation;

/// <summary>Çevrilen parçalardan seslendirilecek cümleleri çıkarır (Mac: SpeechScript.swift).</summary>
internal static class SpeechScript
{
    /// <summary><paramref name="translations"/>[i], <paramref name="pieces"/>[i] çevrilecek bir parçaysa onun Türkçesidir.</summary>
    public static IReadOnlyList<SpokenLine> Lines(IReadOnlyList<SubtitleSegmenter.Piece> pieces, IReadOnlyList<string?> translations)
    {
        var lines = new List<SpokenLine>();
        string? speaker = null;
        var newTurn = false;
        for (var i = 0; i < pieces.Count; i++)
        {
            var piece = pieces[i];
            if (piece.Translate)
            {
                if (i >= translations.Count || translations[i] is not { } turkish || !turkish.Any(char.IsLetter)) continue;
                lines.Add(new SpokenLine(piece.Text, turkish, speaker, newTurn));
                // Aynı konuşmanın sonraki cümleleri aynı sesle sürer.
                newTurn = false;
            }
            else if (piece.Text == "\n")
            {
                speaker = null;
                newTurn = false;
            }
            else if (SubtitleSegmenter.LabelName(piece) is { } name)
            {
                speaker = name.Length > 0 ? name : null;
                newTurn = false;
            }
            else if (piece.Text.Length > 0 && "-–—".Contains(piece.Text[0]))
            {
                speaker = null;
                newTurn = true;
            }
        }
        return lines;
    }

    /// <summary>
    /// Önceki oturumdan önbellekte duran satır: cümleleri de önbellekteyse konuşmacılarıyla kurulur, değilse
    /// satırın tamamı tek cümle sayılır.
    /// </summary>
    public static IReadOnlyList<SpokenLine> FromCache(string text, TranslationCache cache)
    {
        if (!cache.TryGet(text, out var whole)) return [];
        var pieces = SubtitleSegmenter.Split(text);
        var translations = new List<string?>(pieces.Count);
        foreach (var piece in pieces)
        {
            if (!piece.Translate)
            {
                translations.Add(null);
                continue;
            }
            if (!cache.TryGet(piece.Text, out var sentence)) return [new SpokenLine(text, whole)];
            translations.Add(sentence);
        }
        return Lines(pieces, translations);
    }
}
