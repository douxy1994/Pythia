namespace Pythia.Models;

using Microsoft.UI.Xaml;

public sealed class TranslationResult
{
    public TranslationResult(string ServiceId, string ServiceName, string Text, string? Model = null, string? Error = null)
    {
        this.ServiceId = ServiceId;
        this.ServiceName = ServiceName;
        this.Text = Text;
        this.Model = Model;
        this.Error = Error;
    }

    public string ServiceId { get; set; }
    public string ServiceName { get; set; }
    public string Text { get; set; }
    public string? Model { get; set; }
    public string? Error { get; set; }
    public bool IsSuccess => Error is null;
    public string DisplayText => Error ?? Text;
    public bool IsPlugin => ServiceId.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase);
    public Visibility RetryVisibility => IsPlugin ? Visibility.Visible : Visibility.Collapsed;
}

public sealed record TranslationBatch(
    string SourceText,
    string SourceLanguage,
    string TargetLanguage,
    IReadOnlyList<TranslationResult> Results);

public static class ServiceCatalog
{
    public static readonly IReadOnlyList<(string Id, string Name)> All =
    [
        ("google", "Google 翻译"),
        ("baidu", "百度翻译"),
        ("youdao", "有道翻译"),
        ("openai-compatible", "AI 翻译"),
        ("deepl", "DeepL"),
        ("libretranslate", "LibreTranslate"),
    ];

    public static string DisplayName(string id) =>
        All.FirstOrDefault(item => item.Id == id).Name ?? id;
}
