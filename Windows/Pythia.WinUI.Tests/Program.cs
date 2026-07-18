using System.Text.Json;
using Pythia.Models;
using Pythia.Services;

var failures = new List<string>();

void Check(bool condition, string message)
{
    if (!condition) failures.Add(message);
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
