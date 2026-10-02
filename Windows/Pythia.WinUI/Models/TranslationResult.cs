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
    private string _text = string.Empty;
    private string? _error;
    private string? _model;
    private bool _isLoading;
    public string Text { get => _text; set { _text = value; NotifyResult(); } }
    public string? Model { get => _model; set { _model = value; OnPropertyChanged(); } }
    public string? Error { get => _error; set { _error = value; NotifyResult(); } }
    public string? IconPath { get; set; }
    public bool IsLoading
    {
        get => _isLoading;
        set { _isLoading = value; NotifyResult(); OnPropertyChanged(); OnPropertyChanged(nameof(LoadingVisibility)); OnPropertyChanged(nameof(CanRetry)); }
    }
    public bool CanRetry => !IsLoading;
    public Visibility LoadingVisibility => IsLoading ? Visibility.Visible : Visibility.Collapsed;
    public bool IsSuccess => !IsLoading && Error is null;
    private void NotifyResult()
    {
        OnPropertyChanged(nameof(Text));
        OnPropertyChanged(nameof(Error));
        OnPropertyChanged(nameof(DisplayText));
        OnPropertyChanged(nameof(IsSuccess));
    }
    public void Apply(TranslationResult completed)
    {
        ServiceName = completed.ServiceName;
        OnPropertyChanged(nameof(ServiceName));
        Text = completed.Text;
        Error = completed.Error;
        Model = completed.Model;
        IsLoading = false;
    }
    public string DisplayText => IsLoading ? "正在翻译…" : Error ?? Text;
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
