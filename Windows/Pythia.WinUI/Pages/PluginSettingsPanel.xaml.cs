using System.Collections.ObjectModel;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Pythia.Models;
using Pythia.Services;
using Windows.Storage.Pickers;

namespace Pythia.Pages;

public sealed partial class PluginSettingsPanel : UserControl
{
    private readonly Dictionary<string, Control> _configurationControls = new(StringComparer.Ordinal);
    private readonly PluginService _service = App.Services.Plugins;
    private PluginInfo? _selectedPlugin;

    public PluginSettingsPanel()
    {
        Plugins = [];
        InitializeComponent();
        Loaded += (_, _) => Reload();
    }

    public ObservableCollection<PluginInfo> Plugins { get; }

    public void Reload(string? preferredPluginId = null)
    {
        preferredPluginId ??= _selectedPlugin?.Id;
        Plugins.Clear();
        foreach (var plugin in _service.LoadInstalled().OrderBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase))
            Plugins.Add(plugin);

        EmptyPluginInfo.IsOpen = Plugins.Count == 0;
        SelectedPluginPanel.Visibility = Plugins.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        PluginPicker.SelectedItem = Plugins.FirstOrDefault(item =>
            item.Id.Equals(preferredPluginId, StringComparison.OrdinalIgnoreCase)) ?? Plugins.FirstOrDefault();
        if (Plugins.Count == 0) ShowPlugin(null);
    }

    private void PluginPicker_SelectionChanged(object sender, SelectionChangedEventArgs e) =>
        ShowPlugin(PluginPicker.SelectedItem as PluginInfo);

    private void ShowPlugin(PluginInfo? plugin)
    {
        _selectedPlugin = plugin;
        _configurationControls.Clear();
        ConfigurationFieldsPanel.Children.Clear();
        if (plugin is null)
        {
            SelectedPluginPanel.Visibility = Visibility.Collapsed;
            return;
        }

        SelectedPluginPanel.Visibility = Visibility.Visible;
        PluginNameText.Text = plugin.Name;
        PluginVersionText.Text = plugin.VersionDisplay;
        PluginDescriptionText.Text = plugin.Description;
        PluginMetadataText.Text = $"作者：{plugin.Author} · 标识：{plugin.ServiceId} · {plugin.ConfigurationDisplay}";
        PluginPathText.Text = plugin.DirectoryPath;
        PluginIconImage.Source = plugin.IconSource;
        PluginIconImage.Visibility = plugin.IconVisibility;
        PluginFallbackImage.Visibility = plugin.FallbackIconVisibility;
        PluginEnabledText.Text = plugin.Enabled ? "已启用" : "已停用";
        PluginEnabledText.Foreground = plugin.Enabled
            ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["SystemFillColorSuccessBrush"]
            : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        TogglePluginButton.Content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            Children =
            {
                new SymbolIcon { Symbol = plugin.Enabled ? Symbol.Stop : Symbol.Play },
                new TextBlock { Text = plugin.Enabled ? "停用" : "启用" },
            },
        };

        var current = _service.GetConfiguration(plugin);
        if (plugin.Configuration.Count == 0)
        {
            ConfigurationFieldsPanel.Children.Add(new TextBlock
            {
                Text = "该插件无需配置，可以直接测试连通性。",
                Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                TextWrapping = TextWrapping.Wrap,
            });
            return;
        }

        foreach (var field in plugin.Configuration)
        {
            var label = field.Required ? $"{field.Label} *" : field.Label;
            Control control;
            if (field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase))
            {
                control = new PasswordBox
                {
                    Header = label,
                    PasswordRevealMode = PasswordRevealMode.Hidden,
                    PlaceholderText = string.IsNullOrWhiteSpace(current.GetValueOrDefault(field.Key))
                        ? "请输入凭据"
                        : "已安全保存 · 留空则保留",
                };
            }
            else if (field.Type.Equals("select", StringComparison.OrdinalIgnoreCase) && field.Options.Count > 0)
            {
                var combo = new ComboBox { Header = label, HorizontalAlignment = HorizontalAlignment.Stretch };
                foreach (var option in field.Options)
                    combo.Items.Add(new ComboBoxItem { Content = option.Value, Tag = option.Key });
                var selected = current.GetValueOrDefault(field.Key) ?? field.DefaultValue;
                combo.SelectedItem = combo.Items.OfType<ComboBoxItem>().FirstOrDefault(item =>
                    string.Equals((string?)item.Tag, selected, StringComparison.Ordinal)) ?? combo.Items.FirstOrDefault();
                control = combo;
            }
            else
            {
                control = new TextBox
                {
                    Header = label,
                    Text = current.GetValueOrDefault(field.Key) ?? field.DefaultValue ?? string.Empty,
                };
            }
            AutomationProperties.SetName(control, $"{plugin.Name} {field.Label}");
            _configurationControls[field.Key] = control;
            ConfigurationFieldsPanel.Children.Add(control);
        }
    }

    private async void SaveConfiguration_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedPlugin is not { } plugin) return;
        var current = _service.GetConfiguration(plugin);
        var values = CollectConfigurationValues();
        var missing = plugin.Configuration.Where(field => field.Required &&
            string.IsNullOrWhiteSpace(values.GetValueOrDefault(field.Key)) &&
            string.IsNullOrWhiteSpace(current.GetValueOrDefault(field.Key))).ToArray();
        if (missing.Length > 0)
        {
            ShowStatus(InfoBarSeverity.Error, "配置不完整", $"请填写：{string.Join("、", missing.Select(item => item.Label))}");
            return;
        }

        _service.SaveConfiguration(plugin, values);
        await App.Services.SaveSettingsAsync();
        ShowStatus(InfoBarSeverity.Success, "插件配置已保存", plugin.Name);
        Reload(plugin.Id);
    }

    private Dictionary<string, string> CollectConfigurationValues() => _configurationControls.ToDictionary(
        item => item.Key,
        item => item.Value switch
        {
            PasswordBox password => password.Password,
            ComboBox combo when combo.SelectedItem is ComboBoxItem option => (string?)option.Tag ?? string.Empty,
            TextBox text => text.Text,
            _ => string.Empty,
        }, StringComparer.Ordinal);

    private async void TestConnection_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedPlugin is not { } plugin) return;
        TestPluginButton.IsEnabled = false;
        ShowStatus(InfoBarSeverity.Informational, $"正在测试 {plugin.Name}", "最长等待 30 秒，失败时最多重试一次。", false);
        try
        {
            var result = await _service.TestConnectionAsync(plugin);
            ShowStatus(result.IsSuccess ? InfoBarSeverity.Success : InfoBarSeverity.Error,
                $"{plugin.Name}：{result.StatusDisplay}",
                $"{result.Message} · 尝试 {result.Attempts} 次 · {result.Duration.TotalSeconds:0.0} 秒");
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, $"{plugin.Name}：测试失败", exception.Message);
        }
        finally
        {
            TestPluginButton.IsEnabled = true;
            Reload(plugin.Id);
        }
    }

    private async void TogglePlugin_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedPlugin is not { } plugin) return;
        var enabled = !plugin.Enabled;
        _service.SetEnabled(plugin, enabled);
        if (enabled)
        {
            if (!App.Services.Settings.TranslateServiceOrder.Contains(plugin.ServiceId, StringComparer.OrdinalIgnoreCase))
                App.Services.Settings.TranslateServiceOrder.Add(plugin.ServiceId);
            if (!App.Services.Settings.EnabledTranslateServices.Contains(plugin.ServiceId, StringComparer.OrdinalIgnoreCase))
                App.Services.Settings.EnabledTranslateServices.Add(plugin.ServiceId);
        }
        else
        {
            App.Services.Settings.EnabledTranslateServices.RemoveAll(id =>
                id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
        }
        await App.Services.SaveSettingsAsync();
        ShowStatus(InfoBarSeverity.Success, enabled ? "插件已启用" : "插件已停用", plugin.Name);
        Reload(plugin.Id);
    }

    private async void Install_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainAppWindow is null) return;
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".pythia");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(App.MainAppWindow));
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        try
        {
            var plugin = _service.Install(file.Path);
            if (!App.Services.Settings.TranslateServiceOrder.Contains(plugin.ServiceId, StringComparer.OrdinalIgnoreCase))
                App.Services.Settings.TranslateServiceOrder.Add(plugin.ServiceId);
            if (!App.Services.Settings.EnabledTranslateServices.Contains(plugin.ServiceId, StringComparer.OrdinalIgnoreCase))
                App.Services.Settings.EnabledTranslateServices.Add(plugin.ServiceId);
            await App.Services.SaveSettingsAsync();
            ShowStatus(InfoBarSeverity.Success, "插件安装完成", $"{plugin.Name} {plugin.Version}");
            Reload(plugin.Id);
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, "插件安装失败", exception.Message);
        }
    }

    private async void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedPlugin is not { } plugin) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"卸载 {plugin.Name}？",
            Content = "将删除该插件的本机文件、状态与凭据。",
            PrimaryButtonText = "卸载",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        _service.Remove(plugin);
        App.Services.Settings.TranslateServiceOrder.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
        App.Services.Settings.EnabledTranslateServices.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
        await App.Services.SaveSettingsAsync();
        ShowStatus(InfoBarSeverity.Success, "插件已卸载", plugin.Name);
        Reload();
    }

    private void Refresh_Click(object sender, RoutedEventArgs e)
    {
        Reload();
        ShowStatus(InfoBarSeverity.Informational, "插件列表已刷新", $"共 {Plugins.Count} 个插件");
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(App.Services.Store.PluginsDirectory);
        Process.Start(new ProcessStartInfo("explorer.exe", App.Services.Store.PluginsDirectory) { UseShellExecute = true });
    }

    private void ShowStatus(InfoBarSeverity severity, string title, string message, bool closable = true)
    {
        PluginStatusInfo.Severity = severity;
        PluginStatusInfo.Title = title;
        PluginStatusInfo.Message = message;
        PluginStatusInfo.IsClosable = closable;
        PluginStatusInfo.IsOpen = true;
        App.Services.Status.Report($"{title} · {message}");
    }
}
