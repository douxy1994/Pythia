using Microsoft.UI.Windowing;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Pythia.Models;
using Pythia.Services;
using System.Diagnostics;
using Windows.System;
using Windows.UI.Core;
using Windows.Storage.Pickers;

namespace Pythia.Pages;

public sealed partial class SettingsPage : Page
{
    private readonly Dictionary<string, FrameworkElement> _sections = [];
    private CancellationTokenSource? _autoSaveDelay;
    private bool _loadingValues;

    public SettingsPage()
    {
        InitializeComponent();
        _sections.Add("general", GeneralSection);
        _sections.Add("services", ServicesSection);
        _sections.Add("plugins", PluginsSection);
        _sections.Add("ocr", OcrSection);
        _sections.Add("shortcuts", ShortcutsSection);
        _sections.Add("sync", SyncSection);
        _sections.Add("window", WindowSection);
        _sections.Add("about", AboutSection);
        LoadValues();
        ShowSection("general");
        HookAutoSave();
        Loaded += (_, _) =>
        {
            App.UpdateAvailable -= App_UpdateAvailable;
            App.UpdateAvailable += App_UpdateAvailable;
            RefreshUpdateState();
        };
        Unloaded += (_, _) =>
        {
            App.UpdateAvailable -= App_UpdateAvailable;
            _autoSaveDelay?.Cancel();
            _ = SaveSettingsCoreAsync(false);
        };
    }

    private void LoadValues()
    {
        _loadingValues = true;
        try { LoadValuesCore(); }
        finally { _loadingValues = false; }
    }

    private void LoadValuesCore()
    {
        var settings = App.Services.Settings;
        ThemeBox.SelectedItem = ThemeBox.Items.OfType<ComboBoxItem>().First(item => (string)item.Tag == settings.ThemeMode);
        SaveHistorySwitch.IsOn = settings.SaveHistory;
        CompactTranslationWindowSwitch.IsOn = settings.CompactTranslationWindow;
        LaunchAtStartupSwitch.IsOn = settings.LaunchAtStartup;
        GoogleSwitch.IsOn = settings.GoogleEnabled || settings.EnabledTranslateServices.Contains("google");
        BaiduSwitch.IsOn = settings.BaiduEnabled || settings.EnabledTranslateServices.Contains("baidu");
        YoudaoSwitch.IsOn = settings.YoudaoEnabled || settings.EnabledTranslateServices.Contains("youdao");
        OpenAiSwitch.IsOn = settings.OpenAICompatibleEnabled || settings.EnabledTranslateServices.Contains("openai-compatible");
        DeepLSwitch.IsOn = settings.DeepLEnabled || settings.EnabledTranslateServices.Contains("deepl");
        LibreSwitch.IsOn = settings.LibreTranslateEnabled || settings.EnabledTranslateServices.Contains("libretranslate");
        OpenAiNameBox.Text = settings.OpenAICompatibleName;
        OpenAiApiBox.SelectedItem = OpenAiApiBox.Items.OfType<ComboBoxItem>()
            .FirstOrDefault(item => (string)item.Tag == settings.OpenAICompatibleApi) ?? OpenAiApiBox.Items[0];
        OpenAiUrlBox.Text = settings.OpenAICompatibleBaseUrl;
        OpenAiModelBox.Text = settings.OpenAICompatibleModel;
        DeepLUrlBox.Text = settings.DeepLBaseUrl;
        LibreUrlBox.Text = settings.LibreTranslateBaseUrl;
        OcrAutoTranslateSwitch.IsOn = settings.ScreenshotOcrAutoTranslate;
        ShowWindowHotkeyBox.Text = settings.ShowWindowHotkey;
        SelectionHotkeyBox.Text = settings.SelectionTranslateHotkey;
        ScreenshotTranslateHotkeyBox.Text = settings.ScreenshotTranslateHotkey;
        ScreenshotOcrHotkeyBox.Text = settings.ScreenshotOcrHotkey;
        WebDavUrlBox.Text = settings.WebdavUrl;
        WebDavUserBox.Text = settings.WebdavUsername;
        WebDavAutoSyncSwitch.IsOn = settings.WebdavHistoryAutoSync;
        SyncIntervalBox.Value = settings.WebdavHistorySyncIntervalValue;
        SyncUnitBox.SelectedItem = SyncUnitBox.Items.OfType<ComboBoxItem>().FirstOrDefault(item => (string)item.Tag == settings.WebdavHistorySyncIntervalUnit) ?? SyncUnitBox.Items[1];
        WebDavStatusText.Text = settings.WebdavLastSyncStatus;
        UpdateStatusText.Text = $"当前版本 {UpdateService.CurrentVersion.ToString(3)}";
        VersionText.Text = UpdateService.CurrentVersion.ToString(3);
        AlwaysOnTopSwitch.IsOn = settings.AlwaysOnTop;
        CloseToTraySwitch.IsOn = settings.CloseToTray;
        HideOnBlurSwitch.IsOn = settings.HideOnBlur;
        NotificationsSwitch.IsOn = settings.NotificationsEnabled;
        CheckUpdateOnStartupSwitch.IsOn = settings.CheckForUpdatesOnStartup;
        RefreshUpdateState();
        MarkExistingCredential(BaiduAppIdBox, "provider.baidu.appId");
        MarkExistingCredential(BaiduSecretBox, "provider.baidu.secret");
        MarkExistingCredential(YoudaoAppKeyBox, "provider.youdao.appKey");
        MarkExistingCredential(YoudaoSecretBox, "provider.youdao.secret");
        MarkExistingCredential(OpenAiKeyBox, "provider.openai-compatible.apiKey");
        MarkExistingCredential(DeepLKeyBox, "provider.deepl.apiKey");
        MarkExistingCredential(LibreKeyBox, "provider.libretranslate.apiKey");
        MarkExistingCredential(WebDavPasswordBox, "webdav.password");
    }

