using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using WpfClipboard = System.Windows.Clipboard;
using WpfDataObject = System.Windows.DataObject;

namespace Pythia.Services;

public enum SelectionCaptureStatus
{
    Success,
    NoPreviousApplication,
    ForegroundActivationFailed,
    ClipboardUnavailable,
    CopyFailed,
    EmptySelection,
}

public sealed record SelectionCaptureResult(
    SelectionCaptureStatus Status,
    string? Text,
    string Message,
    bool UsedClipboardFallback)
{
    public bool IsSuccess => Status == SelectionCaptureStatus.Success && !string.IsNullOrWhiteSpace(Text);
}

public static class SelectionCaptureService
{
    private const ushort VkControl = 0x11;
    private const ushort VkC = 0x43;
    private const uint InputKeyboard = 1;
    private const uint Keyup = 0x0002;
    private const uint EventSystemForeground = 0x0003;
    private const uint WineventOutOfContext = 0x0000;
    private const uint WineventSkipOwnProcess = 0x0002;
    private static readonly WinEventDelegate ForegroundChangedDelegate = ForegroundChanged;
    private static IntPtr _foregroundHook;
    private static IntPtr _pythiaWindow;
    private static IntPtr _lastExternalWindow;

    public static void Initialize(IntPtr pythiaWindow)
    {
        _pythiaWindow = pythiaWindow;
        RememberExternalForeground(GetForegroundWindow());
        if (_foregroundHook != IntPtr.Zero) return;
        _foregroundHook = SetWinEventHook(
            EventSystemForeground,
            EventSystemForeground,
            IntPtr.Zero,
            ForegroundChangedDelegate,
            0,
            0,
            WineventOutOfContext | WineventSkipOwnProcess);
    }

    public static async Task<SelectionCaptureResult> CaptureAsync(CancellationToken cancellationToken = default)
    {
        var current = GetForegroundWindow();
        RememberExternalForeground(current);
        var target = current != IntPtr.Zero && current != _pythiaWindow ? current : _lastExternalWindow;
        if (target == IntPtr.Zero || !IsWindow(target))
            return new(SelectionCaptureStatus.NoPreviousApplication, null,
                "没有可返回的外部应用。请先在其他应用中选中文字，再使用划词快捷键。", false);

        if (!await ActivateTargetAsync(target, cancellationToken))
            return new(SelectionCaptureStatus.ForegroundActivationFailed, null,
                "无法返回原应用读取选区。请使用全局划词快捷键，或手动切回原应用后重试。", false);

        var automationText = ReadWithUiAutomation();
        if (!string.IsNullOrWhiteSpace(automationText))
            return new(SelectionCaptureStatus.Success, automationText.Trim(), "已通过 UI Automation 读取选区。", false);

        if (!TrySnapshotClipboard(out var previousClipboard, out var clipboardWasEmpty))
            return new(SelectionCaptureStatus.ClipboardUnavailable, null,
                "剪贴板正被其他程序占用，Pythia 未覆盖其中内容。请稍后重试。", true);

        var sequence = GetClipboardSequenceNumber();
        try
        {
            var inputs = new[]
            {
                Key(VkControl, false), Key(VkC, false), Key(VkC, true), Key(VkControl, true),
            };
            if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) != inputs.Length)
                return new(SelectionCaptureStatus.CopyFailed, null,
                    "目标应用拒绝了复制快捷键，剪贴板内容未被保留为翻译输入。", true);

            for (var attempt = 0; attempt < 20 && GetClipboardSequenceNumber() == sequence; attempt++)
                await Task.Delay(40, cancellationToken);
            if (GetClipboardSequenceNumber() == sequence)
                return new(SelectionCaptureStatus.EmptySelection, null,
                    "当前控件没有可读取的选区，或不支持 UI Automation/复制。原剪贴板未改变。", true);

