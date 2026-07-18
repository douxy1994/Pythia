namespace Pythia.Models;

public sealed record LanguageOption(string Code, string Name)
{
    public override string ToString() => Name;

    public static IReadOnlyList<LanguageOption> TargetLanguages { get; } =
    [
        new("zh-CN", "简体中文"),
        new("zh-TW", "繁體中文"),
        new("en", "English"),
        new("ja", "日本語"),
        new("ko", "한국어"),
        new("fr", "Français"),
        new("de", "Deutsch"),
        new("es", "Español"),
        new("ru", "Русский"),
        new("it", "Italiano"),
        new("pt", "Português"),
        new("ar", "العربية"),
    ];

    public static IReadOnlyList<LanguageOption> SourceLanguages { get; } =
    [
        new("auto", "自动检测"),
        .. TargetLanguages,
    ];

    public static LanguageOption FindSource(string code) =>
        SourceLanguages.FirstOrDefault(item => item.Code == code) ?? SourceLanguages[0];

    public static LanguageOption FindTarget(string code) =>
        TargetLanguages.FirstOrDefault(item => item.Code == code) ?? TargetLanguages[0];
}