    private void App_UpdateAvailable(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(RefreshUpdateState);

    private void RefreshUpdateState()
    {
        var update = App.PendingUpdate;
        if (update is null)
        {
            UpdateCard.Visibility = Visibility.Collapsed;
            UpdateButton.Visibility = Visibility.Collapsed;
            LatestNotesText.Text =
                "1.2.1 · 修复自定义大模型 API 翻译长文档时被固定超时取消的问题。\n" +
                "长文档按语义边界分段翻译，并避免切断数字、日期和 Unicode 字符。\n" +
                "对超时、限流及临时服务错误进行有限重试，用户主动取消仍会立即停止。";
            return;
        }

        UpdateCard.Visibility = Visibility.Visible;
        UpdateButton.Visibility = Visibility.Visible;
        UpdateVersionText.Text = $"{update.Tag} 可用";
        UpdateNotesText.Text = string.IsNullOrWhiteSpace(update.Notes)
            ? "该版本未提供更新说明。"
            : update.Notes;
        LatestNotesText.Text = $"最新版本：{update.Tag}";
        UpdateStatusText.Text = $"发现新版本 {update.Tag}，下载并校验后将自动重启安装。";
    }

    private void HookAutoSave()
    {
        foreach (var toggle in new[]
                 {
                     SaveHistorySwitch, CompactTranslationWindowSwitch, LaunchAtStartupSwitch, GoogleSwitch, BaiduSwitch,
                     YoudaoSwitch, OpenAiSwitch, DeepLSwitch, LibreSwitch, OcrAutoTranslateSwitch,
                     WebDavAutoSyncSwitch, AlwaysOnTopSwitch, CloseToTraySwitch, HideOnBlurSwitch,
                     NotificationsSwitch, CheckUpdateOnStartupSwitch,
                 })
            toggle.Toggled += (_, _) => ScheduleAutoSave();

        ThemeBox.SelectionChanged += (_, _) => ScheduleAutoSave();
        OpenAiApiBox.SelectionChanged += (_, _) => ScheduleAutoSave();
        SyncUnitBox.SelectionChanged += (_, _) => ScheduleAutoSave();
        SyncIntervalBox.ValueChanged += (_, _) => ScheduleAutoSave();
        foreach (var textBox in new[]
                 {
                     BaiduAppIdBox, YoudaoAppKeyBox, OpenAiNameBox, OpenAiUrlBox, OpenAiModelBox,
                     DeepLUrlBox, LibreUrlBox, ShowWindowHotkeyBox, SelectionHotkeyBox,
                     ScreenshotTranslateHotkeyBox, ScreenshotOcrHotkeyBox, WebDavUrlBox, WebDavUserBox,
                 })
            textBox.TextChanged += (_, _) => ScheduleAutoSave();
        foreach (var passwordBox in new[]
                 { BaiduSecretBox, YoudaoSecretBox, OpenAiKeyBox, DeepLKeyBox, LibreKeyBox, WebDavPasswordBox })
            passwordBox.PasswordChanged += (_, _) => ScheduleAutoSave();
    }

    private void ScheduleAutoSave()
    {
        if (_loadingValues) return;
        _autoSaveDelay?.Cancel();
        var delay = new CancellationTokenSource();
        _autoSaveDelay = delay;
        _ = AutoSaveAfterDelayAsync(delay);
    }

    private async Task AutoSaveAfterDelayAsync(CancellationTokenSource delay)
    {
        try
        {
            await Task.Delay(450, delay.Token);
            await SaveSettingsCoreAsync(false);
        }
        catch (OperationCanceledException) { }
        catch (Exception exception)
        {
            SaveStatusText.Text = $"自动保存失败：{exception.Message}";
        }
        finally
        {
            if (ReferenceEquals(_autoSaveDelay, delay))
            {
                _autoSaveDelay = null;
                delay.Dispose();
            }
        }
    }

    private static void MarkExistingCredential(Control control, string key)
    {
        try
        {
            if (string.IsNullOrEmpty(App.Services.Credentials.Read(key))) return;
            if (control is TextBox text) text.PlaceholderText = "已安全保存 · 留空则保留";
            if (control is PasswordBox password) password.PlaceholderText = "已安全保存 · 留空则保留";
        }
        catch { }
    }

    private void CategoryList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((CategoryList.SelectedItem as ListViewItem)?.Tag is string tag) ShowSection(tag);
    }

