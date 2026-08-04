using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Pythia.Models;

namespace Pythia.Services;

public sealed class PluginService
{
    private const int MaxArchiveEntries = 2048;
    private const long MaxArchiveBytes = 64L * 1024 * 1024;
    private static readonly Regex ValidId = new("^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$", RegexOptions.CultureInvariant);
    private static readonly Regex ValidVersion = new("^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$", RegexOptions.CultureInvariant);
    private static readonly HashSet<string> AllowedPermissions = new(["network"], StringComparer.OrdinalIgnoreCase);
    private static readonly HashSet<string> AllowedConfigurationTypes = new(["text", "secret", "select"], StringComparer.OrdinalIgnoreCase);
    private static readonly HashSet<string> BlockedPackageExtensions = new([".exe", ".dll", ".com", ".cmd", ".bat", ".ps1", ".msi"], StringComparer.OrdinalIgnoreCase);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };
    private readonly object _stateLock = new();
    private readonly LocalStore store;
    private readonly CredentialStore credentials;
    private readonly string? _nodeExecutableOverride;
    private string? _stateLoadError;
    private string? _legacyMigrationError;

    public IReadOnlyList<string> LastLoadErrors { get; private set; } = [];

    public PluginService(LocalStore store, CredentialStore credentials, string? nodeExecutableOverride = null)
    {
        this.store = store;
        this.credentials = credentials;
        _nodeExecutableOverride = nodeExecutableOverride;
    }

    private string StatePath => Path.Combine(store.PluginsDirectory, "plugin-state.json");
    private string RunnerPath => Path.Combine(store.RuntimeDirectory, "pythia-plugin-runner.cjs");

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(store.PluginsDirectory);
        Directory.CreateDirectory(store.LegacyPluginsDirectory);
        Directory.CreateDirectory(store.LegacyPluginBackupsDirectory);
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
        var errors = new List<string>();
        if (!string.IsNullOrWhiteSpace(_stateLoadError)) errors.Add(_stateLoadError);
        if (!string.IsNullOrWhiteSpace(_legacyMigrationError)) errors.Add(_legacyMigrationError);
        foreach (var directory in Directory.EnumerateDirectories(store.PluginsDirectory, "*.pythia"))
        {
            try { result.Add(ReadPlugin(directory, state)); }
            catch (Exception exception)
            {
                errors.Add($"{Path.GetFileName(directory)}：{Limit(exception.Message)}");
            }
        }
        LastLoadErrors = errors;
        return result.OrderBy(item => item.DisplayName, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    public string DisplayName(string serviceId)
    {
        var id = serviceId.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase)
            ? serviceId["plugin:".Length..]
            : serviceId;
        return LoadInstalled().FirstOrDefault(item => item.Id.Equals(id, StringComparison.OrdinalIgnoreCase))?.DisplayName
            ?? ServiceCatalog.DisplayName(serviceId);
    }

    public string? IconPath(string serviceId)
    {
        var id = serviceId.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase)
            ? serviceId["plugin:".Length..]
            : serviceId;
        return LoadInstalled().FirstOrDefault(item => item.Id.Equals(id, StringComparison.OrdinalIgnoreCase))?.IconPath;
    }

    public PluginInfo Install(string archivePath)
    {
        if (File.Exists(archivePath) && archivePath.EndsWith(".potext", StringComparison.OrdinalIgnoreCase))
            return InstallPotext(archivePath);
        if (!archivePath.EndsWith(".pythia", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("请选择 .pythia 或 .potext 插件包。");
        if (!File.Exists(archivePath) && !Directory.Exists(archivePath))
            throw new FileNotFoundException("插件包不存在。", archivePath);
        if (File.Exists(archivePath) && new FileInfo(archivePath).Length > MaxArchiveBytes)
            throw new InvalidDataException("插件包超过 64 MiB 限制。");

        var staging = Path.Combine(store.PluginsDirectory, ".install-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            if (Directory.Exists(archivePath))
            {
                CopyPluginDirectory(archivePath, staging);
            }
            else
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
                    ValidatePackageRelativePath(archiveEntry.FullName);
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
            }

            var manifests = Directory.EnumerateFiles(staging, "manifest.json", SearchOption.AllDirectories).ToArray();
            if (manifests.Length != 1)
                throw new InvalidDataException("插件包必须且只能包含一个 manifest.json。");
            var rootDirectory = Path.GetDirectoryName(manifests[0])!;
            var plugin = ReadPlugin(rootDirectory, ReadState(), requirePythiaExtension: false);
            var target = Path.Combine(store.PluginsDirectory, plugin.Id + ".pythia");
            var backup = target + ".replace-" + Guid.NewGuid().ToString("N");
            if (Directory.Exists(target)) Directory.Move(target, backup);
            try
            {
                Directory.Move(rootDirectory, target);
                if (Directory.Exists(backup)) Directory.Delete(backup, true);
            }
            catch
            {
                if (Directory.Exists(target)) Directory.Delete(target, true);
                if (Directory.Exists(backup)) Directory.Move(backup, target);
                throw;
            }
            EnsureState(plugin.Id);
            MigrateLegacyPotConfigurations(plugin.Id);
            return LoadInstalled().First(item => item.Id == plugin.Id);
        }
        finally
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
        }
    }

    private PluginInfo InstallPotext(string archivePath)
    {
        if (!File.Exists(archivePath))
            throw new FileNotFoundException("插件包不存在。", archivePath);
        if (new FileInfo(archivePath).Length > MaxArchiveBytes)
            throw new InvalidDataException("插件包超过 64 MiB 限制。");

        var extraction = Path.Combine(store.LegacyPluginsDirectory, ".install-" + Guid.NewGuid().ToString("N"));
        var converted = Path.Combine(store.PluginsDirectory, ".convert-" + Guid.NewGuid().ToString("N") + ".pythia");
        Directory.CreateDirectory(extraction);
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
                ValidatePackageRelativePath(archiveEntry.FullName);
                var destination = Path.GetFullPath(Path.Combine(extraction, archiveEntry.FullName));
                var extractionRoot = Path.GetFullPath(extraction) + Path.DirectorySeparatorChar;
                if (!destination.StartsWith(extractionRoot, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("插件包包含不安全路径。");
                if (archiveEntry.Name.Length == 0)
                {
                    Directory.CreateDirectory(destination);
                    continue;
                }
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                archiveEntry.ExtractToFile(destination, true);
            }

            var infoFiles = Directory.EnumerateFiles(extraction, "info.json", SearchOption.AllDirectories).ToArray();
            if (infoFiles.Length != 1)
                throw new InvalidDataException(".potext 插件必须且只能包含一个 info.json。");
            var root = Path.GetDirectoryName(infoFiles[0])!;
            var mainPath = Path.Combine(root, "main.js");
            if (!File.Exists(mainPath))
                throw new InvalidDataException(".potext 插件缺少 main.js。");
            var conversion = PotextPluginConverter.Convert(
                File.ReadAllBytes(infoFiles[0]),
                File.ReadAllText(mainPath, Encoding.UTF8),
                Path.GetFileNameWithoutExtension(archivePath));

            CopyPluginDirectory(root, converted);
            WriteConvertedPlugin(converted, conversion, File.ReadAllText(mainPath, Encoding.UTF8), Path.GetFileName(archivePath));
            var target = Path.Combine(store.PluginsDirectory, conversion.Manifest.Id + ".pythia");
            ReplacePluginDirectory(converted, target);
            EnsureState(conversion.Manifest.Id);
            MigrateLegacyPotConfigurations(conversion.Manifest.Id);
            PreserveLegacyBackup(archivePath);
            return LoadInstalled().First(item => item.Id.Equals(conversion.Manifest.Id, StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            if (Directory.Exists(extraction)) Directory.Delete(extraction, true);
            if (Directory.Exists(converted)) Directory.Delete(converted, true);
        }
    }

    public PluginInfo Reconvert(PluginInfo plugin)
    {
        var target = Path.GetFullPath(plugin.DirectoryPath);
        var root = Path.GetFullPath(store.PluginsDirectory) + Path.DirectorySeparatorChar;
        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("插件路径不在 Pythia 数据目录中。");
        var infoPath = Path.Combine(target, "info.json");
        var legacyMainPath = Path.Combine(target, "legacy-main.js");
        if (!File.Exists(infoPath) || !File.Exists(legacyMainPath))
            throw new InvalidOperationException("该插件没有保留可重新转换的原始 .potext 内容。");

        var conversion = PotextPluginConverter.Convert(
            File.ReadAllBytes(infoPath),
            File.ReadAllText(legacyMainPath, Encoding.UTF8),
            plugin.Id);
        if (!conversion.Manifest.Id.Equals(plugin.Id, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("重新转换改变了插件服务标识，已中止以保护现有配置。");

        var staging = Path.Combine(store.PluginsDirectory, ".reconvert-" + Guid.NewGuid().ToString("N") + ".pythia");
        try
        {
            CopyPluginDirectory(target, staging);
            WriteConvertedPlugin(staging, conversion, File.ReadAllText(legacyMainPath, Encoding.UTF8),
                Path.GetFileName(plugin.DirectoryPath));
            ReplacePluginDirectory(staging, target);
            EnsureState(plugin.Id);
            return LoadInstalled().First(item => item.Id.Equals(plugin.Id, StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
        }
    }

    public void RenameDisplay(PluginInfo plugin, string displayName)
    {
        var trimmed = displayName.Trim();
        if (trimmed.Length is 0 or > 120 || trimmed.Any(char.IsControl))
            throw new ArgumentException("插件显示名称必须为 1 至 120 个可显示字符。", nameof(displayName));
        lock (_stateLock)
        {
            var state = ReadStateUnlocked();
            var item = GetState(state, plugin.Id);
            item.DisplayName = trimmed;
            state[plugin.Id] = item;
            WriteStateUnlocked(state);
        }
        plugin.DisplayName = trimmed;
    }

    private void WriteConvertedPlugin(
        string directory,
        PotextConversionResult conversion,
        string legacyMain,
        string sourceName)
    {
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "manifest.json"),
            JsonSerializer.Serialize(conversion.Manifest, JsonOptions), new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(directory, "main.js"), conversion.MainJavaScript, new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(directory, "legacy-main.js"), legacyMain, new UTF8Encoding(false));
        var report = new
        {
            schemaVersion = 1,
            sourceFormat = "potext",
            sourcePlugin = sourceName,
            convertedAt = DateTimeOffset.UtcNow,
            status = "converted",
            warnings = conversion.Warnings,
        };
        File.WriteAllText(Path.Combine(directory, "conversion.json"),
            JsonSerializer.Serialize(report, JsonOptions), new UTF8Encoding(false));
    }

    private void PreserveLegacyBackup(string archivePath)
    {
        Directory.CreateDirectory(store.LegacyPluginBackupsDirectory);
        var name = Path.GetFileName(archivePath);
        var destination = Path.Combine(store.LegacyPluginBackupsDirectory, name);
        if (File.Exists(destination))
            destination = Path.Combine(store.LegacyPluginBackupsDirectory,
                Path.GetFileNameWithoutExtension(name) + "-" + Guid.NewGuid().ToString("N") + ".potext");
        File.Copy(archivePath, destination, false);
    }

    private static void ReplacePluginDirectory(string source, string target)
    {
        var backup = target + ".replace-" + Guid.NewGuid().ToString("N");
        if (Directory.Exists(target)) Directory.Move(target, backup);
        try
        {
            Directory.Move(source, target);
            if (Directory.Exists(backup)) Directory.Delete(backup, true);
        }
        catch
        {
            if (Directory.Exists(target)) Directory.Delete(target, true);
            if (Directory.Exists(backup)) Directory.Move(backup, target);
            throw;
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
                    if (value.Length > 0) credentials.Write(SecretKey(plugin.Id, field.Key), values[field.Key]);
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
        var plugin = FindPlugin(serviceId);
        if (!plugin.Enabled) throw new InvalidOperationException($"{plugin.Name} 已停用。");
        var timeout = TimeSpan.FromSeconds(Math.Min(300, Math.Max(30, 30 + text.Length / 20d)));
        return await ExecuteAsync(plugin, text, sourceLanguage, targetLanguage, timeout, cancellationToken);
    }

    public async Task<PluginConnectionResult> TestConnectionAsync(
        PluginInfo plugin,
        CancellationToken cancellationToken = default,
        TimeSpan? maximumDuration = null)
    {
        var maximum = maximumDuration ?? TimeSpan.FromSeconds(30);
        if (maximum <= TimeSpan.Zero || maximum > TimeSpan.FromSeconds(30))
            maximum = TimeSpan.FromSeconds(30);
        var started = Stopwatch.StartNew();
        var config = GetConfiguration(plugin);
        var missingCredential = plugin.Configuration
            .Where(field => field.Required && field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase) &&
                            string.IsNullOrWhiteSpace(config.GetValueOrDefault(field.Key)))
            .Select(field => field.Label)
            .ToArray();
        if (missingCredential.Length > 0)
        {
            var result = new PluginConnectionResult(PluginConnectionStatus.MissingCredential,
                $"请先配置：{string.Join("、", missingCredential)}。", 0, started.Elapsed);
            RecordError(plugin.Id, $"[{result.StatusDisplay}] {result.Message}");
            return result;
        }
        var missingConfiguration = plugin.Configuration
            .Where(field => field.Required && !field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase) &&
                            string.IsNullOrWhiteSpace(config.GetValueOrDefault(field.Key)))
            .Select(field => field.Label)
            .ToArray();
        if (missingConfiguration.Length > 0)
        {
            var result = new PluginConnectionResult(PluginConnectionStatus.MissingRequiredConfiguration,
                $"请先配置：{string.Join("、", missingConfiguration)}。", 0, started.Elapsed);
            RecordError(plugin.Id, $"[{result.StatusDisplay}] {result.Message}");
            return result;
        }

        PluginConnectionResult? lastResult = null;
        for (var attempt = 1; attempt <= 2; attempt++)
        {
            var remaining = maximum - started.Elapsed;
            if (remaining <= TimeSpan.Zero)
                return new(PluginConnectionStatus.Timeout, "插件连通性测试已在 30 秒内停止。", attempt - 1, started.Elapsed);
            try
            {
                await ExecuteAsync(plugin, "Hello", "en", "zh-CN", remaining, cancellationToken);
                RecordError(plugin.Id, string.Empty);
                return new(PluginConnectionStatus.Success, "插件返回了有效译文。", attempt, started.Elapsed);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                var failure = ClassifyFailure(exception);
                lastResult = new(failure.Status, failure.Message, attempt, started.Elapsed);
                var canRetry = failure.Retryable && attempt == 1 && maximum - started.Elapsed > TimeSpan.FromMilliseconds(750);
                if (!canRetry) break;
                await Task.Delay(TimeSpan.FromMilliseconds(350), cancellationToken);
            }
        }
        lastResult ??= new(PluginConnectionStatus.ProcessAbnormalExit, "插件测试未能完成。", 1, started.Elapsed);
        RecordError(plugin.Id, $"[{lastResult.StatusDisplay}] {lastResult.Message}");
        return lastResult with { Duration = started.Elapsed };
    }

    public static PluginConnectionStatus ClassifyConnectionFailure(string? code, string message, bool processExited = false)
    {
        var value = $"{code} {message}".ToLowerInvariant();
        if (value.Contains("model") && (value.Contains("not found") || value.Contains("unavailable") ||
            value.Contains("disabled") || value.Contains("不存在") || value.Contains("不可用") || value.Contains("已停用")))
            return PluginConnectionStatus.ModelUnavailable;
        if (value.Contains("authentication_failed") || value.Contains("unauthorized") || value.Contains("invalid api") ||
            value.Contains("invalid credential") || value.Contains("http 401") || value.Contains("http status: 401") ||
            value.Contains("http 403") || value.Contains("http status: 403") || value.Contains("凭据无效") || value.Contains("密钥无效"))
            return PluginConnectionStatus.InvalidCredential;
        if (value.Contains("timeout") || value.Contains("timed out") || value.Contains("超时"))
            return PluginConnectionStatus.Timeout;
        if (value.Contains("invalid_response") || value.Contains("invalid response") || value.Contains("invalid json") ||
            value.Contains("统一响应") || value.Contains("data.text") || value.Contains("格式") || value.Contains("协议"))
            return PluginConnectionStatus.ProtocolIncompatible;
        if (value.Contains("rate_limited") || value.Contains("http 408") || value.Contains("http status: 408") ||
            value.Contains("http 429") || value.Contains("http status: 429") || Regex.IsMatch(value, @"http(?: status:)? 5\d\d"))
            return PluginConnectionStatus.UpstreamError;
        if (value.Contains("network_error") || value.Contains("failed to fetch") || value.Contains("network unreachable") ||
            value.Contains("econn") || value.Contains("enotfound") || value.Contains("dns") || value.Contains("tls") ||
            value.Contains("网络不可达") || value.Contains("无法连接"))
            return PluginConnectionStatus.NetworkUnreachable;
        return processExited ? PluginConnectionStatus.ProcessAbnormalExit : PluginConnectionStatus.UpstreamError;
    }

    private async Task<string> ExecuteAsync(
        PluginInfo plugin,
        string text,
        string sourceLanguage,
        string targetLanguage,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var config = GetConfiguration(plugin);
        var missing = plugin.Configuration
            .Where(field => field.Required && string.IsNullOrWhiteSpace(config.GetValueOrDefault(field.Key)))
            .Select(field => field.Label)
            .ToArray();
        if (missing.Length > 0)
            throw new PluginExecutionException("CONFIGURATION_REQUIRED", $"插件配置不完整：{string.Join("、", missing)}。", false);
        var node = ResolveNodeExecutable()
            ?? throw new PluginExecutionException("RUNTIME_MISSING", "Pythia 插件运行时缺少 runtime\\node.exe。", false, processExited: true);
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
        timeout = timeout < TimeSpan.FromMilliseconds(250) ? TimeSpan.FromMilliseconds(250) : timeout;
        var startInfo = new ProcessStartInfo
        {
            FileName = node,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = new UTF8Encoding(false, true),
            StandardErrorEncoding = new UTF8Encoding(false, true),
        };
        startInfo.ArgumentList.Add(RunnerPath);
        startInfo.ArgumentList.Add(plugin.DirectoryPath);
        startInfo.ArgumentList.Add(plugin.Entry);
        startInfo.Environment["PYTHIA_PLUGIN_REQUEST"] = request;
        startInfo.Environment["PYTHIA_PLUGIN_CONFIG"] = JsonSerializer.Serialize(config);
        startInfo.Environment["PYTHIA_PLUGIN_TIMEOUT_MS"] = ((long)timeout.TotalMilliseconds).ToString();
        startInfo.Environment["PYTHONUTF8"] = "1";
        startInfo.Environment["PYTHONIOENCODING"] = "utf-8";

        using var process = new Process { StartInfo = startInfo };
        try
        {
            process.Start();
            var stdoutTask = ReadBoundedAsync(process.StandardOutput, 8 * 1024 * 1024);
            var stderrTask = ReadBoundedAsync(process.StandardError, 1024 * 1024);
            using var timeoutSource = new CancellationTokenSource(timeout);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
            try
            {
                await process.WaitForExitAsync(linked.Token);
            }
            catch (OperationCanceledException) when (timeoutSource.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
            {
                TryKillAndWait(process);
                throw new PluginExecutionException("TIMEOUT", "插件执行超时，已终止该插件进程。", true);
            }
            catch
            {
                TryKillAndWait(process);
                throw;
            }

            var stdout = await stdoutTask;
            var stderr = Redact(await stderrTask, plugin, config);
            if (Encoding.UTF8.GetByteCount(stdout) > 8 * 1024 * 1024)
                throw new InvalidDataException("插件响应超过 8 MiB 限制。");
            if (process.ExitCode != 0)
                throw new PluginExecutionException("PROCESS_EXITED", string.IsNullOrWhiteSpace(stderr)
                    ? "插件进程异常退出。"
                    : Limit(SanitizeExternalError(stderr)), false, processExited: true);
            JsonDocument response;
            try { response = JsonDocument.Parse(stdout); }
            catch (JsonException exception)
            {
                throw new PluginExecutionException("INVALID_RESPONSE", "插件返回的 JSON 格式无效。", false, innerException: exception);
            }
            using (response)
            {
            var root = response.RootElement;
            if (!root.TryGetProperty("requestId", out var responseId) || responseId.GetString() != requestId ||
                !root.TryGetProperty("success", out var success) || success.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new PluginExecutionException("INVALID_RESPONSE", "插件返回了无效的统一响应。", false);
            if (!success.GetBoolean())
            {
                var error = root.TryGetProperty("error", out var errorObject) ? errorObject : default;
                var code = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("code", out var codeValue)
                    ? codeValue.GetString() : "RUNTIME_ERROR";
                var message = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var messageValue)
                    ? messageValue.GetString() : "插件报告执行失败。";
                var retryable = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("retryable", out var retryableValue) &&
                                retryableValue.ValueKind == JsonValueKind.True;
                throw new PluginExecutionException(code ?? "RUNTIME_ERROR",
                    Limit(SanitizeExternalError(Redact(message ?? string.Empty, plugin, config))), retryable);
            }
            if (!root.TryGetProperty("data", out var data) || !data.TryGetProperty("text", out var translated) ||
                string.IsNullOrWhiteSpace(translated.GetString()))
                throw new PluginExecutionException("INVALID_RESPONSE", "插件成功响应缺少非空 data.text。", false);
            RecordError(plugin.Id, string.Empty);
            return translated.GetString()!.Trim();
            }
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception)
        {
            var safeMessage = Limit(SanitizeExternalError(Redact(exception.Message, plugin, config)));
            RecordError(plugin.Id, safeMessage);
            if (exception is PluginExecutionException pluginException)
                throw new PluginExecutionException(pluginException.Code, safeMessage, pluginException.Retryable,
                    pluginException.ProcessExited, pluginException);
            throw new PluginExecutionException("RUNTIME_ERROR", safeMessage, false, innerException: exception);
        }
        finally
        {
            TryKillAndWait(process);
        }
    }

    public void MigrateLegacyPotConfigurations(string? onlyPluginId = null)
    {
        _legacyMigrationError = null;
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
        catch (Exception exception)
        {
            _legacyMigrationError = $"旧版插件配置无法读取，已跳过迁移：{Limit(exception.Message)}";
            return;
        }

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
        if (root.ValueKind != JsonValueKind.Object) throw new InvalidDataException("插件清单必须是 JSON 对象。");
        var schemaVersion = RequiredString(root, "schemaVersion");
        var id = RequiredString(root, "id");
        var name = RequiredString(root, "name");
        var version = RequiredString(root, "version");
        var description = RequiredString(root, "description");
        var author = RequiredString(root, "author");
        var type = RequiredString(root, "type");
        var entry = RequiredString(root, "entry");
        var minimumVersion = RequiredString(root, "minimumPythiaVersion");
        if (schemaVersion != "1.0" || !ValidId.IsMatch(id) || !ValidVersion.IsMatch(version) ||
            !ValidVersion.IsMatch(minimumVersion) || !type.Equals("translator", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("插件清单版本、ID 或类型无效。");
        if (Version.TryParse(minimumVersion.Split('-', '+')[0], out var requiredVersion) && requiredVersion > new Version(1, 0, 0))
            throw new InvalidDataException($"插件需要 Pythia {minimumVersion} 或更高版本。");
        if (!root.TryGetProperty("supportedPlatforms", out var platforms) || platforms.ValueKind != JsonValueKind.Array ||
            platforms.GetArrayLength() == 0 || platforms.EnumerateArray().Any(item => item.ValueKind != JsonValueKind.String))
            throw new InvalidDataException("插件 supportedPlatforms 字段无效。");
        if (!platforms.EnumerateArray().Any(item => item.GetString()?.Equals("windows", StringComparison.OrdinalIgnoreCase) == true))
            throw new InvalidDataException("插件不支持 Windows。");
        if (!root.TryGetProperty("capabilities", out var capabilities) || capabilities.ValueKind != JsonValueKind.Array ||
            !capabilities.EnumerateArray().Any(item => item.ValueKind == JsonValueKind.String &&
                item.GetString()?.Equals("translate", StringComparison.OrdinalIgnoreCase) == true))
            throw new InvalidDataException("插件未声明 translate 能力。");
        if (!root.TryGetProperty("permissions", out var permissions) || permissions.ValueKind != JsonValueKind.Array ||
            permissions.EnumerateArray().Any(item => item.ValueKind != JsonValueKind.String ||
                !AllowedPermissions.Contains(item.GetString() ?? string.Empty)))
            throw new InvalidDataException("插件 permissions 字段包含不支持的权限。");
        if (Path.IsPathRooted(entry) || Path.GetExtension(entry) != ".js" ||
            entry.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries).Any(part => part == ".."))
            throw new InvalidDataException("插件入口必须是包内安全的相对 .js 路径。");
        var entryPath = Path.GetFullPath(Path.Combine(directory, entry));
        var directoryRoot = Path.GetFullPath(directory) + Path.DirectorySeparatorChar;
        if (!entryPath.StartsWith(directoryRoot, StringComparison.OrdinalIgnoreCase) || !File.Exists(entryPath))
            throw new InvalidDataException("插件入口文件无效。");

        if (!root.TryGetProperty("configuration", out var configuration) || configuration.ValueKind != JsonValueKind.Array)
            throw new InvalidDataException("插件 configuration 字段无效。");
        var fields = new List<PluginConfigurationField>();
        var fieldKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in configuration.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object) throw new InvalidDataException("插件配置字段必须是对象。");
            var key = RequiredString(item, "key");
            var label = RequiredString(item, "label");
            var fieldType = RequiredString(item, "type");
            if (!ValidId.IsMatch("x." + key) || !fieldKeys.Add(key) || !AllowedConfigurationTypes.Contains(fieldType))
                throw new InvalidDataException("插件配置字段的 key 或 type 无效。");
            if (!item.TryGetProperty("required", out var requiredValue) || requiredValue.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new InvalidDataException($"插件配置字段 {key} 缺少 required 布尔值。");
            string? defaultValue = null;
            if (item.TryGetProperty("defaultValue", out var defaultElement) && defaultElement.ValueKind != JsonValueKind.Null)
            {
                if (defaultElement.ValueKind != JsonValueKind.String)
                    throw new InvalidDataException($"插件配置字段 {key} 的默认值必须是字符串或 null。");
                defaultValue = defaultElement.GetString();
            }
            if (fieldType.Equals("secret", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(defaultValue))
                throw new InvalidDataException($"秘密配置字段 {key} 不能包含默认值。");
            var options = new Dictionary<string, string>(StringComparer.Ordinal);
            if (item.TryGetProperty("options", out var optionObject) && optionObject.ValueKind != JsonValueKind.Null)
            {
                if (optionObject.ValueKind != JsonValueKind.Object)
                    throw new InvalidDataException($"插件配置字段 {key} 的 options 必须是对象。");
                foreach (var option in optionObject.EnumerateObject())
                {
                    if (option.Value.ValueKind != JsonValueKind.String)
                        throw new InvalidDataException($"插件配置字段 {key} 的选项显示名必须是字符串。");
                    options[option.Name] = option.Value.GetString() ?? option.Name;
                }
            }
            if (fieldType.Equals("select", StringComparison.OrdinalIgnoreCase) && options.Count == 0)
                throw new InvalidDataException($"选择配置字段 {key} 必须声明 options。");
            fields.Add(new PluginConfigurationField(key, label, fieldType, requiredValue.GetBoolean(), defaultValue, options));
        }
        var iconPath = ResolvePluginIcon(root, directory);
        var itemState = GetState(state, id);
        var configured = fields.Where(field => field.Required).All(field =>
            field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase)
                ? !string.IsNullOrWhiteSpace(credentials.Read(SecretKey(id, field.Key)))
                : itemState.Configuration.ContainsKey(field.Key) || !string.IsNullOrWhiteSpace(field.DefaultValue));
        var result = new PluginInfo(
            id, name, version,
            description,
            author,
            directory, entry, iconPath, fields,
            itemState.Enabled, configured, itemState.LastError);
        if (!string.IsNullOrWhiteSpace(itemState.DisplayName)) result.DisplayName = itemState.DisplayName;
        return result;
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
            if (!File.Exists(StatePath))
            {
                _stateLoadError = null;
                return new(StringComparer.OrdinalIgnoreCase);
            }
            var state = JsonSerializer.Deserialize<Dictionary<string, PluginStateItem>>(File.ReadAllText(StatePath), JsonOptions)
                ?? new Dictionary<string, PluginStateItem>();
            _stateLoadError = null;
            return new Dictionary<string, PluginStateItem>(state, StringComparer.OrdinalIgnoreCase);
        }
        catch (Exception exception)
        {
            _stateLoadError = $"插件状态文件无法读取，已使用空状态：{Limit(exception.Message)}";
            try
            {
                if (File.Exists(StatePath))
                {
                    var backup = $"{StatePath}.corrupt-{DateTime.UtcNow:yyyyMMddHHmmssfff}";
                    File.Copy(StatePath, backup, false);
                }
            }
            catch { }
            return new(StringComparer.OrdinalIgnoreCase);
        }
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

    private PluginInfo FindPlugin(string serviceId)
    {
        var id = serviceId.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase)
            ? serviceId["plugin:".Length..]
            : serviceId;
        return LoadInstalled().FirstOrDefault(item => item.Id.Equals(id, StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("插件未安装或清单无效。");
    }

    private string? ResolveNodeExecutable()
    {
        if (!string.IsNullOrWhiteSpace(_nodeExecutableOverride) && File.Exists(_nodeExecutableOverride))
            return _nodeExecutableOverride;
        var bundled = Path.Combine(AppContext.BaseDirectory, "Runtime", "node.exe");
        return File.Exists(bundled) ? bundled : null;
    }

    private static (PluginConnectionStatus Status, string Message, bool Retryable) ClassifyFailure(Exception exception)
    {
        var plugin = exception as PluginExecutionException;
        var status = ClassifyConnectionFailure(plugin?.Code, exception.Message, plugin?.ProcessExited == true);
        var retryable = plugin?.Retryable == true || status is PluginConnectionStatus.NetworkUnreachable or
            PluginConnectionStatus.Timeout or PluginConnectionStatus.UpstreamError;
        return (status, string.IsNullOrWhiteSpace(exception.Message) ? "插件测试失败。" : exception.Message, retryable);
    }

    private static string? ResolvePluginIcon(JsonElement manifest, string directory)
    {
        string? relative = null;
        if (manifest.TryGetProperty("icon", out var icon) && icon.ValueKind == JsonValueKind.String)
            relative = icon.GetString();
        if (string.IsNullOrWhiteSpace(relative))
            relative = Directory.EnumerateFiles(directory, "*", SearchOption.TopDirectoryOnly)
                .Select(Path.GetFileName)
                .FirstOrDefault(file => file is not null && new[] { ".svg", ".png", ".jpg", ".jpeg", ".ico" }
                    .Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase));
        if (string.IsNullOrWhiteSpace(relative)) return null;
        if (Path.IsPathRooted(relative) || relative.Split(['/', '\\']).Any(part => part == ".."))
            throw new InvalidDataException("插件图标路径无效。");
        var path = Path.GetFullPath(Path.Combine(directory, relative));
        var root = Path.GetFullPath(directory) + Path.DirectorySeparatorChar;
        var extension = Path.GetExtension(path);
        if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(path) ||
            !new[] { ".svg", ".png", ".jpg", ".jpeg", ".ico" }.Contains(extension, StringComparer.OrdinalIgnoreCase))
            throw new InvalidDataException("插件图标文件无效。");
        return path;
    }

    private static string RequiredString(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
            throw new InvalidDataException($"插件清单缺少有效的 {name} 字段。");
        return value.GetString()!.Trim();
    }

    private static void ValidatePackageRelativePath(string relativePath)
    {
        var normalized = relativePath.Replace('\\', '/');
        if (normalized.Split('/', StringSplitOptions.RemoveEmptyEntries).Any(part => part is ".." or "node_modules"))
            throw new InvalidDataException("插件包包含不安全或不允许的目录。");
        if (BlockedPackageExtensions.Contains(Path.GetExtension(normalized)))
            throw new InvalidDataException("插件包不能包含可执行文件或安装脚本。");
    }

    private static void CopyPluginDirectory(string sourceDirectory, string destinationDirectory)
    {
        var sourceRoot = Path.GetFullPath(sourceDirectory) + Path.DirectorySeparatorChar;
        var files = Directory.EnumerateFiles(sourceDirectory, "*", SearchOption.AllDirectories).ToArray();
        if (files.Length > MaxArchiveEntries) throw new InvalidDataException("插件包文件数量超过限制。");
        long total = 0;
        foreach (var file in files)
        {
            if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("插件目录不能包含符号链接或重解析点。");
            total += new FileInfo(file).Length;
            if (total > MaxArchiveBytes) throw new InvalidDataException("插件目录超过 64 MiB 限制。");
            var full = Path.GetFullPath(file);
            if (!full.StartsWith(sourceRoot, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("插件目录包含不安全路径。");
            var relative = Path.GetRelativePath(sourceDirectory, full);
            ValidatePackageRelativePath(relative);
            var destination = Path.Combine(destinationDirectory, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(full, destination, true);
        }
    }

    private static string SecretKey(string id, string key) => $"plugin.{id}.{key}";

    private static string Redact(string message, PluginInfo plugin, IReadOnlyDictionary<string, string> config)
    {
        var result = message;
        foreach (var field in plugin.Configuration.Where(field => field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase)))
            if (config.TryGetValue(field.Key, out var value) && value.Length >= 4)
                result = result.Replace(value, "[REDACTED]", StringComparison.Ordinal);
        return Regex.Replace(result,
            @"(?i)(bearer|api[-_ ]?key|access[-_ ]?token|secret|password)\s*[:=]\s*[^\s;,]+",
            "$1=[REDACTED]");
    }

    private static string SanitizeExternalError(string message)
    {
        var lines = message.Replace("\r", string.Empty).Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var safe = lines
            .Where(line => !line.StartsWith('{') && !line.StartsWith('[') &&
                           !line.Contains("request_id", StringComparison.OrdinalIgnoreCase) &&
                           !line.Contains("authorization:", StringComparison.OrdinalIgnoreCase) &&
                           !line.Contains("set-cookie:", StringComparison.OrdinalIgnoreCase) &&
                           !line.Contains("cookie:", StringComparison.OrdinalIgnoreCase))
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

    private static async Task<string> ReadBoundedAsync(StreamReader reader, int maximumCharacters)
    {
        var builder = new StringBuilder(Math.Min(maximumCharacters + 1, 64 * 1024));
        var buffer = new char[4096];
        while (true)
        {
            var count = await reader.ReadAsync(buffer);
            if (count == 0) break;
            if (builder.Length <= maximumCharacters)
            {
                var remaining = maximumCharacters + 1 - builder.Length;
                builder.Append(buffer, 0, Math.Min(count, remaining));
            }
        }
        return builder.ToString();
    }

    private static void TryKillAndWait(Process process)
    {
        try
        {
            if (!process.HasExited) process.Kill(true);
            process.WaitForExit(2000);
        }
        catch { }
    }

    private sealed class PluginExecutionException : Exception
    {
        public PluginExecutionException(
            string code,
            string message,
            bool retryable,
            bool processExited = false,
            Exception? innerException = null) : base(message, innerException)
        {
            Code = code;
            Retryable = retryable;
            ProcessExited = processExited;
        }

        public string Code { get; }
        public bool Retryable { get; }
        public bool ProcessExited { get; }
    }

    private sealed class PluginStateItem
    {
        public bool Enabled { get; set; } = true;
        public string DisplayName { get; set; } = string.Empty;
        public Dictionary<string, string> Configuration { get; set; } = new(StringComparer.Ordinal);
        public string LastError { get; set; } = string.Empty;
    }
}
