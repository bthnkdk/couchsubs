// SPDX-License-Identifier: AGPL-3.0-only

using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace CouchSubs.Translation;

/// <summary>
/// Marian kodlayıcı/kod çözücüsünü ONNX Runtime (CPU) ile çalıştırır: ışın aramalı kod çözme, KV önbellekli.
/// Birleşik kod çözücü (decoder_model_merged) ilk adımda çapraz dikkat anahtarlarını üretir,
/// sonraki adımlarda yalnızca yeni belirteci işler (use_cache_branch).
/// </summary>
internal sealed class OnnxMarianEngine : ISentenceEngine
{
    public static readonly string[] RequiredFiles =
        [ModelStore.EncoderFile, ModelStore.DecoderFile, ModelStore.SourceSpmFile, ModelStore.VocabFile];

    /// <summary>tc-big en-tr tek hedef dilli; dil belirteci gerekmez, kod çözme &lt;pad&gt; ile başlar.</summary>
    private const int DecoderStartId = MarianTokenizer.PadId;
    private const int HeadCount = 16;
    private const int HeadSize = 64;
    /// <summary>Çok uzun girdi kesilir; altyazı cümlesi bunun çok altında kalır.</summary>
    private const int MaxInputTokens = 256;
    /// <summary>
    /// Işın araması: her adımda en olası tek belirteç yerine dört aday cümle birlikte sürer, sonunda en iyisi seçilir.
    /// Modelin kendi ayarı da budur (num_beams 4); açgözlü çözme "dost canlısı" gibi ilk kelimede sapan çeviriler veriyordu.
    /// </summary>
    public const int DefaultBeams = 4;

    /// <summary>
    /// Çevirinin en çok kullanacağı iş parçacığı. Aynı anda yazı tanıma ve görüntü çözme de çalışıyor; çeviri bütün
    /// çekirdekleri alırsa okuma yavaşlar. ProcessorCount mantıksal çekirdek sayar (16 iş parçacıklı dizüstünde yarısı 8
    /// ederdi); altyazı cümlesi kısa olduğundan 2 iş parçacığı yeter.
    /// </summary>
    public const int MaxIntraOpThreads = 2;

    /// <summary>Çekirdek sayısının yarısı, en az 1 en çok <see cref="MaxIntraOpThreads"/>.</summary>
    internal static int IntraOpThreads(int processorCount) => Math.Clamp(processorCount / 2, 1, MaxIntraOpThreads);

    private readonly MarianTokenizer _tokenizer;
    private readonly InferenceSession _encoder;
    private readonly InferenceSession _decoder;
    private readonly int _maxOutputTokens;
    private readonly int _beams;
    private readonly string[] _pastNames;
    private readonly string[] _decoderInputNames;
    private readonly string[] _decoderOutputNames;
    /// <summary>Her present çıktısının hangi past girdisine döndüğü; kodlayıcı kısımları yalnızca ilk adımda alınır.</summary>
    private readonly bool[] _isSelfAttention;

    public OnnxMarianEngine(string modelDirectory, int maxOutputTokens, int beams = DefaultBeams)
    {
        _maxOutputTokens = maxOutputTokens;
        _beams = Math.Max(1, beams);
        _tokenizer = MarianTokenizer.Load(
            Path.Combine(modelDirectory, ModelStore.SourceSpmFile), Path.Combine(modelDirectory, ModelStore.VocabFile));

        using var options = new SessionOptions
        {
            GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
            ExecutionMode = ExecutionMode.ORT_SEQUENTIAL,
            IntraOpNumThreads = IntraOpThreads(Environment.ProcessorCount),
            InterOpNumThreads = 1,
        };
        // Bellek havuzunu ya da ağırlık ön paketlemeyi kapatmak denendi: yüklemede bellek düşse de
        // çeviriler başladıktan sonra bellek artıyor, satır süresi de %20'ye kadar uzuyordu. Varsayılanlar kalır.
        _encoder = new InferenceSession(Path.Combine(modelDirectory, ModelStore.EncoderFile), options);
        try
        {
            _decoder = new InferenceSession(Path.Combine(modelDirectory, ModelStore.DecoderFile), options);
        }
        catch
        {
            _encoder.Dispose();
            throw;
        }

        _pastNames = _decoder.InputNames.Where(n => n.StartsWith("past_key_values.", StringComparison.Ordinal)).ToArray();
        _decoderInputNames = ["input_ids", "encoder_attention_mask", "encoder_hidden_states", "use_cache_branch", .. _pastNames];
        _decoderOutputNames = ["logits", .. _pastNames.Select(n => "present." + n["past_key_values.".Length..])];
        _isSelfAttention = _pastNames.Select(n => n.EndsWith(".decoder.key", StringComparison.Ordinal) ||
                                                  n.EndsWith(".decoder.value", StringComparison.Ordinal)).ToArray();
    }