    private void ShowSection(string tag)
    {
        if (_sections.Count == 0 || !_sections.ContainsKey(tag)) return;
        foreach (var (sectionTag, section) in _sections)
            section.Visibility = sectionTag == tag ? Visibility.Visible : Visibility.Collapsed;
        SettingsScroll.ChangeView(null, 0, null, true);
    }

    public void SelectSection(string tag)
    {
        var item = CategoryList.Items.OfType<ListViewItem>().FirstOrDefault(candidate =>
            string.Equals(candidate.Tag as string, tag, StringComparison.OrdinalIgnoreCase));
        if (item is null) return;
        CategoryList.SelectedItem = item;
        ShowSection((string)item.Tag);
    }

    private async Task SaveSettingsCoreAsync(bool showStatus)
    {
        _autoSaveDelay?.Cancel();
        var settings = App.Services.Settings;
        var previousHotkeys = (
            settings.ShowWindowHotkey,
            settings.SelectionTranslateHotkey,
            settings.ScreenshotTranslateHotkey,
            settings.ScreenshotOcrHotkey);
        var hotkeysApplied = false;
        try
        {
            settings.ShowWindowHotkey = ShowWindowHotkeyBox.Text.Trim();
            settings.SelectionTranslateHotkey = SelectionHotkeyBox.Text.Trim();
            settings.ScreenshotTranslateHotkey = ScreenshotTranslateHotkeyBox.Text.Trim();
            settings.ScreenshotOcrHotkey = ScreenshotOcrHotkeyBox.Text.Trim();
            if (App.MainAppWindow is MainWindow window &&
                !window.TryApplyHotkeys(settings, out var hotkeyError))
            {
                RestorePreviousHotkeys(settings, previousHotkeys);
                throw new InvalidOperationException(hotkeyError);
            }
            hotkeysApplied = true;
            settings.ThemeMode = (string)((ComboBoxItem)ThemeBox.SelectedItem).Tag;
            settings.SaveHistory = SaveHistorySwitch.IsOn;
            settings.CompactTranslationWindow = CompactTranslationWindowSwitch.IsOn;
            settings.LaunchAtStartup = LaunchAtStartupSwitch.IsOn;
            settings.GoogleEnabled = GoogleSwitch.IsOn;
            settings.BaiduEnabled = BaiduSwitch.IsOn;
            settings.YoudaoEnabled = YoudaoSwitch.IsOn;
            settings.OpenAICompatibleEnabled = OpenAiSwitch.IsOn;
            settings.DeepLEnabled = DeepLSwitch.IsOn;
            settings.LibreTranslateEnabled = LibreSwitch.IsOn;
            var enabledBuiltIns = new[]
            {
                ("google", GoogleSwitch.IsOn), ("baidu", BaiduSwitch.IsOn), ("youdao", YoudaoSwitch.IsOn),
                ("openai-compatible", OpenAiSwitch.IsOn), ("deepl", DeepLSwitch.IsOn), ("libretranslate", LibreSwitch.IsOn),
            }.Where(item => item.Item2).Select(item => item.Item1).ToList();
            settings.EnabledTranslateServices = HomeInteractionPolicy
                .MergeBuiltInEnabled(settings.EnabledTranslateServices, enabledBuiltIns).ToList();
            settings.OpenAICompatibleName = OpenAiNameBox.Text.Trim();
            settings.OpenAICompatibleApi = (OpenAiApiBox.SelectedItem as ComboBoxItem)?.Tag as string ?? "openai";
            settings.OpenAICompatibleBaseUrl = OpenAiUrlBox.Text.Trim();
            settings.OpenAICompatibleModel = OpenAiModelBox.Text.Trim();
            settings.DeepLBaseUrl = DeepLUrlBox.Text.Trim();
            settings.LibreTranslateBaseUrl = LibreUrlBox.Text.Trim();
            settings.ScreenshotOcrAutoTranslate = OcrAutoTranslateSwitch.IsOn;
            settings.WebdavUrl = WebDavUrlBox.Text.Trim();
            settings.WebdavUsername = WebDavUserBox.Text.Trim();
            settings.WebdavHistoryAutoSync = WebDavAutoSyncSwitch.IsOn;
            settings.WebdavHistorySyncIntervalValue = Math.Max(1, (int)SyncIntervalBox.Value);
            settings.WebdavHistorySyncIntervalUnit = (string)((ComboBoxItem)SyncUnitBox.SelectedItem).Tag;
            settings.WebdavHistorySyncIntervalMinutes = (int)Math.Min(int.MaxValue,
                AppServices.GetSyncInterval(settings).TotalMinutes);
            settings.AlwaysOnTop = AlwaysOnTopSwitch.IsOn;
            settings.CloseToTray = CloseToTraySwitch.IsOn;
            settings.HideOnBlur = HideOnBlurSwitch.IsOn;
            settings.NotificationsEnabled = NotificationsSwitch.IsOn;
            settings.CheckForUpdatesOnStartup = CheckUpdateOnStartupSwitch.IsOn;

            SaveCredential("provider.baidu.appId", BaiduAppIdBox.Text);
            SaveCredential("provider.baidu.secret", BaiduSecretBox.Password);
            SaveCredential("provider.youdao.appKey", YoudaoAppKeyBox.Text);
            SaveCredential("provider.youdao.secret", YoudaoSecretBox.Password);
            SaveCredential("provider.openai-compatible.apiKey", OpenAiKeyBox.Password);
            SaveCredential("provider.deepl.apiKey", DeepLKeyBox.Password);
            SaveCredential("provider.libretranslate.apiKey", LibreKeyBox.Password);
            SaveCredential("webdav.password", WebDavPasswordBox.Password);
            await App.Services.SaveSettingsAsync();
            WindowsIntegrationService.ApplyTheme(settings.ThemeMode);
            WindowsIntegrationService.SetLaunchAtStartup(settings.LaunchAtStartup);
            if (App.MainAppWindow?.AppWindow.Presenter is OverlappedPresenter presenter)
                presenter.IsAlwaysOnTop = settings.AlwaysOnTop;
            if (showStatus) SaveStatusText.Text = $"已保存 · {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception exception)
        {
            if (hotkeysApplied)
            {
                RestorePreviousHotkeys(settings, previousHotkeys);
                if (App.MainAppWindow is MainWindow window) window.TryApplyHotkeys(settings, out _);
            }
            SaveStatusText.Text = showStatus ? $"保存失败：{exception.Message}" : $"自动保存失败：{exception.Message}";
        }
    }

    private static void RestorePreviousHotkeys(
        PythiaSettings settings,
        (string Show, string Selection, string ScreenshotTranslate, string ScreenshotOcr) previous)
    {
        settings.ShowWindowHotkey = previous.Show;
        settings.SelectionTranslateHotkey = previous.Selection;
        settings.ScreenshotTranslateHotkey = previous.ScreenshotTranslate;
        settings.ScreenshotOcrHotkey = previous.ScreenshotOcr;
    }

    private void HotkeyBox_PreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (sender is not TextBox box) return;
        e.Handled = true;
        if (e.Key is VirtualKey.Control or VirtualKey.LeftControl or VirtualKey.RightControl or
            VirtualKey.Shift or VirtualKey.LeftShift or VirtualKey.RightShift or
            VirtualKey.Menu or VirtualKey.LeftMenu or VirtualKey.RightMenu or
            VirtualKey.LeftWindows or VirtualKey.RightWindows)
            return;

        var key = HotkeyToken(e.Key);
        if (key is null)
        {
            SaveStatusText.Text = "快捷键主键仅支持 A–Z、0–9 和 F1–F24。";
            return;
        }
        var parts = new List<string>();
        if (IsKeyDown(VirtualKey.Control)) parts.Add("Ctrl");
        if (IsKeyDown(VirtualKey.Menu)) parts.Add("Alt");
        if (IsKeyDown(VirtualKey.Shift)) parts.Add("Shift");
        if (IsKeyDown(VirtualKey.LeftWindows) || IsKeyDown(VirtualKey.RightWindows)) parts.Add("Win");
        if (parts.Count == 0)
        {
            SaveStatusText.Text = "快捷键必须至少包含 Ctrl、Alt、Shift 或 Win 中的一个修饰键。";
            return;
        }
        parts.Add(key);
        box.Text = string.Join('+', parts);
        box.SelectAll();
            SaveStatusText.Text = "快捷键已录入，将自动保存并生效。";
    }

