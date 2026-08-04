namespace Pythia.Models;

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using System.ComponentModel;
using System.Runtime.CompilerServices;

public sealed class TranslationResult : INotifyPropertyChanged
{
    private bool _isExpanded = true;
    private bool _showCollapse = true;
    public TranslationResult(string ServiceId, string ServiceName, string Text, string? Model = null, string? Error = null, string? IconPath = null)
    {
        this.ServiceId = ServiceId;
        this.ServiceName = ServiceName;
        this.Text = Text;
        this.Model = Model;
        this.Error = Error;
        this.IconPath = IconPath;
    }

    public string ServiceId { get; set; }
    public string ServiceName { get; set; }
    public string Text { get; set; }
    public string? Model { get; set; }
    public string? Error { get; set; }
    public string? IconPath { get; set; }
    public bool IsSuccess => Error is null;
    public string DisplayText => Error ?? Text;
    public bool IsPlugin => ServiceId.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase);
    public Visibility RetryVisibility => Visibility.Visible;
    public Visibility CollapseVisibility => _showCollapse ? Visibility.Visible : Visibility.Collapsed;
    public bool ShowCollapse
    {
        get => _showCollapse;
        set
        {
            if (_showCollapse == value) return;
            _showCollapse = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CollapseVisibility));
        }
    }
    public Visibility PluginIconVisibility => IsPlugin && !string.IsNullOrWhiteSpace(IconPath) ? Visibility.Visible : Visibility.Collapsed;
    public Visibility PluginFallbackVisibility => IsPlugin && string.IsNullOrWhiteSpace(IconPath) ? Visibility.Visible : Visibility.Collapsed;
    public Visibility BuiltInIconVisibility => IsPlugin ? Visibility.Collapsed : Visibility.Visible;
    public ImageSource? IconSource
    {
        get
        {
            if (string.IsNullOrWhiteSpace(IconPath) || !File.Exists(IconPath)) return null;
            var uri = new Uri(IconPath);
            return Path.GetExtension(IconPath).Equals(".svg", StringComparison.OrdinalIgnoreCase)
                ? new SvgImageSource(uri)
                : new BitmapImage(uri);
        }
    }
    public bool IsExpanded
    {
        get => _isExpanded;
        set
        {
            if (_isExpanded == value) return;
            _isExpanded = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(BodyVisibility));
            OnPropertyChanged(nameof(ExpandIcon));
        }
    }
    public Visibility BodyVisibility => IsExpanded ? Visibility.Visible : Visibility.Collapsed;
    public string ExpandIcon => IsExpanded ? "chevron-up" : "chevron-down";

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
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
        ("openai-compatible", "大模型翻译"),
        ("deepl", "DeepL"),
        ("libretranslate", "LibreTranslate"),
    ];

    public static string DisplayName(string id) =>
        All.FirstOrDefault(item => item.Id == id).Name ?? id;
}
