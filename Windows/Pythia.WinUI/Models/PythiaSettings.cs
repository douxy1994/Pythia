using System.Text.Json.Serialization;

namespace Pythia.Models;

public sealed class PythiaSettings
{
    public string SourceLanguage { get; set; } = "auto";
    public string TargetLanguage { get; set; } = "zh-CN";
    public List<string> EnabledTranslateServices { get; set; } = ["google"];
    public List<string> TranslateServiceOrder { get; set; } =
        ["google", "baidu", "youdao", "openai-compatible", "deepl", "libretranslate"];
    public bool GoogleEnabled { get; set; } = true;
    public bool BaiduEnabled { get; set; }
    public bool YoudaoEnabled { get; set; }
    public bool OpenAICompatibleEnabled { get; set; }
    public string OpenAICompatibleName { get; set; } = "大模型翻译";
    public string OpenAICompatibleApi { get; set; } = "openai";
    public string OpenAICompatibleBaseUrl { get; set; } = "https://api.openai.com/v1";
    public string OpenAICompatibleModel { get; set; } = "gpt-4o-mini";
    public bool DeepLEnabled { get; set; }
    public string DeepLBaseUrl { get; set; } = "https://api-free.deepl.com/v2";
    public bool LibreTranslateEnabled { get; set; }
    public string LibreTranslateBaseUrl { get; set; } = "https://libretranslate.com";
    public bool SaveHistory { get; set; } = true;
    public string ThemeMode { get; set; } = "system";
    public bool LaunchAtStartup { get; set; }
    public bool CloseToTray { get; set; } = true;
    public bool AlwaysOnTop { get; set; }
    public bool HideOnBlur { get; set; }
    public bool NotificationsEnabled { get; set; } = true;
    public bool CheckForUpdatesOnStartup { get; set; } = true;
    public int WindowX { get; set; }
    public int WindowY { get; set; }
    public int WindowWidth { get; set; }
    public int WindowHeight { get; set; }
    public int WindowDpi { get; set; }
    public string ShowWindowHotkey { get; set; } = "Ctrl+Alt+P";
    public string SelectionTranslateHotkey { get; set; } = "Ctrl+Alt+D";
    public string ScreenshotTranslateHotkey { get; set; } = "Ctrl+Alt+Shift+D";
    public string ScreenshotOcrHotkey { get; set; } = "Ctrl+Alt+Shift+R";
    public bool ScreenshotOcrAutoTranslate { get; set; } = true;
    public bool CompactTranslationWindow { get; set; }
    public bool ExperimentalFloatingSelectionButton { get; set; }
    public string WebdavUrl { get; set; } = string.Empty;
    public string WebdavUsername { get; set; } = string.Empty;
    public bool WebdavHistoryAutoSync { get; set; }
    public int WebdavHistorySyncIntervalValue { get; set; } = 1;
    public string WebdavHistorySyncIntervalUnit { get; set; } = "hour";
    public int WebdavHistorySyncIntervalMinutes { get; set; } = 60;
    public string WebdavLastSyncAt { get; set; } = string.Empty;
    public string WebdavLastSyncStatus { get; set; } = string.Empty;
    public string WebdavLastSyncError { get; set; } = string.Empty;

    [JsonIgnore]
    public IReadOnlyList<string> ActiveServices
    {
        get
        {
            var enabled = EnabledTranslateServices.Count > 0
                ? EnabledTranslateServices
                : ["google"];
            return TranslateServiceOrder
                .Where(enabled.Contains)
                .Concat(enabled.Where(item => !TranslateServiceOrder.Contains(item)))
                .Distinct()
                .ToArray();
        }
    }
}
