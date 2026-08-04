using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Pythia.Controls;
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
    private bool _isCompactMode;
    private TranslationBatch? _lastBatch;

    public HomePage()
    {
        Services = App.Services;
        Results = [];
        _selectedServices = Services.Settings.ActiveServices.ToList();
        InitializeComponent();
        AppVersionText.Text = $"v{UpdateService.CurrentVersion.ToString(3)}";
        SourceLanguageBox.ItemsSource = LanguageOption.SourceLanguages;
        TargetLanguageBox.ItemsSource = LanguageOption.TargetLanguages;
        SourceLanguageBox.SelectedItem = LanguageOption.FindSource(Services.Settings.SourceLanguage);
        TargetLanguageBox.SelectedItem = LanguageOption.FindTarget(Services.Settings.TargetLanguage);
        UpdateServiceLabel();
        UpdatePinButtonVisual();
        Results.CollectionChanged += (_, _) =>
        {
            foreach (var result in Results)
            {
                result.ShowCollapse = !_isCompactMode;
                if (_isCompactMode) result.IsExpanded = true;
            }
            EmptyResultsText.Visibility = Results.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        };
        Unloaded += (_, _) =>
        {
            _translationCancellation?.Cancel();
            _translationCancellation?.Dispose();
            _translationCancellation = null;
        };
    }

    public AppServices Services { get; }
    public ObservableCollection<TranslationResult> Results { get; }

    public void SetCompactMode(bool compact)
    {
        _isCompactMode = compact;
        FullToolbar.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        SourcePanel.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        FullFooter.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        CompactHeader.Visibility = compact ? Visibility.Visible : Visibility.Collapsed;
        ResultsTitle.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        Grid.SetRow(ResultsPanel, compact ? 1 : 2);
        Grid.SetRowSpan(ResultsPanel, compact ? 3 : 1);
        WorkspaceRoot.Padding = compact ? new Thickness(8, 6, 8, 8) : new Thickness(32, 24, 32, 12);
        WorkspaceRoot.RowSpacing = compact ? 8 : 12;
        foreach (var result in Results)
        {
            result.ShowCollapse = !compact;
            if (compact) result.IsExpanded = true;
        }
    }

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
            _translationCancellation?.Dispose();
            _translationCancellation = null;
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
            HorizontalAlignment = HorizontalAlignment.Stretch,
            // SelectionMode.None: a selection competes with drag for pointer ownership on
            // WinUI 3 desktop; None lets the press start a reorder drag on the whole row.
            SelectionMode = ListViewSelectionMode.None,
            CanDragItems = true,
            CanReorderItems = true,
            AllowDrop = true,
            ReorderMode = ListViewReorderMode.Enabled,
        };
        ScrollViewer.SetVerticalScrollMode(list, ScrollMode.Enabled);
        ScrollViewer.SetVerticalScrollBarVisibility(list, ScrollBarVisibility.Auto);

        ListViewItem CreateRow(string id)
        {
            var row = new Grid { ColumnSpacing = 10, Padding = new Thickness(4, 2, 4, 2) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var handle = new SvgIcon { Icon = "reorder", VerticalAlignment = VerticalAlignment.Center };
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
            var item = new ListViewItem
            {
                Content = row,
                Tag = id,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                // Disable focus engagement so a press on the row starts a drag instead of
                // entering engage-focus, which otherwise blocks drag-start on desktop when
                // the row contains a focusable CheckBox.
                IsFocusEngagementEnabled = false,
            };
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
            if (!control || keyEvent.Key is not (VirtualKey.Up or VirtualKey.Down)) return;
            // SelectionMode.None: there is no SelectedIndex, so use the currently focused
            // ListViewItem container as the keyboard reorder anchor.
            var focused = Microsoft.UI.Xaml.Input.FocusManager.GetFocusedElement(XamlRoot) as ListViewItem;
            if (focused?.Tag is not string id) return;
            var index = list.Items.IndexOf(focused);
            if (index < 0) return;
            var target = Math.Clamp(index + (keyEvent.Key == VirtualKey.Up ? -1 : 1), 0, list.Items.Count - 1);
            if (target == index) return;
            list.Items.RemoveAt(index);
            list.Items.Insert(target, focused);
            focused.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
            keyEvent.Handled = true;
            await PersistServiceStateAsync(list, enabled);
        };
        var content = new Grid { RowSpacing = 8 };
        content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var guidance = new TextBlock
        {
            Text = "拖动左侧手柄排序；键盘可选中一行后按 Ctrl+↑ / Ctrl+↓。更改会立即保存。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        };
        content.Children.Add(guidance);
        Grid.SetRow(list, 1);
        content.Children.Add(list);

        void ResizeDialogContent()
        {
            // ContentDialog command/title areas consume part of the compact window.
            // Give the ListView an explicit bounded viewport so its internal
            // ScrollViewer receives finite height instead of being clipped by the
            // dialog's bottom command area.
            var rootWidth = XamlRoot?.Size.Width ?? ActualWidth;
            var rootHeight = XamlRoot?.Size.Height ?? ActualHeight;
            content.Width = Math.Clamp(rootWidth - 72, 260, 520);
            list.Height = Math.Clamp(rootHeight - 190, 96, 520);
        }
        ResizeDialogContent();
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "翻译服务与顺序",
            Content = content,
            CloseButtonText = "完成",
        };
        SizeChangedEventHandler resizeHandler = (_, _) => ResizeDialogContent();
        SizeChanged += resizeHandler;
        try
        {
            await dialog.ShowAsync();
            await PersistServiceStateAsync(list, enabled);
        }
        finally { SizeChanged -= resizeHandler; }
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

    private void UpdateServiceLabel()
    {
        var label = _selectedServices.Count switch
        {
        0 => "选择服务",
        1 => Services.TranslationServices.FirstOrDefault(item => item.Id == _selectedServices[0]).Name
            ?? ServiceCatalog.DisplayName(_selectedServices[0]),
        _ => $"{_selectedServices.Count} 个翻译服务",
        };
        ServiceButtonLabel.Text = label;
        CompactServiceButtonLabel.Text = $"服务 {_selectedServices.Count}";
    }

    private void ExpandCompact_Click(object sender, RoutedEventArgs e) =>
        (App.MainAppWindow as MainWindow)?.SetCompactPresentation(false);

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
                item.SourceText == _lastBatch.SourceText && item.TranslatedText == result.Text &&
                (item.Service == result.ServiceId || item.Service == result.ServiceName));
            if (record is null)
            {
                record = new HistoryRecord
                {
                    SourceText = _lastBatch.SourceText,
                    TranslatedText = result.Text,
                    SourceLanguage = _lastBatch.SourceLanguage,
                    TargetLanguage = _lastBatch.TargetLanguage,
                    Service = result.ServiceName,
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
        PinIcon.Icon = pinned ? "pin-off" : "pin";
        PinButton.Style = (Style)Application.Current.Resources[
            pinned ? "AccentButtonStyle" : "PythiaToolbarButtonStyle"];
        var label = pinned ? "取消窗口置顶（当前已置顶）" : "窗口置顶（当前未置顶）";
        ToolTipService.SetToolTip(PinButton, label);
        AutomationProperties.SetName(PinButton, label);
    }

    private async void RetryResult_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not TranslationResult result) return;
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
                if (OcrService.LastWarning is { } reason)
                    Services.Status.Report(OcrUnavailableException.Describe(reason));
                else Services.Status.Report("文字识别完成");
                if (Services.Settings.ScreenshotOcrAutoTranslate) await TranslateAsync();
            }
            else Services.Status.Report("图片中未识别到文字");
        }
        catch (OperationCanceledException) { Services.Status.Report("已取消 OCR"); }
        catch (OcrUnavailableException exception) { Services.Status.Report(exception.Message); }
        catch (Exception exception) { Services.Status.Report($"OCR 失败：{exception.Message}"); }
    }

    private void SourceTextBox_TextCompositionStarted(UIElement sender, TextCompositionStartedEventArgs args) =>
        _isTextCompositionActive = true;

    private void SourceTextBox_TextCompositionEnded(UIElement sender, TextCompositionEndedEventArgs args) =>
        _isTextCompositionActive = false;

    internal bool IsSelectionActionPoint(int clientX, int clientY)
    {
        if (SelectionTranslateButton.XamlRoot is null) return false;
        var origin = SelectionTranslateButton.TransformToVisual(null)
            .TransformPoint(new Windows.Foundation.Point());
        var scale = SelectionTranslateButton.XamlRoot.RasterizationScale;
        var x = clientX / scale;
        var y = clientY / scale;
        return x >= origin.X && x <= origin.X + SelectionTranslateButton.ActualWidth &&
               y >= origin.Y && y <= origin.Y + SelectionTranslateButton.ActualHeight;
    }

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
