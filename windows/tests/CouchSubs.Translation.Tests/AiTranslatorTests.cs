// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CouchSubs.Core;
using CouchSubs.Translation;
using Xunit;

namespace CouchSubs.Translation.Tests;

/// <summary>Mac'teki AITranslationTests ile aynı durumlar. Gerçek hizmetlere hiç gidilmez.</summary>
public class AiTranslatorTests
{
    private const string Secret = "sk-SECRET-123";

    /// <summary>Yapay zekâ hizmetlerinin yerine geçen sahte sunucu: istekleri saklar, cümleleri "[tr] cümle" diye çevirir.</summary>
    private sealed class FakeAi(Func<HttpRequestMessage, string, HttpResponseMessage>? reply = null) : HttpMessageHandler
    {
        public List<(HttpRequestMessage Request, string Body)> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add((request, body));
            return (reply ?? Echo)(request, body);
        }
    }

    private sealed class FakeLocal : ITextTranslator
    {
        public List<string> Calls { get; } = [];
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
        {
            Calls.Add(text);
            return Task.FromResult("yerel: " + text);
        }
    }

    private static HttpResponseMessage Json(string json, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    internal static string UserText(HttpRequestMessage request, string body)
    {
        var root = JsonNode.Parse(body)!;
        return request.RequestUri!.Host == "generativelanguage.googleapis.com"
            ? root["contents"]![0]!["parts"]![0]!["text"]!.GetValue<string>()
            : root["messages"]!.AsArray()[^1]!["content"]!.GetValue<string>();
    }

    /// <summary>İletinin son satırındaki JSON dizisini "[tr] …" diye çevirir.</summary>
    private static string EchoText(string user)
    {
        var sentences = JsonNode.Parse(user.Split('\n')[^1])!.AsArray().Select(n => "[tr] " + n!.GetValue<string>());
        return new JsonArray([.. sentences.Select(s => (JsonNode?)JsonValue.Create(s))]).ToJsonString();
    }

    /// <summary>Hizmetin kendi yanıt biçimi.</summary>
    private static HttpResponseMessage Wrap(HttpRequestMessage request, string text)
    {
        JsonNode reply = request.RequestUri!.Host switch
        {
            "generativelanguage.googleapis.com" => new JsonObject
            {
                ["candidates"] = new JsonArray(new JsonObject
                {
                    ["content"] = new JsonObject
                    {
                        ["role"] = "model",
                        ["parts"] = new JsonArray(new JsonObject { ["text"] = "thinking…", ["thought"] = true }, new JsonObject { ["text"] = text }),
                    },
                }),
            },
            "api.openai.com" => new JsonObject
            {
                ["choices"] = new JsonArray(new JsonObject
                {
                    ["message"] = new JsonObject { ["role"] = "assistant", ["content"] = text },
                    ["finish_reason"] = "stop",
                }),
            },
            _ => new JsonObject
            {
                ["content"] = new JsonArray(new JsonObject { ["type"] = "thinking", ["thinking"] = "…" }, new JsonObject { ["type"] = "text", ["text"] = text }),
                ["stop_reason"] = "end_turn",
            },
        };
        return Json(reply.ToJsonString());
    }

    private static HttpResponseMessage Echo(HttpRequestMessage request, string body) => Wrap(request, EchoText(UserText(request, body)));

    private static AiTranslator Make(AiProvider provider, FakeAi fake, ITextTranslator? local = null, TranslationCache? cache = null, string? model = null) =>
        new(provider, $"  {Secret} ", model, local ?? new FakeLocal(), new HttpClient(fake), cache);

    private static string User(FakeAi fake, int index) => UserText(fake.Requests[index].Request, fake.Requests[index].Body);

    // --- İstek ---

    [Fact]
    public async Task GeminiRequest()
    {
        var fake = new FakeAi();
        Assert.Equal("KRATOS: [tr] We go now.", await Make(AiProvider.Gemini, fake).TranslateAsync("KRATOS: We go now."));
        var (request, body) = fake.Requests[0];
        Assert.Equal("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", request.RequestUri!.AbsoluteUri);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal(Secret, Assert.Single(request.Headers.GetValues("x-goog-api-key")));
        Assert.Null(request.Headers.Authorization);
        var json = JsonNode.Parse(body)!;
        Assert.Equal(AiRequest.SystemPrompt, json["systemInstruction"]!["parts"]![0]!["text"]!.GetValue<string>());
        Assert.Equal(AiRequest.MaxOutputTokens, json["generationConfig"]!["maxOutputTokens"]!.GetValue<int>());
        // Konuşmacı etiketi gönderilmez; yalnız cümle gider.
        Assert.EndsWith("[\"We go now.\"]", User(fake, 0));
        Assert.DoesNotContain("KRATOS", User(fake, 0));
    }

    [Fact]
    public async Task OpenAiRequest()
    {
        var fake = new FakeAi();
        await Make(AiProvider.OpenAi, fake).TranslateAsync("Run!");
        var (request, body) = fake.Requests[0];
        Assert.Equal("https://api.openai.com/v1/chat/completions", request.RequestUri!.AbsoluteUri);
        Assert.Equal($"Bearer {Secret}", Assert.Single(request.Headers.GetValues("Authorization")));
        var json = JsonNode.Parse(body)!;
        Assert.Equal("gpt-6-luna", json["model"]!.GetValue<string>());
        Assert.Equal("none", json["reasoning_effort"]!.GetValue<string>());
        Assert.Equal(AiRequest.MaxOutputTokens, json["max_completion_tokens"]!.GetValue<int>());
        var messages = json["messages"]!.AsArray();
        Assert.Equal(["developer", "user"], messages.Select(m => m!["role"]!.GetValue<string>()));
        Assert.Equal(AiRequest.SystemPrompt, messages[0]!["content"]!.GetValue<string>());
    }

    [Fact]
    public async Task ClaudeRequest()
    {
        var fake = new FakeAi();
        await Make(AiProvider.Claude, fake).TranslateAsync("Run!");
        var (request, body) = fake.Requests[0];
        Assert.Equal("https://api.anthropic.com/v1/messages", request.RequestUri!.AbsoluteUri);
        Assert.Equal(Secret, Assert.Single(request.Headers.GetValues("x-api-key")));
        Assert.Equal("2023-06-01", Assert.Single(request.Headers.GetValues("anthropic-version")));
        var json = JsonNode.Parse(body)!;
        Assert.Equal("claude-haiku-5-5", json["model"]!.GetValue<string>());
        Assert.Equal(AiRequest.MaxOutputTokens, json["max_tokens"]!.GetValue<int>());
        Assert.Equal(AiRequest.SystemPrompt, json["system"]!.GetValue<string>());
        Assert.Null(json["temperature"]);
        Assert.Equal("low", json["output_config"]!["effort"]!.GetValue<string>());
        Assert.Equal("disabled", json["thinking"]!["type"]!.GetValue<string>());
    }

    [Fact]
    public async Task CustomModelIsUsedAndHasItsOwnEngineId()
    {
        var fake = new FakeAi();
        await Make(AiProvider.OpenAi, fake, model: " gpt-6.1-sol ").TranslateAsync("Run!");
        var json = JsonNode.Parse(fake.Requests[0].Body)!;
        Assert.Equal("gpt-6.1-sol", json["model"]!.GetValue<string>());
        Assert.Equal("low", json["reasoning_effort"]!.GetValue<string>());
        Assert.Equal("gemini:gemini-3.5-flash-lite", AiProvider.Gemini.EngineId("gemini-3.5-flash-lite"));
        Assert.Equal("openai:gpt-6-luna", AiProvider.OpenAi.EngineId("gpt-6-luna"));
        Assert.Equal("claude:claude-haiku-5-5", AiProvider.Claude.EngineId(AiProvider.Claude.Model("")));
    }

    /// <summary>Son gösterilen 3 satır ve çevirileri bağlam olarak gider; satırın kendisi ve tekrar okunan satır girmez.</summary>
    [Fact]
    public async Task ContextIsTheLastThreeShownLinesWithTranslations()
    {
        var fake = new FakeAi();
        var translator = Make(AiProvider.Claude, fake);
        foreach (var line in new[] { "One.", "Two.", "Two.", "Three.", "Four.", "Five." }) await translator.TranslateAsync(line);
        Assert.Equal(5, fake.Requests.Count);
        Assert.DoesNotContain("Previous subtitles", User(fake, 0));
        Assert.Contains("English: One.\nTurkish: [tr] One.", User(fake, 1));
        Assert.Contains("English: Two.\nTurkish: [tr] Two.\nEnglish: Three.\nTurkish: [tr] Three.\nEnglish: Four.\nTurkish: [tr] Four.", User(fake, 4));
        Assert.DoesNotContain("English: One.", User(fake, 4));
        Assert.DoesNotContain("English: Five.", User(fake, 4));
    }

    [Fact]
    public async Task SeveralSentencesGoAsOneArray()
    {
        var fake = new FakeAi();
        var translator = Make(AiProvider.Gemini, fake);
        const string line = "We go now. Stay close.\nATREUS: Yes, father.";
        Assert.Equal("[tr] We go now. [tr] Stay close.\nATREUS: [tr] Yes, father.", await translator.TranslateAsync(line));
        Assert.Single(fake.Requests);
        Assert.EndsWith("[\"We go now.\",\"Stay close.\",\"Yes, father.\"]", User(fake, 0));
        Assert.Equal("ATREUS", translator.SpokenLines(line)[^1].Speaker);
    }

    // --- Yanıt ---

    [Fact]
    public void ReplyParsing()
    {
        Assert.Equal(["Gidelim.", "Yakın dur."], AiRequest.Translations("```json\n[\"Gidelim.\", \"Yakın dur.\"]\n```", 2));
        Assert.Equal(["Gidelim."], AiRequest.Translations("“Gidelim.”", 1));
        Assert.Throws<AiException>(() => AiRequest.Translations("[\"Tek\"]", 2));
        Assert.Throws<AiException>(() => AiRequest.Translations("Gidelim. Yakın dur.", 2));
        Assert.Throws<AiException>(() => AiRequest.Text(AiProvider.Gemini, """{"promptFeedback":{"blockReason":"OTHER"}}"""));
        Assert.Equal("Koş!", AiRequest.Text(AiProvider.OpenAi, """{"choices":[{"message":{"content":"Koş!"}}]}"""));
    }

    [Fact]
    public async Task PlainTextReplyForOneSentence()
    {
        var fake = new FakeAi((request, _) => Wrap(request, "Koş!"));
        Assert.Equal("Koş!", await Make(AiProvider.OpenAi, fake).TranslateAsync("Run!"));
    }

    [Fact]
    public void FailureMapping()
    {
        Assert.Equal(OnlineKeyState.Invalid, AiRequest.Failure(HttpStatusCode.Unauthorized, ""));
        Assert.Equal(OnlineKeyState.Invalid, AiRequest.Failure(HttpStatusCode.Forbidden, ""));
        Assert.Equal(OnlineKeyState.Invalid, AiRequest.Failure(HttpStatusCode.BadRequest,
            """{"error":{"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"""));
        Assert.Equal(OnlineKeyState.QuotaExceeded, AiRequest.Failure(HttpStatusCode.TooManyRequests, """{"error":{"code":"insufficient_quota"}}"""));
        Assert.Equal(OnlineKeyState.QuotaExceeded, AiRequest.Failure(HttpStatusCode.BadRequest,
            """{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low"}}"""));
        Assert.Equal(OnlineKeyState.ModelRejected, AiRequest.Failure(HttpStatusCode.NotFound, ""));
        Assert.Equal(OnlineKeyState.ModelRejected, AiRequest.Failure(HttpStatusCode.BadRequest, "unknown model"));
        Assert.Equal(OnlineKeyState.Unreachable, AiRequest.Failure((HttpStatusCode)529, ""));
        Assert.Equal(OnlineKeyState.Unreachable, AiRequest.Failure(HttpStatusCode.InternalServerError, ""));
    }

    // --- Hata ve yerel çeviri ---

    /// <summary>Kota biterse o satır yerel modelle çevrilir, bir süre hizmet denenmez, hata durumu bildirilir.</summary>
    [Fact]
    public async Task FallsBackAndPausesOnError()
    {
        var fake = new FakeAi((_, _) => Json("""{"error":{"message":"quota"}}""", HttpStatusCode.TooManyRequests));
        var local = new FakeLocal();
        var cache = new TranslationCache();
        var translator = Make(AiProvider.Gemini, fake, local, cache);
        var reported = new List<OnlineKeyState?>();
        translator.FailureChanged += reported.Add;
        Assert.Equal("yerel: Run!", await translator.TranslateAsync("Run!"));
        Assert.Equal("yerel: Hide!", await translator.TranslateAsync("Hide!"));
        Assert.Single(fake.Requests);
        Assert.Equal(["Run!", "Hide!"], local.Calls);
        Assert.Equal(OnlineKeyState.QuotaExceeded, translator.LastError);
        Assert.Equal([OnlineKeyState.QuotaExceeded], reported);
        // Yerel çeviri bu motorun önbelleğine yazılmaz.
        Assert.False(cache.TryGet("Run!", out _));
    }

    [Fact]
    public async Task TimeoutFallsBack()
    {
        var fake = new FakeAi((_, _) => throw new TaskCanceledException("timeout"));
        var translator = Make(AiProvider.Claude, fake);
        Assert.Equal("yerel: Run!", await translator.TranslateAsync("Run!"));
        Assert.Equal(OnlineKeyState.Unreachable, translator.LastError);
    }

    // --- Önbellek ---

    /// <summary>Önceki oturumda çevrilen satır ve cümleler hizmete hiç gitmez; yalnız yeni cümle gönderilir.</summary>
    [Fact]
    public async Task PersistentCacheAcrossSessions()
    {
        var file = Path.Combine(Path.GetTempPath(), "couchsubs-ai-" + Guid.NewGuid().ToString("N"), "cache.jsonl");
        try
        {
            await Make(AiProvider.OpenAi, new FakeAi(), cache: new TranslationCache(file)).TranslateAsync("KRATOS: We go now. Stay close.");

            var fake = new FakeAi();
            var translator = Make(AiProvider.OpenAi, fake, cache: new TranslationCache(file));
            Assert.Equal("KRATOS: [tr] We go now. [tr] Stay close.", await translator.TranslateAsync("KRATOS: We go now. Stay close."));
            Assert.Empty(fake.Requests);
            Assert.Equal("[tr] Stay close. [tr] Run!", await translator.TranslateAsync("Stay close. Run!"));
            Assert.Single(fake.Requests);
            Assert.EndsWith("[\"Run!\"]", User(fake, 0));
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(file)!, recursive: true);
        }
    }

    // --- Deneme ve anahtarın gizliliği ---

    [Fact]
    public async Task TestTranslatesTheSample()
    {
        var result = await AiTranslator.TestAsync(AiProvider.Gemini, Secret, null, new HttpClient(new FakeAi()));
        Assert.Equal(new AiTestResult(OnlineKeyState.Valid, "KRATOS: [tr] We go now. [tr] Stay close, boy."), result);
    }

    /// <summary>Anahtar hiçbir hata metninde ya da durumda görünmez.</summary>
    [Fact]
    public async Task KeyNeverAppearsInErrors()
    {
        var rejecting = new FakeAi((_, _) => Json($$$"""{"error":{"message":"Incorrect API key provided: {{{Secret}}}"}}""",HttpStatusCode.Unauthorized));
        foreach (var provider in Enum.GetValues<AiProvider>())
        {
            var result = await AiTranslator.TestAsync(provider, Secret, null, new HttpClient(rejecting));
            Assert.Equal(new AiTestResult(OnlineKeyState.Invalid), result);
            Assert.DoesNotContain(Secret, result.ToString());
        }
        Assert.DoesNotContain(Secret, new AiException(OnlineKeyState.Invalid).ToString());

        var timeout = new FakeAi((_, _) => throw new TaskCanceledException("timeout"));
        Assert.Equal(OnlineKeyState.Unreachable, (await AiTranslator.TestAsync(AiProvider.OpenAi, Secret, null, new HttpClient(timeout))).State);
        Assert.Equal(OnlineKeyState.Invalid, (await AiTranslator.TestAsync(AiProvider.Claude, "  ", null)).State);
    }
}
