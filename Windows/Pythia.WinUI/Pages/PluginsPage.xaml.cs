using System.Collections.ObjectModel;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pythia.Models;
using Pythia.Services;
using Windows.Storage.Pickers;

namespace Pythia.Pages;

public sealed partial class PluginsPage : Page
{
    private readonly PluginService _service = App.Services.Plugins;

    public PluginsPage()
    {
        Plugins = [];
        InitializeComponent();
        Reload();
    }

    public ObservableCollection<PluginInfo> Plugins { get; }

    private void Reload()
    {
        Plugins.Clear();
        foreach (var plugin in _service.LoadInstalled()) Plugins.Add(plugin);
        EmptyState.Visibility = Plugins.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void Install_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".pythia");
        if (App.MainAppWindow is null) return;
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(App.MainAppWindow));
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        try
        {
            var plugin = _service.Install(file.Path);
            App.Services.Settings.TranslateServiceOrder.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
            App.Services.Settings.TranslateServiceOrder.Insert(0, plugin.ServiceId);
            App.Services.Settings.EnabledTranslateServices.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
            App.Services.Settings.EnabledTranslateServices.Insert(0, plugin.ServiceId);
            await App.Services.SaveSettingsAsync();
            Reload();
            App.Services.Status.Report($"已安装插件：{plugin.Name} {plugin.Version}");
        }
        catch (Exception exception)
        {
            await new ContentDialog { XamlRoot = XamlRoot, Title = "插件安装失败", Content = exception.Message, CloseButtonText = "确定" }.ShowAsync();
        }
    }

    private async void Remove_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not PluginInfo plugin) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"卸载 {plugin.Name}？",
            Content = "将删除该插件的本机文件。",
            PrimaryButtonText = "卸载",
            CloseButtonText = "取消",
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        _service.Remove(plugin);
        App.Services.Settings.TranslateServiceOrder.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
        App.Services.Settings.EnabledTranslateServices.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
        await App.Services.SaveSettingsAsync();
        Reload();
        App.Services.Status.Report($"已卸载插件：{plugin.Name}");
    }

    private async void Configure_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not PluginInfo plugin) return;
        var current = _service.GetConfiguration(plugin);
        var controls = new Dictionary<string, Control>(StringComparer.Ordinal);
        var panel = new StackPanel { Spacing = 12, MinWidth = 460 };
        foreach (var field in plugin.Configuration)
        {
            panel.Children.Add(new TextBlock
            {
                Text = field.Required ? $"{field.Label} *" : field.Label,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            });
            Control control;
            if (field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase))
            {
                control = new PasswordBox
                {
                    PasswordRevealMode = PasswordRevealMode.Hidden,
                    PlaceholderText = string.IsNullOrWhiteSpace(current.GetValueOrDefault(field.Key))
                        ? "安全存储在 Windows Credential Manager"
                        : "已安全保存 · 留空则保留",
                };
            }
            else if (field.Type.Equals("select", StringComparison.OrdinalIgnoreCase) && field.Options.Count > 0)
            {
                var combo = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
                foreach (var option in field.Options)
                    combo.Items.Add(new ComboBoxItem { Content = option.Value, Tag = option.Key });
                var selected = current.GetValueOrDefault(field.Key) ?? field.DefaultValue;
                combo.SelectedItem = combo.Items.OfType<ComboBoxItem>().FirstOrDefault(item => (string)item.Tag == selected)
                    ?? combo.Items.FirstOrDefault();
                control = combo;
            }
            else
            {
                control = new TextBox { Text = current.GetValueOrDefault(field.Key) ?? field.DefaultValue ?? string.Empty };
            }
            controls[field.Key] = control;
            panel.Children.Add(control);
        }
        if (plugin.Configuration.Count == 0)
            panel.Children.Add(new TextBlock { Text = "此插件无需配置。" });
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"配置 {plugin.Name}",
            Content = new ScrollViewer { Content = panel, MaxHeight = 560 },
            PrimaryButtonText = "保存",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        var values = controls.ToDictionary(
            item => item.Key,
            item => item.Value switch
            {
                PasswordBox password => password.Password,
                ComboBox combo when combo.SelectedItem is ComboBoxItem option => (string)option.Tag,
                TextBox text => text.Text,
                _ => string.Empty,
            }, StringComparer.Ordinal);
        var missing = plugin.Configuration.Where(field => field.Required &&
            string.IsNullOrWhiteSpace(values.GetValueOrDefault(field.Key)) &&
            (!field.Type.Equals("secret", StringComparison.OrdinalIgnoreCase) ||
             string.IsNullOrWhiteSpace(current.GetValueOrDefault(field.Key)))).ToArray();
        if (missing.Length > 0)
        {
            await new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "配置不完整",
                Content = $"请填写：{string.Join("、", missing.Select(item => item.Label))}",
                CloseButtonText = "确定",
            }.ShowAsync();
            return;
        }
        _service.SaveConfiguration(plugin, values);
        Reload();
        App.Services.Status.Report($"已保存 {plugin.Name} 的配置");
    }

    private async void Test_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not PluginInfo plugin) return;
        App.Services.Status.Report($"正在测试 {plugin.Name}…", true);
        try
        {
            var result = await _service.TestConnectionAsync(plugin);
            App.Services.Status.Report($"{plugin.Name}：{result.StatusDisplay} · {result.Message}");
        }
        catch (Exception exception)
        {
            App.Services.Status.Report($"{plugin.Name} 测试失败：{exception.Message}");
        }
        Reload();
    }

    private async void Toggle_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not PluginInfo plugin) return;
        _service.SetEnabled(plugin, !plugin.Enabled);
        if (plugin.Enabled)
        {
            App.Services.Settings.EnabledTranslateServices.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
        }
        else
        {
            if (!App.Services.Settings.TranslateServiceOrder.Contains(plugin.ServiceId, StringComparer.OrdinalIgnoreCase))
                App.Services.Settings.TranslateServiceOrder.Insert(0, plugin.ServiceId);
            App.Services.Settings.EnabledTranslateServices.RemoveAll(id => id.Equals(plugin.ServiceId, StringComparison.OrdinalIgnoreCase));
            App.Services.Settings.EnabledTranslateServices.Add(plugin.ServiceId);
        }
        await App.Services.SaveSettingsAsync();
        Reload();
        App.Services.Status.Report($"{plugin.Name} 已{(plugin.Enabled ? "停用" : "启用")}");
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(App.Services.Store.PluginsDirectory);
        Process.Start(new ProcessStartInfo("explorer.exe", App.Services.Store.PluginsDirectory) { UseShellExecute = true });
    }
}
