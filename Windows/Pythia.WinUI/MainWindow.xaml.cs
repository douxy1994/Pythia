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
    private CancellationTokenSource? _placementSaveDelay;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Title = "Pythia";
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        SelectionCaptureService.Initialize(WinRT.Interop.WindowNative.GetWindowHandle(this));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
            presenter.IsAlwaysOnTop = App.Services.Settings.AlwaysOnTop;
        var translateItem = NavView.MenuItems.OfType<NavigationViewItem>().First(item => (string)item.Tag == "translate");
        NavView.SelectedItem = translateItem;
        NavFrame.Navigate(typeof(HomePage));
        try
        {
            _shell = new WindowsShellService(this);
            _shell.HotkeyInvoked += Shell_HotkeyInvoked;
            _shell.ShowRequested += (_, _) => ShowWindow();
            _shell.TrayActionInvoked += Shell_TrayActionInvoked;
        }
        catch (Exception exception)
        {
            App.Services.Status.Report($"Windows 集成初始化失败：{exception.Message}");
        }
        Closed += (_, _) => _shell?.Dispose();
        Activated += async (_, args) =>
        {
            WindowsIntegrationService.ApplyTheme(App.Services.Settings.ThemeMode);
            PositionInitialWindow();
            if (args.WindowActivationState == WindowActivationState.Deactivated &&
                App.Services.Settings.HideOnBlur && AppWindow.IsVisible)
            {
                await Task.Delay(120);
                if (App.Services.Settings.HideOnBlur) AppWindow.Hide();
            }
        };
        AppWindow.Changed += AppWindow_Changed;
    }

    private async void Shell_TrayActionInvoked(object? sender, PythiaTrayAction action)
    {
        switch (action)
        {
            case PythiaTrayAction.QuickTranslate:
                await ShowHomeTextAsync(string.Empty, false);
                App.Services.Status.Report("请输入需要翻译的文本");
                break;
            case PythiaTrayAction.History:
                ShowWindow();
                SelectNavigationItem("history");
                break;
            case PythiaTrayAction.Settings:
                await ShowSettingsAsync();
                break;
            case PythiaTrayAction.SyncHistory:
                ShowWindow();
                try { await App.Services.SyncHistoryAsync(); }
                catch { }
                break;
        }
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
                    await TranslateSelectionAsync();
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

    public async Task CaptureScreenTextAsync(bool translate)
    {
        AppWindow.Hide();
        try
        {
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
        catch (OperationCanceledException)
        {
            ShowWindow();
            App.Services.Status.Report("已取消截图识别");
        }
        catch (Exception exception)
        {
            ShowWindow();
            App.Services.Status.Report($"截图识别失败：{exception.Message}");
        }
    }

    public async Task TranslateSelectionAsync()
    {
        App.Services.Status.Report("正在读取选中文本…", true);
        if (AppWindow.IsVisible)
        {
            AppWindow.Hide();
            await Task.Delay(180);
        }
        SelectionCaptureResult selection;
        try { selection = await SelectionCaptureService.CaptureAsync(); }
        catch (Exception exception)
        {
            ShowWindow();
            App.Services.Status.Report($"划词翻译失败：{exception.Message}");
            return;
        }
        if (!selection.IsSuccess)
        {
            ShowWindow();
            App.Services.Status.Report(selection.Message);
            return;
        }
        await ShowHomeTextAsync(selection.Text!, true);
    }

    public async Task ShowHomeTextAsync(string text, bool translate)
    {
        ShowWindow();
        var translateItem = NavView.MenuItems.OfType<NavigationViewItem>().First(item => (string)item.Tag == "translate");
        NavView.SelectedItem = translateItem;
        if (NavFrame.Content is not HomePage) NavFrame.Navigate(typeof(HomePage));
        await Task.Yield();
        if (NavFrame.Content is HomePage home) await home.LoadTextAsync(text, translate);
    }

    public void ShowAndActivate()
    {
        AppWindow.Show();
        Activate();
    }

    private void ShowWindow() => ShowAndActivate();

    public async Task ShowSettingsAsync(string section = "general")
    {
        ShowAndActivate();
        await Task.Yield();
        NavView.SelectedItem = NavView.SettingsItem;
        if (NavFrame.CurrentSourcePageType != typeof(SettingsPage)) NavFrame.Navigate(typeof(SettingsPage));
        await Task.Yield();
        if (NavFrame.Content is SettingsPage settingsPage) settingsPage.SelectSection(section);
    }

    public bool TryApplyHotkeys(Pythia.Models.PythiaSettings settings, out string? error)
    {
        if (_shell is null)
        {
            error = null;
            return true;
        }
        return _shell.TryRegisterHotkeys(settings, out error);
    }

    public void ExitApplication()
    {
        if (_shell is not null) _shell.ExitApplication();
        else Close();
    }

    private void SelectNavigationItem(string tag)
    {
        var item = NavView.MenuItems.OfType<NavigationViewItem>().First(entry => (string)entry.Tag == tag);
        NavView.SelectedItem = item;
    }

    private void PositionInitialWindow()
    {
        if (_initiallyPositioned) return;
        _initiallyPositioned = true;
        var scale = (Content as FrameworkElement)?.XamlRoot?.RasterizationScale ?? 1;
        var settings = App.Services.Settings;
        var hasPlacement = settings.WindowWidth > 0 && settings.WindowHeight > 0;
        var display = hasPlacement
            ? DisplayArea.GetFromPoint(new PointInt32(
                settings.WindowX + settings.WindowWidth / 2,
                settings.WindowY + settings.WindowHeight / 2), DisplayAreaFallback.Nearest)
            : DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var work = display.WorkArea;
        var width = hasPlacement ? settings.WindowWidth : Math.Min((int)Math.Round(1180 * scale), (int)Math.Round(work.Width * 0.90));
        var height = hasPlacement ? settings.WindowHeight : Math.Min((int)Math.Round(780 * scale), (int)Math.Round(work.Height * 0.90));
        width = Math.Max(width, Math.Min(960, work.Width));
        height = Math.Max(height, Math.Min(680, work.Height));
        width = Math.Min(width, work.Width);
        height = Math.Min(height, work.Height);
        var x = hasPlacement ? Math.Clamp(settings.WindowX, work.X, work.X + work.Width - width) : work.X + (work.Width - width) / 2;
        var y = hasPlacement ? Math.Clamp(settings.WindowY, work.Y, work.Y + work.Height - height) : work.Y + (work.Height - height) / 2;
        AppWindow.MoveAndResize(new RectInt32(
            x, y, width, height));
    }

    private async void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!_initiallyPositioned || (!args.DidPositionChange && !args.DidSizeChange)) return;
        App.Services.Settings.WindowX = sender.Position.X;
        App.Services.Settings.WindowY = sender.Position.Y;
        App.Services.Settings.WindowWidth = sender.Size.Width;
        App.Services.Settings.WindowHeight = sender.Size.Height;
        _placementSaveDelay?.Cancel();
        _placementSaveDelay = new CancellationTokenSource();
        try
        {
            await Task.Delay(500, _placementSaveDelay.Token);
            await App.Services.Store.SaveSettingsAsync(App.Services.Settings);
        }
        catch (OperationCanceledException) { }
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
