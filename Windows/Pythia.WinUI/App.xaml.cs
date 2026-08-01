using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Pythia.Services;

namespace Pythia;

public partial class App : Application
{
    private Window? _window;

    public static AppServices Services { get; } = new();
    public static Window? MainAppWindow { get; private set; }

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
            if (update is not null)
            {
                Services.Status.Report($"发现新版本 {update.Tag}，可在“设置 → 关于与更新”中安装");
                (MainAppWindow as MainWindow)?.NotifyBackground("Pythia", $"发现新版本 {update.Tag}，可在设置中安装");
            }
        }
        catch
        {
            // Startup update checks are best effort and never block the application.
        }
    }

    private static void LogException(Exception exception)
    {
        try
        {
            File.AppendAllText(Path.Combine(Path.GetTempPath(), "Pythia-native.log"),
                $"[{DateTimeOffset.Now:O}] {exception}\r\n\r\n");
        }
        catch { }
    }
}
