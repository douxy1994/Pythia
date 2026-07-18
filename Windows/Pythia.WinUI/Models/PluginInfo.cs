namespace Pythia.Models;

public sealed class PluginInfo
{
    public PluginInfo(string id, string name, string version, string description, string author, string directoryPath)
    {
        Id = id;
        Name = name;
        Version = version;
        Description = description;
        Author = author;
        DirectoryPath = directoryPath;
    }

    public string Id { get; set; }
    public string Name { get; set; }
    public string Version { get; set; }
    public string Description { get; set; }
    public string Author { get; set; }
    public string DirectoryPath { get; set; }
    public string NameInitial => string.IsNullOrWhiteSpace(Name) ? "P" : Name[..1].ToUpperInvariant();
    public string VersionDisplay => $"v{Version}";
}
