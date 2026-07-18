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

    private async void ServiceButton_Click(object sender, RoutedEventArgs e)
    {
        var available = Services.TranslationServices
            .DistinctBy(item => item.Id, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(item => item.Id, item => item.Name, StringComparer.OrdinalIgnoreCase);
        var ordered = Services.Settings.TranslateServiceOrder
            .Where(available.ContainsKey)
            .Concat(available.Keys.Where(id => !Services.Settings.TranslateServiceOrder.Contains(id, StringComparer.OrdinalIgnoreCase)))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        var enabled = new HashSet<string>(_selectedServices, StringComparer.OrdinalIgnoreCase);
        var rows = new StackPanel { Spacing = 6 };

        void RebuildRows()
        {
            rows.Children.Clear();
            for (var index = 0; index < ordered.Count; index++)
            {
                var id = ordered[index];
                var row = new Grid { ColumnSpacing = 8 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var check = new CheckBox
                {
                    Content = available[id],
                    IsChecked = enabled.Contains(id),
                    VerticalAlignment = VerticalAlignment.Center,
                };
                check.Checked += (_, _) => enabled.Add(id);
                check.Unchecked += (_, _) => enabled.Remove(id);
                row.Children.Add(check);

                var capturedIndex = index;
                var up = new Button
                {
                    Content = new FontIcon { Glyph = "\uE70E" },
                    IsEnabled = index > 0,
                    Style = (Style)Application.Current.Resources["PythiaToolbarButtonStyle"],
                };
                ToolTipService.SetToolTip(up, "上移");
                up.Click += (_, _) =>
                {
                    (ordered[capturedIndex - 1], ordered[capturedIndex]) = (ordered[capturedIndex], ordered[capturedIndex - 1]);
                    RebuildRows();
                };
                Grid.SetColumn(up, 1);
                row.Children.Add(up);

                var down = new Button
                {
                    Content = new FontIcon { Glyph = "\uE70D" },
                    IsEnabled = index < ordered.Count - 1,
                    Style = (Style)Application.Current.Resources["PythiaToolbarButtonStyle"],
                };
                ToolTipService.SetToolTip(down, "下移");
                down.Click += (_, _) =>
                {
                    (ordered[capturedIndex + 1], ordered[capturedIndex]) = (ordered[capturedIndex], ordered[capturedIndex + 1]);
                    RebuildRows();
                };
                Grid.SetColumn(down, 2);
                row.Children.Add(down);
                rows.Children.Add(row);
            }
        }

        RebuildRows();
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "翻译服务与顺序",
            Content = new ScrollViewer { Content = rows, MaxHeight = 520, MinWidth = 430 },
            PrimaryButtonText = "保存",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        Services.Settings.TranslateServiceOrder = ordered;
        Services.Settings.EnabledTranslateServices = ordered.Where(enabled.Contains).ToList();
        _selectedServices.Clear();
        _selectedServices.AddRange(Services.Settings.EnabledTranslateServices);
        await Services.SaveSettingsAsync();
        UpdateServiceLabel();
    }

    private void UpdateServiceLabel() => ServiceButtonLabel.Text = _selectedServices.Count switch
    {
        0 => "选择服务",
        1 => Services.TranslationServices.FirstOrDefault(item => item.Id == _selectedServices[0]).Name
            ?? ServiceCatalog.DisplayName(_selectedServices[0]),
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
        if (App.MainAppWindow is MainWindow window) await window.TranslateSelectionAsync();
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

    private async void RetryResult_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not TranslationResult result || !result.IsPlugin) return;
        var index = Results.IndexOf(result);
        if (index < 0 || string.IsNullOrWhiteSpace(SourceTextBox.Text)) return;
        Services.Status.Report($"正在重试 {result.ServiceName}…", true);
        try
        {
            var batch = await Services.Translator.TranslateAsync(
                SourceTextBox.Text,
                ((LanguageOption)SourceLanguageBox.SelectedItem).Code,
                ((LanguageOption)TargetLanguageBox.SelectedItem).Code,
                [result.ServiceId],
                Services.Settings);
            Results[index] = batch.Results[0];
            await Services.AddHistoryAsync(batch);
            Services.Status.Report(batch.Results[0].IsSuccess
                ? $"{result.ServiceName} 重试成功"
                : $"{result.ServiceName} 重试失败");
        }
        catch (Exception exception) { Services.Status.Report(exception.Message); }
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
        var shift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        if (!shift && e.Key == VirtualKey.Enter)
        {
            e.Handled = true;
            await TranslateAsync();
        }
    }
}
