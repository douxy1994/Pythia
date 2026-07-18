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
                    _window.AppWindow.Show();
                    _window.Activate();
                });
            };
            await Services.InitializeAsync();
            _window = new MainWindow();
            MainAppWindow = _window;
            _window.Activate();
        }
        catch (Exception exception)
        {
            LogException(exception);
            throw;
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
