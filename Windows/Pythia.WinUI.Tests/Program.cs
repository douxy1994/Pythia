using System.Text.Json;
using System.IO.Compression;
using Windows.Globalization;
using Windows.Graphics;
using Pythia.Models;
using Pythia.Services;

var failures = new List<string>();

string? FindNodeForTests()
{
    var candidates = new[]
    {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "nodejs", "node.exe"),
    }.Concat((Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
        .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Select(path => Path.Combine(path.Trim('"'), "node.exe")));
    return candidates.FirstOrDefault(File.Exists);
}

void Check(bool condition, string message)
{
    if (!condition) failures.Add(message);
}

string? FindRepositoryFile(string relativePath)
{
    foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
    {
        var directory = new DirectoryInfo(start);
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, relativePath);
            if (File.Exists(candidate)) return candidate;
            directory = directory.Parent;
        }
    }
    return null;
}

if (args.Length >= 2 && args[0] == "--install-repo-plugins")
{
    var packageDirectory = Path.GetFullPath(args[1]);
    var runConnectivity = args.Contains("--connectivity", StringComparer.OrdinalIgnoreCase);
    var store = new LocalStore();
    var service = new PluginService(store, new CredentialStore(), FindNodeForTests());
    await service.InitializeAsync();
    var installed = new List<PluginInfo>();
    foreach (var package in Directory.EnumerateFiles(packageDirectory, "*.pythia").OrderBy(Path.GetFileName))
    {
        var plugin = service.Install(package);
        installed.Add(plugin);
        Console.WriteLine($"已安装\t{plugin.Name}\t{plugin.Version}");
    }
    service.MigrateLegacyPotConfigurations();
    installed = service.LoadInstalled().ToList();
    var maintenanceSettings = await store.LoadSettingsAsync();
    var pluginIds = installed.Select(item => item.ServiceId).ToList();
    maintenanceSettings.TranslateServiceOrder = pluginIds
        .Concat(maintenanceSettings.TranslateServiceOrder.Where(id => !pluginIds.Contains(id, StringComparer.OrdinalIgnoreCase)))
        .ToList();
    maintenanceSettings.EnabledTranslateServices = pluginIds
        .Concat(maintenanceSettings.EnabledTranslateServices.Where(id => !pluginIds.Contains(id, StringComparer.OrdinalIgnoreCase)))
        .ToList();
    await store.SaveSettingsAsync(maintenanceSettings);

    if (runConnectivity)
    {
        foreach (var plugin in installed)
        {
            try
            {
                var result = await service.TestConnectionAsync(plugin);
                Console.WriteLine($"连通性\t{plugin.Name}\t{result.StatusDisplay}\t尝试 {result.Attempts} 次\t{result.Duration.TotalSeconds:F1} 秒");
            }
            catch (Exception exception)
            {
                Console.WriteLine($"连通性\t{plugin.Name}\t测试中止\t{exception.GetType().Name}");
            }
        }
    }
    return 0;
}

if (args.Length >= 3 && args[0] == "--translate-plugin")
{
    Console.OutputEncoding = System.Text.Encoding.UTF8;
    var serviceId = args[1];
    var sourceText = args[2];
    var store = new LocalStore();
    var service = new PluginService(store, new CredentialStore(), FindNodeForTests());
    await service.InitializeAsync();
    var translated = await service.TranslateAsync(serviceId, sourceText, "en", "zh-CN");
    Console.WriteLine(translated);
    return 0;
}

Check(LanguageOption.FindSource("auto").Name == "自动检测", "source language lookup");
Check(LanguageOption.FindTarget("zh-CN").Name == "简体中文", "target language lookup");

var settings = new PythiaSettings
{
    EnabledTranslateServices = ["deepl", "google"],
    TranslateServiceOrder = ["google", "deepl"],
};
Check(settings.ActiveServices.SequenceEqual(["google", "deepl"]), "service ordering");
Check(HomeInteractionPolicy.ResolveEnter(true, false, false, false) == HomeInputAction.Submit, "Enter submits");
Check(HomeInteractionPolicy.ResolveEnter(true, true, false, false) == HomeInputAction.InsertLineBreak, "Shift+Enter line break");
Check(HomeInteractionPolicy.ResolveEnter(true, false, true, false) == HomeInputAction.None, "IME composing Enter is ignored");
Check(HomeInteractionPolicy.ResolveEnter(true, false, false, true) == HomeInputAction.None, "repeated Enter is ignored");
var homePageXamlPath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Pages", "HomePage.xaml"));
var homePageXaml = homePageXamlPath is null ? string.Empty : File.ReadAllText(homePageXamlPath);
var homePageSourcePath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Pages", "HomePage.xaml.cs"));
var homePageSource = homePageSourcePath is null ? string.Empty : File.ReadAllText(homePageSourcePath);
Check(homePageXaml.Contains("PreviewKeyDown=\"SourceTextBox_PreviewKeyDown\"", StringComparison.Ordinal) &&
      !homePageXaml.Contains("KeyDown=\"SourceTextBox_KeyDown\"", StringComparison.Ordinal),
    "real HomePage TextBox intercepts Enter before multiline handling");
Check(homePageXaml.Contains("PlaceholderText=\"输入或粘贴原文… Enter 翻译 · Shift + Enter 换行\"", StringComparison.Ordinal) &&
      !homePageXaml.Contains("Text=\"Enter 翻译 · Shift + Enter 换行\"", StringComparison.Ordinal) &&
      !homePageXaml.Contains("PythiaPageTitleStyle", StringComparison.Ordinal) &&
      homePageXaml.Contains("Icon=\"text-select\"", StringComparison.Ordinal) &&
      homePageXaml.Contains("Icon=\"expand\"", StringComparison.Ordinal) &&
      homePageXaml.Contains("Icon=\"crop\"", StringComparison.Ordinal) &&
      homePageXaml.Contains("PythiaResultIconButtonStyle", StringComparison.Ordinal) &&
      homePageXaml.Contains("x:Name=\"AppVersionText\"", StringComparison.Ordinal),
    "home uses in-field guidance, a title-free compact toolbar, SVG actions, and a bottom version label");
