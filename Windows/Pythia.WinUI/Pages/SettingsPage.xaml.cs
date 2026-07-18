using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pythia.Models;
using Pythia.Services;

namespace Pythia.Pages;

public sealed partial class SettingsPage : Page
{
    private readonly Dictionary<string, FrameworkElement> _sections = [];

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
    }

    private void LoadValues()
    {
        var settings = App.Services.Settings;
        ThemeBox.SelectedItem = ThemeBox.Items.OfType<ComboBoxItem>().First(item => (string)item.Tag == settings.ThemeMode);
        SaveHistorySwitch.IsOn = settings.SaveHistory;
        LaunchAtStartupSwitch.IsOn = settings.LaunchAtStartup;
        GoogleSwitch.IsOn = settings.GoogleEnabled || settings.EnabledTranslateServices.Contains("google");
        BaiduSwitch.IsOn = settings.BaiduEnabled || settings.EnabledTranslateServices.Contains("baidu");
        YoudaoSwitch.IsOn = settings.YoudaoEnabled || settings.EnabledTranslateServices.Contains("youdao");
        OpenAiSwitch.IsOn = settings.OpenAICompatibleEnabled || settings.EnabledTranslateServices.Contains("openai-compatible");
        DeepLSwitch.IsOn = settings.DeepLEnabled || settings.EnabledTranslateServices.Contains("deepl");
        LibreSwitch.IsOn = settings.LibreTranslateEnabled || settings.EnabledTranslateServices.Contains("libretranslate");
        OpenAiNameBox.Text = settings.OpenAICompatibleName;
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
        AlwaysOnTopSwitch.IsOn = settings.AlwaysOnTop;
        CloseToTraySwitch.IsOn = settings.CloseToTray;
        HideOnBlurSwitch.IsOn = settings.HideOnBlur;
        NotificationsSwitch.IsOn = settings.NotificationsEnabled;
        PluginPathText.Text = App.Services.Store.PluginsDirectory;
        MarkExistingCredential(BaiduAppIdBox, "provider.baidu.appId");
        MarkExistingCredential(BaiduSecretBox, "provider.baidu.secret");
        MarkExistingCredential(YoudaoAppKeyBox, "provider.youdao.appKey");
        MarkExistingCredential(YoudaoSecretBox, "provider.youdao.secret");
        MarkExistingCredential(OpenAiKeyBox, "provider.openai-compatible.apiKey");
        MarkExistingCredential(DeepLKeyBox, "provider.deepl.apiKey");
        MarkExistingCredential(LibreKeyBox, "provider.libretranslate.apiKey");
        MarkExistingCredential(WebDavPasswordBox, "webdav.password");
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
        if ((CategoryList.SelectedItem as ListViewItem)?.Tag is string tag && _sections.TryGetValue(tag, out var section))
            section.StartBringIntoView(new BringIntoViewOptions { AnimationDesired = true, VerticalAlignmentRatio = 0 });
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var settings = App.Services.Settings;
            settings.ThemeMode = (string)((ComboBoxItem)ThemeBox.SelectedItem).Tag;
            settings.SaveHistory = SaveHistorySwitch.IsOn;
            settings.LaunchAtStartup = LaunchAtStartupSwitch.IsOn;
            settings.GoogleEnabled = GoogleSwitch.IsOn;
            settings.BaiduEnabled = BaiduSwitch.IsOn;
            settings.YoudaoEnabled = YoudaoSwitch.IsOn;
            settings.OpenAICompatibleEnabled = OpenAiSwitch.IsOn;
            settings.DeepLEnabled = DeepLSwitch.IsOn;
            settings.LibreTranslateEnabled = LibreSwitch.IsOn;
            settings.EnabledTranslateServices = new[]
            {
                ("google", GoogleSwitch.IsOn), ("baidu", BaiduSwitch.IsOn), ("youdao", YoudaoSwitch.IsOn),
                ("openai-compatible", OpenAiSwitch.IsOn), ("deepl", DeepLSwitch.IsOn), ("libretranslate", LibreSwitch.IsOn),
            }.Where(item => item.Item2).Select(item => item.Item1).ToList();
            settings.OpenAICompatibleName = OpenAiNameBox.Text.Trim();
            settings.OpenAICompatibleBaseUrl = OpenAiUrlBox.Text.Trim();
            settings.OpenAICompatibleModel = OpenAiModelBox.Text.Trim();
            settings.DeepLBaseUrl = DeepLUrlBox.Text.Trim();
            settings.LibreTranslateBaseUrl = LibreUrlBox.Text.Trim();
            settings.ScreenshotOcrAutoTranslate = OcrAutoTranslateSwitch.IsOn;
            settings.ShowWindowHotkey = ShowWindowHotkeyBox.Text.Trim();
            settings.SelectionTranslateHotkey = SelectionHotkeyBox.Text.Trim();
            settings.ScreenshotTranslateHotkey = ScreenshotTranslateHotkeyBox.Text.Trim();
            settings.ScreenshotOcrHotkey = ScreenshotOcrHotkeyBox.Text.Trim();
            settings.WebdavUrl = WebDavUrlBox.Text.Trim();
            settings.WebdavUsername = WebDavUserBox.Text.Trim();
            settings.WebdavHistoryAutoSync = WebDavAutoSyncSwitch.IsOn;
            settings.WebdavHistorySyncIntervalValue = Math.Max(1, (int)SyncIntervalBox.Value);
            settings.WebdavHistorySyncIntervalUnit = (string)((ComboBoxItem)SyncUnitBox.SelectedItem).Tag;
            settings.WebdavHistorySyncIntervalMinutes = settings.WebdavHistorySyncIntervalValue *
                (settings.WebdavHistorySyncIntervalUnit switch { "day" => 1440, "hour" => 60, _ => 1 });
            settings.AlwaysOnTop = AlwaysOnTopSwitch.IsOn;
            settings.CloseToTray = CloseToTraySwitch.IsOn;
            settings.HideOnBlur = HideOnBlurSwitch.IsOn;
            settings.NotificationsEnabled = NotificationsSwitch.IsOn;

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
            SaveStatusText.Text = $"已保存 · {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception exception)
        {
            SaveStatusText.Text = $"保存失败：{exception.Message}";
        }
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
            var password = WebDavPasswordBox.Password;
            if (password.Length == 0) password = App.Services.Credentials.Read("webdav.password") ?? string.Empty;
            await WebDavService.TestConnectionAsync(WebDavUrlBox.Text.Trim(), WebDavUserBox.Text.Trim(), password);
            WebDavStatusText.Text = "连接成功";
        }
        catch (Exception exception) { WebDavStatusText.Text = $"连接失败：{exception.Message}"; }
    }
}