    private static bool IsKeyDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    private static string? HotkeyToken(VirtualKey key)
    {
        var code = (int)key;
        if (code >= (int)VirtualKey.A && code <= (int)VirtualKey.Z) return ((char)code).ToString();
        if (code >= (int)VirtualKey.Number0 && code <= (int)VirtualKey.Number9) return ((char)code).ToString();
        if (code >= (int)VirtualKey.F1 && code <= (int)VirtualKey.F24) return key.ToString();
        return null;
    }

    private static void SaveCredential(string key, string value)
    {
        if (!string.IsNullOrWhiteSpace(value)) App.Services.Credentials.Write(key, value.Trim());
    }

    private async void TestWebDav_Click(object sender, RoutedEventArgs e)
    {
        WebDavStatusText.Text = "正在测试连接…";
        try
        {
            var password = await SaveWebDavInputsAsync();
            await WebDavService.TestConnectionAsync(WebDavUrlBox.Text.Trim(), WebDavUserBox.Text.Trim(), password);
            WebDavStatusText.Text = "连接成功";
        }
        catch (Exception exception) { WebDavStatusText.Text = $"连接失败：{exception.Message}"; }
    }

    private async void SyncWebDav_Click(object sender, RoutedEventArgs e)
    {
        WebDavStatusText.Text = "正在同步历史…";
        try
        {
            await SaveWebDavInputsAsync();
            var result = await App.Services.SyncHistoryAsync();
            WebDavStatusText.Text =
                $"同步成功：远程 {result.DownloadedCount} 条，本地可见 {result.VisibleCount} 条，冲突 {result.ConflictCount} 条";
        }
        catch (Exception exception) { WebDavStatusText.Text = $"同步失败：{exception.Message}"; }
    }

