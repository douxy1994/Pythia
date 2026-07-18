using Pythia.Models;

namespace Pythia.Services;

public enum HomeInputAction
{
    None,
    InsertLineBreak,
    Submit,
}

public static class HomeInteractionPolicy
{
    public static HomeInputAction ResolveEnter(
        bool isEnter,
        bool shiftDown,
        bool isImeComposing,
        bool isKeyRepeat)
    {
        if (!isEnter || isImeComposing || isKeyRepeat) return HomeInputAction.None;
        return shiftDown ? HomeInputAction.InsertLineBreak : HomeInputAction.Submit;
    }

    public static IReadOnlyList<string> MoveService(
        IReadOnlyList<string> order,
        int fromIndex,
        int toIndex)
    {
        if (fromIndex < 0 || fromIndex >= order.Count || toIndex < 0 || toIndex >= order.Count || fromIndex == toIndex)
            return order.ToArray();

        var result = order.ToList();
        var item = result[fromIndex];
        result.RemoveAt(fromIndex);
        result.Insert(toIndex, item);
        return result;
    }

    public static IReadOnlyList<string> MergeBuiltInEnabled(
        IEnumerable<string> currentEnabled,
        IEnumerable<string> enabledBuiltIns)
    {
        var builtIns = new HashSet<string>(ServiceCatalog.All.Select(item => item.Id), StringComparer.OrdinalIgnoreCase);
        return currentEnabled
            .Where(id => !builtIns.Contains(id))
            .Concat(enabledBuiltIns)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }
}

public sealed class HomeSubmissionGate
{
    private int _entered;

    public bool TryEnter() => Interlocked.CompareExchange(ref _entered, 1, 0) == 0;
    public void Exit() => Interlocked.Exchange(ref _entered, 0);
    public bool IsEntered => Volatile.Read(ref _entered) != 0;
}
