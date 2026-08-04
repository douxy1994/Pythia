using System.Text.Json;
using Pythia.Models;

namespace Pythia.Services;

public sealed record HistoryMergeResult(IReadOnlyList<HistoryRecord> Records, int ConflictCount);

public static class HistorySyncService
{
    public static HistoryMergeResult Merge(
        IEnumerable<HistoryRecord> local,
        IEnumerable<HistoryRecord> remote)
    {
        var byId = new Dictionary<string, HistoryRecord>(StringComparer.OrdinalIgnoreCase);
        var conflicts = 0;
        foreach (var candidate in local.Concat(remote).Select(Clone))
        {
            candidate.SchemaVersion = Math.Max(1, candidate.SchemaVersion);
            if (!byId.TryGetValue(candidate.Id, out var current))
            {
                byId[candidate.Id] = candidate;
                continue;
            }

            var conflict = IsContentConflict(current, candidate);
            var selected = Select(current, candidate);
            if (conflict)
            {
                selected.SyncStatus = "conflict";
                conflicts++;
            }
            byId[candidate.Id] = selected;
        }

        var records = byId.Values
            .Select(record =>
            {
                if (record.DeletedAt is not null) record.SyncStatus = "pendingDelete";
                else if (!string.Equals(record.SyncStatus, "conflict", StringComparison.OrdinalIgnoreCase))
                    record.SyncStatus = "synced";
                return record;
            })
            .OrderByDescending(record => record.CreatedAt)
            .ThenByDescending(record => record.UpdatedAt)
            .ToArray();
        return new HistoryMergeResult(records, conflicts);
    }

    public static HistoryRecord Clone(HistoryRecord record) => new()
    {
        Id = record.Id,
        SourceText = record.SourceText,
        TranslatedText = record.TranslatedText,
        SourceLanguage = record.SourceLanguage,
        TargetLanguage = record.TargetLanguage,
        Service = record.Service,
        Model = record.Model,
        CreatedAt = record.CreatedAt,
        UpdatedAt = record.UpdatedAt,
        IsFavorite = record.IsFavorite,
        DeviceId = record.DeviceId,
        SyncStatus = record.SyncStatus,
        DeletedAt = record.DeletedAt,
        SchemaVersion = Math.Max(1, record.SchemaVersion),
    };

    private static HistoryRecord Select(HistoryRecord left, HistoryRecord right)
    {
        if (left.DeletedAt is not null || right.DeletedAt is not null)
        {
            if (left.DeletedAt is null) return right;
            if (right.DeletedAt is null) return left;
        }
        if (right.UpdatedAt > left.UpdatedAt) return right;
        if (left.UpdatedAt > right.UpdatedAt) return left;
        return left;
    }

    private static bool IsContentConflict(HistoryRecord left, HistoryRecord right) =>
        left.UpdatedAt == right.UpdatedAt &&
        (left.SourceText != right.SourceText ||
         left.TranslatedText != right.TranslatedText ||
         left.SourceLanguage != right.SourceLanguage ||
         left.TargetLanguage != right.TargetLanguage ||
         left.Service != right.Service ||
         left.Model != right.Model ||
         left.IsFavorite != right.IsFavorite ||
         left.DeletedAt != right.DeletedAt);
}

public sealed class PortableBackupSettings
{
    public string SourceLanguage { get; set; } = "auto";
    public string TargetLanguage { get; set; } = "zh-CN";
    public List<string> EnabledTranslateServices { get; set; } = [];
    public List<string> TranslateServiceOrder { get; set; } = [];
    public bool GoogleEnabled { get; set; }
    public bool BaiduEnabled { get; set; }
    public bool YoudaoEnabled { get; set; }
    public bool OpenAICompatibleEnabled { get; set; }
    public string OpenAICompatibleName { get; set; } = "大模型翻译";
    public string OpenAICompatibleBaseUrl { get; set; } = "https://api.openai.com/v1";
    public string OpenAICompatibleModel { get; set; } = "gpt-4o-mini";
    public string OpenAICompatibleAPI { get; set; } = "openai";
    public bool CompactTranslationWindow { get; set; }
    public bool ExperimentalFloatingSelectionButton { get; set; }
    public bool DeepLEnabled { get; set; }
    public string DeepLBaseUrl { get; set; } = "https://api-free.deepl.com/v2";
    public bool LibreTranslateEnabled { get; set; }
    public string LibreTranslateBaseUrl { get; set; } = "https://libretranslate.com";
    public bool SaveHistory { get; set; } = true;
    public string ThemeMode { get; set; } = "system";
}

public sealed class PortableBackupEnvelope
{
    public int SchemaVersion { get; set; } = 1;
    public string Product { get; set; } = "Pythia";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public bool SensitiveFieldsOmitted { get; set; } = true;
    public PortableBackupSettings Settings { get; set; } = new();
    public List<HistoryRecord> History { get; set; } = [];
}