    private async void UploadWebDavBackup_Click(object sender, RoutedEventArgs e)
    {
        WebDavStatusText.Text = "正在上传便携备份…";
        try
        {
            var password = await SaveWebDavInputsAsync();
            await WebDavService.UploadPortableBackupAsync(
                App.Services.CreatePortableBackup(),
                WebDavUrlBox.Text.Trim(),
                WebDavUserBox.Text.Trim(),
                password);
            WebDavStatusText.Text = "便携备份已安全上传（不含密码和 API 密钥）";
        }
        catch (Exception exception) { WebDavStatusText.Text = $"上传失败：{exception.Message}"; }
    }

    private async void RestoreWebDavBackup_Click(object sender, RoutedEventArgs e)
    {
        WebDavStatusText.Text = "正在下载远程备份…";
        try
        {
            var password = await SaveWebDavInputsAsync();
            var json = await WebDavService.DownloadPortableBackupAsync(
                WebDavUrlBox.Text.Trim(),
                WebDavUserBox.Text.Trim(),
                password);
            if (!await ConfirmRestoreAsync("恢复远程便携备份？")) return;
            var restored = await App.Services.RestorePortableBackupAsync(json);
            LoadValues();
            WebDavStatusText.Text =
                $"恢复完成：导入 {restored.ImportedCount} 条，合并后 {restored.Records.Count} 条，冲突 {restored.ConflictCount} 条";
        }
        catch (Exception exception) { WebDavStatusText.Text = $"恢复失败：{exception.Message}"; }
    }