Check(homePageXaml.Contains("Style=\"{StaticResource PythiaHomeSectionTitleStyle}\" Text=\"原文\"", StringComparison.Ordinal) &&
      homePageXaml.Contains("Margin=\"18,0,0,0\" Style=\"{StaticResource PythiaHomeSectionTitleStyle}\" Text=\"译文\"", StringComparison.Ordinal),
    "source and translation labels share the aligned blue title style");
Check(homePageXaml.Contains("x:Name=\"PinIcon\"", StringComparison.Ordinal),
    "pin action exposes a stateful icon");
var settingsPageXamlPath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Pages", "SettingsPage.xaml"));
var settingsPageXaml = settingsPageXamlPath is null ? string.Empty : File.ReadAllText(settingsPageXamlPath);
var llmCardIndex = settingsPageXaml.IndexOf("Header=\"大模型翻译服务\"", StringComparison.Ordinal);
var googleCardIndex = settingsPageXaml.IndexOf("Header=\"Google 翻译\"", StringComparison.Ordinal);
Check(settingsPageXaml.Contains("Tag=\"plugins\"", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("PluginSettingsPanel", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("Tag=\"about\"", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("InstallUpdate_Click", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("OpenGitHub_Click", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("GitHubMark.svg", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("AGPL-3.0", StringComparison.Ordinal) &&
      !settingsPageXaml.Contains("保存全部设置", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("TextWrapping=\"Wrap\"", StringComparison.Ordinal),
    "Settings owns plugin/About pages, auto-saves, and exposes GitHub/update/license actions");
Check(llmCardIndex >= 0 && googleCardIndex > llmCardIndex &&
      settingsPageXaml.Contains("x:Name=\"OpenAiApiBox\"", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("Header=\"划词翻译或截图 OCR 翻译时默认打开简约窗口\"", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("x:Name=\"FloatingSelectionButtonSwitch\"", StringComparison.Ordinal) &&
      settingsPageXaml.Contains("实验功能：选中文字后显示悬浮翻译按钮", StringComparison.Ordinal),
    "large-model service is first and compact/floating selection settings are exposed");
Check(homePageXaml.Contains("x:Name=\"CompactHeader\"", StringComparison.Ordinal) &&
      homePageXaml.Contains("x:Name=\"CompactServiceButtonLabel\"", StringComparison.Ordinal) &&
      homePageXaml.Contains("x:Name=\"ResultsPanel\"", StringComparison.Ordinal) &&
      homePageXaml.Contains("Click=\"CopyResult_Click\"", StringComparison.Ordinal),
    "compact translation keeps synchronized service selection and result copy actions");
Check(homePageSource.Contains("ScrollViewer.SetVerticalScrollMode(list, ScrollMode.Enabled)", StringComparison.Ordinal) &&
      homePageSource.Contains("list.Height = Math.Clamp(rootHeight - 190, 96, 520)", StringComparison.Ordinal) &&
      homePageSource.Contains("SizeChanged += resizeHandler", StringComparison.Ordinal) &&
      homePageSource.Contains("SizeChanged -= resizeHandler", StringComparison.Ordinal),
    "service picker keeps a bounded scrolling viewport inside the compact window and follows resize");
var mainWindowXamlPath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "MainWindow.xaml"));
var mainWindowXaml = mainWindowXamlPath is null ? string.Empty : File.ReadAllText(mainWindowXamlPath);
Check(!mainWindowXaml.Contains("Tag=\"plugins\"", StringComparison.Ordinal) &&
      !mainWindowXaml.Contains("Tag=\"about\"", StringComparison.Ordinal) &&
      mainWindowXaml.Contains("Title=\"Pythia\"", StringComparison.Ordinal) &&
      mainWindowXaml.Contains("IsPaneOpen=\"False\"", StringComparison.Ordinal) &&
      mainWindowXaml.Contains("PaneDisplayMode=\"LeftCompact\"", StringComparison.Ordinal) &&
      !mainWindowXaml.Contains("Subtitle=", StringComparison.Ordinal),
    "main sidebar defaults collapsed, excludes Plugins, keeps About in Settings, and uses the Pythia-only title");
var selectionServicePath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Services", "SelectionCaptureService.cs"));
var selectionServiceSource = selectionServicePath is null ? string.Empty : File.ReadAllText(selectionServicePath);
var mainWindowSourcePath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "MainWindow.xaml.cs"));
var mainWindowSource = mainWindowSourcePath is null ? string.Empty : File.ReadAllText(mainWindowSourcePath);
Check(mainWindowXaml.Contains("x:Name=\"TitleBarRow\"", StringComparison.Ordinal) &&
      mainWindowSource.Contains("TitleBarHeightOption.Standard", StringComparison.Ordinal) &&
      mainWindowSource.Contains("NavigationViewPaneDisplayMode.LeftMinimal", StringComparison.Ordinal) &&
      homePageSource.Contains("new Thickness(8, 6, 8, 8)", StringComparison.Ordinal),
    "compact presentation removes the navigation gutter and prioritizes result space");
var selectionMethodStart = mainWindowSource.IndexOf("public async Task TranslateSelectionAsync", StringComparison.Ordinal);
var selectionMethodSource = selectionMethodStart >= 0 ? mainWindowSource[selectionMethodStart..] : string.Empty;
Check(selectionServiceSource.Contains("WaitForModifierReleaseAsync", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("GetAsyncKeyState", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("Task.Delay(attempt", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("Size = 32", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("GetGUIThreadInfo", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("SetFocus(focusedWindow)", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("ReadSelectionFromWindow(target)", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("ReadSelectionBoundedAsync", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("WaitAsync(TimeSpan.FromMilliseconds", StringComparison.Ordinal) &&
      !selectionServiceSource.Contains("TreeScope.Subtree", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("HasCapturedText", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("BeginCaptureBeforePythiaActivation", StringComparison.Ordinal) &&
      selectionServiceSource.Contains("CopySelectionWhileSourceIsForeground", StringComparison.Ordinal) &&
      selectionServiceSource.IndexOf("CopySelectionWhileSourceIsForeground();", StringComparison.Ordinal) >= 0 &&
      selectionServiceSource.Contains("ClipboardFirstProcessNames", StringComparison.Ordinal) &&
      SelectionCaptureService.IsClipboardFirstProcessName("wps") &&
      SelectionCaptureService.IsClipboardFirstProcessName("WPSPDF") &&
      !SelectionCaptureService.IsClipboardFirstProcessName("notepad") &&
      selectionServiceSource.Contains("!request.PrefersClipboardCapture", StringComparison.Ordinal) &&
      mainWindowSource.Contains("IsSelectionActionPoint", StringComparison.Ordinal) &&
      selectionMethodSource.IndexOf("PrepareCaptureAsync()", StringComparison.Ordinal) >= 0 &&
      selectionMethodSource.IndexOf("PrepareCaptureAsync()", StringComparison.Ordinal) < selectionMethodSource.IndexOf("AppWindow.Hide()", StringComparison.Ordinal) &&
      selectionMethodSource.Contains("!captureRequest.HasCapturedText", StringComparison.Ordinal),
    "selection capture snapshots UIA or clipboard text before mouse activation, avoids a full UIA subtree, and keeps the native x64 clipboard fallback");

Check(WindowPlacementPolicy.DipToPixels(680, 96) == 680 &&
      WindowPlacementPolicy.DipToPixels(680, 144) == 1020 &&
      WindowPlacementPolicy.DipToPixels(680, 192) == 1360,
    "window policy converts logical sizes at 100, 150, and 200 percent DPI");
var compact4k = WindowPlacementPolicy.CompactBounds(new RectInt32(0, 0, 3840, 2080), 192);
Check(compact4k.Width == 1360 && compact4k.Height == 860,
    "compact window preserves its logical size on a 200 percent 4K display");
var compactSmall = WindowPlacementPolicy.CompactBounds(new RectInt32(0, 0, 800, 560), 192);
Check(compactSmall.X >= 0 && compactSmall.Y >= 0 &&
      compactSmall.X + compactSmall.Width <= 800 && compactSmall.Y + compactSmall.Height <= 560,
    "compact window shrinks inside a small display work area");
var compactNegativeMonitor = WindowPlacementPolicy.CompactBounds(
    new RectInt32(-1920, 0, 1920, 1040), 96, new PointInt32(-100, 100));
Check(compactNegativeMonitor.X >= -1920 && compactNegativeMonitor.Y >= 0 &&
      compactNegativeMonitor.X + compactNegativeMonitor.Width <= 0 &&
      compactNegativeMonitor.Y + compactNegativeMonitor.Height <= 1040,
    "compact window stays on a left-hand monitor with negative virtual coordinates");
var rescaledFull = WindowPlacementPolicy.FullBounds(
    new RectInt32(0, 0, 2560, 1400), new RectInt32(100, 100, 1180, 780), 96, 144);
Check(rescaledFull.Width == 1770 && rescaledFull.Height == 1170,
    "saved full window size follows the destination monitor DPI");
var legacyFull = WindowPlacementPolicy.FullBounds(
    new RectInt32(0, 0, 1920, 1040), new RectInt32(100, 100, 1180, 780), 0, 144);
Check(legacyFull.Width == 1440 && legacyFull.Height == 1020,
    "legacy physical window bounds remain compatible while respecting new DPI minimums");
Check(!new PythiaSettings().ExperimentalFloatingSelectionButton &&
      FloatingSelectionButtonPolicy.IsSelectionDrag(
          new PointInt32(10, 10), new PointInt32(20, 10), 100) &&
      !FloatingSelectionButtonPolicy.IsSelectionDrag(
          new PointInt32(10, 10), new PointInt32(12, 11), 100) &&
      !FloatingSelectionButtonPolicy.IsSelectionDrag(
          new PointInt32(10, 10), new PointInt32(20, 10), 20),
    "experimental floating button defaults off and ignores clicks or implausibly fast drags");
Check(FloatingSelectionButtonPolicy.SupportsDragFallback("WINWORD") &&
      FloatingSelectionButtonPolicy.SupportsDragFallback("AcroRd32") &&
      FloatingSelectionButtonPolicy.SupportsDragFallback("msedge") &&
      FloatingSelectionButtonPolicy.SupportsDragFallback("WeChat") &&
      !FloatingSelectionButtonPolicy.SupportsDragFallback("explorer"),
    "floating button fallback covers Word, PDF, web, and chat apps without enabling arbitrary drags");
var floatingServicePath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Services", "FloatingSelectionButtonService.cs"));
var floatingServiceSource = floatingServicePath is null ? string.Empty : File.ReadAllText(floatingServicePath);
Check(floatingServiceSource.Contains("WsExNoActivate", StringComparison.Ordinal) &&
      floatingServiceSource.Contains("AppIcon.ico", StringComparison.Ordinal) &&
      floatingServiceSource.Contains("TimeSpan.FromSeconds(5)", StringComparison.Ordinal) &&
      floatingServiceSource.Contains("TryReadSelectionForFloatingButtonAsync", StringComparison.Ordinal) &&
      mainWindowSource.Contains("TranslateSelectionAsync(true)", StringComparison.Ordinal),
    "floating Pythia icon is non-activating, auto-dismisses, probes UIA first, and forces compact translation on click");
var pluginPanelPath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Pages", "PluginSettingsPanel.xaml"));
var pluginPanelXaml = pluginPanelPath is null ? string.Empty : File.ReadAllText(pluginPanelPath);
Check(pluginPanelXaml.Contains("Expanding=\"PluginExpander_Expanding\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("CanReorderItems=\"True\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("FlowDirection=\"RightToLeft\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("HorizontalAlignment=\"Stretch\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("Click=\"OpenGuide_Click\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("Click=\"OpenExistingPlugins_Click\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("x:Name=\"PluginEnabledSwitch\"", StringComparison.Ordinal) &&
      !pluginPanelXaml.Contains("x:Name=\"TogglePluginButton\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("x:Name=\"PluginStatusHost\"", StringComparison.Ordinal) &&
      pluginPanelXaml.Contains("CountdownRing", StringComparison.Ordinal),
    "plugin settings use aligned left-chevron rows, unified enable switch, guide and existing-plugin actions, and timed status feedback");
var pluginPanelSourcePath = FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Pages", "PluginSettingsPanel.xaml.cs"));
var pluginPanelSource = pluginPanelSourcePath is null ? string.Empty : File.ReadAllText(pluginPanelSourcePath);
var testConnectionStart = pluginPanelSource.IndexOf("private async void TestConnection_Click", StringComparison.Ordinal);
var testConnectionSource = testConnectionStart >= 0 ? pluginPanelSource[testConnectionStart..] : string.Empty;
Check(testConnectionSource.IndexOf("finally", StringComparison.Ordinal) >= 0 &&
      !testConnectionSource[..Math.Min(testConnectionSource.Length, 1200)].Contains("Reload(plugin.Id)", StringComparison.Ordinal),
    "plugin connectivity test keeps the expanded configuration panel open");
var homeAlignment = homePageXaml.Contains("PythiaAccentButtonStyle", StringComparison.Ordinal) &&
                    homePageXaml.Contains("x:Name=\"SwapLanguagesGlyph\"", StringComparison.Ordinal) &&
                    !homePageXaml.Contains("Margin=\"0,20,0,0\" Style=\"{StaticResource AccentButtonStyle}\"", StringComparison.Ordinal);
Check(homeAlignment, "home action buttons share the aligned control style");
var startupSettingsRequest = StartupRequest.Parse(["Pythia.exe", "--settings", "plugins"]);
var startupTextRequest = StartupRequest.Parse(["Pythia.exe", "--text=hello"]);
var winUiStartupRequest = StartupRequest.Parse(["--settings", "plugins"]);
Check(startupSettingsRequest.SettingsSection == "plugins" && startupSettingsRequest.SourceText is null,
    "startup settings route");
Check(startupTextRequest.SourceText == "hello" && startupTextRequest.SettingsSection is null,
    "startup source-text route");
Check(winUiStartupRequest.SettingsSection == "plugins", "WinUI launch arguments without executable route correctly");
Check(StartupRequest.Tokenize("--settings plugins --text \"hello world\"")
        .SequenceEqual(["--settings", "plugins", "--text", "hello world"]),
    "WinUI activation argument tokenizer preserves quoted text");
var submissionGate = new HomeSubmissionGate();
Check(submissionGate.TryEnter() && !submissionGate.TryEnter() && submissionGate.IsEntered,
    "duplicate translation submission is rejected while busy");
submissionGate.Exit();
Check(submissionGate.TryEnter(), "translation submission gate reopens after completion");
submissionGate.Exit();
Check(HomeInteractionPolicy.MoveService(["a", "b", "c"], 0, 2).SequenceEqual(["b", "c", "a"]), "service reorder first to last");
Check(HomeInteractionPolicy.MoveService(["a", "b", "c"], 2, 0).SequenceEqual(["c", "a", "b"]), "service reorder last to first");
Check(HomeInteractionPolicy.MoveService(["a", "b"], -1, 1).SequenceEqual(["a", "b"]), "cancelled service reorder is stable");
Check(HomeInteractionPolicy.MergeBuiltInEnabled(
    ["plugin:one", "google", "plugin:two"], ["deepl"]).SequenceEqual(["plugin:one", "plugin:two", "deepl"]),
    "settings preserve enabled plugins");
Check(TranslationCoordinator.ResolveLanguages("今天天气很好", "auto", "zh-CN") == ("auto", "en"),
    "pure Chinese auto-routes to English");
Check(TranslationCoordinator.ResolveLanguages("The weather is good", "auto", "en") == ("auto", "zh-CN"),
    "pure English auto-routes to Chinese");
Check(TranslationCoordinator.ResolveLanguages("今天 weather forecast", "auto", "en") == ("zh-CN", "en") &&
      TranslationCoordinator.ResolveLanguages("今天 weather forecast", "auto", "zh-CN") == ("en", "zh-CN"),
    "balanced Chinese and English respects selected target");
Check(TranslationCoordinator.ResolveLanguages(
          "这是一段以中文为主的说明，其中包含 API、HTTP 和 WinUI 等英文缩写。", "auto", "zh-CN") == ("zh-CN", "en"),
    "Chinese-dominant text with English acronyms auto-routes to English");
Check(TranslationCoordinator.ResolveLanguages(
          "This paragraph is predominantly English but includes 少量中文 terms and API names.", "auto", "en") == ("en", "zh-CN"),
    "English-dominant text with a little Chinese auto-routes to Chinese");
Check(TranslationCoordinator.CustomLlmEndpoint("https://api.openai.com/v1", "openai")?.AbsoluteUri ==
      "https://api.openai.com/v1/chat/completions", "OpenAI custom endpoint normalization");
Check(TranslationCoordinator.CustomLlmEndpoint("https://api.anthropic.com/v1/messages", "anthropic")?.AbsoluteUri ==
      "https://api.anthropic.com/v1/messages", "Anthropic custom endpoint normalization");
using var anthropicResponse = JsonDocument.Parse("""{"content":[{"type":"text","text":"你好"}]}""");
using var openAiResponse = JsonDocument.Parse("""{"choices":[{"message":{"content":"你好"}}]}""");
Check(TranslationCoordinator.CustomLlmContent(anthropicResponse.RootElement, "anthropic") == "你好" &&
      TranslationCoordinator.CustomLlmContent(openAiResponse.RootElement, "openai") == "你好",
    "custom LLM response extraction supports Anthropic Messages and OpenAI Chat Completions");
var longLlmText = new string('x', 1797) + "6.02e-23" + new string('y', 120);
var longLlmChunks = TranslationCoordinator.CustomLlmChunks(longLlmText);
Check(longLlmChunks.Count == 2 && string.Concat(longLlmChunks) == longLlmText &&
      longLlmChunks[1].StartsWith("6.02e-23", StringComparison.Ordinal),
    "custom LLM long-text chunks preserve scientific notation and exact input");
var surrogateLlmText = new string('x', 1799) + "😀" + new string('y', 50);
var surrogateLlmChunks = TranslationCoordinator.CustomLlmChunks(surrogateLlmText);
Check(string.Concat(surrogateLlmChunks) == surrogateLlmText &&
      surrogateLlmChunks.All(chunk => chunk.Length == 0 || !char.IsHighSurrogate(chunk[^1])),
    "custom LLM long-text chunks do not split Unicode surrogate pairs");
Check(TranslationCoordinator.IsRetryableCustomLlmStatus(408) &&
      TranslationCoordinator.IsRetryableCustomLlmStatus(429) &&
      TranslationCoordinator.IsRetryableCustomLlmStatus(503) &&
      !TranslationCoordinator.IsRetryableCustomLlmStatus(400) &&
      !TranslationCoordinator.IsRetryableCustomLlmStatus(401),
    "custom LLM retry policy only retries transient upstream responses");
Check(PluginService.ClassifyConnectionFailure("AUTHENTICATION_FAILED", "HTTP 401") == PluginConnectionStatus.InvalidCredential,
    "plugin invalid credential classification");
Check(PluginService.ClassifyConnectionFailure("MODEL_NOT_FOUND", "model unavailable") == PluginConnectionStatus.ModelUnavailable,
    "plugin model classification");
Check(PluginService.ClassifyConnectionFailure("NETWORK_ERROR", "ENOTFOUND") == PluginConnectionStatus.NetworkUnreachable,
    "plugin network classification");
Check(PluginService.ClassifyConnectionFailure("TIMEOUT", "timed out") == PluginConnectionStatus.Timeout,
    "plugin timeout classification");
Check(PluginService.ClassifyConnectionFailure("NETWORK_ERROR", "HTTP Status: 502") == PluginConnectionStatus.UpstreamError,
    "plugin upstream classification");
Check(PluginService.ClassifyConnectionFailure("INVALID_RESPONSE", "invalid JSON") == PluginConnectionStatus.ProtocolIncompatible,
    "plugin protocol classification");
Check(PluginService.ClassifyConnectionFailure("PROCESS_EXITED", "crashed", true) == PluginConnectionStatus.ProcessAbnormalExit,
    "plugin process classification");
Check(IconSemantics.Actions.Count >= 25 && IconSemantics.Actions.Values.All(item =>
        !string.IsNullOrWhiteSpace(item.Resource) && !string.IsNullOrWhiteSpace(item.AccessibleName) &&
        FindRepositoryFile(Path.Combine("Windows", "Pythia.WinUI", "Assets", "FluentIcons", $"{item.Resource}.svg")) is not null),
    "semantic icon mapping resolves to packaged Fluent SVG resources");
Check(IconSemantics.Actions["plugin.toggle"].Resource == "checkmark",
    "plugin enable state uses an SVG checkmark semantic");
var expectedHomeIcons = new Dictionary<string, string>
{
    ["home.services"] = "sort",
    ["home.pin"] = "pin",
    ["home.swapLanguages"] = "swap",
    ["home.translate"] = "send",
    ["home.copySource"] = "copy",
    ["home.paste"] = "paste",
    ["home.removeLineBreaks"] = "text-align-left",
    ["home.clear"] = "delete",
    ["home.selection"] = "text-select",
    ["home.screenshot"] = "crop",
    ["home.ocrImage"] = "image",
    ["home.copyAll"] = "copy",
    ["home.favorite"] = "star",
    ["home.speak"] = "speaker",
};
Check(expectedHomeIcons.All(expected => IconSemantics.Actions.TryGetValue(expected.Key, out var actual) &&
        actual.Resource == expected.Value),
    "home actions keep exact SVG resource semantics");
Check(SpeechService.NormalizeText("  hello  ") == "hello" && SpeechService.NormalizeText("   ").Length == 0,
    "speech input normalization");
var syncTime = DateTimeOffset.Parse("2026-07-18T00:00:00Z");
var timestampStableFavorite = new HistoryRecord { UpdatedAt = syncTime };
timestampStableFavorite.IsFavorite = true;
Check(timestampStableFavorite.UpdatedAt == syncTime,
    "history deserialization-safe favorite setter preserves timestamps");
var localSyncRecord = new HistoryRecord
{
    Id = "same",
    SourceText = "old",
    TranslatedText = "旧",
    UpdatedAt = syncTime,
    CreatedAt = syncTime,
};
var remoteSyncRecord = new HistoryRecord
{
    Id = "same",
    SourceText = "new",
    TranslatedText = "新",
    UpdatedAt = syncTime.AddMinutes(1),
    CreatedAt = syncTime,
};
var newestMerge = HistorySyncService.Merge([localSyncRecord], [remoteSyncRecord]);
Check(newestMerge.Records.Single().SourceText == "new" && newestMerge.Records.Single().SyncStatus == "synced",
    "history sync newest update wins");
var deletionRecord = HistorySyncService.Clone(localSyncRecord);
deletionRecord.DeletedAt = syncTime.AddMinutes(-1);
deletionRecord.UpdatedAt = syncTime.AddMinutes(-1);
var deletionMerge = HistorySyncService.Merge([remoteSyncRecord], [deletionRecord]);
Check(deletionMerge.Records.Single().DeletedAt is not null && deletionMerge.Records.Single().SyncStatus == "pendingDelete",
    "history tombstone wins across devices");
var conflictRight = HistorySyncService.Clone(localSyncRecord);
conflictRight.SourceText = "conflict";
var conflictMerge = HistorySyncService.Merge([localSyncRecord], [conflictRight]);
Check(conflictMerge.ConflictCount == 1 && conflictMerge.Records.Single().SyncStatus == "conflict",
    "history sync marks equal-time content conflicts");
var portableSettings = new PythiaSettings
{
    SourceLanguage = "en",
    TargetLanguage = "zh-CN",
    EnabledTranslateServices = ["google"],
    TranslateServiceOrder = ["google"],
    OpenAICompatibleApi = "anthropic",
    CompactTranslationWindow = true,
    ExperimentalFloatingSelectionButton = true,
    WebdavUrl = "https://private.example.invalid/dav",
    WebdavUsername = "private-user",
};
var portableJson = PortableBackupService.Create(portableSettings, [localSyncRecord]);
Check(!portableJson.Contains("private.example", StringComparison.Ordinal) &&
      !portableJson.Contains("private-user", StringComparison.Ordinal) &&
      !portableJson.Contains("apiKey", StringComparison.OrdinalIgnoreCase),
    "portable backup omits credentials and WebDAV identity");
var portableRestore = PortableBackupService.Restore(portableJson, []);
Check(portableRestore.ImportedCount == 1 && portableRestore.Records.Single().SyncStatus == "pendingUpload",
    "portable backup restores mergeable pending history");
Check(portableRestore.Settings.OpenAICompatibleAPI == "anthropic" &&
      portableRestore.Settings.CompactTranslationWindow &&
      portableRestore.Settings.ExperimentalFloatingSelectionButton,
    "portable backup preserves non-secret compact-window, floating-button, and custom-API settings");
Check(AppServices.GetSyncInterval(new PythiaSettings
{ WebdavHistorySyncIntervalValue = 2, WebdavHistorySyncIntervalUnit = "week" }) == TimeSpan.FromDays(14),
    "WebDAV week schedule");
Check(WebDavService.NormalizeRootUrl("https://example.invalid/dav").AbsoluteUri ==
      "https://example.invalid/dav/Pythia/", "WebDAV root normalization");
Check(WindowsShellService.TryParseHotkey("Ctrl+Alt+P", out var parsedModifiers, out var parsedKey) &&
      parsedModifiers != 0 && parsedKey == (uint)'P', "hotkey parser accepts recorded shortcut");
Check(!WindowsShellService.TryParseHotkey("P", out _, out _),
    "hotkey parser rejects unmodified keys");
Check(UpdateService.TryParseVersion("v1.2.3", out var updateVersion) && updateVersion == new Version(1, 2, 3) &&
      UpdateService.TryParseVersion("2.0.0-beta.1", out var previewVersion) && previewVersion == new Version(2, 0, 0),
    "update version parser");
Check(UpdateService.ExpectedInstallerName(new Version(1, 2, 3)) == "Pythia-1.2.3-windows-x64.exe",
    "updater selects the exact Pythia Windows x64 asset");
Check(ScreenRegionSelector.NormalizeSelection(new System.Drawing.Point(120, 90), new System.Drawing.Point(20, 10)) ==
      new System.Drawing.Rectangle(20, 10, 100, 80), "screenshot reverse drag geometry");

// --- P0: system notification gating + de-dupe ---------------------------------------------
var notificationCalls = new List<NotifyBalloon>();
bool NotificationEnabled() => true;
var notifier = new NotificationService(b => { notificationCalls.Add(b); return true; }, NotificationEnabled);
notifier.Show("Pythia", "hello", NotificationKind.Info);
notifier.Show("Pythia", "hello", NotificationKind.Info); // identical — must be suppressed
Check(notificationCalls.Count == 1 && notificationCalls[0].Body == "hello",
    "notification de-duplicates identical back-to-back balloons");
notifier.Show("Pythia", "different", NotificationKind.Warning);
Check(notificationCalls.Count == 2 && notificationCalls[1].Kind == NotificationKind.Warning,
    "notification forwards distinct balloons with their kind");
var disabledCalls = new List<NotifyBalloon>();
var disabledNotifier = new NotificationService(b => { disabledCalls.Add(b); return true; }, () => false);
disabledNotifier.Show("Pythia", "ignored", NotificationKind.Info);
Check(disabledCalls.Count == 0, "notification respects NotificationsEnabled=false");

// --- P1: OCR language-pack selection -------------------------------------------------------
Language Tag(string tag) => new(tag);
Check(OcrService.SelectLanguage([], "zh") is null, "OCR empty language list yields no selection");
Check(OcrService.SelectLanguage([Tag("en-US")], "zh") is null, "OCR no Chinese pack detectable");
// Note: WinRT Language normalizes "zh-CN" to "zh-Hans-CN" (inserts the default script), so we
// assert on the primary subtag rather than the exact input string.
Check(OcrService.SelectLanguage([Tag("zh-CN"), Tag("en-US")], "zh")?.LanguageTag.Split('-')[0] == "zh",
    "OCR selects Chinese when available");
Check(OcrService.SelectLanguage([Tag("zh-Hans"), Tag("en-US")], "zh")?.LanguageTag.Split('-')[0] == "zh",
    "OCR Chinese prefix match handles subtags");
Check(OcrService.SelectLanguage([Tag("en-US")], "en")?.LanguageTag.Split('-')[0] == "en",
    "OCR selects English when available");
Check(OcrUnavailableException.Describe(OcrUnavailableReason.NoLanguagePack).Contains("设置", StringComparison.Ordinal),
    "OCR missing-pack message points to Windows Settings");
Check(OcrUnavailableException.Describe(OcrUnavailableReason.NoChinesePack).Contains("改用英文", StringComparison.Ordinal),
    "OCR missing-Chinese message explains the English fallback");

// --- P1: Authenticode verify decision (pure policy) ----------------------------------------
Check(!AuthenticodeVerifier.Evaluate(SignatureStatus.NoSignature, "", "CN=douxy1994").Accepted,
    "Authenticode rejects unsigned installer when a publisher is pinned");
Check(!AuthenticodeVerifier.Evaluate(SignatureStatus.Invalid, "CN=douxy1994", "CN=douxy1994").Accepted,
    "Authenticode rejects invalid signatures");
Check(!AuthenticodeVerifier.Evaluate(SignatureStatus.Untrusted, "CN=douxy1994", "CN=douxy1994").Accepted,
    "Authenticode rejects untrusted chains");
Check(!AuthenticodeVerifier.Evaluate(SignatureStatus.Trusted, "CN=attacker", "CN=douxy1994").Accepted,
    "Authenticode rejects signer-identity mismatch");
Check(AuthenticodeVerifier.Evaluate(SignatureStatus.Trusted, "CN=douxy1994", "CN=douxy1994").Accepted,
    "Authenticode accepts matching signer");
// EXT-1 (no cert provisioned): unsigned is accepted, but tampering is not.
Check(AuthenticodeVerifier.Evaluate(SignatureStatus.NoSignature, "", "").Accepted,
    "EXT-1: unsigned release accepted while no publisher is pinned");
Check(!AuthenticodeVerifier.Evaluate(SignatureStatus.Invalid, "", "").Accepted,
    "EXT-1: invalid signature still rejected");
Check(!AuthenticodeVerifier.Evaluate(SignatureStatus.Untrusted, "", "").Accepted,
    "EXT-1: untrusted signature still rejected");


var json = """
{
  "sourceLanguage": "en",
  "targetLanguage": "zh-CN",
  "enabledTranslateServices": ["google", "deepl"],
  "themeMode": "dark",
  "closeToTray": true,
  "screenshotOcrHotkey": "Ctrl+Alt+Shift+R"
}
""";
var decoded = JsonSerializer.Deserialize<PythiaSettings>(json, new JsonSerializerOptions
{
    PropertyNameCaseInsensitive = true,
});
Check(decoded?.ThemeMode == "dark" && decoded.CloseToTray, "legacy settings compatibility");

var concurrentStoreRoot = Path.Combine(Path.GetTempPath(), "Pythia-store-test-" + Guid.NewGuid().ToString("N"));
try
{
    var concurrentStore = new LocalStore(concurrentStoreRoot);
    await Task.WhenAll(Enumerable.Range(0, 12).Select(index => concurrentStore.SaveSettingsAsync(new PythiaSettings
    {
        SourceLanguage = index % 2 == 0 ? "en" : "auto",
        TargetLanguage = "zh-CN",
    })));
    var concurrentReload = await concurrentStore.LoadSettingsAsync();
    Check(concurrentReload.TargetLanguage == "zh-CN" &&
          !Directory.EnumerateFiles(concurrentStoreRoot, "*.tmp").Any(),
        "concurrent settings saves serialize atomically without temp-file collisions");
}
finally
{
    try { if (Directory.Exists(concurrentStoreRoot)) Directory.Delete(concurrentStoreRoot, true); } catch { }
}

var historyJson = """
[{"id":"one","sourceText":"hello","translatedText":"你好","sourceLanguage":"en","targetLanguage":"zh-CN","service":"google","createdAt":"2026-07-18T08:00:00Z","updatedAt":"2026-07-18T08:00:00Z","isFavorite":true,"deviceId":"device","syncStatus":"local","schemaVersion":1}]
""";
var history = JsonSerializer.Deserialize<List<HistoryRecord>>(historyJson, new JsonSerializerOptions
{
    PropertyNameCaseInsensitive = true,
});
Check(history is [{ IsFavorite: true, Service: "google" }], "legacy history compatibility");

try
{
    await WebDavService.TestConnectionAsync("file:///not-webdav", string.Empty, string.Empty);
    failures.Add("WebDAV URL validation");
}
catch (InvalidOperationException) { }

var pluginTestRoot = Path.Combine(Path.GetTempPath(), "Pythia-plugin-test-" + Guid.NewGuid().ToString("N"));
try
{
    var packageRoot = Path.Combine(pluginTestRoot, "package");
    Directory.CreateDirectory(packageRoot);
    await File.WriteAllTextAsync(Path.Combine(packageRoot, "manifest.json"), """
    {
      "schemaVersion": "1.0",
      "id": "test.echo.runtime",
      "name": "Runtime Echo",
      "version": "1.0.0",
      "description": "Native plugin runtime smoke test",
      "author": "Pythia",
      "type": "translator",
      "entry": "main.js",
      "minimumPythiaVersion": "1.0.0",
      "supportedPlatforms": ["windows"],
      "permissions": [],
      "configuration": [],
      "capabilities": ["translate"]
    }
    """);
    await File.WriteAllTextAsync(Path.Combine(packageRoot, "main.js"),
        "module.exports.translate = async (request) => request.input.text + '—你好，世界';");
    var archive = Path.Combine(pluginTestRoot, "runtime-echo.pythia");
    ZipFile.CreateFromDirectory(packageRoot, archive);
    var pluginStore = new LocalStore(Path.Combine(pluginTestRoot, "data"));
    var testNode = FindNodeForTests() ?? throw new FileNotFoundException("Node.js is required for plugin runtime tests.");
    var pluginService = new PluginService(pluginStore, new CredentialStore(), testNode);
    await pluginService.InitializeAsync();

    var missingCredentialPlugin = new PluginInfo(
        "test.missing.credential", "Missing Credential", "1.0.0", "test", "Pythia",
        pluginTestRoot, "main.js", null,
        [new PluginConfigurationField("apiKey", "API Key", "secret", true, null, new Dictionary<string, string>())]);
    var missingCredentialResult = await pluginService.TestConnectionAsync(missingCredentialPlugin, maximumDuration: TimeSpan.FromSeconds(1));
    Check(missingCredentialResult is { Status: PluginConnectionStatus.MissingCredential, Attempts: 0 },
        "plugin missing credential preflight");
    var missingConfigPlugin = new PluginInfo(
        "test.missing.configuration", "Missing Configuration", "1.0.0", "test", "Pythia",
        pluginTestRoot, "main.js", null,
        [new PluginConfigurationField("endpoint", "Endpoint", "text", true, null, new Dictionary<string, string>())]);
    var missingConfigResult = await pluginService.TestConnectionAsync(missingConfigPlugin, maximumDuration: TimeSpan.FromSeconds(1));
    Check(missingConfigResult is { Status: PluginConnectionStatus.MissingRequiredConfiguration, Attempts: 0 },
        "plugin missing required configuration preflight");

    var installed = pluginService.Install(archive);
    Check(installed.ServiceId == "plugin:test.echo.runtime" && installed.Enabled, "plugin install and service registration");
    pluginService.RenameDisplay(installed, "Renamed Echo");
    var renamed = pluginService.LoadInstalled().First(item => item.Id == installed.Id);
    Check(renamed.DisplayName == "Renamed Echo" && pluginService.DisplayName(installed.ServiceId) == "Renamed Echo",
        "plugin display name persists without changing service ID");
    var pluginOutput = await pluginService.TranslateAsync(installed.ServiceId, "hello", "en", "zh-CN");
    Check(pluginOutput == "hello—你好，世界", "plugin runtime preserves exact UTF-8 output");
    var connection = await pluginService.TestConnectionAsync(installed, maximumDuration: TimeSpan.FromSeconds(3));
    Check(connection is { Status: PluginConnectionStatus.Success, Attempts: 1 }, "plugin classified connectivity success");
    var pluginCoordinator = new TranslationCoordinator(new CredentialStore(), pluginService);
    var pluginBatch = await pluginCoordinator.TranslateAsync(
        "integrated", "en", "zh-CN", [installed.ServiceId], new PythiaSettings());
    Check(pluginBatch.Results is [{ IsSuccess: true, Text: "integrated—你好，世界" }], "plugin translation coordinator integration");

    var secondRoot = Path.Combine(pluginTestRoot, "package-two");
    Directory.CreateDirectory(secondRoot);
    await File.WriteAllTextAsync(Path.Combine(secondRoot, "manifest.json"), """
    {
      "schemaVersion": "1.0",
      "id": "test.echo.runtime.two",
      "name": "Runtime Echo Two",
      "version": "1.0.0",
      "description": "Second deterministic plugin",
      "author": "Pythia",
      "type": "translator",
      "entry": "main.js",
      "minimumPythiaVersion": "1.0.0",
      "supportedPlatforms": ["windows"],
      "permissions": [],
      "configuration": [],
      "capabilities": ["translate"]
    }
    """);
    await File.WriteAllTextAsync(Path.Combine(secondRoot, "main.js"),
        "module.exports.translate = async (request) => request.input.text + '-two';");
    await File.WriteAllTextAsync(Path.Combine(secondRoot, "plugin.svg"),
        "<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32'><rect width='32' height='32' fill='#3b82f6'/></svg>");
    var secondArchive = Path.Combine(pluginTestRoot, "runtime-echo-two.pythia");
    ZipFile.CreateFromDirectory(secondRoot, secondArchive);
    var second = pluginService.Install(secondArchive);
    Check(second.IconPath is not null && File.Exists(second.IconPath), "plugin-provided icon discovery");
    var orderedBatch = await pluginCoordinator.TranslateAsync(
        "order", "en", "zh-CN", [second.ServiceId, installed.ServiceId], new PythiaSettings());
    Check(orderedBatch.Results.Select(item => item.ServiceId).SequenceEqual([second.ServiceId, installed.ServiceId]) &&
          orderedBatch.Results.Select(item => item.Text).SequenceEqual(["order-two", "order—你好，世界"]),
        "plugin dispatch and result order");
    var persistedOrder = new PythiaSettings
    {
        TranslateServiceOrder = [second.ServiceId, installed.ServiceId],
        EnabledTranslateServices = [second.ServiceId, installed.ServiceId],
    };
    await pluginStore.SaveSettingsAsync(persistedOrder);
    var reloadedOrder = await pluginStore.LoadSettingsAsync();
    Check(reloadedOrder.ActiveServices.SequenceEqual([second.ServiceId, installed.ServiceId]),
        "service order persists across restart");

    var timeoutRoot = Path.Combine(pluginTestRoot, "package-timeout");
    Directory.CreateDirectory(timeoutRoot);
    await File.WriteAllTextAsync(Path.Combine(timeoutRoot, "manifest.json"), """
    {
      "schemaVersion": "1.0", "id": "test.timeout.runtime", "name": "Runtime Timeout",
      "version": "1.0.0", "description": "Timeout test", "author": "Pythia",
      "type": "translator", "entry": "main.js", "minimumPythiaVersion": "1.0.0",
      "supportedPlatforms": ["windows"], "permissions": [], "configuration": [], "capabilities": ["translate"]
    }
    """);
    await File.WriteAllTextAsync(Path.Combine(timeoutRoot, "main.js"),
        "module.exports.translate = async () => new Promise(() => {});");
    var timeoutArchive = Path.Combine(pluginTestRoot, "runtime-timeout.pythia");
    ZipFile.CreateFromDirectory(timeoutRoot, timeoutArchive);
    var timeoutPlugin = pluginService.Install(timeoutArchive);
    var timeoutResult = await pluginService.TestConnectionAsync(timeoutPlugin, maximumDuration: TimeSpan.FromMilliseconds(650));
    Check(timeoutResult.Status == PluginConnectionStatus.Timeout && timeoutResult.Attempts <= 2 &&
          timeoutResult.Duration < TimeSpan.FromSeconds(2), "plugin bounded timeout and retry");

    var unsafeArchive = Path.Combine(pluginTestRoot, "unsafe.pythia");
    using (var unsafeZip = ZipFile.Open(unsafeArchive, ZipArchiveMode.Create))
        unsafeZip.CreateEntry("../escape.txt");
    try
    {
        pluginService.Install(unsafeArchive);
        failures.Add("plugin path traversal was accepted");
    }
    catch (InvalidDataException) { }

    await File.WriteAllTextAsync(Path.Combine(installed.DirectoryPath, "main.js"),
        "module.exports.translate = async () => { throw new Error('Http Request Error\\nHttp Status: 403\\n{\\\"private\\\":\\\"body\\\"}'); }; ");
    try
    {
        await pluginService.TranslateAsync(installed.ServiceId, "error", "en", "zh-CN");
        failures.Add("plugin error sanitization did not throw");
    }
    catch (Exception exception)
    {
        Check(exception.Message == "Http Request Error；Http Status: 403", "plugin error response sanitization");
    }

    var legacyRoot = Path.Combine(pluginTestRoot, "legacy-potext");
    Directory.CreateDirectory(legacyRoot);
    await File.WriteAllTextAsync(Path.Combine(legacyRoot, "info.json"), """
    {
      "plugin_type": "translate",
      "id": "test.legacy.potext",
      "display": "Legacy Potext",
      "version": "1.0.0",
      "description": "Legacy conversion test",
      "needs": [{ "key": "endpoint", "display": "Endpoint", "type": "input" }]
    }
    """);
    await File.WriteAllTextAsync(Path.Combine(legacyRoot, "main.js"),
        "const translate = async (text) => text + '-converted';");
    var legacyArchive = Path.Combine(pluginTestRoot, "legacy.potext");
    ZipFile.CreateFromDirectory(legacyRoot, legacyArchive);
    var converted = pluginService.Install(legacyArchive);
    Check(converted.Id == "test.legacy.potext" && converted.CanReconvert,
        "potext installs through the native settings path and retains conversion source");
    Check(await pluginService.TranslateAsync(converted.ServiceId, "legacy", "en", "zh-CN") == "legacy-converted",
        "converted potext plugin uses the shared runner contract");
    var reconverted = pluginService.Reconvert(converted);
    Check(reconverted.CanReconvert &&
          await pluginService.TranslateAsync(reconverted.ServiceId, "again", "en", "zh-CN") == "again-converted",
        "potext reconversion preserves runtime behavior");
}
catch (Exception exception)
{
    failures.Add("plugin runtime smoke test: " + exception.Message);
}
finally
{
    try { if (Directory.Exists(pluginTestRoot)) Directory.Delete(pluginTestRoot, true); } catch { }
}

if (Environment.GetEnvironmentVariable("PYTHIA_NETWORK_TEST") == "1")
{
    var coordinator = new TranslationCoordinator(new CredentialStore());
    var batch = await coordinator.TranslateAsync("test it", "en", "zh-CN", ["google"], new PythiaSettings());
    Check(batch.Results is [{ IsSuccess: true }] && batch.Results[0].Text.Length > 0, "Google translation integration");
}

if (failures.Count > 0)
{
    Console.Error.WriteLine("Pythia native smoke tests failed:");
    foreach (var failure in failures) Console.Error.WriteLine("- " + failure);
    return 1;
}

Console.WriteLine("Pythia native smoke tests passed.");
return 0;
