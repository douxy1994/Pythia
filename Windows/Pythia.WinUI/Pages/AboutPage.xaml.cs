using System.Reflection;
using Microsoft.UI.Xaml.Controls;

namespace Pythia.Pages;

public sealed partial class AboutPage : Page
{
    public AboutPage()
    {
        InitializeComponent();
        VersionText.Text = $"版本 {Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0"}";
        DataPathText.Text = App.Services.Store.DataDirectory;
    }
}
