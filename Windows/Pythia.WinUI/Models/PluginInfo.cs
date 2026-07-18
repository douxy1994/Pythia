namespace Pythia.Models;

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

public sealed record PluginConfigurationField(
    string Key,
    string Label,
    string Type,
    bool Required,
    string? DefaultValue,
    IReadOnlyDictionary<string, string> Options);

public sealed class PluginInfo
{
    public PluginInfo(
        string id,
        string name,
        string version,
        string description,
        string author,
        string directoryPath,
        string entry,
        string? iconPath,
        IReadOnlyList<PluginConfigurationField> configuration,
        bool enabled = true,
        bool isConfigured = false,
        string lastError = "")
    {
        Id = id;
        Name = name;
        Version = version;
        Description = description;
        Author = author;
        DirectoryPath = directoryPath;
        Entry = entry;
        IconPath = iconPath;
        Configuration = configuration;
        Enabled = enabled;
        IsConfigured = isConfigured;
        LastError = lastError;
    }

    public string Id { get; set; }
    public string Name { get; set; }
    public string Version { get; set; }
    public string Description { get; set; }
    public string Author { get; set; }
    public string DirectoryPath { get; set; }
    public string Entry { get; set; }
    public string? IconPath { get; set; }
    public IReadOnlyList<PluginConfigurationField> Configuration { get; set; }
    public bool Enabled { get; set; }
    public bool IsConfigured { get; set; }
    public string LastError { get; set; }
    public string ServiceId => $"plugin:{Id}";
    public string NameInitial => string.IsNullOrWhiteSpace(Name) ? "P" : Name[..1].ToUpperInvariant();
    public string VersionDisplay => $"v{Version}";
    public string EnabledDisplay => Enabled ? "已启用" : "已停用";
    public string ToggleDisplay => Enabled ? "停用" : "启用";
    public Symbol ToggleSymbol => Enabled ? Symbol.Stop : Symbol.Play;
    public string ConfigurationDisplay => Configuration.Count == 0
        ? "无需配置"
        : IsConfigured ? "配置完整" : "配置不完整";
    public Visibility LastErrorVisibility => string.IsNullOrWhiteSpace(LastError) ? Visibility.Collapsed : Visibility.Visible;
    public Visibility IconVisibility => string.IsNullOrWhiteSpace(IconPath) ? Visibility.Collapsed : Visibility.Visible;
    public Visibility FallbackIconVisibility => IconVisibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
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
}

public enum PluginConnectionStatus
{
    Success,
    MissingRequiredConfiguration,
    MissingCredential,
    InvalidCredential,
    ModelUnavailable,
    NetworkUnreachable,
    Timeout,
    UpstreamError,
    ProtocolIncompatible,
    ProcessAbnormalExit,
}

public sealed record PluginConnectionResult(
    PluginConnectionStatus Status,
    string Message,
    int Attempts,
    TimeSpan Duration)
{
    public bool IsSuccess => Status == PluginConnectionStatus.Success;
    public string StatusDisplay => Status switch
    {
        PluginConnectionStatus.Success => "成功",
        PluginConnectionStatus.MissingRequiredConfiguration => "缺少必填配置",
        PluginConnectionStatus.MissingCredential => "缺少凭据",
        PluginConnectionStatus.InvalidCredential => "凭据无效",
        PluginConnectionStatus.ModelUnavailable => "模型不可用",
        PluginConnectionStatus.NetworkUnreachable => "网络不可达",
        PluginConnectionStatus.Timeout => "超时",
        PluginConnectionStatus.UpstreamError => "上游服务错误",
        PluginConnectionStatus.ProtocolIncompatible => "格式或协议不兼容",
        PluginConnectionStatus.ProcessAbnormalExit => "插件进程异常退出",
        _ => "未知错误",
    };
}
