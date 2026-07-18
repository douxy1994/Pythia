using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Pythia.Models;

namespace Pythia.Services;

public sealed class PluginService(LocalStore store, CredentialStore credentials)
{
    private const int MaxArchiveEntries = 2048;
    private const long MaxArchiveBytes = 64L * 1024 * 1024;
    private static readonly Regex ValidId = new("^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$", RegexOptions.CultureInvariant);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };
    private readonly object _stateLock = new();

    private string StatePath => Path.Combine(store.PluginsDirectory, "plugin-state.json");
    private string RunnerPath => Path.Combine(store.RuntimeDirectory, "pythia-plugin-runner.cjs");

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(store.PluginsDirectory);
        Directory.CreateDirectory(store.RuntimeDirectory);
        var bundledRunner = Path.Combine(AppContext.BaseDirectory, "Assets", "pythia-plugin-runner.cjs");
        if (!File.Exists(bundledRunner))
            throw new FileNotFoundException("Pythia 插件运行器缺失。", bundledRunner);
        var source = await File.ReadAllTextAsync(bundledRunner, Encoding.UTF8);
        if (!File.Exists(RunnerPath) || await File.ReadAllTextAsync(RunnerPath, Encoding.UTF8) != source)
            await File.WriteAllTextAsync(RunnerPath, source, new UTF8Encoding(false));
        MigrateLegacyPotConfigurations();
    }

    public IReadOnlyList<PluginInfo> LoadInstalled()
    {
        Directory.CreateDirectory(store.PluginsDirectory);
        var state = ReadState();
        var result = new List<PluginInfo>();
        foreach (var directory in Directory.EnumerateDirectories(store.PluginsDirectory, "*.pythia"))
        {
            try { result.Add(ReadPlugin(directory, state)); }
            catch { }
        }
        return result.OrderBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    public string DisplayName(string serviceId)
    {
        var id = serviceId.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase)
            ? serviceId["plugin:".Length..]
            : serviceId;
        return LoadInstalled().FirstOrDefault(item => item.Id.Equals(id, StringComparison.OrdinalIgnoreCase))?.Name
            ?? ServiceCatalog.DisplayName(serviceId);
    }

    public PluginInfo Install(string archivePath)
    {
        if (!archivePath.EndsWith(".pythia", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("请选择 .pythia 插件包。");
        if (new FileInfo(archivePath).Length > MaxArchiveBytes)
            throw new InvalidDataException("插件包超过 64 MiB 限制。");

        var staging = Path.Combine(store.PluginsDirectory, ".install-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            using var archive = ZipFile.OpenRead(archivePath);
            if (archive.Entries.Count > MaxArchiveEntries)
                throw new InvalidDataException("插件包文件数量超过限制。");
            long expandedBytes = 0;
            foreach (var archiveEntry in archive.Entries)
            {
                expandedBytes += archiveEntry.Length;
                if (expandedBytes > MaxArchiveBytes)
                    throw new InvalidDataException("插件解压后超过 64 MiB 限制。");
                if (((archiveEntry.ExternalAttributes >> 16) & 0xF000) == 0xA000)
                    throw new InvalidDataException("插件包不能包含符号链接。");
                var destination = Path.GetFullPath(Path.Combine(staging, archiveEntry.FullName));
                var stagingRoot = Path.GetFullPath(staging) + Path.DirectorySeparatorChar;
                if (!destination.StartsWith(stagingRoot, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("插件包包含不安全路径。");
                if (archiveEntry.Name.Length == 0)
                {
                    Directory.CreateDirectory(destination);
                    continue;
                }
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                archiveEntry.ExtractToFile(destination, true);
            }

            var manifests = Directory.EnumerateFiles(staging, "manifest.json", SearchOption.AllDirectories).ToArray();
            if (manifests.Length != 1)
                throw new InvalidDataException("插件包必须且只能包含一个 manifest.json。");
            var rootDirectory = Path.GetDirectoryName(manifests[0])!;
            var plugin = ReadPlugin(rootDirectory, ReadState(), requirePythiaExtension: false);
            var target = Path.Combine(store.PluginsDirectory, plugin.Id + ".pythia");
            if (Directory.Exists(target)) Directory.Delete(target, true);
            Directory.Move(rootDirectory, target);
            EnsureState(plugin.Id);
            MigrateLegacyPotConfigurations(plugin.Id);
            return LoadInstalled().First(item => item.Id == plugin.Id);
        }
        finally
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
        }
    }

    public IReadOnlyDictionary<string, string> GetConfiguration(PluginInfo plugin)
    {
        var state = ReadState();
        var item = GetState(state, plugin.Id);
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var field in plugin.Configuration)
        {
            if (!string.IsNullOrEmpty(field.DefaultValue)) result[field.Key] = field.DefaultValue;
            if (field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase))
            {
                var secret = credentials.Read(SecretKey(plugin.Id, field.Key));
                if (!string.IsNullOrEmpty(secret)) result[field.Key] = secret;
            }
            else if (item.Configuration.TryGetValue(field.Key, out var value) && !string.IsNullOrEmpty(value))
            {
                result[field.Key] = value;
            }
        }
        return result;
    }

    public void SaveConfiguration(PluginInfo plugin, IReadOnlyDictionary<string, string> values)
    {
        lock (_stateLock)
        {
            var state = ReadStateUnlocked();
            var item = GetState(state, plugin.Id);
            var publicConfig = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var field in plugin.Configuration)
            {
                var value = values.GetValueOrDefault(field.Key)?.Trim() ?? string.Empty;
                if (field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase))
                {
                    if (value.Length == 0) credentials.Delete(SecretKey(plugin.Id, field.Key));
                    else credentials.Write(SecretKey(plugin.Id, field.Key), values[field.Key]);
                }
                else if (value.Length > 0)
                {
                    publicConfig[field.Key] = values[field.Key];
                }
            }
            item.Configuration = publicConfig;
            item.LastError = string.Empty;
            state[plugin.Id] = item;
            WriteStateUnlocked(state);
        }
    }

    public void SetEnabled(PluginInfo plugin, bool enabled)
    {
        lock (_stateLock)
        {
            var state = ReadStateUnlocked();
            var item = GetState(state, plugin.Id);
            item.Enabled = enabled;
            item.LastError = string.Empty;
            state[plugin.Id] = item;
            WriteStateUnlocked(state);
        }
    }

    public void Remove(PluginInfo plugin)
    {
        var target = Path.GetFullPath(plugin.DirectoryPath);
        var root = Path.GetFullPath(store.PluginsDirectory) + Path.DirectorySeparatorChar;
        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("插件路径不在 Pythia 数据目录中。");
        foreach (var field in plugin.Configuration.Where(item => item.Type.Equals("secret", StringComparison.OrdinalIgnoreCase)))
            credentials.Delete(SecretKey(plugin.Id, field.Key));
        if (Directory.Exists(target)) Directory.Delete(target, true);
        lock (_stateLock)
        {
            var state = ReadStateUnlocked();
            state.Remove(plugin.Id);
            WriteStateUnlocked(state);
        }
    }

    public async Task<string> TranslateAsync(
        string serviceId,
        string text,
        string sourceLanguage,
        string targetLanguage,
        CancellationToken cancellationToken = default)
    {
        var id = serviceId.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase)
            ? serviceId["plugin:".Length..]
            : serviceId;
        var plugin = LoadInstalled().FirstOrDefault(item => item.Id.Equals(id, StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("插件未安装或清单无效。");
        if (!plugin.Enabled) throw new InvalidOperationException($"{plugin.Name} 已停用。");
        var config = GetConfiguration(plugin);
        var missing = plugin.Configuration
            .Where(field => field.Required && string.IsNullOrWhiteSpace(config.GetValueOrDefault(field.Key)))
            .Select(field => field.Label)
            .ToArray();
        if (missing.Length > 0)
            throw new InvalidOperationException($"插件配置不完整：{string.Join("、", missing)}。");
        var node = ResolveNodeExecutable()
            ?? throw new InvalidOperationException("Pythia 插件运行时缺少 node.exe。");
        var requestId = Guid.NewGuid().ToString("N");
        var request = JsonSerializer.Serialize(new
        {
            schemaVersion = "1.0",
            requestId,
            type = "translate",
            input = new
            {
                text,
                sourceLanguage,
                targetLanguage,
                detectedLanguage = sourceLanguage,
            },
            context = new { platform = "windows", pythiaVersion = "1.0.0" },
        });
        var timeout = TimeSpan.FromSeconds(Math.Min(1200, Math.Max(180, 180 + text.Length / 20d)));
        var startInfo = new ProcessStartInfo
        {
            FileName = node,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        startInfo.ArgumentList.Add(RunnerPath);
        startInfo.ArgumentList.Add(plugin.DirectoryPath);
        startInfo.ArgumentList.Add(plugin.Entry);
        startInfo.Environment["PYTHIA_PLUGIN_REQUEST"] = request;
        startInfo.Environment["PYTHIA_PLUGIN_CONFIG"] = JsonSerializer.Serialize(config);
        startInfo.Environment["PYTHIA_PLUGIN_TIMEOUT_MS"] = ((long)timeout.TotalMilliseconds).ToString();

        using var process = new Process { StartInfo = startInfo };
        try
        {
            process.Start();
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            using var timeoutSource = new CancellationTokenSource(timeout + TimeSpan.FromSeconds(2));
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
            try
            {
                await process.WaitForExitAsync(linked.Token);
            }
            catch (OperationCanceledException) when (timeoutSource.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
            {
                TryKill(process);
                throw new TimeoutException("插件执行超时，已终止该插件进程。");
            }
            catch
            {
                TryKill(process);
                throw;
            }

            var stdout = await stdoutTask;
            var stderr = Redact(await stderrTask, plugin, config);
            if (Encoding.UTF8.GetByteCount(stdout) > 8 * 1024 * 1024)
                throw new InvalidDataException("插件响应超过 8 MiB 限制。");
            if (process.ExitCode != 0)
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderr)
                    ? "插件执行失败。"
                    : Limit(SanitizeExternalError(stderr)));
            using var response = JsonDocument.Parse(stdout);
            var root = response.RootElement;
            if (!root.TryGetProperty("requestId", out var responseId) || responseId.GetString() != requestId ||
                !root.TryGetProperty("success", out var success) || success.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new InvalidDataException("插件返回了无效的统一响应。");
            if (!success.GetBoolean())
            {
                var error = root.TryGetProperty("error", out var errorObject) ? errorObject : default;
                var code = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("code", out var codeValue)
                    ? codeValue.GetString() : "RUNTIME_ERROR";
                var message = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var messageValue)
                    ? messageValue.GetString() : "插件报告执行失败。";
                throw new InvalidOperationException($"{code}：{Limit(SanitizeExternalError(Redact(message ?? string.Empty, plugin, config)))}");
            }
            if (!root.TryGetProperty("data", out var data) || !data.TryGetProperty("text", out var translated) ||
                string.IsNullOrWhiteSpace(translated.GetString()))
                throw new InvalidDataException("插件成功响应缺少非空 data.text。");
            RecordError(plugin.Id, string.Empty);
            return translated.GetString()!.Trim();
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception)
        {
            var safeMessage = Limit(SanitizeExternalError(Redact(exception.Message, plugin, config)));
            RecordError(plugin.Id, safeMessage);
            throw new InvalidOperationException(safeMessage, exception);
        }
        finally
        {
            TryKill(process);
        }
    }

    public void MigrateLegacyPotConfigurations(string? onlyPluginId = null)
    {
        var legacyPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "com.pot-app.desktop", "config.json");
        if (!File.Exists(legacyPath)) return;
        Dictionary<string, Dictionary<string, string>> candidates = new(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(legacyPath));
            foreach (var property in document.RootElement.EnumerateObject())
            {
                var separator = property.Name.IndexOf('@');
                if (!property.Name.StartsWith("plugin.", StringComparison.OrdinalIgnoreCase) || separator < 0 ||
                    property.Value.ValueKind != JsonValueKind.Object) continue;
                var id = property.Name[..separator];
                if (onlyPluginId is not null && !id.Equals(onlyPluginId, StringComparison.OrdinalIgnoreCase)) continue;
                var values = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (var field in property.Value.EnumerateObject())
                {
                    var value = field.Value.ValueKind switch
                    {
                        JsonValueKind.String => field.Value.GetString() ?? string.Empty,
                        JsonValueKind.True => "true",
                        JsonValueKind.False => "false",
                        JsonValueKind.Number => field.Value.GetRawText(),
                        _ => string.Empty,
                    };
                    if (value.Length > 0) values[field.Name] = value;
                }
                if (!candidates.TryGetValue(id, out var existing) || values.Count > existing.Count)
                    candidates[id] = values;
            }
        }
        catch { return; }

        foreach (var plugin in LoadInstalled())
        {
            if (onlyPluginId is not null && !plugin.Id.Equals(onlyPluginId, StringComparison.OrdinalIgnoreCase)) continue;
            if (!candidates.TryGetValue(plugin.Id, out var legacy)) continue;
            lock (_stateLock)
            {
                var state = ReadStateUnlocked();
                var item = GetState(state, plugin.Id);
                foreach (var field in plugin.Configuration)
                {
                    if (!legacy.TryGetValue(field.Key, out var value) || string.IsNullOrWhiteSpace(value)) continue;
                    if (field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase))
                    {
                        if (string.IsNullOrEmpty(credentials.Read(SecretKey(plugin.Id, field.Key))))
                            credentials.Write(SecretKey(plugin.Id, field.Key), value);
                    }
                    else if (!item.Configuration.ContainsKey(field.Key))
                    {
                        item.Configuration[field.Key] = value;
                    }
                }
                state[plugin.Id] = item;
                WriteStateUnlocked(state);
            }
        }
    }

    private PluginInfo ReadPlugin(
        string directory,
        Dictionary<string, PluginStateItem> state,
        bool requirePythiaExtension = true)
    {
        if (requirePythiaExtension && !directory.EndsWith(".pythia", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("插件目录扩展名无效。");
        var manifestPath = Path.Combine(directory, "manifest.json");
        using var json = JsonDocument.Parse(File.ReadAllText(manifestPath));
        var root = json.RootElement;
        var id = Read(root, "id", string.Empty);
        var name = Read(root, "name", string.Empty);
        var version = Read(root, "version", string.Empty);
        var entry = Read(root, "entry", string.Empty);
        if (!ValidId.IsMatch(id) || name.Length == 0 || version.Length == 0 || entry.Length == 0)
            throw new InvalidDataException("插件清单格式无效。");
        if (root.TryGetProperty("supportedPlatforms", out var platforms) && platforms.ValueKind == JsonValueKind.Array &&
            !platforms.EnumerateArray().Any(item => item.GetString()?.Equals("windows", StringComparison.OrdinalIgnoreCase) == true))
            throw new InvalidDataException("插件不支持 Windows。");
        if (root.TryGetProperty("capabilities", out var capabilities) && capabilities.ValueKind == JsonValueKind.Array &&
            !capabilities.EnumerateArray().Any(item => item.GetString()?.Equals("translate", StringComparison.OrdinalIgnoreCase) == true))
            throw new InvalidDataException("插件未声明 translate 能力。");
        var entryPath = Path.GetFullPath(Path.Combine(directory, entry));
        var directoryRoot = Path.GetFullPath(directory) + Path.DirectorySeparatorChar;
        if (!entryPath.StartsWith(directoryRoot, StringComparison.OrdinalIgnoreCase) || !File.Exists(entryPath))
            throw new InvalidDataException("插件入口文件无效。");

        var fields = new List<PluginConfigurationField>();
        if (root.TryGetProperty("configuration", out var configuration) && configuration.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in configuration.EnumerateArray())
            {
                var key = Read(item, "key", string.Empty);
                if (key.Length == 0) continue;
                var options = new Dictionary<string, string>(StringComparer.Ordinal);
                if (item.TryGetProperty("options", out var optionObject) && optionObject.ValueKind == JsonValueKind.Object)
                    foreach (var option in optionObject.EnumerateObject()) options[option.Name] = option.Value.GetString() ?? option.Name;
                fields.Add(new PluginConfigurationField(
                    key,
                    Read(item, "label", key),
                    Read(item, "type", "text"),
                    item.TryGetProperty("required", out var required) && required.ValueKind == JsonValueKind.True,
                    item.TryGetProperty("defaultValue", out var defaultValue) && defaultValue.ValueKind == JsonValueKind.String
                        ? defaultValue.GetString() : null,
                    options));
            }
        }
        var itemState = GetState(state, id);
        var configured = fields.Where(field => field.Required).All(field =>
            field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase)
                ? !string.IsNullOrWhiteSpace(credentials.Read(SecretKey(id, field.Key)))
                : itemState.Configuration.ContainsKey(field.Key) || !string.IsNullOrWhiteSpace(field.DefaultValue));
        return new PluginInfo(
            id, name, version,
            Read(root, "description", "翻译插件"),
            Read(root, "author", "未知作者"),
            directory, entry, fields,
            itemState.Enabled, configured, itemState.LastError);
    }

    private void EnsureState(string id)
    {
        lock (_stateLock)
        {
            var state = ReadStateUnlocked();
            state[id] = GetState(state, id);
            WriteStateUnlocked(state);
        }
    }

    private void RecordError(string id, string error)
    {
        lock (_stateLock)
        {
            var state = ReadStateUnlocked();
            var item = GetState(state, id);
            item.LastError = error;
            state[id] = item;
            WriteStateUnlocked(state);
        }
    }

    private Dictionary<string, PluginStateItem> ReadState()
    {
        lock (_stateLock) return ReadStateUnlocked();
    }

    private Dictionary<string, PluginStateItem> ReadStateUnlocked()
    {
        try
        {
            if (!File.Exists(StatePath)) return new(StringComparer.OrdinalIgnoreCase);
            var state = JsonSerializer.Deserialize<Dictionary<string, PluginStateItem>>(File.ReadAllText(StatePath), JsonOptions)
                ?? new Dictionary<string, PluginStateItem>();
            return new Dictionary<string, PluginStateItem>(state, StringComparer.OrdinalIgnoreCase);
        }
        catch { return new(StringComparer.OrdinalIgnoreCase); }
    }

    private void WriteStateUnlocked(Dictionary<string, PluginStateItem> state)
    {
        Directory.CreateDirectory(store.PluginsDirectory);
        var temporary = StatePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(state, JsonOptions), new UTF8Encoding(false));
        File.Move(temporary, StatePath, true);
    }

    private static PluginStateItem GetState(Dictionary<string, PluginStateItem> state, string id)
    {
        if (!state.TryGetValue(id, out var item)) item = new PluginStateItem();
        item.Configuration ??= new Dictionary<string, string>(StringComparer.Ordinal);
        return item;
    }

    private static string? ResolveNodeExecutable()
    {
        var candidates = new List<string>
        {
            Path.Combine(AppContext.BaseDirectory, "Runtime", "node.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "nodejs", "node.exe"),
        };
        candidates.AddRange((Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(path => Path.Combine(path.Trim('"'), "node.exe")));
        return candidates.Distinct(StringComparer.OrdinalIgnoreCase).FirstOrDefault(File.Exists);
    }

    private static string SecretKey(string id, string key) => $"plugin.{id}.{key}";

    private static string Redact(string message, PluginInfo plugin, IReadOnlyDictionary<string, string> config)
    {
        var result = message;
        foreach (var field in plugin.Configuration.Where(field => field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase)))
            if (config.TryGetValue(field.Key, out var value) && value.Length >= 4)
                result = result.Replace(value, "[REDACTED]", StringComparison.Ordinal);
        return result;
    }

    private static string SanitizeExternalError(string message)
    {
        var lines = message.Replace("\r", string.Empty).Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var safe = lines
            .Where(line => !line.StartsWith('{') && !line.StartsWith('[') && !line.Contains("request_id", StringComparison.OrdinalIgnoreCase))
            .Select(line =>
            {
                var jsonStart = line.IndexOf('{');
                return jsonStart >= 0 ? line[..jsonStart].Trim() : line;
            })
            .Where(line => line.Length > 0)
            .Take(2)
            .ToArray();
        return safe.Length == 0 ? "插件请求失败，请检查服务配置与账户状态。" : string.Join("；", safe);
    }

    private static string Limit(string value) => value.Length <= 2000 ? value : value[..2000] + "…";

    private static void TryKill(Process process)
    {
        try { if (!process.HasExited) process.Kill(true); }
        catch { }
    }

    private static string Read(JsonElement root, string name, string fallback) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? fallback : fallback;

    private sealed class PluginStateItem
    {
        public bool Enabled { get; set; } = true;
        public Dictionary<string, string> Configuration { get; set; } = new(StringComparer.Ordinal);
        public string LastError { get; set; } = string.Empty;
    }
}
