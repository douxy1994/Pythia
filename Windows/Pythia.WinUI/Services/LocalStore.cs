using System.Text.Json;
using Pythia.Models;

namespace Pythia.Services;

public sealed class LocalStore
{
    private readonly SemaphoreSlim _writeGate = new(1, 1);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public LocalStore(string? dataDirectory = null)
    {
        DataDirectory = dataDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "DouXY", "Pythia", "Pythia");
        Directory.CreateDirectory(DataDirectory);
    }

    public string DataDirectory { get; }
    public string SettingsPath => Path.Combine(DataDirectory, "settings.json");
    public string HistoryPath => Path.Combine(DataDirectory, "history.json");
    public string HistoryBackupPath => Path.Combine(DataDirectory, "Backups", "history-before-sync.json");
    public string DeviceIdPath => Path.Combine(DataDirectory, "device-id.txt");
    public string PluginsDirectory => Path.Combine(DataDirectory, "Plugins");
    public string RuntimeDirectory => Path.Combine(DataDirectory, "Runtime");

    public async Task<PythiaSettings> LoadSettingsAsync()
    {
        try
        {
            if (!File.Exists(SettingsPath)) return new();
            await using var stream = File.OpenRead(SettingsPath);
            return await JsonSerializer.DeserializeAsync<PythiaSettings>(stream, JsonOptions) ?? new();
        }
        catch
        {
            BackupUnreadable(SettingsPath);
            return new();
        }
    }

    public Task SaveSettingsAsync(PythiaSettings settings) => WriteAtomicAsync(SettingsPath, settings);

    public async Task<List<HistoryRecord>> LoadHistoryAsync()
    {
        try
        {
            if (!File.Exists(HistoryPath)) return [];
            await using var stream = File.OpenRead(HistoryPath);
            return await JsonSerializer.DeserializeAsync<List<HistoryRecord>>(stream, JsonOptions) ?? [];
        }
        catch
        {
            BackupUnreadable(HistoryPath);
            return [];
        }
    }

    public Task SaveHistoryAsync(IEnumerable<HistoryRecord> records) =>
        WriteAtomicAsync(HistoryPath, records.ToArray());

    public async Task BackupHistoryBeforeSyncAsync()
    {
        if (!File.Exists(HistoryPath)) return;
        Directory.CreateDirectory(Path.GetDirectoryName(HistoryBackupPath)!);
        await using var source = new FileStream(HistoryPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        await using var destination = new FileStream(HistoryBackupPath, FileMode.Create, FileAccess.Write, FileShare.None);
        await source.CopyToAsync(destination);
        await destination.FlushAsync();
    }

    public async Task<string> GetDeviceIdAsync()
    {
        if (File.Exists(DeviceIdPath))
        {
            var existing = (await File.ReadAllTextAsync(DeviceIdPath)).Trim();
            if (existing.Length > 0) return existing;
        }

        var id = Guid.NewGuid().ToString("N");
        await File.WriteAllTextAsync(DeviceIdPath, id);
        return id;
    }

    private async Task WriteAtomicAsync<T>(string path, T value)
    {
        await _writeGate.WaitAsync();
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            await using (var stream = File.Create(temporary))
            {
                await JsonSerializer.SerializeAsync(stream, value, JsonOptions);
                await stream.FlushAsync();
            }
            File.Move(temporary, path, true);
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
            _writeGate.Release();
        }
    }

    private static void BackupUnreadable(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Copy(path, $"{path}.unreadable-{DateTime.UtcNow:yyyyMMddHHmmss}", true);
        }
        catch { }
    }
}
