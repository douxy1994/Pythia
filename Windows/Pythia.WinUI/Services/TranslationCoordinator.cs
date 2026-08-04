using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Pythia.Models;

namespace Pythia.Services;

public sealed class TranslationCoordinator(CredentialStore credentials, PluginService? plugins = null)
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private readonly HttpClient _customLlmHttp = new() { Timeout = Timeout.InfiniteTimeSpan };
    private const int CustomLlmChunkLimit = 1800;
    private static readonly TimeSpan CustomLlmRequestTimeout = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan[] CustomLlmRetryDelays =
        [TimeSpan.Zero, TimeSpan.FromMilliseconds(750), TimeSpan.FromSeconds(2)];

    public async Task<TranslationBatch> TranslateAsync(
        string text,
        string sourceLanguage,
        string targetLanguage,
        IEnumerable<string> serviceIds,
        PythiaSettings settings,
        CancellationToken cancellationToken = default)
    {
        var normalizedText = text.Trim();
        if (normalizedText.Length == 0)
            throw new ArgumentException("请输入需要翻译的文本。", nameof(text));

        var pair = ResolveLanguages(normalizedText, sourceLanguage, targetLanguage);
        using var concurrencyGate = new SemaphoreSlim(4);
        var tasks = serviceIds.Distinct(StringComparer.OrdinalIgnoreCase).Select(async id =>
        {
            await concurrencyGate.WaitAsync(cancellationToken);
            try
            {
                try
                {
                    return id switch
                    {
                        "google" => await TranslateGoogleAsync(normalizedText, pair.Source, pair.Target, cancellationToken),
                        "baidu" => await TranslateBaiduAsync(normalizedText, pair.Source, pair.Target, cancellationToken),
                        "youdao" => await TranslateYoudaoAsync(normalizedText, pair.Source, pair.Target, cancellationToken),
                        "openai-compatible" => await TranslateOpenAiAsync(normalizedText, pair.Source, pair.Target, settings, cancellationToken),
                        "deepl" => await TranslateDeepLAsync(normalizedText, pair.Source, pair.Target, settings, cancellationToken),
                        "libretranslate" => await TranslateLibreAsync(normalizedText, pair.Source, pair.Target, settings, cancellationToken),
                        _ when id.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase) && plugins is not null =>
                            new TranslationResult(id, plugins.DisplayName(id),
                                await plugins.TranslateAsync(id, normalizedText, pair.Source, pair.Target, cancellationToken),
                                IconPath: plugins.IconPath(id)),
                        _ => new TranslationResult(id, ServiceCatalog.DisplayName(id), string.Empty, Error: "当前版本不支持此翻译服务。"),
                    };
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception exception)
                {
                    return new TranslationResult(id, plugins?.DisplayName(id) ?? ServiceCatalog.DisplayName(id), string.Empty,
                        Error: SafeError(exception),
                        IconPath: id.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase) ? plugins?.IconPath(id) : null);
                }
            }
            finally { concurrencyGate.Release(); }
        });

        var results = await Task.WhenAll(tasks);
        return new TranslationBatch(normalizedText, pair.Source, pair.Target, results);
    }

    private async Task<TranslationResult> TranslateGoogleAsync(string text, string source, string target, CancellationToken ct)
    {
        var url = "https://translate.googleapis.com/translate_a/single?client=gtx" +
                  $"&sl={Uri.EscapeDataString(source)}&tl={Uri.EscapeDataString(target)}&dt=t&q={Uri.EscapeDataString(text)}";
        using var response = await _http.GetAsync(url, ct);
        EnsureSuccess(response, "Google 翻译");
        using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        var builder = new StringBuilder();
        foreach (var segment in json.RootElement[0].EnumerateArray())
            if (segment.GetArrayLength() > 0 && segment[0].ValueKind == JsonValueKind.String)
                builder.Append(segment[0].GetString());
        if (builder.Length == 0) throw new InvalidOperationException("Google 翻译未返回文本。");
        return new("google", "Google 翻译", builder.ToString());
    }

    private async Task<TranslationResult> TranslateBaiduAsync(string text, string source, string target, CancellationToken ct)
    {
        var appId = RequiredSecret("provider.baidu.appId", "请先在设置中填写百度翻译 AppID。");
        var secret = RequiredSecret("provider.baidu.secret", "请先在设置中填写百度翻译密钥。");
        var salt = RandomNumberGenerator.GetInt32(100000, 999999).ToString();
        var sign = Convert.ToHexStringLower(MD5.HashData(Encoding.UTF8.GetBytes(appId + text + salt + secret)));
        var url = "https://fanyi-api.baidu.com/api/trans/vip/translate" +
                  $"?q={Uri.EscapeDataString(text)}&from={MapBaidu(source)}&to={MapBaidu(target)}" +
                  $"&appid={Uri.EscapeDataString(appId)}&salt={salt}&sign={sign}";
        using var response = await _http.GetAsync(url, ct);
        EnsureSuccess(response, "百度翻译");
        using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        if (json.RootElement.TryGetProperty("error_code", out _))
            throw new InvalidOperationException("百度翻译请求失败，请检查凭据、语言和账户额度。");
        var translated = string.Join("\n", json.RootElement.GetProperty("trans_result")
            .EnumerateArray().Select(item => item.GetProperty("dst").GetString()));
        return new("baidu", "百度翻译", translated);
    }

    private async Task<TranslationResult> TranslateYoudaoAsync(string text, string source, string target, CancellationToken ct)
    {
        var appKey = RequiredSecret("provider.youdao.appKey", "请先在设置中填写有道翻译 AppKey。");
        var secret = RequiredSecret("provider.youdao.secret", "请先在设置中填写有道翻译密钥。");
        var salt = Guid.NewGuid().ToString("N");
        var curtime = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var input = text.Length <= 20 ? text : text[..10] + text.Length + text[^10..];
        var sign = Convert.ToHexStringLower(SHA256.HashData(
            Encoding.UTF8.GetBytes(appKey + input + salt + curtime + secret)));
        var fields = new Dictionary<string, string>
        {
            ["q"] = text,
            ["from"] = MapYoudao(source),
            ["to"] = MapYoudao(target),
            ["appKey"] = appKey,
            ["salt"] = salt,
            ["sign"] = sign,
            ["signType"] = "v3",
            ["curtime"] = curtime,
        };
        using var response = await _http.PostAsync("https://openapi.youdao.com/api", new FormUrlEncodedContent(fields), ct);
        EnsureSuccess(response, "有道翻译");
        using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        if (!json.RootElement.TryGetProperty("errorCode", out var error) || error.GetString() != "0")
            throw new InvalidOperationException("有道翻译请求失败，请检查凭据、语言和账户额度。");
        var translated = string.Join("\n", json.RootElement.GetProperty("translation")
            .EnumerateArray().Select(item => item.GetString()));
        return new("youdao", "有道翻译", translated);
    }

    private async Task<TranslationResult> TranslateOpenAiAsync(
        string text, string source, string target, PythiaSettings settings, CancellationToken ct)
    {
        var apiKey = RequiredSecret("provider.openai-compatible.apiKey", "请先在设置中填写 AI 服务 API Key。");
        var api = settings.OpenAICompatibleApi.Equals("anthropic", StringComparison.OrdinalIgnoreCase)
            ? "anthropic" : "openai";
        var endpoint = CustomLlmEndpoint(settings.OpenAICompatibleBaseUrl, api);
        if (endpoint is null) throw new InvalidOperationException("自定义 API 基础地址无效。");
        var serviceName = string.IsNullOrWhiteSpace(settings.OpenAICompatibleName)
            ? "AI 翻译" : settings.OpenAICompatibleName.Trim();
        var chunks = CustomLlmChunks(text);
        var translatedChunks = new List<string>(chunks.Count);
        for (var index = 0; index < chunks.Count; index++)
        {
            ct.ThrowIfCancellationRequested();
            var envelope = WhitespaceEnvelope(chunks[index]);
            if (envelope.Core.Length == 0)
            {
                translatedChunks.Add(chunks[index]);
                continue;
            }
            try
            {
                var translated = await TranslateOpenAiChunkAsync(
                    envelope.Core, source, target, settings, api, apiKey, endpoint, serviceName,
                    index, chunks.Count, ct);
                translatedChunks.Add(envelope.Leading + translated.Trim() + envelope.Trailing);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                throw new InvalidOperationException(
                    $"{serviceName} 第 {index + 1}/{chunks.Count} 段翻译失败：{SafeError(exception)}", exception);
            }
        }
        return new("openai-compatible", serviceName, string.Concat(translatedChunks), settings.OpenAICompatibleModel);
    }

    private async Task<string> TranslateOpenAiChunkAsync(
        string text,
        string source,
        string target,
        PythiaSettings settings,
        string api,
        string apiKey,
        Uri endpoint,
        string serviceName,
        int chunkIndex,
        int chunkCount,
        CancellationToken ct)
    {
        var segmentNote = chunkCount > 1
            ? $" This is segment {chunkIndex + 1} of {chunkCount}; preserve its paragraph and list formatting."
            : string.Empty;
        var prompt = $"Translate the following text from {source} to {target}. Return only the translation.{segmentNote}\n\n{text}";
        var payload = api == "anthropic"
            ? JsonSerializer.Serialize(new
            {
                model = settings.OpenAICompatibleModel,
                system = "You are a concise translation engine.",
                messages = new object[] { new { role = "user", content = prompt } },
                max_tokens = 4096,
                temperature = 0.2,
            })
            : JsonSerializer.Serialize(new
            {
                model = settings.OpenAICompatibleModel,
                temperature = 0.2,
                messages = new object[]
                {
                    new { role = "system", content = "You are a concise translation engine." },
                    new { role = "user", content = prompt },
                },
            });

        HttpRequestMessage CreateRequest()
        {
            var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json"),
            };
            if (api == "anthropic")
            {
                request.Headers.TryAddWithoutValidation("x-api-key", apiKey);
                request.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01");
            }
            else request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            return request;
        }

        using var response = await SendCustomLlmWithRetryAsync(CreateRequest, ct);
        EnsureSuccess(response, serviceName);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        var translated = CustomLlmContent(json.RootElement, api)?.Trim();
        if (string.IsNullOrWhiteSpace(translated)) throw new InvalidOperationException("AI 服务未返回文本。");
        return translated;
    }

    private async Task<HttpResponseMessage> SendCustomLlmWithRetryAsync(
        Func<HttpRequestMessage> requestFactory,
        CancellationToken cancellationToken)
    {
        Exception? lastError = null;
        var delayBeforeAttempt = TimeSpan.Zero;
        for (var attempt = 0; attempt < CustomLlmRetryDelays.Length; attempt++)
        {
            if (delayBeforeAttempt > TimeSpan.Zero)
                await Task.Delay(delayBeforeAttempt, cancellationToken);
            delayBeforeAttempt = attempt + 1 < CustomLlmRetryDelays.Length
                ? CustomLlmRetryDelays[attempt + 1]
                : TimeSpan.Zero;

            using var timeoutSource = new CancellationTokenSource(CustomLlmRequestTimeout);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
            using var request = requestFactory();
            try
            {
                // Buffer the response under the linked timeout as well. Using
                // ResponseHeadersRead here would let a server send headers and then
                // stall the JSON body indefinitely after the timeout source is disposed.
                var response = await _customLlmHttp.SendAsync(request, linked.Token);
                if (!IsRetryableCustomLlmStatus((int)response.StatusCode) ||
                    attempt == CustomLlmRetryDelays.Length - 1)
                    return response;

                delayBeforeAttempt = RetryAfterDelay(response) ?? delayBeforeAttempt;
                response.Dispose();
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException exception) when (timeoutSource.IsCancellationRequested)
            {
                lastError = new TimeoutException(
                    $"AI 服务单次请求等待 {CustomLlmRequestTimeout.TotalSeconds:0} 秒后超时。", exception);
            }
            catch (HttpRequestException exception)
            {
                lastError = exception;
            }

            if (attempt == CustomLlmRetryDelays.Length - 1 && lastError is not null)
                throw lastError;
        }
        throw lastError ?? new HttpRequestException("AI 服务请求失败。");
    }

    public static bool IsRetryableCustomLlmStatus(int statusCode) =>
        statusCode is 408 or 409 or 425 or 429 or >= 500 and <= 599;

    private static TimeSpan? RetryAfterDelay(HttpResponseMessage response)
    {
        var retryAfter = response.Headers.RetryAfter;
        if (retryAfter?.Delta is { } delta)
            return TimeSpan.FromSeconds(Math.Clamp(delta.TotalSeconds, 0.75, 60));
        if (retryAfter?.Date is { } date)
            return TimeSpan.FromSeconds(Math.Clamp((date - DateTimeOffset.UtcNow).TotalSeconds, 0.75, 60));
        return null;
    }

    public static IReadOnlyList<string> CustomLlmChunks(string text, int maxCharacters = CustomLlmChunkLimit)
    {
        if (maxCharacters < 64) throw new ArgumentOutOfRangeException(nameof(maxCharacters));
        if (text.Length <= maxCharacters) return [text];

        var chunks = new List<string>();
        var cursor = 0;
        while (cursor < text.Length)
        {
            var hardEnd = Math.Min(text.Length, cursor + maxCharacters);
            if (hardEnd == text.Length)
            {
                chunks.Add(text[cursor..]);
                break;
            }

            var minimumBoundary = cursor + (int)(maxCharacters * 0.55);
            var preferredEnd = -1;
            for (var index = minimumBoundary; index <= hardEnd; index++)
            {
                if (IsPreferredChunkBoundary(text, index) && IsSafeChunkBoundary(text, index))
                    preferredEnd = index;
            }
            var end = preferredEnd > cursor ? preferredEnd : SafeChunkEnd(text, cursor, hardEnd);
            if (end <= cursor) end = hardEnd;
            chunks.Add(text[cursor..end]);
            cursor = end;
        }
        return chunks;
    }

    private static bool IsPreferredChunkBoundary(string text, int index)
    {
        if (index <= 0 || index > text.Length) return false;
        var previous = text[index - 1];
        if (previous is '\n' or '\r' or '。' or '！' or '？' or '!' or '?' or '；' or ';' or '：' or ':') return true;
        if (char.IsWhiteSpace(previous) && index >= 2 && text[index - 2] is '.' or ',' or '，') return true;
        return false;
    }

    private static int SafeChunkEnd(string text, int cursor, int proposedEnd)
    {
        var end = proposedEnd;
        while (end > cursor && !IsSafeChunkBoundary(text, end)) end--;
        if (end > cursor) return end;
        end = proposedEnd;
        while (end < text.Length && !IsSafeChunkBoundary(text, end)) end++;
        return end;
    }

    private static bool IsSafeChunkBoundary(string text, int index)
    {
        if (index <= 0 || index >= text.Length) return true;
        if (char.IsHighSurrogate(text[index - 1]) && char.IsLowSurrogate(text[index])) return false;
        return !WouldSplitNumber(text, index);
    }

    private static bool WouldSplitNumber(string text, int index)
    {
        char At(int offset) => index + offset >= 0 && index + offset < text.Length ? text[index + offset] : '\0';
        var before = At(-1);
        var after = At(0);
        var beforeBefore = At(-2);
        var afterAfter = At(1);
        var threeBefore = At(-3);
        var twoAfter = At(2);
        static bool Digit(char value) => char.IsDigit(value);
        static bool Separator(char value) => ".,，．:/：／-－'’ \u00A0\u202F".Contains(value);
        static bool Sign(char value) => "+-−＋－".Contains(value);

        if (Digit(before) && Digit(after)) return true;
        if (Digit(before) && Separator(after) && Digit(afterAfter)) return true;
        if (Separator(before) && Digit(beforeBefore) && Digit(after)) return true;
        if (".,，．".Contains(before) && Digit(after)) return true;
        if (Sign(before) && Digit(after)) return true;
        if (Digit(before) && after is 'e' or 'E' &&
            (Digit(afterAfter) || (afterAfter is '+' or '-' && Digit(twoAfter)))) return true;
        if (before is 'e' or 'E' && Digit(beforeBefore) &&
            (Digit(after) || (after is '+' or '-' && Digit(afterAfter)))) return true;
        return before is '+' or '-' && beforeBefore is 'e' or 'E' && Digit(threeBefore) && Digit(after);
    }

    private static (string Leading, string Core, string Trailing) WhitespaceEnvelope(string chunk)
    {
        var start = 0;
        while (start < chunk.Length && char.IsWhiteSpace(chunk[start])) start++;
        var end = chunk.Length;
        while (end > start && char.IsWhiteSpace(chunk[end - 1])) end--;
        return (chunk[..start], chunk[start..end], chunk[end..]);
    }

    public static Uri? CustomLlmEndpoint(string baseUrl, string api)
    {
        if (!Uri.TryCreate(baseUrl.Trim(), UriKind.Absolute, out var parsed) ||
            parsed.Scheme is not ("http" or "https")) return null;
        var suffix = api == "anthropic" ? "messages" : "chat/completions";
        var builder = new UriBuilder(parsed) { Query = string.Empty, Fragment = string.Empty };
        var path = builder.Path.TrimEnd('/');
        if (!path.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
            path = path.Length == 0 || path == "/" ? $"/v1/{suffix}" : $"{path}/{suffix}";
        builder.Path = path;
        return builder.Uri;
    }

    public static string? CustomLlmContent(JsonElement json, string api)
    {
        if (api == "anthropic")
        {
            if (!json.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array) return null;
            return string.Concat(content.EnumerateArray()
                .Where(block => block.TryGetProperty("type", out var type) && type.GetString() == "text")
                .Select(block => block.TryGetProperty("text", out var text) ? text.GetString() : null));
        }
        if (!json.TryGetProperty("choices", out var choices) || choices.GetArrayLength() == 0) return null;
        var message = choices[0].GetProperty("message");
        if (!message.TryGetProperty("content", out var value)) return null;
        if (value.ValueKind == JsonValueKind.String) return value.GetString();
        if (value.ValueKind != JsonValueKind.Array) return null;
        return string.Concat(value.EnumerateArray().Select(block =>
        {
            if (!block.TryGetProperty("text", out var text)) return null;
            if (text.ValueKind == JsonValueKind.String) return text.GetString();
            return text.ValueKind == JsonValueKind.Object && text.TryGetProperty("value", out var nested)
                ? nested.GetString() : null;
        }));
    }

    private async Task<TranslationResult> TranslateDeepLAsync(
        string text, string source, string target, PythiaSettings settings, CancellationToken ct)
    {
        var apiKey = RequiredSecret("provider.deepl.apiKey", "请先在设置中填写 DeepL API Key。");
        var fields = new Dictionary<string, string>
        {
            ["text"] = text,
            ["target_lang"] = MapDeepL(target),
        };
        if (source != "auto") fields["source_lang"] = MapDeepL(source);
        using var request = new HttpRequestMessage(HttpMethod.Post,
            settings.DeepLBaseUrl.Trim().TrimEnd('/') + "/translate")
        {
            Content = new FormUrlEncodedContent(fields),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("DeepL-Auth-Key", apiKey);
        using var response = await _http.SendAsync(request, ct);
        EnsureSuccess(response, "DeepL");
        using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        var translated = json.RootElement.GetProperty("translations")[0].GetProperty("text").GetString();
        if (string.IsNullOrWhiteSpace(translated)) throw new InvalidOperationException("DeepL 未返回文本。");
        return new("deepl", "DeepL", translated);
    }

    private async Task<TranslationResult> TranslateLibreAsync(
        string text, string source, string target, PythiaSettings settings, CancellationToken ct)
    {
        var payload = new Dictionary<string, object?>
        {
            ["q"] = text,
            ["source"] = source,
            ["target"] = target,
            ["format"] = "text",
        };
        var apiKey = credentials.Read("provider.libretranslate.apiKey");
        if (!string.IsNullOrWhiteSpace(apiKey)) payload["api_key"] = apiKey;
        using var response = await _http.PostAsync(
            settings.LibreTranslateBaseUrl.Trim().TrimEnd('/') + "/translate",
            new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"), ct);
        EnsureSuccess(response, "LibreTranslate");
        using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        var translated = json.RootElement.GetProperty("translatedText").GetString();
        if (string.IsNullOrWhiteSpace(translated)) throw new InvalidOperationException("LibreTranslate 未返回文本。");
        return new("libretranslate", "LibreTranslate", translated);
    }

    private string RequiredSecret(string key, string message)
    {
        var value = credentials.Read(key);
        if (string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException(message);
        return value;
    }

    private static void EnsureSuccess(HttpResponseMessage response, string service)
    {
        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"{service}请求失败（HTTP {(int)response.StatusCode}）。");
    }

    private static string SafeError(Exception exception) => exception switch
    {
        HttpRequestException http => http.Message,
        TaskCanceledException => "请求超时，请检查网络连接。",
        _ => exception.Message,
    };

    public static (string Source, string Target) ResolveLanguages(string text, string source, string target)
    {
        source = string.IsNullOrWhiteSpace(source) ? "auto" : source;
        target = string.IsNullOrWhiteSpace(target) ? "zh-CN" : target;
        if (source.Equals("auto", StringComparison.OrdinalIgnoreCase))
        {
            var chineseCount = 0;
            var englishCount = 0;
            var insideEnglishWord = false;
            foreach (var rune in text.EnumerateRunes())
            {
                var value = rune.Value;
                if (value is >= 0x4E00 and <= 0x9FFF or >= 0x3400 and <= 0x4DBF or >= 0x20000 and <= 0x2A6DF)
                {
                    chineseCount++;
                    insideEnglishWord = false;
                }
                else if (value is >= 'A' and <= 'Z' or >= 'a' and <= 'z')
                {
                    if (!insideEnglishWord) englishCount++;
                    insideEnglishWord = true;
                }
                else insideEnglishWord = false;
            }

            if (chineseCount > 0 && englishCount == 0) target = "en";
            else if (englishCount > 0 && chineseCount == 0) target = "zh-CN";
            else if (chineseCount > 0 && englishCount > 0)
            {
                // Product names and abbreviations should not make a mostly-Chinese
                // paragraph look English (or vice versa). Count each Han character and
                // each contiguous Latin word/acronym as one unit, then switch direction
                // only when one side owns at least 65% of those meaningful units;
                // balanced bilingual text keeps the user's selected target, matching
                // the macOS mixed-content fallback.
                var total = chineseCount + englishCount;
                if (chineseCount * 100 >= total * 65)
                {
                    source = "zh-CN";
                    target = "en";
                }
                else if (englishCount * 100 >= total * 65)
                {
                    source = "en";
                    target = "zh-CN";
                }
                else if (target.StartsWith("en", StringComparison.OrdinalIgnoreCase)) source = "zh-CN";
                else if (target.StartsWith("zh", StringComparison.OrdinalIgnoreCase)) source = "en";
            }
        }
        if (source == target)
            target = target.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "en" : "zh-CN";
        return (source, target);
    }

    private static string MapBaidu(string language) => language switch
    {
        "auto" => "auto",
        "zh-CN" => "zh",
        "zh-TW" => "cht",
        "ja" => "jp",
        "ko" => "kor",
        "fr" => "fra",
        "es" => "spa",
        _ => language,
    };

    private static string MapYoudao(string language) => language switch
    {
        "auto" => "auto",
        "zh-CN" => "zh-CHS",
        "zh-TW" => "zh-CHT",
        "ja" => "ja",
        "ko" => "ko",
        "fr" => "fr",
        "de" => "de",
        "es" => "es",
        "ru" => "ru",
        "pt" => "pt",
        _ => language,
    };

    private static string MapDeepL(string language) => language switch
    {
        "zh-CN" => "ZH-HANS",
        "zh-TW" => "ZH-HANT",
        "en" => "EN",
        "pt" => "PT-BR",
        _ => language.ToUpperInvariant(),
    };
}
