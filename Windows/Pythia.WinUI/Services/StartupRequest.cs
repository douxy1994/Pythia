namespace Pythia.Services;

using System.Text;

public sealed record StartupRequest(string? SettingsSection, string? SourceText)
{
    private static readonly HashSet<string> SettingsSections =
    [
        "general", "services", "plugins", "ocr", "shortcuts", "sync", "window", "about",
    ];

    public static StartupRequest Parse(IEnumerable<string> arguments)
    {
        string? settings = null;
        string? text = null;
        var allArguments = arguments.ToArray();
        var args = allArguments.Length > 0 && !allArguments[0].StartsWith("--", StringComparison.Ordinal)
            ? allArguments[1..]
            : allArguments;
        for (var index = 0; index < args.Length; index++)
        {
            var argument = args[index];
            if (argument.Equals("--settings", StringComparison.OrdinalIgnoreCase))
            {
                var requested = index + 1 < args.Length && !args[index + 1].StartsWith("--", StringComparison.Ordinal)
                    ? args[++index]
                    : "general";
                settings = NormalizeSettingsSection(requested);
            }
            else if (argument.StartsWith("--settings=", StringComparison.OrdinalIgnoreCase))
            {
                settings = NormalizeSettingsSection(argument["--settings=".Length..]);
            }
            else if (argument.Equals("--text", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
            {
                text = Limit(args[++index]);
            }
            else if (argument.StartsWith("--text=", StringComparison.OrdinalIgnoreCase))
            {
                text = Limit(argument["--text=".Length..]);
            }
        }
        return new StartupRequest(settings, text);
    }

    public static IReadOnlyList<string> Tokenize(string? commandLine)
    {
        if (string.IsNullOrWhiteSpace(commandLine)) return [];
        var result = new List<string>();
        var token = new StringBuilder();
        var quoted = false;
        for (var index = 0; index < commandLine.Length; index++)
        {
            var character = commandLine[index];
            if (character == '"')
            {
                quoted = !quoted;
                continue;
            }
            if (char.IsWhiteSpace(character) && !quoted)
            {
                if (token.Length > 0)
                {
                    result.Add(token.ToString());
                    token.Clear();
                }
                continue;
            }
            token.Append(character);
        }
        if (token.Length > 0) result.Add(token.ToString());
        return result;
    }

    private static string NormalizeSettingsSection(string value) =>
        SettingsSections.Contains(value.Trim()) ? value.Trim().ToLowerInvariant() : "general";

    private static string Limit(string value) => value.Length <= 50_000 ? value : value[..50_000];
}
