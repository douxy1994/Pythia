using System.Collections.ObjectModel;
using System.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Pythia.Models;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;

namespace Pythia.Pages;

public sealed partial class HistoryPage : Page
{
    public HistoryPage()
    {
        FilteredHistory = [];
        InitializeComponent();
        App.Services.History.CollectionChanged += History_CollectionChanged;
        Refresh();
        Unloaded += (_, _) => App.Services.History.CollectionChanged -= History_CollectionChanged;
    }

    public ObservableCollection<HistoryRecord> FilteredHistory { get; }

    private void History_CollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e) => Refresh();
    private void SearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) => Refresh();
    private void FavoritesOnly_Click(object sender, RoutedEventArgs e) => Refresh();

    private void Refresh()
    {
        if (SearchBox is null) return;
        var query = SearchBox.Text.Trim();
        var records = App.Services.History.Where(record =>
            (!FavoritesOnlyButton.IsChecked.GetValueOrDefault() || record.IsFavorite) &&
            (query.Length == 0 || record.SourceText.Contains(query, StringComparison.CurrentCultureIgnoreCase) ||
             record.TranslatedText.Contains(query, StringComparison.CurrentCultureIgnoreCase) ||
             record.ServiceDisplayName.Contains(query, StringComparison.CurrentCultureIgnoreCase)));
        FilteredHistory.Clear();
        foreach (var record in records) FilteredHistory.Add(record);
        EmptyState.Visibility = FilteredHistory.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        CountText.Text = $"显示 {FilteredHistory.Count} 条 · 共 {App.Services.History.Count} 条";
    }

    private async void Favorite_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not HistoryRecord record) return;
        record.IsFavorite = !record.IsFavorite;
        await App.Services.SaveHistoryAsync();
        Refresh();
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not HistoryRecord record) return;
        var package = new DataPackage();
        package.SetText(record.TranslatedText);
        Clipboard.SetContent(package);
        App.Services.Status.Report("译文已复制");
    }

    private async void Delete_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is HistoryRecord record)
            await App.Services.DeleteHistoryAsync(record);
    }

    private async void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        if (App.Services.History.Count == 0) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "清空历史记录？",
            Content = "此操作会删除本机全部翻译历史，且无法撤销。",
            PrimaryButtonText = "清空",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            await App.Services.ClearHistoryAsync();
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileSavePicker { SuggestedFileName = $"Pythia-history-{DateTime.Now:yyyyMMdd}" };
        picker.FileTypeChoices.Add("CSV 文件", [".csv"]);
        if (App.MainAppWindow is null) return;
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(App.MainAppWindow));
        var file = await picker.PickSaveFileAsync();
        if (file is null) return;
        var builder = new StringBuilder("时间,翻译服务,原文,译文\r\n");
        foreach (var record in App.Services.History)
            builder.AppendLine($"{Csv(record.CreatedDisplay)},{Csv(record.ServiceDisplayName)},{Csv(record.SourceText)},{Csv(record.TranslatedText)}");
        await File.WriteAllTextAsync(file.Path, builder.ToString(), new UTF8Encoding(true));
        App.Services.Status.Report($"已导出 {App.Services.History.Count} 条历史记录");
    }

    private static string Csv(string value) => $"\"{value.Replace("\"", "\"\"")}\"";
}
