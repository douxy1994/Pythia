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
    private const string PluginGuideUrl = "https://github.com/douxy1994/Pythia/blob/master/Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md";
    private const string ExistingPluginsUrl = "https://github.com/douxy1994/Pythia/tree/master/Plugins";
    private readonly Dictionary<string, Control> _configurationControls = new(StringComparer.Ordinal);
    private readonly PluginService _service = App.Services.Plugins;
    private readonly DispatcherTimer _statusTimer;
    private PluginInfo? _selectedPlugin;

    public ObservableCollection<PluginInfo> Plugins { get; }
    public ObservableCollection<PluginInfo> OrderedPlugins { get; }

    private bool _reloading;
    private bool _updatingPluginUi;
    private DateTimeOffset _statusDeadline;

    public PluginSettingsPanel()
    {
        Plugins = [];
        OrderedPlugins = [];
        InitializeComponent();
        _statusTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        _statusTimer.Tick += PluginStatusTimer_Tick;
        Loaded += (_, _) => Reload();
        Unloaded += (_, _) =>
        {
            _statusTimer.Stop();
            PluginStatusCountdownRing.Stop();
        };
    }

    public void Reload(string? preferredPluginId = null)
    {
        if (_reloading) return;
        _reloading = true;
        try
        {
        var preferred = preferredPluginId ?? _selectedPlugin?.Id;
        if (_expandedExpander is not null)
        {
            var expanded = _expandedExpander;
            _expandedExpander = null;
            expanded.Content = null;
            expanded.IsExpanded = false;
        }
        SelectedPluginHost.Content = SelectedPluginPanel;
        SelectedPluginHost.Visibility = Visibility.Collapsed;
        Plugins.Clear();
        var installed = _service.LoadInstalled();
        foreach (var plugin in installed.OrderBy(item => item.DisplayName, StringComparer.CurrentCultureIgnoreCase))
            Plugins.Add(plugin);

        var byId = installed.ToDictionary(item => item.Id, StringComparer.OrdinalIgnoreCase);
        OrderedPlugins.Clear();
        foreach (var id in App.Services.Settings.TranslateServiceOrder)
            if (byId.TryGetValue(id.StartsWith("plugin:", StringComparison.OrdinalIgnoreCase) ? id[7..] : id, out var ordered))
                OrderedPlugins.Add(ordered);
        foreach (var plugin in installed.OrderBy(item => item.DisplayName, StringComparer.CurrentCultureIgnoreCase))
            if (!OrderedPlugins.Contains(plugin)) OrderedPlugins.Add(plugin);

        EmptyPluginInfo.IsOpen = Plugins.Count == 0;
        InvalidPluginInfo.IsOpen = _service.LastLoadErrors.Count > 0;
        InvalidPluginInfo.Message = _service.LastLoadErrors.Count == 0
            ? string.Empty
            : string.Join("\n", _service.LastLoadErrors);
        PluginOrderCard.Visibility = Plugins.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        SelectedPluginPanel.Visibility = Visibility.Collapsed;
        _selectedPlugin = installed.FirstOrDefault(item =>
            item.Id.Equals(preferred, StringComparison.OrdinalIgnoreCase));
        if (Plugins.Count == 0) ShowPlugin(null);
        }
        finally { _reloading = false; }
    }

    private Expander? _expandedExpander;

    private void PluginExpander_Expanding(Expander expander, ExpanderExpandingEventArgs e)
    {
        if (expander.Tag is not PluginInfo plugin) return;
        if (_expandedExpander is { } previous && !ReferenceEquals(previous, expander))
        {
            _expandedExpander = null;
            previous.Content = null;
            previous.IsExpanded = false;
        }

        _expandedExpander = expander;
        SelectedPluginHost.Content = null;
        expander.Content = SelectedPluginPanel;
        AutomationProperties.SetName(expander, $"{plugin.DisplayName} 插件设置");
        ShowPlugin(plugin);
    }

    private void PluginExpander_Collapsed(Expander expander, ExpanderCollapsedEventArgs e)
    {
        if (!ReferenceEquals(_expandedExpander, expander)) return;
        _expandedExpander = null;
        expander.Content = null;
        SelectedPluginHost.Content = SelectedPluginPanel;
        SelectedPluginHost.Visibility = Visibility.Collapsed;
        ShowPlugin(null);
    }

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
        PluginNameText.Text = plugin.DisplayName;
        PluginVersionText.Text = plugin.VersionDisplay;
        PluginDescriptionText.Text = plugin.Description;
        PluginMetadataText.Text = $"作者：{plugin.Author} · 标识：{plugin.ServiceId} · {plugin.ConfigurationDisplay}";
        PluginPathText.Text = plugin.DirectoryPath;
        PluginConversionText.Text = plugin.CanReconvert
            ? "来源：兼容 .potext（保留原始文件，可重新转换）"
            : "来源：原生 .pythia";
        ReconvertButton.Visibility = plugin.CanReconvert ? Visibility.Visible : Visibility.Collapsed;
        PluginIconImage.Source = plugin.IconSource;
        PluginIconImage.Visibility = plugin.IconVisibility;
        PluginFallbackImage.Visibility = plugin.FallbackIconVisibility;
        _updatingPluginUi = true;
        try { PluginEnabledSwitch.IsOn = plugin.Enabled; }
        finally { _updatingPluginUi = false; }

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
            AutomationProperties.SetName(control, $"{plugin.DisplayName} {field.Label}");
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
        ShowStatus(InfoBarSeverity.Success, "插件配置已保存", plugin.DisplayName);
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
        ShowStatus(InfoBarSeverity.Informational, $"正在测试 {plugin.DisplayName}", "最长等待 30 秒，失败时最多重试一次。", false);
        try
        {
            var result = await _service.TestConnectionAsync(plugin);
            ShowStatus(result.IsSuccess ? InfoBarSeverity.Success : InfoBarSeverity.Error,
                $"{plugin.DisplayName}：{result.StatusDisplay}",
                $"{result.Message} · 尝试 {result.Attempts} 次 · {result.Duration.TotalSeconds:0.0} 秒");
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, $"{plugin.DisplayName}：测试失败", exception.Message);
        }
        finally
        {
            TestPluginButton.IsEnabled = true;
        }
    }

    private async void PluginEnabledSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_updatingPluginUi || _selectedPlugin is not { } plugin) return;
        var enabled = PluginEnabledSwitch.IsOn;
        _service.SetEnabled(plugin, enabled);
        plugin.Enabled = enabled;
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
        ShowStatus(InfoBarSeverity.Success, enabled ? "插件已启用" : "插件已停用", plugin.DisplayName);
    }

    private async void PluginOrderList_DragItemsCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
    {
        var pluginIds = OrderedPlugins.Select(item => item.ServiceId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var order = App.Services.Settings.TranslateServiceOrder
            .Where(id => !pluginIds.Contains(id))
            .Concat(OrderedPlugins.Select(item => item.ServiceId))
            .ToList();
        App.Services.Settings.TranslateServiceOrder = order;
        await App.Services.SaveSettingsAsync();
        ShowStatus(InfoBarSeverity.Success, "插件顺序已保存", "首页结果卡会按新的顺序显示。");
    }

    private async void Rename_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedPlugin is not { } plugin) return;
        var input = new TextBox { Text = plugin.DisplayName, MaxLength = 120, PlaceholderText = "插件显示名称" };
        var content = new StackPanel { Spacing = 8 };
        content.Children.Add(new TextBlock
        {
            Text = "只修改 Pythia 中的显示名称，不会改变插件目录、服务标识或配置。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        });
        content.Children.Add(input);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "改名插件",
            Content = content,
            PrimaryButtonText = "保存",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            _service.RenameDisplay(plugin, input.Text);
            await App.Services.SaveSettingsAsync();
            ShowStatus(InfoBarSeverity.Success, "插件名称已更新", plugin.DisplayName);
            Reload(plugin.Id);
        }
        catch (Exception exception) { ShowStatus(InfoBarSeverity.Error, "插件改名失败", exception.Message); }
    }

    private async void Reconvert_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedPlugin is not { } plugin) return;
        try
        {
            var converted = _service.Reconvert(plugin);
            await App.Services.SaveSettingsAsync();
            ShowStatus(InfoBarSeverity.Success, "插件已重新转换", $"{converted.DisplayName} 的 .potext 兼容层已更新。");
            Reload(converted.Id);
        }
        catch (Exception exception) { ShowStatus(InfoBarSeverity.Error, "重新转换失败", exception.Message); }
    }

    private async void Install_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainAppWindow is null) return;
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".pythia");
        picker.FileTypeFilter.Add(".potext");
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
            ShowStatus(InfoBarSeverity.Success, "插件安装完成", $"{plugin.DisplayName} {plugin.Version}");
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
            Title = $"卸载 {plugin.DisplayName}？",
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
        ShowStatus(InfoBarSeverity.Success, "插件已卸载", plugin.DisplayName);
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

    private void OpenGuide_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo(PluginGuideUrl) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, "无法打开插件开发指南", exception.Message);
        }
    }

    private void OpenExistingPlugins_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo(ExistingPluginsUrl) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, "无法打开现有插件页面", exception.Message);
        }
    }

    private void PluginStatusClose_Click(object sender, RoutedEventArgs e) => DismissPluginStatus();

    private void PluginStatusTimer_Tick(object? sender, object e)
    {
        if (DateTimeOffset.UtcNow >= _statusDeadline) DismissPluginStatus();
    }

    private void DismissPluginStatus()
    {
        _statusTimer.Stop();
        PluginStatusCountdownRing.Stop();
        PluginStatusInfo.IsOpen = false;
        PluginStatusHost.Visibility = Visibility.Collapsed;
    }

    private void ShowStatus(InfoBarSeverity severity, string title, string message, bool closable = true)
    {
        PluginStatusInfo.Severity = severity;
        PluginStatusInfo.Title = title;
        PluginStatusInfo.Message = message;
        PluginStatusCloseButton.IsEnabled = closable;
        PluginStatusHost.Visibility = Visibility.Visible;
        PluginStatusInfo.IsOpen = true;
        _statusDeadline = DateTimeOffset.UtcNow.AddSeconds(5);
        PluginStatusCountdownRing.Start(TimeSpan.FromSeconds(5));
        _statusTimer.Stop();
        _statusTimer.Start();
        App.Services.Status.Report($"{title} · {message}");
    }
}
