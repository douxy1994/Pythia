using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Pythia.Models;
using Pythia.Services;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;

namespace Pythia.Pages;

public sealed partial class HomePage : Page
{
    private readonly List<string> _selectedServices;
    private CancellationTokenSource? _translationCancellation;

    public HomePage()
    {
        Services = App.Services;
        Results = [];
        _selectedServices = Services.Settings.ActiveServices.ToList();
        InitializeComponent();
        SourceLanguageBox.ItemsSource = LanguageOption.SourceLanguages;
        TargetLanguageBox.ItemsSource = LanguageOption.TargetLanguages;
        SourceLanguageBox.SelectedItem = LanguageOption.FindSource(Services.Settings.SourceLanguage);
        TargetLanguageBox.SelectedItem = LanguageOption.FindTarget(Services.Settings.TargetLanguage);
        UpdateServiceLabel();
        Results.CollectionChanged += (_, _) => EmptyResultsText.Visibility = Results.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    public AppServices Services { get; }
    public ObservableCollection<TranslationResult> Results { get; }

    public async Task LoadTextAsync(string text, bool translate)
    {
        SourceTextBox.Text = text;
        SourceTextBox.Focus(FocusState.Programmatic);
        Services.Status.Report("已读取文本");
        if (translate) await TranslateAsync();
    }

    private async void Translate_Click(object sender, RoutedEventArgs e) => await TranslateAsync();

    private async Task TranslateAsync()
    {
        if (string.IsNullOrWhiteSpace(SourceTextBox.Text))
        {
            Services.Status.Report("请输入需要翻译的文本");
            SourceTextBox.Focus(FocusState.Programmatic);
            return;
        }
        if (_selectedServices.Count == 0)
        {
            Services.Status.Report("请至少选择一个翻译服务");
            return;
        }

        _translationCancellation?.Cancel();
        _translationCancellation = new CancellationTokenSource();
        Services.Status.Report($"正在通过 {_selectedServices.Count} 个服务翻译…", true);
        Results.Clear();
        try
        {
            var batch = await Services.Translator.TranslateAsync(
                SourceTextBox.Text,
                ((LanguageOption)SourceLanguageBox.SelectedItem).Code,
                ((LanguageOption)TargetLanguageBox.SelectedItem).Code,
                _selectedServices,
                Services.Settings,
                _translationCancellation.Token);
            foreach (var result in batch.Results) Results.Add(result);
            await Services.AddHistoryAsync(batch);
            var successCount = batch.Results.Count(item => item.IsSuccess);
            Services.Status.Report(successCount > 0
                ? $"翻译完成 · {successCount}/{batch.Results.Count} 个服务成功"
                : "翻译失败，请检查服务设置");
        }
        catch (OperationCanceledException) { Services.Status.Report("已取消翻译"); }
        catch (Exception exception) { Services.Status.Report(exception.Message); }
    }

    private void ServiceButton_Click(object sender, RoutedEventArgs e)
    {
        var flyout = new MenuFlyout();
        foreach (var service in ServiceCatalog.All)
        {
            var item = new ToggleMenuFlyoutItem
            {
                Text = service.Name,
                Tag = service.Id,
                IsChecked = _selectedServices.Contains(service.Id),
            };
            item.Click += (_, _) =>
            {
                var id = (string)item.Tag;
                if (item.IsChecked && !_selectedServices.Contains(id)) _selectedServices.Add(id);
                if (!item.IsChecked) _selectedServices.Remove(id);
                Services.Settings.EnabledTranslateServices = _selectedServices.ToList();
                _ = Services.SaveSettingsAsync();
                UpdateServiceLabel();
            };
            flyout.Items.Add(item);
        }
        flyout.ShowAt(ServiceButton);
    }

    private void UpdateServiceLabel() => ServiceButtonLabel.Text = _selectedServices.Count switch
    {
        0 => "选择服务",
        1 => ServiceCatalog.DisplayName(_selectedServices[0]),
        _ => $"{_selectedServices.Count} 个翻译服务",
    };

    private async void Language_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SourceLanguageBox.SelectedItem is not LanguageOption source ||
            TargetLanguageBox.SelectedItem is not LanguageOption target) return;
        Services.Settings.SourceLanguage = source.Code;
        Services.Settings.TargetLanguage = target.Code;
        await Services.SaveSettingsAsync();
    }

    private void SwapLanguages_Click(object sender, RoutedEventArgs e)
    {
        var source = (LanguageOption)SourceLanguageBox.SelectedItem;
        var target = (LanguageOption)TargetLanguageBox.SelectedItem;
        SourceLanguageBox.SelectedItem = LanguageOption.FindSource(target.Code);
        TargetLanguageBox.SelectedItem = LanguageOption.FindTarget(source.Code == "auto" ? "en" : source.Code);
        if (Results.FirstOrDefault(item => item.IsSuccess) is { } first)
            SourceTextBox.Text = first.Text;
    }

    private async void Paste_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var content = Clipboard.GetContent();
            if (content.Contains(StandardDataFormats.Text))
                SourceTextBox.Text = await content.GetTextAsync();
        }
        catch { Services.Status.Report("无法读取剪贴板"); }
    }

    private async void SelectionTranslate_Click(object sender, RoutedEventArgs e)
    {
        Paste_Click(sender, e);
        await Task.Delay(50);
        if (!string.IsNullOrWhiteSpace(SourceTextBox.Text)) await TranslateAsync();
    }

    private void RemoveLineBreaks_Click(object sender, RoutedEventArgs e) =>
        SourceTextBox.Text = string.Join(" ", SourceTextBox.Text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).Select(item => item.Trim()));

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        SourceTextBox.Text = string.Empty;
        Results.Clear();
        Services.Status.Report("已清空");
    }

    private void CopyResult_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not TranslationResult result) return;
        var package = new DataPackage();
        package.SetText(result.DisplayText);
        Clipboard.SetContent(package);
        Services.Status.Report("译文已复制");
    }

    private async void OcrImage_Click(object sender, RoutedEventArgs e)
    {
        Services.Status.Report("正在打开图片…", true);
        try
        {
            var text = await OcrService.RecognizeFromFileAsync(this);
            if (!string.IsNullOrWhiteSpace(text))
            {
                SourceTextBox.Text = text;
                Services.Status.Report("文字识别完成");
                if (Services.Settings.ScreenshotOcrAutoTranslate) await TranslateAsync();
            }
            else Services.Status.Report("图片中未识别到文字");
        }
        catch (OperationCanceledException) { Services.Status.Report("已取消 OCR"); }
        catch (Exception exception) { Services.Status.Report($"OCR 失败：{exception.Message}"); }
    }

    private async void SourceTextBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        var ctrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        if (ctrl && e.Key == VirtualKey.Enter)
        {
            e.Handled = true;
            await TranslateAsync();
        }
    }
}
