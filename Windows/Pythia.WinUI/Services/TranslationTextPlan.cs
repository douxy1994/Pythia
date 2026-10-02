using System.Globalization;
using System.Runtime.ExceptionServices;
using System.Text.RegularExpressions;

namespace Pythia.Services;

public sealed record TranslationTextPart(string Text, bool RequiresTranslation);

/// <summary>Immutable local structure shared by every provider and plugin.</summary>
public sealed class TranslationTextPlan
{
    public IReadOnlyList<TranslationTextPart> Parts { get; }
    private readonly bool _deleteNewline;
    private TranslationTextPlan(List<TranslationTextPart> parts, bool deleteNewline)
    {
        Parts = parts.AsReadOnly();
        _deleteNewline = deleteNewline;
    }

    public static TranslationTextPlan Create(string text, bool deleteNewline = false, int chunkLimit = 1800)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (chunkLimit < 1) throw new ArgumentOutOfRangeException(nameof(chunkLimit));
        var parts = new List<TranslationTextPart>();
        void Body(string body)
        {
            foreach (var chunk in SplitChunks(body, chunkLimit))
            {
                var start = 0;
                while (start < chunk.Length && char.IsWhiteSpace(chunk[start])) start++;
                var end = chunk.Length;
                while (end > start && char.IsWhiteSpace(chunk[end - 1])) end--;
                if (start > 0) parts.Add(new(chunk[..start], false));
                if (end > start) parts.Add(new(chunk[start..end], true));
                if (end < chunk.Length) parts.Add(new(chunk[end..], false));
            }
        }
        if (deleteNewline) Body(text);
        else
        {
            var cursor = 0;
            foreach (Match separator in Regex.Matches(text, @"\r\n|[\r\n\u0085\u2028\u2029]"))
            {
                Body(text[cursor..separator.Index]);
                parts.Add(new(separator.Value, false));
                cursor = separator.Index + separator.Length;
            }
            Body(text[cursor..]);
        }
        return new(parts, deleteNewline);
    }

    public async Task<string> ExecuteAsync(Func<string, CancellationToken, Task<string>> translate,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(translate);
        cancellationToken.ThrowIfCancellationRequested();
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var output = new string[Parts.Count];
        var next = -1;
        Exception? failure = null;
        async Task Worker()
        {
            try
            {
                while (true)
                {
                    linked.Token.ThrowIfCancellationRequested();
                    var index = Interlocked.Increment(ref next);
                    if (index >= Parts.Count) return;
                    var part = Parts[index];
                    linked.Token.ThrowIfCancellationRequested();
                    output[index] = part.RequiresTranslation
                        ? await translate(part.Text, linked.Token).ConfigureAwait(false)
                        : part.Text;
                }
            }
            catch (Exception exception)
            {
                Interlocked.CompareExchange(ref failure, exception, null);
                await linked.CancelAsync().ConfigureAwait(false);
            }
        }
        await Task.WhenAll(Worker(), Worker()).ConfigureAwait(false);
        cancellationToken.ThrowIfCancellationRequested();
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
        var result = string.Concat(output);
        return _deleteNewline ? Regex.Replace(result, @"\s+", " ").Trim() : result;
    }

    public static IReadOnlyList<string> SplitChunks(string text, int maxCharacters = 1800)
    {
        if (maxCharacters < 1) throw new ArgumentOutOfRangeException(nameof(maxCharacters));
        if (text.Length == 0) return [];
        // Boundaries are UTF-16 offsets at complete Unicode grapheme clusters.
        var boundaries = StringInfo.ParseCombiningCharacters(text).Append(text.Length).ToArray();
        var chunks = new List<string>();
        var cursor = 0;
        while (cursor < text.Length)
        {
            var hardEnd = Math.Min(text.Length, cursor + maxCharacters);
            var candidates = boundaries.Where(index => index > cursor && index <= hardEnd &&
                !WouldSplitNumber(text, index)).ToArray();
            var end = candidates.LastOrDefault();
            if (hardEnd < text.Length)
            {
                var preferred = candidates.LastOrDefault(index => index >= cursor + maxCharacters * 0.55 &&
                    (char.IsWhiteSpace(text[index - 1]) || "。！？!?；;：:".Contains(text[index - 1])));
                if (preferred > cursor) end = preferred;
            }
            // An indivisible number/grapheme may exceed the soft request limit.
            if (end <= cursor)
                end = boundaries.First(index => index > hardEnd && !WouldSplitNumber(text, index));
            chunks.Add(text[cursor..end]);
            cursor = end;
        }
        return chunks;
    }

    private static bool WouldSplitNumber(string text, int index)
    {
        if (index <= 0 || index >= text.Length) return false;
        char At(int offset) => index + offset >= 0 && index + offset < text.Length ? text[index + offset] : '\0';
        var before = At(-1);
        var after = At(0);
        var beforeBefore = At(-2);
        var afterAfter = At(1);
        var threeBefore = At(-3);
        var twoAfter = At(2);
        static bool Digit(char value) => char.IsDigit(value);
        static bool Separator(char value) => ".,，．:/：／-－'’ \u00A0\u202F".Contains(value);
        static bool Sign(char value) => "+-−＋－".Contains(value);
        if (before is 'v' or 'V' && Digit(after)) return true;
        if (Digit(before) && Digit(after)) return true;
        if (Digit(before) && Separator(after) && Digit(afterAfter)) return true;
        if (Separator(before) && Digit(beforeBefore) && Digit(after)) return true;
        if (".,，．".Contains(before) && Digit(after)) return true;
        if (Sign(before) && Digit(after)) return true;
        if (Digit(before) && after is 'e' or 'E' &&
            (Digit(afterAfter) || (afterAfter is '+' or '-' && Digit(twoAfter)))) return true;
        if (before is 'e' or 'E' && Digit(beforeBefore) &&
            (Digit(after) || (after is '+' or '-' && Digit(afterAfter)))) return true;
        return before is '+' or '-' && beforeBefore is 'e' or 'E' && Digit(threeBefore) && Digit(after);
    }
}
