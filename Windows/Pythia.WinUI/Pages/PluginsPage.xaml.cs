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
    private readonly PluginService _service = new(App.Services.Store);

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
        Reload();
        App.Services.Status.Report($"已卸载插件：{plugin.Name}");
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(App.Services.Store.PluginsDirectory);
        Process.Start(new ProcessStartInfo("explorer.exe", App.Services.Store.PluginsDirectory) { UseShellExecute = true });
    }
}
