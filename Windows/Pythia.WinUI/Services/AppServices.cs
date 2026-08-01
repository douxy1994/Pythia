using System.Collections.ObjectModel;
using Pythia.Models;

namespace Pythia.Services;

public sealed class AppServices
{
    private readonly List<HistoryRecord> _allHistory = [];
    private readonly SemaphoreSlim _historySyncGate = new(1, 1);
    private CancellationTokenSource? _autoSyncLoop;
    private CancellationTokenSource? _historySyncDebounce;

    public AppServices()
    {
        Plugins = new PluginService(Store, Credentials);
        Translator = new TranslationCoordinator(Credentials, Plugins);
    }

    public StatusService Status { get; } = new();
    /// <summary>
    /// System balloon notifier. Null until <see cref="Pythia.MainWindow"/> wires it to the
    /// tray shell service; callers must null-check. Honors
    /// <see cref="PythiaSettings.NotificationsEnabled"/> and de-dupes repeats.
    /// </summary>
    public NotificationService? Notifications { get; set; }
    public LocalStore Store { get; } = new();
    public CredentialStore Credentials { get; } = new();
    public PluginService Plugins { get; }
    public TranslationCoordinator Translator { get; }
    public ObservableCollection<HistoryRecord> History { get; } = [];
    public PythiaSettings Settings { get; private set; } = new();
    public string DeviceId { get; private set; } = string.Empty;

    public event EventHandler? SettingsSaved;
    public event EventHandler? HistoryChanged;

    public async Task InitializeAsync()
    {
        Status.Report("正在载入设置…", true);
        Directory.CreateDirectory(Store.PluginsDirectory);
        Directory.CreateDirectory(Store.RuntimeDirectory);
        await Plugins.InitializeAsync();
        Settings = await Store.LoadSettingsAsync();
        DeviceId = await Store.GetDeviceIdAsync();
        var records = await Store.LoadHistoryAsync();
        _allHistory.AddRange(records);
        foreach (var record in records.Where(item => item.DeletedAt is null).OrderByDescending(item => item.CreatedAt))
            History.Add(record);
        RestartAutoSyncLoop();
        Status.Report("已就绪");
    }

    public IReadOnlyList<(string Id, string Name)> TranslationServices =>
        ServiceCatalog.All
            .Concat(Plugins.LoadInstalled().Where(item => item.Enabled).Select(item => (item.ServiceId, item.Name)))
            .ToArray();

    public IReadOnlyList<HistoryRecord> AllHistoryForSync =>
        _allHistory.Select(HistorySyncService.Clone).ToArray();

    public async Task SaveSettingsAsync()
    {
        await Store.SaveSettingsAsync(Settings);
        RestartAutoSyncLoop();
        SettingsSaved?.Invoke(this, EventArgs.Empty);
        Status.Report("设置已保存");
    }

    public async Task AddHistoryAsync(TranslationBatch batch)
    {
        if (!Settings.SaveHistory) return;
        foreach (var result in batch.Results.Where(item => item.IsSuccess))
        {
            var record = new HistoryRecord
            {
                SourceText = batch.SourceText,
                TranslatedText = result.Text,
                SourceLanguage = batch.SourceLanguage,
                TargetLanguage = batch.TargetLanguage,
                Service = result.ServiceId,
                Model = result.Model,
                DeviceId = DeviceId,
                SyncStatus = Settings.WebdavHistoryAutoSync ? "pendingUpload" : "local",
            };
            _allHistory.Insert(0, record);
            History.Insert(0, record);
        }
        await SaveHistoryAsync();
        RequestHistoryAutoSync();
    }

    public async Task SaveHistoryAsync()
    {
        await Store.SaveHistoryAsync(_allHistory);
        HistoryChanged?.Invoke(this, EventArgs.Empty);
        RequestHistoryAutoSync();
    }

    public void AddVisibleHistoryRecord(HistoryRecord record)
    {
        if (_allHistory.Any(item => item.Id.Equals(record.Id, StringComparison.OrdinalIgnoreCase))) return;
        _allHistory.Insert(0, record);
        History.Insert(0, record);
    }

    public async Task DeleteHistoryAsync(HistoryRecord record)
    {
        record.DeletedAt = DateTimeOffset.UtcNow;
        record.UpdatedAt = record.DeletedAt.Value;
        record.SyncStatus = "pendingDelete";
        History.Remove(record);
        await SaveHistoryAsync();
        Status.Report("历史记录已删除");
    }

    public async Task ClearHistoryAsync()
    {
        var deletedAt = DateTimeOffset.UtcNow;
        foreach (var record in History)
        {
            record.DeletedAt = deletedAt;
            record.UpdatedAt = deletedAt;
            record.SyncStatus = "pendingDelete";
        }
        History.Clear();
        await SaveHistoryAsync();
        Status.Report("历史记录已清空");
    }

    public async Task<WebDavHistorySyncResult> SyncHistoryAsync(CancellationToken cancellationToken = default)
        => await SyncHistoryAsync(notify: false, cancellationToken);