            var selected = TryReadClipboardText();
            return string.IsNullOrWhiteSpace(selected)
                ? new(SelectionCaptureStatus.EmptySelection, null,
                    "目标应用没有提供文本选区。Pythia 已恢复原剪贴板。", true)
                : new(SelectionCaptureStatus.Success, selected.Trim(),
                    "已通过受控复制读取选区，并恢复原剪贴板。", true);
        }
        finally
        {
            RestoreClipboard(previousClipboard, clipboardWasEmpty);
        }
    }

    private static async Task<bool> ActivateTargetAsync(IntPtr target, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 12; attempt++)
        {
            if (GetForegroundWindow() == target) return true;
            var currentThread = GetCurrentThreadId();
            var targetThread = GetWindowThreadProcessId(target, out _);
            var attached = targetThread != 0 && targetThread != currentThread &&
                           AttachThreadInput(currentThread, targetThread, true);
            try
            {
                ShowWindow(target, 9);
                BringWindowToTop(target);
                SetForegroundWindow(target);
            }
            finally
            {
                if (attached) AttachThreadInput(currentThread, targetThread, false);
            }
            await Task.Delay(40, cancellationToken);
        }
        return GetForegroundWindow() == target;
    }

    private static string? ReadWithUiAutomation()
    {
        try
        {
            var focused = AutomationElement.FocusedElement;
            if (focused?.TryGetCurrentPattern(TextPattern.Pattern, out var rawPattern) != true ||
                rawPattern is not TextPattern pattern) return null;
            var selected = pattern.GetSelection()
                .Select(range => range.GetText(-1).Trim())
                .Where(text => text.Length > 0)
                .ToArray();
            return selected.Length == 0 ? null : string.Join("\n", selected);
        }
        catch { return null; }
    }

    private static bool TrySnapshotClipboard(out WpfDataObject? snapshot, out bool wasEmpty)
    {
        snapshot = null;
        wasEmpty = false;
        for (var attempt = 0; attempt < 4; attempt++)
        {
            try
            {
                var source = WpfClipboard.GetDataObject();
                if (source is null)
                {
                    wasEmpty = true;
                    return true;
                }
                var clone = new WpfDataObject();
                var formats = source.GetFormats(false);
                foreach (var format in formats)
                {
                    var value = source.GetData(format, false);
                    if (value is not null) clone.SetData(format, value);
                }
                if (formats.Length > 0 && clone.GetFormats(false).Length == 0) return false;
                snapshot = clone;
                return true;
            }
            catch (ExternalException)
            {
                Thread.Sleep(35);
            }
            catch { return false; }
        }
        return false;
    }

    private static string? TryReadClipboardText()
    {
        for (var attempt = 0; attempt < 4; attempt++)
        {
            try { return WpfClipboard.ContainsText() ? WpfClipboard.GetText() : null; }
            catch (ExternalException) { Thread.Sleep(35); }
        }
        return null;
    }

    private static void RestoreClipboard(WpfDataObject? snapshot, bool wasEmpty)
    {
        for (var attempt = 0; attempt < 4; attempt++)
        {
            try
            {
                if (wasEmpty) WpfClipboard.Clear();
                else if (snapshot is not null) WpfClipboard.SetDataObject(snapshot, true);
                return;
            }
            catch (ExternalException) { Thread.Sleep(35); }
            catch { return; }
        }
    }

    private static void ForegroundChanged(IntPtr hook, uint eventType, IntPtr hwnd, int objectId, int childId, uint thread, uint time) =>
        RememberExternalForeground(hwnd);

    private static void RememberExternalForeground(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || hwnd == _pythiaWindow || !IsWindow(hwnd)) return;
        GetWindowThreadProcessId(hwnd, out var processId);
        if (processId == Environment.ProcessId) return;
        Interlocked.Exchange(ref _lastExternalWindow, hwnd);
    }

    private static Input Key(ushort virtualKey, bool up) => new()
    {
        Type = InputKeyboard,
        Union = new InputUnion { Keyboard = new KeyboardInput { VirtualKey = virtualKey, Flags = up ? Keyup : 0 } },
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputUnion Union; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion { [FieldOffset(0)] public KeyboardInput Keyboard; }
    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void WinEventDelegate(IntPtr hook, uint eventType, IntPtr hwnd, int objectId, int childId, uint thread, uint time);

    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attachThread, uint attachToThread, bool attach);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int processId);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr module,
        WinEventDelegate callback, uint processId, uint threadId, uint flags);
}
