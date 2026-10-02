using System.Globalization;
using Pythia.Models;
using Pythia.Services;

internal static class TranslationParityTests
{
    public static async Task RunAsync(Action<bool, string> check)
    {
        const string source = "First paragraph.\r\n\r\n  - Second item.\nThird.\rFourth.\u0085Next.\u2028Line.\u2029Paragraph.";
        var plan = TranslationTextPlan.Create(source);
        var calls = 0;
        var translated = await plan.ExecuteAsync((text, _) =>
        {
            calls++;
            check(!text.Any(c => "\r\n\u0085\u2028\u2029".Contains(c)), "provider input excludes original separators");
            return Task.FromResult(text.ToUpperInvariant());
        });
        check(translated == source.ToUpperInvariant(), "all newline forms, blank lines and indentation preserved");
        check(calls == 7, "whitespace fragments never invoke provider");
        foreach (var empty in new[] { "", " \t\r\n\r\n  \u2028" })
        {
            var result = await TranslationTextPlan.Create(empty).ExecuteAsync((_, _) => throw new Exception("Whitespace sent to provider"));
            check(result == empty, "empty and whitespace input is lossless");
        }
        var flattened = await TranslationTextPlan.Create(source, true).ExecuteAsync((text, _) => Task.FromResult(text + "\n\t "));
        check(!flattened.Any(c => "\r\n\u0085\u2028\u2029".Contains(c)) && !flattened.Contains("  "), "enabled option compacts output whitespace");

        foreach (var token in new[] { "6.02e-23", "2026-10-02", "v1.2.4", "123,456.789", "😀", "e\u0301", "👩‍👩‍👧‍👦" })
        {
            var text = new string('x', 63) + token + new string('y', 90);
            var parts = TranslationTextPlan.Create(text, chunkLimit: 64).Parts;
            check(string.Concat(parts.Select(p => p.Text)) == text, "long plan lossless: " + token);
            var boundaries = StringInfo.ParseCombiningCharacters(text).ToHashSet();
            var offset = 0;
            foreach (var part in parts)
            {
                check(boundaries.Contains(offset) || offset == text.Length, "grapheme safe boundary: " + token);
                check(offset <= 63 || offset >= 63 + token.Length, "numeric/token safe boundary: " + token);
                offset += part.Text.Length;
            }
        }

        var active = 0;
        var peak = 0;
        var started = 0;
        var bothStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var run = TranslationTextPlan.Create("first\nsecond\nthird\nfourth").ExecuteAsync(async (text, ct) =>
        {
            var current = Interlocked.Increment(ref active);
            Interlocked.Exchange(ref peak, Math.Max(peak, current));
            if (Interlocked.Increment(ref started) == 2) bothStarted.TrySetResult();
            try
            {
                await release.Task.WaitAsync(ct);
                if (text == "first") await Task.Delay(40, ct);
                return text.ToUpperInvariant();
            }
            finally { Interlocked.Decrement(ref active); }
        });
        await bothStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        check(started == 2 && peak == 2, "exactly two requests start per service");
        release.SetResult();
        check(await run == "FIRST\nSECOND\nTHIRD\nFOURTH" && peak == 2, "out-of-order responses retain source order and cap");

        using var cancel = new CancellationTokenSource();
        started = 0;
        var cancelStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var canceledRun = TranslationTextPlan.Create("a\nb\nc\nd").ExecuteAsync(async (text, ct) =>
        {
            if (Interlocked.Increment(ref started) == 2) cancelStarted.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, ct);
            return text;
        }, cancel.Token);
        await cancelStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        cancel.Cancel();
        try { await canceledRun; check(false, "caller cancellation propagated"); }
        catch (OperationCanceledException) { check(started == 2, "no pending requests start after cancellation"); }

        var root = Path.Combine(Path.GetTempPath(), "Pythia-parity-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new LocalStore(root);
            await File.WriteAllTextAsync(store.SettingsPath, "{\"themeMode\":\"dark\",\"enabledTranslateServices\":[\"google\"]}");
            var settings = await store.LoadSettingsAsync();
            check(!settings.TranslateDeleteNewline && settings.ThemeMode == "dark", "old settings default off without changing existing fields");
            settings.TranslateDeleteNewline = true;
            await store.SaveSettingsAsync(settings);
            var reload = await new LocalStore(root).LoadSettingsAsync();
            check(reload.TranslateDeleteNewline && reload.ThemeMode == "dark", "newline setting survives save and fresh store load");
            check((await File.ReadAllTextAsync(store.SettingsPath)).Contains("\"translateDeleteNewline\": true"), "camelCase setting compatibility");
        }
        finally { Directory.Delete(root, true); }
        Console.WriteLine("Translation parity: separators, whitespace, Unicode/numbers, ordering, peak=2, cancellation, settings verified.");
    }
}
