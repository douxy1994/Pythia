using System.IO.Compression;
using System.Text.Json;
using Pythia.Models;

namespace Pythia.Services;

public sealed class PluginService(LocalStore store)
{
    public IReadOnlyList<PluginInfo> LoadInstalled()
    {
        Directory.CreateDirectory(store.PluginsDirectory);
        var result = new List<PluginInfo>();
        foreach (var directory in Directory.EnumerateDirectories(store.PluginsDirectory))
        {
            var manifestPath = Path.Combine(directory, "manifest.json");
            if (!File.Exists(manifestPath)) continue;
            try
            {
                using var json = JsonDocument.Parse(File.ReadAllText(manifestPath));
                var root = json.RootElement;
                result.Add(new PluginInfo(
                    Read(root, "id", Path.GetFileNameWithoutExtension(directory)),
                    Read(root, "name", Path.GetFileNameWithoutExtension(directory)),
                    Read(root, "version", "0.0.0"),
                    Read(root, "description", "翻译插件"),
                    Read(root, "author", "未知作者"),
                    directory));
            }
            catch { }
        }
        return result.OrderBy(item => item.Name).ToArray();
    }

    public PluginInfo Install(string archivePath)
    {
        if (!archivePath.EndsWith(".pythia", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("请选择 .pythia 插件包。");
        var staging = Path.Combine(store.PluginsDirectory, ".install-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            using var archive = ZipFile.OpenRead(archivePath);
            foreach (var archiveEntry in archive.Entries)
            {
                var destination = Path.GetFullPath(Path.Combine(staging, archiveEntry.FullName));
                if (!destination.StartsWith(Path.GetFullPath(staging) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("插件包包含不安全路径。");
                if (archiveEntry.Name.Length == 0) { Directory.CreateDirectory(destination); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                archiveEntry.ExtractToFile(destination, true);
            }
            var manifest = Directory.EnumerateFiles(staging, "manifest.json", SearchOption.AllDirectories).FirstOrDefault()
                ?? throw new InvalidDataException("插件包缺少 manifest.json。");
            using var json = JsonDocument.Parse(File.ReadAllText(manifest));
            var root = json.RootElement;
            var id = Read(root, "id", string.Empty);
            var name = Read(root, "name", string.Empty);
            var version = Read(root, "version", string.Empty);
            var entry = Read(root, "entry", string.Empty);
            if (!System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$") ||
                name.Length == 0 || version.Length == 0 || entry.Length == 0 || entry.Contains(".."))
                throw new InvalidDataException("插件清单格式无效。");
            var rootDirectory = Path.GetDirectoryName(manifest)!;
            if (!File.Exists(Path.Combine(rootDirectory, entry)))
                throw new InvalidDataException("插件入口文件不存在。");
            var target = Path.Combine(store.PluginsDirectory, id + ".pythia");
            if (Directory.Exists(target)) Directory.Delete(target, true);
            Directory.Move(rootDirectory, target);
            return new PluginInfo(id, name, version,
                Read(root, "description", "翻译插件"), Read(root, "author", "未知作者"), target);
        }
        finally
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
        }
    }

    public void Remove(PluginInfo plugin)
    {
        var target = Path.GetFullPath(plugin.DirectoryPath);
        var root = Path.GetFullPath(store.PluginsDirectory) + Path.DirectorySeparatorChar;
        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("插件路径不在 Pythia 数据目录中。");
        if (Directory.Exists(target)) Directory.Delete(target, true);
    }

    private static string Read(JsonElement root, string name, string fallback) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? fallback : fallback;
}
