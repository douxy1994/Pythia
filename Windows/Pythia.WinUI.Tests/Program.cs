using System.Text.Json;
using System.IO.Compression;
using Pythia.Models;
using Pythia.Services;

var failures = new List<string>();

void Check(bool condition, string message)
{
    if (!condition) failures.Add(message);
}

if (args.Length >= 2 && args[0] == "--install-repo-plugins")
{
    var packageDirectory = Path.GetFullPath(args[1]);
    var runConnectivity = args.Contains("--connectivity", StringComparer.OrdinalIgnoreCase);
    var store = new LocalStore();
    var service = new PluginService(store, new CredentialStore());
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
            var config = service.GetConfiguration(plugin);
            var missing = plugin.Configuration
                .Where(field => field.Required && string.IsNullOrWhiteSpace(config.GetValueOrDefault(field.Key)))
                .Select(field => field.Label)
                .ToArray();
            if (missing.Length > 0)
            {
                Console.WriteLine($"连通性\t{plugin.Name}\t未测试（缺少必填配置）");
                continue;
            }
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(60));
            try
            {
                await service.TranslateAsync(plugin.ServiceId, "Hello", "en", "zh-CN", timeout.Token);
                Console.WriteLine($"连通性\t{plugin.Name}\t通过");
            }
            catch (OperationCanceledException)
            {
                Console.WriteLine($"连通性\t{plugin.Name}\t失败（60 秒超时）");
            }
            catch (Exception exception)
            {
                Console.WriteLine($"连通性\t{plugin.Name}\t失败（{exception.Message}）");
            }
        }
    }
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
      "supportedPlatforms": ["windows"],
      "permissions": [],
      "configuration": [],
      "capabilities": ["translate"]
    }
    """);
    await File.WriteAllTextAsync(Path.Combine(packageRoot, "main.js"),
        "module.exports.translate = async (request) => request.input.text + '-ok';");
    var archive = Path.Combine(pluginTestRoot, "runtime-echo.pythia");
    ZipFile.CreateFromDirectory(packageRoot, archive);
    var pluginStore = new LocalStore(Path.Combine(pluginTestRoot, "data"));
    var pluginService = new PluginService(pluginStore, new CredentialStore());
    await pluginService.InitializeAsync();
    var installed = pluginService.Install(archive);
    Check(installed.ServiceId == "plugin:test.echo.runtime" && installed.Enabled, "plugin install and service registration");
    var pluginOutput = await pluginService.TranslateAsync(installed.ServiceId, "hello", "en", "zh-CN");
    Check(pluginOutput == "hello-ok", "plugin runtime execution");
    var pluginCoordinator = new TranslationCoordinator(new CredentialStore(), pluginService);
    var pluginBatch = await pluginCoordinator.TranslateAsync(
        "integrated", "en", "zh-CN", [installed.ServiceId], new PythiaSettings());
    Check(pluginBatch.Results is [{ IsSuccess: true, Text: "integrated-ok" }], "plugin translation coordinator integration");
    await File.WriteAllTextAsync(Path.Combine(installed.DirectoryPath, "main.js"),
        "module.exports.translate = async () => { throw new Error('Http Request Error\\nHttp Status: 403\\n{\\\"private\\\":\\\"body\\\"}'); }; ");
    try
    {
        await pluginService.TranslateAsync(installed.ServiceId, "error", "en", "zh-CN");
        failures.Add("plugin error sanitization did not throw");
    }
    catch (InvalidOperationException exception)
    {
        Check(exception.Message == "Http Request Error；Http Status: 403", "plugin error response sanitization");
    }
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
