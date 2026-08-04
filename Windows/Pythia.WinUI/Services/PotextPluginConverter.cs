using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pythia.Services;

public sealed class PotextConversionManifest
{
    public string SchemaVersion { get; init; } = "1.0";
    public string Id { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string Version { get; init; } = "1.0.0";
    public string Description { get; init; } = string.Empty;
    public string Author { get; init; } = "Unknown";
    public string Type { get; init; } = "translator";
    public string Entry { get; init; } = "main.js";
    public string MinimumPythiaVersion { get; init; } = "1.0.0";
    public IReadOnlyList<string> SupportedPlatforms { get; init; } = ["macos", "windows"];
    public IReadOnlyList<string> Permissions { get; init; } = [];
    public IReadOnlyList<PotextConfigurationField> Configuration { get; init; } = [];
    public IReadOnlyList<string> Capabilities { get; init; } = ["translate"];
}

public sealed class PotextConfigurationField
{
    public string Key { get; init; } = string.Empty;
    public string Label { get; init; } = string.Empty;
    public string Type { get; init; } = "text";
    public bool Required { get; init; }
    public string? DefaultValue { get; init; }
    public IReadOnlyDictionary<string, string>? Options { get; init; }
}

public sealed record PotextConversionResult(
    PotextConversionManifest Manifest,
    string MainJavaScript,
    IReadOnlyList<string> Warnings);

/// <summary>
/// Converts the legacy Pot .potext translator contract to the shared Pythia
/// manifest/runner contract. The generated package retains info.json and the
/// original main.js so a later conversion can be repeated without guessing.
/// </summary>
public static class PotextPluginConverter
{
    private static readonly Regex VersionPattern = new(
        "^[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$",
        RegexOptions.CultureInvariant);
    private static readonly Regex NetworkPattern = new(
        "tauriFetch|utils\\.http|\\bfetch\\s*\\(",
        RegexOptions.CultureInvariant);

    public static PotextConversionResult Convert(
        byte[] infoData,
        string mainJavaScript,
        string fallbackIdentifier)
    {
        using var document = JsonDocument.Parse(infoData);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException(".potext 的 info.json 必须是 JSON 对象。");

        var legacyType = StringValue(root, "plugin_type");
        if (!legacyType.Equals("translate", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"不支持旧插件类型：{legacyType}。");

        var rawIdentifier = StringValue(root, "id");
        var id = NormalizeIdentifier(string.IsNullOrWhiteSpace(rawIdentifier) ? fallbackIdentifier : rawIdentifier);
        var name = FirstNonEmpty(StringValue(root, "display"), StringValue(root, "name"), id);
        var declaredVersion = StringValue(root, "version");
        var version = VersionPattern.IsMatch(declaredVersion) ? declaredVersion : "1.0.0";
        var warnings = new List<string>();
        if (string.IsNullOrWhiteSpace(declaredVersion))
            warnings.Add("原插件未声明版本，转换后使用 1.0.0。");
        else if (!version.Equals(declaredVersion, StringComparison.Ordinal))
            warnings.Add("原插件版本格式不兼容，转换后使用 1.0.0。");

        var configuration = new List<PotextConfigurationField>();
        if (root.TryGetProperty("needs", out var needs) && needs.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in needs.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.Object) continue;
                var key = StringValue(item, "key").Trim();
                if (key.Length == 0)
                {
                    warnings.Add("已忽略缺少 key 的配置项。");
                    continue;
                }

                var legacyTypeValue = StringValue(item, "type");
                var isSecret = BoolValue(item, "secret") ||
                    legacyTypeValue.Equals("password", StringComparison.OrdinalIgnoreCase) ||
                    legacyTypeValue.Equals("secret", StringComparison.OrdinalIgnoreCase) ||
                    IsLikelySecretKey(key);
                var type = isSecret
                    ? "secret"
                    : legacyTypeValue.Equals("select", StringComparison.OrdinalIgnoreCase) ? "select" : "text";
                var defaultValue = StringValue(item, "default");
                var options = ReadOptions(item, "options");
                configuration.Add(new PotextConfigurationField
                {
                    Key = key,
                    Label = FirstNonEmpty(StringValue(item, "display"), key),
                    Type = type,
                    Required = isSecret && string.IsNullOrWhiteSpace(defaultValue),
                    DefaultValue = isSecret ? null : NullIfEmpty(defaultValue),
                    Options = options,
                });
            }
        }

        var permissions = NetworkPattern.IsMatch(mainJavaScript) ? new[] { "network" } : Array.Empty<string>();
        var manifest = new PotextConversionManifest
        {
            Id = id,
            Name = name,
            Version = version,
            Description = FirstNonEmpty(StringValue(root, "description"), "由 Pythia 从 Pot 插件自动转换。"),
            Author = InferAuthor(StringValue(root, "homepage")),
            Permissions = permissions,
            Configuration = configuration,
        };
        warnings.Add("已保留原 main.js，并通过 Pythia 统一请求/响应适配层运行。");
        return new PotextConversionResult(manifest, CompatibilityPrelude + "\n" + mainJavaScript + "\n" + CompatibilityPostlude, warnings);
    }