    /// <param name="notify">When true (background auto-sync), surface a system balloon on
    /// completion or failure so the user learns about an event they did not trigger.
    /// User-initiated sync passes false — the status bar already covers that case.</param>
    public async Task<WebDavHistorySyncResult> SyncHistoryAsync(bool notify, CancellationToken cancellationToken = default)
    {
        await _historySyncGate.WaitAsync(cancellationToken);
        try
        {
            if (string.IsNullOrWhiteSpace(Settings.WebdavUrl))
                throw new InvalidOperationException("请先配置 WebDAV 地址。");
            var password = Credentials.Read("webdav.password") ?? string.Empty;
            Status.Report("正在同步 WebDAV 历史…", true);
            await Store.BackupHistoryBeforeSyncAsync();
            var result = await WebDavService.SyncHistoryAsync(
                Settings.WebdavUrl,
                Settings.WebdavUsername,
                password,
                AllHistoryForSync,
                DeviceId,
                cancellationToken);
            ReplaceAllHistory(result.Records);
            await Store.SaveHistoryAsync(_allHistory);
            Settings.WebdavLastSyncAt = DateTimeOffset.UtcNow.ToString("O");
            Settings.WebdavLastSyncStatus =
                $"同步成功：远程 {result.DownloadedCount} 条，本地可见 {result.VisibleCount} 条，冲突 {result.ConflictCount} 条";
            Settings.WebdavLastSyncError = string.Empty;
            await Store.SaveSettingsAsync(Settings);
            HistoryChanged?.Invoke(this, EventArgs.Empty);
            Status.Report(Settings.WebdavLastSyncStatus);
            if (notify) Notifications?.Show("Pythia 同步", Settings.WebdavLastSyncStatus, NotificationKind.Info);
            return result;
        }
        catch (Exception exception)
        {
            Settings.WebdavLastSyncAt = DateTimeOffset.UtcNow.ToString("O");
            Settings.WebdavLastSyncStatus = "同步失败";
            Settings.WebdavLastSyncError = exception.Message;
            await Store.SaveSettingsAsync(Settings);
            Status.Report($"WebDAV 同步失败：{exception.Message}");
            if (notify) Notifications?.Show("Pythia 同步", $"历史同步失败：{exception.Message}", NotificationKind.Error);
            throw;
        }
        finally
        {
            _historySyncGate.Release();
        }
    }

    public string CreatePortableBackup() => PortableBackupService.Create(Settings, AllHistoryForSync);

    public async Task<PortableBackupRestoreResult> RestorePortableBackupAsync(string json)
    {
        var restored = PortableBackupService.Restore(json, AllHistoryForSync);
        await Store.BackupHistoryBeforeSyncAsync();
        PortableBackupService.ApplySettings(restored.Settings, Settings);
        var available = TranslationServices.Select(item => item.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Settings.EnabledTranslateServices = Settings.EnabledTranslateServices.Where(available.Contains).ToList();
        Settings.TranslateServiceOrder = Settings.TranslateServiceOrder
            .Where(id => available.Contains(id) || !id.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (Settings.EnabledTranslateServices.Count == 0) Settings.EnabledTranslateServices.Add("google");
        ReplaceAllHistory(restored.Records);
        await Store.SaveHistoryAsync(_allHistory);
        await SaveSettingsAsync();
        HistoryChanged?.Invoke(this, EventArgs.Empty);
        RequestHistoryAutoSync();
        return restored;
    }

    private void ReplaceAllHistory(IEnumerable<HistoryRecord> records)
    {
        _allHistory.Clear();
        _allHistory.AddRange(records.Select(HistorySyncService.Clone));
        History.Clear();
        foreach (var record in _allHistory.Where(item => item.DeletedAt is null).OrderByDescending(item => item.CreatedAt))
            History.Add(record);
    }

    private void RestartAutoSyncLoop()
    {
        _autoSyncLoop?.Cancel();
        _autoSyncLoop = null;
        if (!Settings.WebdavHistoryAutoSync || string.IsNullOrWhiteSpace(Settings.WebdavUrl)) return;
        var cancellation = new CancellationTokenSource();
        _autoSyncLoop = cancellation;
        _ = RunAutoSyncLoopAsync(cancellation.Token);
    }

    private async Task RunAutoSyncLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(GetSyncInterval(Settings), cancellationToken);
                await SyncHistoryAsync(notify: true, cancellationToken);
            }
            catch (OperationCanceledException) { return; }
            catch { }
        }
    }

    private void RequestHistoryAutoSync()
    {
        if (!Settings.WebdavHistoryAutoSync || string.IsNullOrWhiteSpace(Settings.WebdavUrl)) return;
        _historySyncDebounce?.Cancel();
        var cancellation = new CancellationTokenSource();
        _historySyncDebounce = cancellation;
        _ = DebouncedHistorySyncAsync(cancellation.Token);
    }

    private async Task DebouncedHistorySyncAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
            await SyncHistoryAsync(notify: true, cancellationToken);
        }
        catch (OperationCanceledException) { }
        catch { }
    }

    public static TimeSpan GetSyncInterval(PythiaSettings settings)
    {
        var value = Math.Clamp(settings.WebdavHistorySyncIntervalValue, 1, 10_080);
        return settings.WebdavHistorySyncIntervalUnit switch
        {
            "day" => TimeSpan.FromDays(Math.Min(value, 365)),
            "week" => TimeSpan.FromDays(Math.Min(value, 52) * 7),
            "minute" => TimeSpan.FromMinutes(value),
            _ => TimeSpan.FromHours(Math.Min(value, 8_760)),
        };
    }
}