    public string Translate(string sentence, CancellationToken cancellationToken)
    {
        var ids = _tokenizer.Encode(sentence);
        if (ids.Length > MaxInputTokens)
        {
            ids = ids[..MaxInputTokens];
            ids[^1] = MarianTokenizer.EosId;
        }
        var output = Generate(ids, cancellationToken);
        return _tokenizer.Decode(output);
    }

    private List<int> Generate(int[] sourceIds, CancellationToken cancellationToken)
    {
        var beams = _beams;
        var length = sourceIds.Length;
        var inputIds = sourceIds.Select(i => (long)i).ToArray();
        long[] sourceShape = [1, length];

        using var inputValue = OrtValue.CreateTensorValueFromMemory(inputIds, sourceShape);
        using var sourceMask = OrtValue.CreateTensorValueFromMemory(Enumerable.Repeat(1L, length).ToArray(), sourceShape);
        using var runOptions = new RunOptions();
        using var encoderOutputs = _encoder.Run(runOptions, ["input_ids", "attention_mask"], [inputValue, sourceMask],
            ["last_hidden_state"]);
        // Her ışın aynı kaynak cümleye bakar: kodlayıcı çıktısı ışın sayısı kadar çoğaltılır.
        var encoded = encoderOutputs[0].GetTensorDataAsSpan<float>();
        var hiddenData = new float[encoded.Length * beams];
        for (var b = 0; b < beams; b++) encoded.CopyTo(hiddenData.AsSpan(b * encoded.Length));
        var hiddenSize = encoded.Length / length;
        using var hidden = OrtValue.CreateTensorValueFromMemory(hiddenData, [beams, length, hiddenSize]);
        using var maskValue = OrtValue.CreateTensorValueFromMemory(Enumerable.Repeat(1L, beams * length).ToArray(),
            [beams, length]);

        var past = new OrtValue[_pastNames.Length];
        for (var i = 0; i < past.Length; i++)
            past[i] = OrtValue.CreateAllocatedTensorValue(OrtAllocator.DefaultInstance, TensorElementType.Float,
                [beams, HeadCount, 0, HeadSize]);

        var running = new List<int>[beams];
        var scores = new float[beams];
        for (var b = 0; b < beams; b++)
        {
            running[b] = [];
            // Başta bütün ışınlar aynıdır; yalnız ilki aday üretir, yoksa aynı cümle dört kez seçilirdi.
            scores[b] = b == 0 ? 0 : float.NegativeInfinity;
        }
        var finished = new List<(List<int> Tokens, float Score)>();
        var tokens = Enumerable.Repeat((long)DecoderStartId, beams).ToArray();
        var useCache = new bool[1];
        // Türkçe çıktı İngilizce girdiden biraz uzun olur; sınır döngüye giren çözmeyi keser.
        var limit = Math.Min(_maxOutputTokens, 2 * length + 16);
        try
        {
            for (var step = 0; step < limit; step++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                useCache[0] = step > 0;
                using var tokenValue = OrtValue.CreateTensorValueFromMemory(tokens, [beams, 1]);
                using var cacheValue = OrtValue.CreateTensorValueFromMemory(useCache, [1]);
                OrtValue[] inputs = [tokenValue, maskValue, hidden, cacheValue, .. past];
                // Çıktılar tek tek sahiplenilir: present değerleri bir sonraki adımın past girdisi olur.
                var outputs = _decoder.Run(runOptions, _decoderInputNames, inputs, _decoderOutputNames);
                List<(int Beam, int Token, float Score)> candidates;
                using (var logits = outputs[0])
                    candidates = Candidates(logits.GetTensorDataAsSpan<float>(), scores, 2 * beams);

                var sources = new int[beams];
                var nextRunning = new List<int>[beams];
                var count = 0;
                for (var rank = 0; rank < candidates.Count && count < beams; rank++)
                {
                    var (beam, token, score) = candidates[rank];
                    if (float.IsNegativeInfinity(score)) break;
                    if (token == MarianTokenizer.EosId)
                    {
                        // Yalnız ilk ışın sayısı kadar sıradaki biten aday sayılır (Hugging Face ile aynı kural).
                        if (rank < beams) AddFinished(finished, running[beam], score, beams);
                        continue;
                    }
                    sources[count] = beam;
                    nextRunning[count] = [.. running[beam], token];
                    scores[count] = score;
                    tokens[count] = token;
                    count++;
                }
                for (var b = count; b < beams; b++)
                {
                    sources[b] = sources[0];
                    nextRunning[b] = nextRunning[0] ?? [];
                    scores[b] = float.NegativeInfinity;
                    tokens[b] = tokens[0];
                }

                for (var i = 0; i < past.Length; i++)
                {
                    var present = outputs[i + 1];
                    if (_isSelfAttention[i])
                    {
                        past[i].Dispose();
                        past[i] = Reorder(present, sources);
                    }
                    else if (step == 0)
                    {
                        // Çapraz dikkat bütün ışınlarda aynıdır; sırası değişmez.
                        past[i].Dispose();
                        past[i] = present;
                    }
                    else
                    {
                        present.Dispose();
                    }
                }
                running = nextRunning;
                if (count == 0) break;
                // En iyi süren ışın, bitenlerin en kötüsünü artık geçemiyorsa çözme biter.
                if (finished.Count >= beams && scores[0] / (step + 1) <= finished[^1].Score) break;
            }
        }
        finally
        {
            foreach (var value in past) value.Dispose();
        }
        if (finished.Count > 0) return finished[0].Tokens;
        return running[0];
    }

