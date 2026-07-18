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
            key.SetValue("Pythia", $"\"{Environment.ProcessPath}\" --startup", RegistryValueKind.String);
        else
            key.DeleteValue("Pythia", false);
    }
}