public sealed record PortableBackupRestoreResult(
    PortableBackupSettings Settings,
    IReadOnlyList<HistoryRecord> Records,
    int ImportedCount,
    int ConflictCount);

public static class PortableBackupService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public static string Create(PythiaSettings settings, IEnumerable<HistoryRecord> history)
    {
        var envelope = new PortableBackupEnvelope
        {
            Settings = new PortableBackupSettings
            {
                SourceLanguage = settings.SourceLanguage,
                TargetLanguage = settings.TargetLanguage,
                EnabledTranslateServices = [.. settings.EnabledTranslateServices],
                TranslateServiceOrder = [.. settings.TranslateServiceOrder],
                GoogleEnabled = settings.GoogleEnabled,
                BaiduEnabled = settings.BaiduEnabled,
                YoudaoEnabled = settings.YoudaoEnabled,
                OpenAICompatibleEnabled = settings.OpenAICompatibleEnabled,
                OpenAICompatibleName = settings.OpenAICompatibleName,
                OpenAICompatibleBaseUrl = settings.OpenAICompatibleBaseUrl,
                OpenAICompatibleModel = settings.OpenAICompatibleModel,
                OpenAICompatibleAPI = settings.OpenAICompatibleApi,
                CompactTranslationWindow = settings.CompactTranslationWindow,
                ExperimentalFloatingSelectionButton = settings.ExperimentalFloatingSelectionButton,
                DeepLEnabled = settings.DeepLEnabled,
                DeepLBaseUrl = settings.DeepLBaseUrl,
                LibreTranslateEnabled = settings.LibreTranslateEnabled,
                LibreTranslateBaseUrl = settings.LibreTranslateBaseUrl,
                SaveHistory = settings.SaveHistory,
                ThemeMode = settings.ThemeMode,
            },
            History = history.Select(HistorySyncService.Clone).ToList(),
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static PortableBackupRestoreResult Restore(
        string json,
        IEnumerable<HistoryRecord> currentHistory)
    {
        PortableBackupEnvelope envelope;
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("sensitiveFieldsOmitted", out var omissionFlag) ||
                omissionFlag.ValueKind != JsonValueKind.True)
                throw new FormatException("备份缺少敏感字段省略标记。");
            envelope = JsonSerializer.Deserialize<PortableBackupEnvelope>(json, JsonOptions)
                       ?? throw new FormatException("备份内容为空。");
        }
        catch (JsonException exception)
        {
            throw new FormatException("备份不是有效的 JSON。", exception);
        }
        if (!string.Equals(envelope.Product, "Pythia", StringComparison.Ordinal) || envelope.SchemaVersion != 1)
            throw new FormatException("这不是受支持的 Pythia 备份文件。");
        if (!envelope.SensitiveFieldsOmitted)
            throw new FormatException("拒绝导入包含敏感字段标记的备份。");
        var merged = HistorySyncService.Merge(currentHistory, envelope.History);
        foreach (var record in merged.Records)
            if (record.SyncStatus != "conflict")
                record.SyncStatus = record.DeletedAt is null ? "pendingUpload" : "pendingDelete";
        return new PortableBackupRestoreResult(
            envelope.Settings,
            merged.Records,
            envelope.History.Count,
            merged.ConflictCount);
    }

    public static void ApplySettings(PortableBackupSettings source, PythiaSettings target)
    {
        target.SourceLanguage = source.SourceLanguage;
        target.TargetLanguage = source.TargetLanguage;
        target.EnabledTranslateServices = [.. source.EnabledTranslateServices];
        target.TranslateServiceOrder = [.. source.TranslateServiceOrder];
        target.GoogleEnabled = source.GoogleEnabled;
        target.BaiduEnabled = source.BaiduEnabled;
        target.YoudaoEnabled = source.YoudaoEnabled;
        target.OpenAICompatibleEnabled = source.OpenAICompatibleEnabled;
        target.OpenAICompatibleName = source.OpenAICompatibleName;
        target.OpenAICompatibleBaseUrl = source.OpenAICompatibleBaseUrl;
        target.OpenAICompatibleModel = source.OpenAICompatibleModel;
        target.OpenAICompatibleApi = source.OpenAICompatibleAPI is "openai" or "anthropic"
            ? source.OpenAICompatibleAPI : "openai";
        target.CompactTranslationWindow = source.CompactTranslationWindow;
        target.ExperimentalFloatingSelectionButton = source.ExperimentalFloatingSelectionButton;
        target.DeepLEnabled = source.DeepLEnabled;
        target.DeepLBaseUrl = source.DeepLBaseUrl;
        target.LibreTranslateEnabled = source.LibreTranslateEnabled;
        target.LibreTranslateBaseUrl = source.LibreTranslateBaseUrl;
        target.SaveHistory = source.SaveHistory;
        target.ThemeMode = source.ThemeMode;
    }
}
