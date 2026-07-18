using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pythia.Pages;
using Pythia.Services;
using Windows.Graphics;

namespace Pythia;

public sealed partial class MainWindow : Window
{
    private bool _initiallyPositioned;
    private readonly WindowsShellService? _shell;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Title = "Pythia";
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
            presenter.IsAlwaysOnTop = App.Services.Settings.AlwaysOnTop;
        NavFrame.Navigate(typeof(HomePage));
        try
        {
            _shell = new WindowsShellService(this);
            _shell.HotkeyInvoked += Shell_HotkeyInvoked;
            _shell.ShowRequested += (_, _) => ShowWindow();
        }
        catch (Exception exception)
        {
            App.Services.Status.Report($"Windows 集成初始化失败：{exception.Message}");
        }
        Closed += (_, _) => _shell?.Dispose();
        Activated += (_, _) =>
        {
            WindowsIntegrationService.ApplyTheme(App.Services.Settings.ThemeMode);
            PositionInitialWindow();
        };
    }

    private async void Shell_HotkeyInvoked(object? sender, PythiaHotkeyAction action)
    {
        try
        {
            switch (action)
            {
                case PythiaHotkeyAction.ShowWindow:
                    if (AppWindow.IsVisible) AppWindow.Hide(); else ShowWindow();
                    break;
                case PythiaHotkeyAction.SelectionTranslate:
                    App.Services.Status.Report("正在读取选中文本…", true);
                    var selection = await SelectionCaptureService.CaptureAsync();
                    if (string.IsNullOrWhiteSpace(selection))
                    {
                        ShowWindow();
                        App.Services.Status.Report("未读取到选中文本");
                    }
                    else await ShowHomeTextAsync(selection, true);
                    break;
                case PythiaHotkeyAction.ScreenshotTranslate:
                    await CaptureScreenTextAsync(true);
                    break;
                case PythiaHotkeyAction.ScreenshotOcr:
                    await CaptureScreenTextAsync(App.Services.Settings.ScreenshotOcrAutoTranslate);
                    break;
            }
        }
        catch (Exception exception)
        {
            ShowWindow();
            App.Services.Status.Report($"快捷操作失败：{exception.Message}");
        }
    }

    private async Task CaptureScreenTextAsync(bool translate)
    {
        AppWindow.Hide();
        await Task.Delay(250);
        var text = await OcrService.RecognizeScreenAsync();
        if (string.IsNullOrWhiteSpace(text))
        {
            ShowWindow();
            App.Services.Status.Report("屏幕中未识别到文字");
            return;
        }
        await ShowHomeTextAsync(text, translate);
    }

    private async Task ShowHomeTextAsync(string text, bool translate)
    {
        ShowWindow();
        var translateItem = NavView.MenuItems.OfType<NavigationViewItem>().First(item => (string)item.Tag == "translate");
        NavView.SelectedItem = translateItem;
        if (NavFrame.Content is not HomePage) NavFrame.Navigate(typeof(HomePage));
        await Task.Yield();
        if (NavFrame.Content is HomePage home) await home.LoadTextAsync(text, translate);
    }

    private void ShowWindow()
    {
        AppWindow.Show();
        Activate();
    }

    private void PositionInitialWindow()
    {
        if (_initiallyPositioned) return;
        _initiallyPositioned = true;
        var scale = (Content as FrameworkElement)?.XamlRoot?.RasterizationScale ?? 1;
        var display = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var work = display.WorkArea;
        var width = Math.Min((int)Math.Round(1180 * scale), (int)Math.Round(work.Width * 0.90));
        var height = Math.Min((int)Math.Round(780 * scale), (int)Math.Round(work.Height * 0.90));
        width = Math.Max(width, Math.Min(960, work.Width));
        height = Math.Max(height, Math.Min(680, work.Height));
        AppWindow.MoveAndResize(new RectInt32(
            work.X + (work.Width - width) / 2,
            work.Y + (work.Height - height) / 2,
            width,
            height));
    }

    private void TitleBar_PaneToggleRequested(TitleBar sender, object args) =>
        NavView.IsPaneOpen = !NavView.IsPaneOpen;

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var page = args.IsSettingsSelected ? typeof(SettingsPage) : (args.SelectedItem as NavigationViewItem)?.Tag switch
        {
            "translate" => typeof(HomePage),
            "history" => typeof(HistoryPage),
            "plugins" => typeof(PluginsPage),
            "about" => typeof(AboutPage),
            _ => null,
        };
        if (page is not null && NavFrame.CurrentSourcePageType != page)
            NavFrame.Navigate(page);
    }

}