    private async void ExportLocalBackup_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileSavePicker { SuggestedFileName = $"Pythia-backup-{DateTime.Now:yyyyMMdd-HHmm}" };
        picker.FileTypeChoices.Add("Pythia JSON 备份", [".json"]);
        if (App.MainAppWindow is null) return;
        WinRT.Interop.InitializeWithWindow.Initialize(picker,
            WinRT.Interop.WindowNative.GetWindowHandle(App.MainAppWindow));
        var file = await picker.PickSaveFileAsync();
        if (file is null) return;
        try
        {
            await File.WriteAllTextAsync(file.Path, App.Services.CreatePortableBackup());
            WebDavStatusText.Text = $"本地备份已导出：{file.Name}";
        }
        catch (Exception exception) { WebDavStatusText.Text = $"导出失败：{exception.Message}"; }
    }

    private async void ImportLocalBackup_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".json");
        if (App.MainAppWindow is null) return;
        WinRT.Interop.InitializeWithWindow.Initialize(picker,
            WinRT.Interop.WindowNative.GetWindowHandle(App.MainAppWindow));
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        try
        {
            var json = await File.ReadAllTextAsync(file.Path);
            if (!await ConfirmRestoreAsync("导入并合并本地备份？")) return;
            var restored = await App.Services.RestorePortableBackupAsync(json);
            LoadValues();
            WebDavStatusText.Text =
                $"导入完成：导入 {restored.ImportedCount} 条，合并后 {restored.Records.Count} 条，冲突 {restored.ConflictCount} 条";
        }
        catch (Exception exception) { WebDavStatusText.Text = $"导入失败：{exception.Message}"; }
    }

    private async Task<string> SaveWebDavInputsAsync()
    {
        var settings = App.Services.Settings;
        settings.WebdavUrl = WebDavUrlBox.Text.Trim();
        settings.WebdavUsername = WebDavUserBox.Text.Trim();
        settings.WebdavHistoryAutoSync = WebDavAutoSyncSwitch.IsOn;
        settings.WebdavHistorySyncIntervalValue = Math.Max(1, (int)SyncIntervalBox.Value);
        settings.WebdavHistorySyncIntervalUnit = (string)((ComboBoxItem)SyncUnitBox.SelectedItem).Tag;
        settings.WebdavHistorySyncIntervalMinutes = (int)Math.Min(int.MaxValue,
            AppServices.GetSyncInterval(settings).TotalMinutes);
        SaveCredential("webdav.password", WebDavPasswordBox.Password);
        await App.Services.SaveSettingsAsync();
        return WebDavPasswordBox.Password.Length > 0
            ? WebDavPasswordBox.Password
            : App.Services.Credentials.Read("webdav.password") ?? string.Empty;
    }

    private async Task<bool> ConfirmRestoreAsync(string title)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = "备份中的设置会应用到本机，历史记录按 ID 和更新时间安全合并；现有密码与 API 密钥不会被覆盖。",
            PrimaryButtonText = "继续",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private async void CheckUpdate_Click(object sender, RoutedEventArgs e)
    {
        CheckUpdateButton.IsEnabled = false;
        UpdateStatusText.Text = "正在检查 GitHub Release…";
        try
        {
            var update = await UpdateService.CheckAsync();
            App.SetPendingUpdate(update);
            if (update is null)
            {
                UpdateStatusText.Text = $"当前已是最新版本 {UpdateService.CurrentVersion.ToString(3)}";
                return;
            }
            RefreshUpdateState();
        }
        catch (Exception exception)
        {
            UpdateStatusText.Text = $"更新检查失败：{exception.Message}";
        }
        finally { CheckUpdateButton.IsEnabled = true; }
    }

    private async void InstallUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (App.PendingUpdate is not { } update) return;
        UpdateButton.IsEnabled = false;
        try
        {
            var progress = new Progress<double>(value =>
                UpdateStatusText.Text = $"正在下载 {update.Tag}：{value:P0}");
            var installer = await UpdateService.DownloadInstallerAsync(update, progress);
            UpdateStatusText.Text = "校验完成，正在启动安装程序…";
            UpdateService.LaunchInstaller(installer);
            if (App.MainAppWindow is MainWindow window) window.ExitApplication();
        }
        catch (Exception exception)
        {
            UpdateStatusText.Text = $"更新安装失败：{exception.Message}";
            UpdateButton.IsEnabled = true;
        }
    }

    private void OpenGitHub_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo(UpdateService.RepositoryUrl) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            UpdateStatusText.Text = $"无法打开 GitHub：{exception.Message}";
        }
    }
}
