using System.Collections.ObjectModel;
using Pythia.Models;

namespace Pythia.Services;

public sealed class AppServices
{
    public AppServices() => Translator = new TranslationCoordinator(Credentials);

    public StatusService Status { get; } = new();
    public LocalStore Store { get; } = new();
    public CredentialStore Credentials { get; } = new();
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
        Settings = await Store.LoadSettingsAsync();
        DeviceId = await Store.GetDeviceIdAsync();
        var records = await Store.LoadHistoryAsync();
        foreach (var record in records.Where(item => item.DeletedAt is null).OrderByDescending(item => item.CreatedAt))
            History.Add(record);
        Status.Report("已就绪");
    }

    public async Task SaveSettingsAsync()
    {
        await Store.SaveSettingsAsync(Settings);
        SettingsSaved?.Invoke(this, EventArgs.Empty);
        Status.Report("设置已保存");
    }

    public async Task AddHistoryAsync(TranslationBatch batch)
    {
        if (!Settings.SaveHistory) return;
        foreach (var result in batch.Results.Where(item => item.IsSuccess))
        {
            History.Insert(0, new HistoryRecord
            {
                SourceText = batch.SourceText,
                TranslatedText = result.Text,
                SourceLanguage = batch.SourceLanguage,
                TargetLanguage = batch.TargetLanguage,
                Service = result.ServiceId,
                Model = result.Model,
                DeviceId = DeviceId,
                SyncStatus = Settings.WebdavHistoryAutoSync ? "pendingUpload" : "local",
            });
        }
        await SaveHistoryAsync();
    }

    public async Task SaveHistoryAsync()
    {
        await Store.SaveHistoryAsync(History);
        HistoryChanged?.Invoke(this, EventArgs.Empty);
    }

    public async Task DeleteHistoryAsync(HistoryRecord record)
    {
        History.Remove(record);
        await SaveHistoryAsync();
        Status.Report("历史记录已删除");
    }

    public async Task ClearHistoryAsync()
    {
        History.Clear();
        await SaveHistoryAsync();
        Status.Report("历史记录已清空");
    }
}
