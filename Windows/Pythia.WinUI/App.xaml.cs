using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Pythia.Services;
using System.Text.RegularExpressions;

namespace Pythia;

public partial class App : Application
{
    private Window? _window;

    public static AppServices Services { get; } = new();
    public static Window? MainAppWindow { get; private set; }
    public static PythiaUpdateInfo? PendingUpdate { get; private set; }
    public static event EventHandler? UpdateAvailable;

    public static void SetPendingUpdate(PythiaUpdateInfo? update)
    {
        PendingUpdate = update;
        UpdateAvailable?.Invoke(null, EventArgs.Empty);
    }

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, args) =>
        {
            Services.Status.Report($"未处理错误：{args.Exception.Message}");
            LogException(args.Exception);
        };
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            var startupArguments = Environment.GetCommandLineArgs()
                .Concat(StartupRequest.Tokenize(args.Arguments));
            var startupRequest = StartupRequest.Parse(startupArguments);
            var current = AppInstance.GetCurrent();
            var primary = AppInstance.FindOrRegisterForKey("Pythia.Windows.Native");
            if (!primary.IsCurrent)
            {
                await primary.RedirectActivationToAsync(current.GetActivatedEventArgs());
                Environment.Exit(0);
                return;
            }
            primary.Activated += (_, _) =>
            {
                _window?.DispatcherQueue.TryEnqueue(() =>
                {
                    if (_window is MainWindow mainWindow) mainWindow.ShowAndActivate();
                    else
                    {
                        _window.AppWindow.Show();
                        _window.Activate();
                    }
                });
            };
            await Services.InitializeAsync();
            _window = new MainWindow();
            MainAppWindow = _window;
            var mainWindow = (MainWindow)_window;
            mainWindow.ShowAndActivate();
            if (startupRequest.SettingsSection is not null)
                await mainWindow.ShowSettingsAsync(startupRequest.SettingsSection);
            else if (startupRequest.SourceText is not null)
                await mainWindow.ShowHomeTextAsync(startupRequest.SourceText, false);
            if (Services.Settings.CheckForUpdatesOnStartup) _ = CheckForStartupUpdateAsync();
        }
        catch (Exception exception)
        {
            LogException(exception);
            throw;
        }
    }

    private static async Task CheckForStartupUpdateAsync()
    {
        try
        {
            var update = await UpdateService.CheckAsync();
            SetPendingUpdate(update);
            if (update is not null)
            {
                Services.Status.Report($"发现新版本 {update.Tag}，可在“设置 → 关于”中安装");
                (MainAppWindow as MainWindow)?.NotifyBackground("Pythia", $"发现新版本 {update.Tag}，请在“设置 → 关于”中点击更新");
            }
        }
        catch
        {
            // Startup update checks are best effort and never block the application, but
            // leave a non-sensitive status trail instead of becoming a silent failure.
            Services.Status.Report("启动更新检查失败，请稍后在设置中手动检查。");
        }
    }

    private static void LogException(Exception exception)
    {
        try
        {
            var safeMessage = Regex.Replace(
                exception.Message.Replace("\r", " ").Replace("\n", " "),
                @"(?i)(bearer|api[-_ ]?key|access[-_ ]?token|secret|password)\s*[:=]\s*[^\s;,]+",
                "$1=[REDACTED]");
            File.AppendAllText(Path.Combine(Path.GetTempPath(), "Pythia-native.log"),
                $"[{DateTimeOffset.Now:O}] {exception.GetType().FullName}: {safeMessage}\r\n");
        }
        catch { }
    }
}
