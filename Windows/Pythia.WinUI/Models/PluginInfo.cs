namespace Pythia.Models;

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
    public IReadOnlyList<PluginConfigurationField> Configuration { get; set; }
    public bool Enabled { get; set; }
    public bool IsConfigured { get; set; }
    public string LastError { get; set; }
    public string ServiceId => $"plugin:{Id}";
    public string NameInitial => string.IsNullOrWhiteSpace(Name) ? "P" : Name[..1].ToUpperInvariant();
    public string VersionDisplay => $"v{Version}";
    public string EnabledDisplay => Enabled ? "已启用" : "已停用";
    public string ToggleDisplay => Enabled ? "停用" : "启用";
    public string ConfigurationDisplay => Configuration.Count == 0
        ? "无需配置"
        : IsConfigured ? "配置完整" : "配置不完整";
}
