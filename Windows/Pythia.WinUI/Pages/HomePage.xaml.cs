using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
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
    private readonly SemaphoreSlim _serviceSaveGate = new(1, 1);
    private readonly HomeSubmissionGate _submissionGate = new();
    private CancellationTokenSource? _translationCancellation;
    private bool _isTextCompositionActive;
    private TranslationBatch? _lastBatch;

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
        UpdatePinButtonVisual();
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

        if (!_submissionGate.TryEnter())
        {
            Services.Status.Report("翻译正在进行，请稍候");
            return;
        }

        _translationCancellation = new CancellationTokenSource();
        TranslateButton.IsEnabled = false;
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
            if (((LanguageOption)TargetLanguageBox.SelectedItem).Code != batch.TargetLanguage)
                TargetLanguageBox.SelectedItem = LanguageOption.FindTarget(batch.TargetLanguage);
            _lastBatch = batch;
            foreach (var result in batch.Results) Results.Add(result);
            await Services.AddHistoryAsync(batch);
            var successCount = batch.Results.Count(item => item.IsSuccess);
            Services.Status.Report(successCount > 0
                ? $"翻译完成 · {successCount}/{batch.Results.Count} 个服务成功"
                : "翻译失败，请检查服务设置");
        }
        catch (OperationCanceledException) { Services.Status.Report("已取消翻译"); }
        catch (Exception exception) { Services.Status.Report(exception.Message); }
        finally
        {
            TranslateButton.IsEnabled = true;
            _submissionGate.Exit();
        }
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
        var list = new ListView
        {
            MinWidth = 430,
            MaxHeight = 520,
            SelectionMode = ListViewSelectionMode.Single,
            CanDragItems = true,
            CanReorderItems = true,
            AllowDrop = true,
            ReorderMode = ListViewReorderMode.Enabled,
        };

        ListViewItem CreateRow(string id)
        {
            var row = new Grid { ColumnSpacing = 10, Padding = new Thickness(4, 2, 4, 2) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var handle = new SymbolIcon { Symbol = Symbol.Bullets, VerticalAlignment = VerticalAlignment.Center };
            AutomationProperties.SetName(handle, $"拖动调整 {available[id]} 的顺序");
            row.Children.Add(handle);
            var check = new CheckBox
            {
                Content = available[id],
                IsChecked = enabled.Contains(id),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(check, 1);
            row.Children.Add(check);
            var item = new ListViewItem { Content = row, Tag = id, HorizontalContentAlignment = HorizontalAlignment.Stretch };
            check.Checked += async (_, _) => { enabled.Add(id); await PersistServiceStateAsync(list, enabled); };
            check.Unchecked += async (_, _) => { enabled.Remove(id); await PersistServiceStateAsync(list, enabled); };
            return item;
        }

        foreach (var id in ordered) list.Items.Add(CreateRow(id));
        list.DragItemsCompleted += async (_, _) => await PersistServiceStateAsync(list, enabled);
        list.KeyDown += async (_, keyEvent) =>
        {
            var control = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control)
                .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
            if (!control || list.SelectedIndex < 0 || keyEvent.Key is not (VirtualKey.Up or VirtualKey.Down)) return;
            var target = list.SelectedIndex + (keyEvent.Key == VirtualKey.Up ? -1 : 1);
            if (target < 0 || target >= list.Items.Count) return;
            var selected = list.SelectedItem;
            list.Items.RemoveAt(list.SelectedIndex);
            list.Items.Insert(target, selected);
            list.SelectedIndex = target;
            keyEvent.Handled = true;
            await PersistServiceStateAsync(list, enabled);
        };
        var content = new StackPanel { Spacing = 8 };
        content.Children.Add(new TextBlock
        {
            Text = "拖动左侧手柄排序；键盘可选中一行后按 Ctrl+↑ / Ctrl+↓。更改会立即保存。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        });
        content.Children.Add(list);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "翻译服务与顺序",
            Content = content,
            CloseButtonText = "完成",
        };
        await dialog.ShowAsync();
        await PersistServiceStateAsync(list, enabled);
    }

    private async Task PersistServiceStateAsync(ListView list, HashSet<string> enabled)
    {
        await _serviceSaveGate.WaitAsync();
        try
        {
            var order = list.Items.OfType<ListViewItem>().Select(item => (string)item.Tag).ToList();
            Services.Settings.TranslateServiceOrder = order;
            Services.Settings.EnabledTranslateServices = order.Where(enabled.Contains).ToList();
            _selectedServices.Clear();
            _selectedServices.AddRange(Services.Settings.EnabledTranslateServices);
            await Services.SaveSettingsAsync();
            UpdateServiceLabel();
        }
        finally { _serviceSaveGate.Release(); }
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

    private void CopySource_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(SourceTextBox.Text))
        {
            Services.Status.Report("原文为空");
            return;
        }
        var package = new DataPackage();
        package.SetText(SourceTextBox.Text);
        Clipboard.SetContent(package);
        Services.Status.Report("原文已复制");
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

    private async void ScreenshotTranslate_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainAppWindow is MainWindow window) await window.CaptureScreenTextAsync(true);
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

    private void ToggleResult_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is TranslationResult result) result.IsExpanded = !result.IsExpanded;
    }

    private void CopyAll_Click(object sender, RoutedEventArgs e)
    {
        var text = string.Join("\n\n", Results.Where(item => item.IsSuccess)
            .Select(item => $"{item.ServiceName}\n{item.Text}"));
        if (string.IsNullOrWhiteSpace(text))
        {
            Services.Status.Report("没有可复制的译文");
            return;
        }
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
        Services.Status.Report("已复制全部译文");
    }

    private async void FavoriteResults_Click(object sender, RoutedEventArgs e)
    {
        if (_lastBatch is null || Results.All(item => !item.IsSuccess))
        {
            Services.Status.Report("没有可收藏的翻译结果");
            return;
        }
        var changed = 0;
        foreach (var result in Results.Where(item => item.IsSuccess))
        {
            var record = Services.History.FirstOrDefault(item =>
                item.SourceText == _lastBatch.SourceText && item.TranslatedText == result.Text && item.Service == result.ServiceId);
            if (record is null)
            {
                record = new HistoryRecord
                {
                    SourceText = _lastBatch.SourceText,
                    TranslatedText = result.Text,
                    SourceLanguage = _lastBatch.SourceLanguage,
                    TargetLanguage = _lastBatch.TargetLanguage,
                    Service = result.ServiceId,
                    Model = result.Model,
                    DeviceId = Services.DeviceId,
                    IsFavorite = true,
                    SyncStatus = Services.Settings.WebdavHistoryAutoSync ? "pendingUpload" : "local",
                };
                Services.AddVisibleHistoryRecord(record);
                changed++;
            }
            else if (!record.IsFavorite)
            {
                record.IsFavorite = true;
                record.UpdatedAt = DateTimeOffset.UtcNow;
                record.SyncStatus = Services.Settings.WebdavHistoryAutoSync ? "pendingUpload" : "local";
                changed++;
            }
        }
        if (changed > 0) await Services.SaveHistoryAsync();
        Services.Status.Report(changed > 0 ? $"已收藏 {changed} 条译文" : "本次译文已收藏");
    }

    private async void Speak_Click(object sender, RoutedEventArgs e)
    {
        var text = Results.FirstOrDefault(item => item.IsSuccess)?.Text;
        if (string.IsNullOrWhiteSpace(text))
        {
            Services.Status.Report("没有可朗读的译文");
            return;
        }
        Services.Status.Report("正在朗读译文…", true);
        try
        {
            await SpeechService.SpeakAsync(text);
            Services.Status.Report("朗读完成");
        }
        catch (Exception exception) { Services.Status.Report($"朗读失败：{exception.Message}"); }
    }

    private async void PinButton_Click(object sender, RoutedEventArgs e)
    {
        Services.Settings.AlwaysOnTop = !Services.Settings.AlwaysOnTop;
        if (App.MainAppWindow?.AppWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter presenter)
            presenter.IsAlwaysOnTop = Services.Settings.AlwaysOnTop;
        await Services.SaveSettingsAsync();
        UpdatePinButtonVisual();
        Services.Status.Report(Services.Settings.AlwaysOnTop ? "窗口已置顶" : "已取消窗口置顶");
    }

    private void UpdatePinButtonVisual()
    {
        var pinned = Services.Settings.AlwaysOnTop;
        PinIcon.Symbol = pinned ? Symbol.UnPin : Symbol.Pin;
        PinButton.Style = (Style)Application.Current.Resources[
            pinned ? "AccentButtonStyle" : "PythiaToolbarButtonStyle"];
        var label = pinned ? "取消窗口置顶（当前已置顶）" : "窗口置顶（当前未置顶）";
        ToolTipService.SetToolTip(PinButton, label);
        AutomationProperties.SetName(PinButton, label);
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

    private void SourceTextBox_TextCompositionStarted(UIElement sender, TextCompositionStartedEventArgs args) =>
        _isTextCompositionActive = true;

    private void SourceTextBox_TextCompositionEnded(UIElement sender, TextCompositionEndedEventArgs args) =>
        _isTextCompositionActive = false;

    private async void SourceTextBox_PreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        var shift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        var action = HomeInteractionPolicy.ResolveEnter(
            e.Key == VirtualKey.Enter,
            shift,
            _isTextCompositionActive,
            e.KeyStatus.WasKeyDown || e.KeyStatus.RepeatCount > 1);
        if (action == HomeInputAction.Submit)
        {
            e.Handled = true;
            await TranslateAsync();
        }
    }
}
