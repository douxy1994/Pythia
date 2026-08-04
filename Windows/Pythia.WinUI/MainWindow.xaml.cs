using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pythia.Models;
using Pythia.Pages;
using Pythia.Services;
using Windows.Graphics;

namespace Pythia;

public sealed partial class MainWindow : Window
{
    private bool _initiallyPositioned;
    private readonly WindowsShellService? _shell;
    private readonly FloatingSelectionButtonService? _floatingSelectionButton;
    private CancellationTokenSource? _placementSaveDelay;
    private CancellationTokenSource? _blurHideDelay;
    private bool _selectionCaptureInProgress;
    private bool _compactPresentation;
    private RectInt32? _fullWindowBounds;
    private readonly IconSource? _fullTitleIconSource;
    private readonly IntPtr _windowHandle;

    public MainWindow()
    {
        InitializeComponent();
        _windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _fullTitleIconSource = AppTitleBar.IconSource;
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Title = "Pythia";
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        SelectionCaptureService.Initialize(_windowHandle);
        if (AppWindow.Presenter is OverlappedPresenter presenter)
            presenter.IsAlwaysOnTop = App.Services.Settings.AlwaysOnTop;
        var translateItem = NavView.MenuItems.OfType<NavigationViewItem>().First(item => (string)item.Tag == "translate");
        NavView.SelectedItem = translateItem;
        NavFrame.Navigate(typeof(HomePage));
        try
        {
            _shell = new WindowsShellService(this);
            _shell.IsSelectionActionPoint = IsSelectionActionPoint;
            _shell.HotkeyInvoked += Shell_HotkeyInvoked;
            _shell.ShowRequested += (_, _) => ShowWindow();
            _shell.TrayActionInvoked += Shell_TrayActionInvoked;
            App.Services.Notifications = new NotificationService(_shell.ShowBalloon, () => App.Services.Settings.NotificationsEnabled);
        }
        catch (Exception exception)
        {
            App.Services.Status.Report($"Windows 集成初始化失败：{exception.Message}");
        }
        try
        {
            _floatingSelectionButton = new FloatingSelectionButtonService(
                _windowHandle, DispatcherQueue, FloatingSelectionButton_Clicked);
            _floatingSelectionButton.SetEnabled(App.Services.Settings.ExperimentalFloatingSelectionButton);
        }
        catch (Exception exception)
        {
            App.Services.Settings.ExperimentalFloatingSelectionButton = false;
            App.Services.Status.Report($"悬浮划词按钮初始化失败：{exception.Message}");
        }
        Closed += (_, _) =>
        {
            _placementSaveDelay?.Cancel();
            _placementSaveDelay?.Dispose();
            _blurHideDelay?.Cancel();
            _blurHideDelay?.Dispose();
            SelectionCaptureService.Shutdown();
            _floatingSelectionButton?.Dispose();
            _shell?.Dispose();
        };
        Activated += async (_, args) =>
        {
            _blurHideDelay?.Cancel();
            WindowsIntegrationService.ApplyTheme(App.Services.Settings.ThemeMode);
            PositionInitialWindow();
            if (args.WindowActivationState == WindowActivationState.Deactivated &&
                App.Services.Settings.HideOnBlur && AppWindow.IsVisible &&
                !_selectionCaptureInProgress)
            {
                var delay = new CancellationTokenSource();
                _blurHideDelay = delay;
                try
                {
                    await Task.Delay(120, delay.Token);
                    if (App.Services.Settings.HideOnBlur && AppWindow.IsVisible) AppWindow.Hide();
                }
                catch (OperationCanceledException) { }
                finally
                {
                    if (ReferenceEquals(_blurHideDelay, delay))
                    {
                        _blurHideDelay = null;
                        delay.Dispose();
                    }
                }
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
                try
                {
                    await App.Services.SyncHistoryAsync();
                }
                catch (Exception exception)
                {
                    App.Services.Status.Report($"同步失败：{exception.Message}");
                    NotifyBackground("Pythia 历史同步", exception.Message, NotificationKind.Error);
                }
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
            ReportOcrWarning();
            if (string.IsNullOrWhiteSpace(text))
            {
                ShowWindow();
                App.Services.Status.Report("屏幕中未识别到文字");
                return;
            }
            await ShowHomeTextAsync(text, translate,
                translate && App.Services.Settings.CompactTranslationWindow);
        }
        catch (OperationCanceledException)
        {
            ShowWindow();
            App.Services.Status.Report("已取消截图识别");
        }
        catch (OcrUnavailableException exception)
        {
            ShowWindow();
            App.Services.Status.Report(exception.Message);
            // OCR is hotkey-triggered and the window may still be hidden — surface a balloon too.
            NotifyBackground("Pythia OCR", exception.Message, NotificationKind.Warning);
        }
        catch (Exception exception)
        {
            ShowWindow();
            App.Services.Status.Report($"截图识别失败：{exception.Message}");
        }
    }

    /// <summary>
    /// If the last OCR call fell back to a non-preferred language pack, tell the user
    /// (status bar + balloon when backgrounded) without blocking the recognized text.
    /// </summary>
    private void ReportOcrWarning()
    {
        if (OcrService.LastWarning is not { } reason) return;
        var message = OcrUnavailableException.Describe(reason);
        App.Services.Status.Report(message);
        NotifyBackground("Pythia OCR", message, NotificationKind.Warning);
    }

    public async Task TranslateSelectionAsync(bool forceCompact = false)
    {
        if (_selectionCaptureInProgress) return;
        _selectionCaptureInProgress = true;
        try
        {
            var captureRequest = await SelectionCaptureService.PrepareCaptureAsync();
            App.Services.Status.Report("正在读取选中文本…", true);
            // UIA selections are captured before any focus transition. Keep Pythia visible in
            // that path so clicking the selection button never produces a needless flash.
            // Clipboard-only applications still require returning focus before Ctrl+C.
            if (!captureRequest.HasCapturedText && AppWindow.IsVisible)
            {
                AppWindow.Hide();
                await Task.Delay(120);
            }
            SelectionCaptureResult selection;
            try { selection = await SelectionCaptureService.CaptureAsync(captureRequest); }
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
            await ShowHomeTextAsync(selection.Text!, true,
                forceCompact || App.Services.Settings.CompactTranslationWindow,
                new PointInt32(captureRequest.AnchorX, captureRequest.AnchorY));
        }
        finally
        {
            _selectionCaptureInProgress = false;
        }
    }

    public async Task ShowHomeTextAsync(
        string text,
        bool translate,
        bool compact = false,
        PointInt32? compactAnchor = null)
    {
        ShowWindow();
        var translateItem = NavView.MenuItems.OfType<NavigationViewItem>().First(item => (string)item.Tag == "translate");
        NavView.SelectedItem = translateItem;
        if (NavFrame.Content is not HomePage) NavFrame.Navigate(typeof(HomePage));
        await Task.Yield();
        SetCompactPresentation(compact, compactAnchor);
        if (NavFrame.Content is HomePage home) await home.LoadTextAsync(text, translate);
    }

    public void SetCompactPresentation(bool compact, PointInt32? anchor = null)
    {
        if (_compactPresentation == compact)
        {
            if (NavFrame.Content is HomePage current) current.SetCompactMode(compact);
            if (compact && anchor is not null) PlaceCompactWindow(anchor);
            return;
        }
        _compactPresentation = compact;
        AppTitleBar.Title = compact ? string.Empty : "Pythia";
        AppTitleBar.IconSource = compact ? null : _fullTitleIconSource;
        AppTitleBar.IsPaneToggleButtonVisible = !compact;
        TitleBarRow.Height = new GridLength(compact ? 32 : 48);
        AppWindow.TitleBar.PreferredHeightOption = compact
            ? TitleBarHeightOption.Standard
            : TitleBarHeightOption.Tall;
        NavView.PaneDisplayMode = compact
            ? NavigationViewPaneDisplayMode.LeftMinimal
            : NavigationViewPaneDisplayMode.LeftCompact;
        NavView.IsPaneOpen = false;
        foreach (var item in NavView.MenuItems.OfType<NavigationViewItem>())
            item.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        foreach (var item in NavView.FooterMenuItems.OfType<NavigationViewItem>())
            item.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        if (NavFrame.Content is HomePage home) home.SetCompactMode(compact);

        if (compact)
        {
            _fullWindowBounds = new RectInt32(AppWindow.Position.X, AppWindow.Position.Y,
                AppWindow.Size.Width, AppWindow.Size.Height);
            PlaceCompactWindow(anchor);
        }
        else if (_fullWindowBounds is { } bounds)
        {
            var display = DisplayArea.GetFromPoint(
                new PointInt32(bounds.X + bounds.Width / 2, bounds.Y + bounds.Height / 2),
                DisplayAreaFallback.Nearest);
            AppWindow.MoveAndResize(WindowPlacementPolicy.Clamp(bounds, display.WorkArea, 0));
            _fullWindowBounds = null;
        }
    }

    private void PlaceCompactWindow(PointInt32? anchor)
    {
        var display = anchor is { } point
            ? DisplayArea.GetFromPoint(point, DisplayAreaFallback.Nearest)
            : DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Nearest);
        var dpi = anchor is { } anchorPoint
            ? GetDpiForPoint(anchorPoint)
            : GetWindowDpi();
        AppWindow.MoveAndResize(WindowPlacementPolicy.CompactBounds(display.WorkArea, dpi, anchor));
    }

