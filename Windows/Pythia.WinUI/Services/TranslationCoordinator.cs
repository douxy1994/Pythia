using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Pythia.Models;

namespace Pythia.Services;

public sealed class TranslationCoordinator(CredentialStore credentials, PluginService? plugins = null)
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(30) };

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
        var tasks = serviceIds.Distinct(StringComparer.OrdinalIgnoreCase).Select(async id =>
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
        var baseUrl = settings.OpenAICompatibleBaseUrl.Trim().TrimEnd('/');
        if (baseUrl.Length == 0) throw new InvalidOperationException("请先填写 AI 服务地址。");
        var serviceName = string.IsNullOrWhiteSpace(settings.OpenAICompatibleName)
            ? "AI 翻译" : settings.OpenAICompatibleName.Trim();
        var payload = JsonSerializer.Serialize(new
        {
            model = settings.OpenAICompatibleModel,
            temperature = 0.2,
            messages = new object[]
            {
                new { role = "system", content = "You are a professional translator. Return only the translation without explanations or quotation marks." },
                new { role = "user", content = $"Translate the following text from {source} to {target}:\n\n{text}" },
            },
        });
        using var request = new HttpRequestMessage(HttpMethod.Post, baseUrl + "/chat/completions")
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        using var response = await _http.SendAsync(request, ct);
        EnsureSuccess(response, serviceName);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        var translated = json.RootElement.GetProperty("choices")[0].GetProperty("message")
            .GetProperty("content").GetString()?.Trim();
        if (string.IsNullOrWhiteSpace(translated)) throw new InvalidOperationException("AI 服务未返回文本。");
        return new("openai-compatible", serviceName, translated, settings.OpenAICompatibleModel);
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
            var hasChinese = false;
            var hasEnglish = false;
            foreach (var rune in text.EnumerateRunes())
            {
                var value = rune.Value;
                if (value is >= 0x4E00 and <= 0x9FFF or >= 0x3400 and <= 0x4DBF or >= 0x20000 and <= 0x2A6DF)
                    hasChinese = true;
                else if (value is >= 'A' and <= 'Z' or >= 'a' and <= 'z')
                    hasEnglish = true;
            }
            if (hasChinese && !hasEnglish) target = "en";
            else if (hasEnglish && !hasChinese) target = "zh-CN";
            else if (hasChinese && hasEnglish)
            {
                if (target.StartsWith("en", StringComparison.OrdinalIgnoreCase)) source = "zh-CN";
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