    /// <summary>Biten aday uzunluğuna bölünmüş puanıyla sıraya girer; en iyi <paramref name="beams"/> tanesi kalır.</summary>
    private static void AddFinished(List<(List<int> Tokens, float Score)> finished, List<int> tokens, float score, int beams)
    {
        var normalized = score / (tokens.Count + 1);
        var index = finished.FindIndex(f => f.Score < normalized);
        finished.Insert(index < 0 ? finished.Count : index, (tokens, normalized));
        if (finished.Count > beams) finished.RemoveAt(finished.Count - 1);
    }

    /// <summary>
    /// Her ışının log-olasılıklarına puanı eklenir, bütün ışınlardan en iyi <paramref name="take"/> aday döner.
    /// &lt;pad&gt; hiçbir zaman üretilmez (modelin bad_words_ids ayarı).
    /// </summary>
    private static List<(int Beam, int Token, float Score)> Candidates(ReadOnlySpan<float> logits, float[] scores, int take)
    {
        var vocab = logits.Length / scores.Length;
        var best = new List<(int Beam, int Token, float Score)>(take + 1);
        for (var b = 0; b < scores.Length; b++)
        {
            if (float.IsNegativeInfinity(scores[b])) continue;
            var row = logits.Slice(b * vocab, vocab);
            var max = float.NegativeInfinity;
            for (var i = 0; i < row.Length; i++)
                if (i != MarianTokenizer.PadId && row[i] > max) max = row[i];
            double sum = 0;
            for (var i = 0; i < row.Length; i++)
                if (i != MarianTokenizer.PadId) sum += Math.Exp(row[i] - max);
            var offset = scores[b] - max - (float)Math.Log(sum);
            for (var i = 0; i < row.Length; i++)
            {
                if (i == MarianTokenizer.PadId) continue;
                var score = row[i] + offset;
                if (best.Count == take && score <= best[^1].Score) continue;
                var index = best.FindIndex(c => c.Score < score);
                best.Insert(index < 0 ? best.Count : index, (b, i, score));
                if (best.Count > take) best.RemoveAt(take);
            }
        }
        return best;
    }

    /// <summary>Öz dikkat önbelleği seçilen ışınların sırasına göre yeniden dizilir.</summary>
    private static OrtValue Reorder(OrtValue present, int[] sources)
    {
        var identity = true;
        for (var b = 0; b < sources.Length; b++) identity &= sources[b] == b;
        if (identity) return present;
        using (present)
        {
            var shape = present.GetTensorTypeAndShape().Shape;
            var data = present.GetTensorDataAsSpan<float>();
            var block = data.Length / sources.Length;
            var copy = new float[data.Length];
            for (var b = 0; b < sources.Length; b++)
                data.Slice(sources[b] * block, block).CopyTo(copy.AsSpan(b * block));
            return OrtValue.CreateTensorValueFromMemory(copy, shape);
        }
    }

    public void Dispose()
    {
        _decoder.Dispose();
        _encoder.Dispose();
    }
}