    public void ShowAndActivate()
    {
        if (!AppWindow.IsVisible) AppWindow.Show();
        if (_shell is not null) _shell.BringWindowToFront();
        else Activate();
    }

    private void ShowWindow() => ShowAndActivate();

    private bool IsSelectionActionPoint(int clientX, int clientY) =>
        NavFrame.Content is Pages.HomePage home && home.IsSelectionActionPoint(clientX, clientY);

    public async Task ShowSettingsAsync(string section = "general")
    {
        SetCompactPresentation(false);
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

    public bool TryApplyFloatingSelectionButton(bool enabled, out string? error)
    {
        if (_floatingSelectionButton is null)
        {
            error = enabled ? "悬浮划词服务未成功初始化" : null;
            return !enabled;
        }
        try
        {
            _floatingSelectionButton.SetEnabled(enabled);
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }

    private async void FloatingSelectionButton_Clicked(string? capturedText, PointInt32 anchor)
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(capturedText))
                await ShowHomeTextAsync(capturedText, true, true, anchor);
            else
                await TranslateSelectionAsync(true);
        }
        catch (Exception exception)
        {
            ShowWindow();
            App.Services.Status.Report($"悬浮划词失败：{exception.Message}");
        }
    }

    /// <summary>
    /// Fires a system balloon only when the Pythia window is not in the foreground,
    /// so events the user is already looking at do not produce a notification.
    /// Silently no-ops when the shell or notifier is unavailable.
    /// </summary>
    public void NotifyBackground(string title, string body, NotificationKind kind = NotificationKind.Info)
    {
        if (_shell is null || !_shell.IsWindowForeground())
            App.Services.Notifications?.Show(title, body, kind);
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
        var settings = App.Services.Settings;
        var hasPlacement = settings.WindowWidth > 0 && settings.WindowHeight > 0;
        var display = hasPlacement
            ? DisplayArea.GetFromPoint(new PointInt32(
                settings.WindowX + settings.WindowWidth / 2,
                settings.WindowY + settings.WindowHeight / 2), DisplayAreaFallback.Nearest)
            : DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var work = display.WorkArea;
        var saved = hasPlacement
            ? new RectInt32(settings.WindowX, settings.WindowY, settings.WindowWidth, settings.WindowHeight)
            : (RectInt32?)null;
        var targetDpi = GetDpiForPoint(new PointInt32(
            work.X + work.Width / 2, work.Y + work.Height / 2));
        AppWindow.MoveAndResize(WindowPlacementPolicy.FullBounds(
            work, saved, (uint)Math.Max(0, settings.WindowDpi), targetDpi));
    }

    private async void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!_initiallyPositioned || _compactPresentation ||
            (!args.DidPositionChange && !args.DidSizeChange)) return;
        App.Services.Settings.WindowX = sender.Position.X;
        App.Services.Settings.WindowY = sender.Position.Y;
        App.Services.Settings.WindowWidth = sender.Size.Width;
        App.Services.Settings.WindowHeight = sender.Size.Height;
        App.Services.Settings.WindowDpi = (int)GetWindowDpi();
        var delay = new CancellationTokenSource();
        var previous = Interlocked.Exchange(ref _placementSaveDelay, delay);
        previous?.Cancel();
        previous?.Dispose();
        try
        {
            await Task.Delay(500, delay.Token);
            await App.Services.Store.SaveSettingsAsync(App.Services.Settings);
        }
        catch (OperationCanceledException) { }
        catch (Exception exception)
        {
            App.Services.Status.Report($"窗口状态保存失败：{exception.Message}");
        }
        finally
        {
            if (ReferenceEquals(_placementSaveDelay, delay))
                _placementSaveDelay = null;
            delay.Dispose();
        }
    }

    private void TitleBar_PaneToggleRequested(TitleBar sender, object args) =>
        NavView.IsPaneOpen = !NavView.IsPaneOpen;

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var page = args.IsSettingsSelected ? typeof(SettingsPage) : (args.SelectedItem as NavigationViewItem)?.Tag switch
        {
            "translate" => typeof(HomePage),
            "history" => typeof(HistoryPage),
            "settings" => typeof(SettingsPage),
            _ => null,
        };
        if (page is not null && NavFrame.CurrentSourcePageType != page)
            NavFrame.Navigate(page);
    }

    private uint GetWindowDpi()
    {
        var dpi = GetDpiForWindow(_windowHandle);
        return dpi == 0 ? WindowPlacementPolicy.DefaultDpi : dpi;
    }

    private static uint GetDpiForPoint(PointInt32 point)
    {
        var monitor = MonitorFromPoint(new NativePoint(point.X, point.Y), 2);
        if (monitor != IntPtr.Zero && GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 && dpiX > 0)
            return dpiX;
        return WindowPlacementPolicy.DefaultDpi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativePoint(int x, int y)
    {
        public readonly int X = x;
        public readonly int Y = y;
    }

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(
        IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);

}
