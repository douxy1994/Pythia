using Microsoft.Win32;
using Microsoft.UI.Xaml;

namespace Pythia.Services;

public static class WindowsIntegrationService
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static void ApplyTheme(string mode)
    {
        if (App.MainAppWindow?.Content is not FrameworkElement root) return;
        root.RequestedTheme = mode switch
        {
            "light" => ElementTheme.Light,
            "dark" => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    public static void SetLaunchAtStartup(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled)
        {
            var processPath = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(processPath))
                throw new InvalidOperationException("无法确定 Pythia 当前程序路径，未写入开机启动项。");
            key.SetValue("Pythia", $"\"{processPath}\" --startup", RegistryValueKind.String);
        }
        else
            key.DeleteValue("Pythia", false);
    }
}