    private static IReadOnlyDictionary<string, string>? ReadOptions(JsonElement root, string property)
    {
        if (!root.TryGetProperty(property, out var options) || options.ValueKind != JsonValueKind.Object)
            return null;
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var option in options.EnumerateObject())
        {
            if (option.Value.ValueKind != JsonValueKind.String) continue;
            result[option.Name] = option.Value.GetString() ?? option.Name;
        }
        return result.Count == 0 ? null : result;
    }

    private static string StringValue(JsonElement root, string property)
    {
        if (!root.TryGetProperty(property, out var value)) return string.Empty;
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString() ?? string.Empty,
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => string.Empty,
        };
    }

    private static bool BoolValue(JsonElement root, string property) =>
        root.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.True;

    private static string? NullIfEmpty(string value) => string.IsNullOrWhiteSpace(value) ? null : value;

    private static string FirstNonEmpty(params string[] values) =>
        values.Select(value => value.Trim()).FirstOrDefault(value => value.Length > 0) ?? "Unknown";

    private static string NormalizeIdentifier(string raw)
    {
        var value = new string(raw.Select(character =>
            (character is >= 'A' and <= 'Z') || (character is >= 'a' and <= 'z') ||
            (character is >= '0' and <= '9') || character is '.' or '_' or '-' ? character : '-').ToArray());
        value = value.Trim('.', '-', '_');
        if (value.Length < 3) value = $"plugin.{(value.Length == 0 ? "converted" : value)}";
        return value[..Math.Min(128, value.Length)];
    }

    private static string InferAuthor(string homepage)
    {
        if (!Uri.TryCreate(homepage, UriKind.Absolute, out var uri) || string.IsNullOrWhiteSpace(uri.Host))
            return "Unknown";
        if (uri.Host.Contains("github.com", StringComparison.OrdinalIgnoreCase))
        {
            var owner = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(owner)) return owner;
        }
        return uri.Host;
    }

    private static bool IsLikelySecretKey(string key)
    {
        var normalized = new string(key.Where(char.IsLetter).ToArray()).ToLowerInvariant();
        return normalized is "secret" or "password" or "passwd" or "token" ||
            normalized.EndsWith("apikey", StringComparison.Ordinal) ||
            normalized.EndsWith("appkey", StringComparison.Ordinal) ||
            normalized.Contains("accesskey", StringComparison.Ordinal) ||
            normalized.EndsWith("secretkey", StringComparison.Ordinal) ||
            normalized.EndsWith("clientsecret", StringComparison.Ordinal) ||
            (normalized.EndsWith("token", StringComparison.Ordinal) && !normalized.EndsWith("tokens", StringComparison.Ordinal));
    }

    private const string CompatibilityPrelude = """
globalThis.ResponseType = Object.freeze({ Text: "Text", Json: "Json", JSON: "Json" });
globalThis.Body = Object.freeze({
  json: (payload) => ({ type: "Json", payload }),
  form: (payload) => ({ type: "Form", payload }),
  text: (payload) => ({ type: "Text", payload })
});
""";

    private const string CompatibilityPostlude = """

const __pythiaLegacyTranslate = translate;

async function __pythiaCompatFetch(context, url, options = {}) {
  const headers = { ...(options.headers || {}) };
  let body = options.body;
  if (body && typeof body === "object" && Object.prototype.hasOwnProperty.call(body, "type")) {
    if (body.type === "Json") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) headers["Content-Type"] = "application/json";
      body = JSON.stringify(body.payload);
    } else if (body.type === "Form") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) headers["Content-Type"] = "application/x-www-form-urlencoded";
      body = new URLSearchParams(body.payload || {}).toString();
    } else {
      body = String(body.payload ?? "");
    }
  } else if (body && typeof body === "object") {
    if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) headers["Content-Type"] = "application/json";
    body = JSON.stringify(body);
  }
  const response = await context.fetch(url, { method: options.method || "GET", headers, body });
  const responseText = await response.text();
  const wantsText = options.responseType === "Text" || options.responseType === "text";
  let data = responseText;
  if (!wantsText) { try { data = responseText ? JSON.parse(responseText) : null; } catch (_) {} }
  return { ok: response.ok, status: response.status, url: response.url, data, headers: Object.fromEntries(response.headers.entries()) };
}

module.exports.translate = async function pythiaConvertedTranslate(request, context) {
  const input = request && request.input ? request.input : {};
  const compatFetch = (url, options) => __pythiaCompatFetch(context, url, options);
  const utils = { tauriFetch: compatFetch, http: { fetch: compatFetch, Body: globalThis.Body } };
  return await __pythiaLegacyTranslate(
    String(input.text || ""),
    String(input.sourceLanguage || "auto"),
    String(input.targetLanguage || "zh-CN"),
    { config: context.config || {}, detect: input.detectedLanguage || input.sourceLanguage || "auto", utils, setResult: () => {} }
  );
};
""";
}
