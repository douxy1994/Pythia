using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using FormsClipboard = System.Windows.Forms.Clipboard;
using FormsDataObject = System.Windows.Forms.DataObject;

namespace Pythia.Services;

public enum SelectionCaptureStatus
{
    Success,
    NoPreviousApplication,
    ForegroundActivationFailed,
    ModifierKeysStillPressed,
    ClipboardUnavailable,
    CopyFailed,
    EmptySelection,
}

public sealed record SelectionCaptureRequest(
    IntPtr TargetWindow,
    IntPtr FocusedWindow,
    string? CapturedText,
    bool CapturedWithClipboard,
    bool PrefersClipboardCapture,
    int AnchorX,
    int AnchorY)
{
    public bool HasCapturedText => !string.IsNullOrWhiteSpace(CapturedText);
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
    private const ushort VkShift = 0x10;
    private const ushort VkMenu = 0x12;
    private const ushort VkLWin = 0x5B;
    private const ushort VkRWin = 0x5C;
    private const ushort VkC = 0x43;
    private const uint InputKeyboard = 1;
    private const uint Keyup = 0x0002;
    private const int SwRestore = 9;
    private const uint EventSystemForeground = 0x0003;
    private const uint WineventOutOfContext = 0x0000;
    private const uint WineventSkipOwnProcess = 0x0002;
    private static readonly HashSet<string> ClipboardFirstProcessNames =
        new(["wps", "et", "wpp", "wpspdf"], StringComparer.OrdinalIgnoreCase);
    private static readonly WinEventDelegate ForegroundChangedDelegate = ForegroundChanged;
    private static IntPtr _foregroundHook;
    private static IntPtr _pythiaWindow;
    private static IntPtr _lastExternalWindow;
    private static IntPtr _lastExternalFocusWindow;
    private static readonly object PreActivationLock = new();
    private static IntPtr _preActivationTarget;
    private static Task<PreActivationSelection?>? _preActivationCapture;
    private static long _preActivationTimestamp;

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

    public static SelectionCaptureRequest PrepareCapture()
    {
        var current = GetForegroundWindow();
        RememberExternalForeground(current);
        var target = IsEligibleExternalWindow(current) ? GetAncestor(current, 2) : _lastExternalWindow;
        var focused = GetFocusedWindow(target);
        if (!IsFocusWindowForTarget(target, focused)) focused = _lastExternalFocusWindow;
        var clipboardFirst = PrefersClipboardCapture(target);

        // Read UIA before hiding Pythia or reactivating the source application. Chromium-
        // based clients such as ChatGPT expose transcript selections on their Document,
        // while their focused element returns to the prompt editor as soon as focus is
        // restored. Reading only AutomationElement.FocusedElement after activation loses
        // the transcript selection and makes Ctrl+C target the empty prompt instead.
        var captured = ConsumeCompletedPreActivationText(target);
        GetCursorPos(out var anchor);
        return new SelectionCaptureRequest(target, focused, captured?.Text,
            captured?.UsedClipboard ?? false, clipboardFirst, anchor.X, anchor.Y);
    }

    public static async Task<SelectionCaptureRequest> PrepareCaptureAsync(CancellationToken cancellationToken = default)
    {
        var current = GetForegroundWindow();
        RememberExternalForeground(current);
        var target = IsEligibleExternalWindow(current) ? GetAncestor(current, 2) : _lastExternalWindow;
        var focused = GetFocusedWindow(target);
        if (!IsFocusWindowForTarget(target, focused)) focused = _lastExternalFocusWindow;
        var clipboardFirst = PrefersClipboardCapture(target);
        var captured = await AwaitPreActivationTextAsync(target, cancellationToken);
        if (!clipboardFirst && string.IsNullOrWhiteSpace(captured?.Text) && IsEligibleExternalWindow(target))
        {
            var automationText = await ReadSelectionBoundedAsync(target, cancellationToken);
            captured = string.IsNullOrWhiteSpace(automationText)
                ? null
                : new PreActivationSelection(automationText, false);
        }
        GetCursorPos(out var anchor);
        return new SelectionCaptureRequest(target, focused, captured?.Text,
            captured?.UsedClipboard ?? false, clipboardFirst, anchor.X, anchor.Y);
    }

    /// <summary>
    /// Called from WM_MOUSEACTIVATE while the source application is still foreground.
    /// This closes the gap between clicking Pythia and the WinUI Click event: Chromium
    /// can move keyboard focus back to its prompt editor during that gap and lose the
    /// transcript selection before normal capture starts.
    /// </summary>
    public static void BeginCaptureBeforePythiaActivation()
    {
        var foreground = GetForegroundWindow();
        if (!IsEligibleExternalWindow(foreground)) return;
        var target = GetAncestor(foreground, 2);
        // WPS and other custom document canvases may not expose TextPattern. Copy
        // while the source is still foreground; doing it after Pythia activates can
        // restore a different editor/caret and lose the selection. The clipboard is
        // snapshotted and restored inside this call.
        var clipboardText = CopySelectionWhileSourceIsForeground();
        lock (PreActivationLock)
        {
            _preActivationTarget = target;
            _preActivationCapture = !string.IsNullOrWhiteSpace(clipboardText)
                ? Task.FromResult<PreActivationSelection?>(new(clipboardText, true))
                : Task.Run(() =>
                {
                    var automationText = ReadSelectionFromWindow(target);
                    return string.IsNullOrWhiteSpace(automationText)
                        ? null
                        : new PreActivationSelection(automationText, false);
                });
            _preActivationTimestamp = Environment.TickCount64;
        }
    }

    public static async Task<SelectionCaptureResult> CaptureAsync(CancellationToken cancellationToken = default) =>
        await CaptureAsync(await PrepareCaptureAsync(cancellationToken), cancellationToken);

    public static Task<string?> TryReadSelectionForFloatingButtonAsync(
        IntPtr target,
        CancellationToken cancellationToken = default) =>
        IsEligibleExternalWindow(target)
            ? ReadSelectionBoundedAsync(target, cancellationToken)
            : Task.FromResult<string?>(null);

    public static async Task<SelectionCaptureResult> CaptureAsync(
        SelectionCaptureRequest request,
        CancellationToken cancellationToken = default)
    {
        var target = request.TargetWindow;
        if (!IsEligibleExternalWindow(target))
            return new(SelectionCaptureStatus.NoPreviousApplication, null,
                "没有可返回的外部应用。请先在其他应用中选中文字，再使用划词快捷键。", false);

        if (request.HasCapturedText)
            return new(SelectionCaptureStatus.Success, request.CapturedText!.Trim(),
                request.CapturedWithClipboard
                    ? "已在源应用仍处于前台时通过受控复制读取选区，并恢复原剪贴板。"
                    : "已在切换窗口前通过 UI Automation 读取选区。",
                request.CapturedWithClipboard);

        if (!await ActivateTargetAsync(target, request.FocusedWindow, cancellationToken))
            return new(SelectionCaptureStatus.ForegroundActivationFailed, null,
                "无法返回原应用读取选区。请使用全局划词快捷键，或手动切回原应用后重试。", false);

        // When the user clicks Pythia's own selection button, the target application
        // has just lost focus. Poll briefly while Windows restores the target's focused
        // text control; a single read is frequently too early in Chromium and editors.
        for (var attempt = 0; !request.PrefersClipboardCapture && attempt < 6; attempt++)
        {
            await Task.Delay(attempt == 0 ? 160 : 60, cancellationToken);
            var automationText = await ReadSelectionBoundedAsync(target, cancellationToken);
            if (!string.IsNullOrWhiteSpace(automationText))
                return new(SelectionCaptureStatus.Success, automationText.Trim(), "已通过 UI Automation 读取选区。", false);
        }

        if (!await WaitForModifierReleaseAsync(cancellationToken))
            return new(SelectionCaptureStatus.ModifierKeysStillPressed, null,
                "快捷键尚未松开。请松开 Ctrl、Alt、Shift 或 Windows 键后重试。", true);

        if (GetForegroundWindow() != target &&
            !await ActivateTargetAsync(target, request.FocusedWindow, cancellationToken))
            return new(SelectionCaptureStatus.ForegroundActivationFailed, null,
                "复制选区前目标应用失去焦点，请重新选中文字后重试。", true);

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

    public static void Shutdown()
    {
        var hook = Interlocked.Exchange(ref _foregroundHook, IntPtr.Zero);
        if (hook != IntPtr.Zero) UnhookWinEvent(hook);
        _pythiaWindow = IntPtr.Zero;
        _lastExternalWindow = IntPtr.Zero;
        _lastExternalFocusWindow = IntPtr.Zero;
        lock (PreActivationLock)
        {
            _preActivationTarget = IntPtr.Zero;
            _preActivationCapture = null;
            _preActivationTimestamp = 0;
        }
    }

    private static PreActivationSelection? ConsumeCompletedPreActivationText(IntPtr target)
    {
        lock (PreActivationLock)
        {
            var fresh = target != IntPtr.Zero && target == _preActivationTarget &&
                        Environment.TickCount64 - _preActivationTimestamp <= 2_000;
            var text = fresh && _preActivationCapture?.IsCompletedSuccessfully == true
                ? _preActivationCapture.Result : null;
            _preActivationTarget = IntPtr.Zero;
            _preActivationCapture = null;
            _preActivationTimestamp = 0;
            return text;
        }
    }

    private static async Task<PreActivationSelection?> AwaitPreActivationTextAsync(IntPtr target, CancellationToken cancellationToken)
    {
        Task<PreActivationSelection?>? pending;
        lock (PreActivationLock)
        {
            var fresh = target != IntPtr.Zero && target == _preActivationTarget &&
                        Environment.TickCount64 - _preActivationTimestamp <= 2_000;
            pending = fresh ? _preActivationCapture : null;
            _preActivationTarget = IntPtr.Zero;
            _preActivationCapture = null;
            _preActivationTimestamp = 0;
        }
        if (pending is null) return null;
        try { return await pending.WaitAsync(TimeSpan.FromMilliseconds(300), cancellationToken); }
        catch (TimeoutException) { return null; }
    }

    private static async Task<string?> ReadSelectionBoundedAsync(IntPtr target, CancellationToken cancellationToken)
    {
        try
        {
            return await Task.Run(() => ReadSelectionFromWindow(target), cancellationToken)
                .WaitAsync(TimeSpan.FromMilliseconds(350), cancellationToken);
        }
        catch (TimeoutException) { return null; }
    }

    private static string? CopySelectionWhileSourceIsForeground()
    {
        if (IsKeyDown(VkControl) || IsKeyDown(VkShift) || IsKeyDown(VkMenu) ||
            IsKeyDown(VkLWin) || IsKeyDown(VkRWin)) return null;
        if (!TrySnapshotClipboard(out var previousClipboard, out var clipboardWasEmpty)) return null;

        var sequence = GetClipboardSequenceNumber();
        try
        {
            var inputs = new[]
            {
                Key(VkControl, false), Key(VkC, false), Key(VkC, true), Key(VkControl, true),
            };
            if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) != inputs.Length) return null;
            for (var attempt = 0; attempt < 20 && GetClipboardSequenceNumber() == sequence; attempt++)
                Thread.Sleep(10);
            return GetClipboardSequenceNumber() == sequence ? null : TryReadClipboardText();
        }
        finally
        {
            RestoreClipboard(previousClipboard, clipboardWasEmpty);
        }
    }

    private static async Task<bool> WaitForModifierReleaseAsync(CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 60; attempt++)
        {
            if (!IsKeyDown(VkControl) && !IsKeyDown(VkShift) && !IsKeyDown(VkMenu) &&
                !IsKeyDown(VkLWin) && !IsKeyDown(VkRWin)) return true;
            await Task.Delay(25, cancellationToken);
        }
        return false;
    }

    private static bool IsKeyDown(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    private static async Task<bool> ActivateTargetAsync(
        IntPtr target,
        IntPtr focusedWindow,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 12; attempt++)
        {
            var currentThread = GetCurrentThreadId();
            var targetThread = GetWindowThreadProcessId(target, out _);
            var focusThread = IsFocusWindowForTarget(target, focusedWindow)
                ? GetWindowThreadProcessId(focusedWindow, out _)
                : 0;
            var attachedTarget = targetThread != 0 && targetThread != currentThread &&
                                 AttachThreadInput(currentThread, targetThread, true);
            var attachedFocus = focusThread != 0 && focusThread != currentThread && focusThread != targetThread &&
                                AttachThreadInput(currentThread, focusThread, true);
            try
            {
                // Only restore if minimized. Calling ShowWindow on a normal target can
                // trigger a restore animation and steal focus twice, which makes selection
                // capture visibly flicker and can clear the focused text control.
                if (IsIconic(target)) ShowWindow(target, SwRestore);
                BringWindowToTop(target);
                SetForegroundWindow(target);
                if (IsFocusWindowForTarget(target, focusedWindow)) SetFocus(focusedWindow);
            }
            finally
            {
                if (attachedFocus) AttachThreadInput(currentThread, focusThread, false);
                if (attachedTarget) AttachThreadInput(currentThread, targetThread, false);
            }
            await Task.Delay(40, cancellationToken);
            if (GetForegroundWindow() == target) return true;
        }
        return GetForegroundWindow() == target;
    }

    private static string? ReadSelectionFromWindow(IntPtr target)
    {
        if (target == IntPtr.Zero || !IsWindow(target)) return null;
        try
        {
            var root = AutomationElement.FromHandle(target);
            var focused = AutomationElement.FocusedElement;
            if (focused is not null && focused.Current.ProcessId == root.Current.ProcessId)
            {
                var element = focused;
                for (var depth = 0; depth < 8 && element is not null; depth++)
                {
                    var text = ReadSelection(element);
                    if (!string.IsNullOrWhiteSpace(text)) return text;
                    element = TreeWalker.ControlViewWalker.GetParent(element);
                }
            }
            var rootText = ReadSelection(root);
            if (!string.IsNullOrWhiteSpace(rootText)) return rootText;
            return null;
        }
        catch { return null; }
    }

    private static string? ReadSelection(AutomationElement element)
    {
        try
        {
            if (!element.TryGetCurrentPattern(TextPattern.Pattern, out var rawPattern) ||
                rawPattern is not TextPattern pattern) return null;
            var selected = pattern.GetSelection()
                .Select(range => range.GetText(-1).Trim())
                .Where(text => text.Length > 0)
                .ToArray();
            return selected.Length == 0 ? null : string.Join("\n", selected);
        }
        catch (ElementNotAvailableException) { return null; }
        catch (InvalidOperationException) { return null; }
        catch (COMException) { return null; }
    }

    private static bool TrySnapshotClipboard(out FormsDataObject? snapshot, out bool wasEmpty)
    {
        snapshot = null;
        wasEmpty = false;
        for (var attempt = 0; attempt < 4; attempt++)
        {
            try
            {
                var source = FormsClipboard.GetDataObject();
                if (source is null)
                {
                    wasEmpty = true;
                    return true;
                }
                var clone = new FormsDataObject();
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
            try { return FormsClipboard.ContainsText() ? FormsClipboard.GetText() : null; }
            catch (ExternalException) { Thread.Sleep(35); }
        }
        return null;
    }

    private static void RestoreClipboard(FormsDataObject? snapshot, bool wasEmpty)
    {
        for (var attempt = 0; attempt < 4; attempt++)
        {
            try
            {
                if (wasEmpty) FormsClipboard.Clear();
                else if (snapshot is not null) FormsClipboard.SetDataObject(snapshot, true);
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
        if (!IsEligibleExternalWindow(hwnd)) return;
        var root = GetAncestor(hwnd, 2);
        Interlocked.Exchange(ref _lastExternalWindow, root);
        var focused = GetFocusedWindow(root);
        if (IsFocusWindowForTarget(root, focused))
            Interlocked.Exchange(ref _lastExternalFocusWindow, focused);
    }

    private static IntPtr GetFocusedWindow(IntPtr target)
    {
        if (target == IntPtr.Zero || !IsWindow(target)) return IntPtr.Zero;
        var thread = GetWindowThreadProcessId(target, out _);
        if (thread == 0) return IntPtr.Zero;
        var info = new GuiThreadInfo { Size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        return GetGUIThreadInfo(thread, ref info) ? info.FocusWindow : IntPtr.Zero;
    }

    private static bool IsFocusWindowForTarget(IntPtr target, IntPtr focusedWindow) =>
        focusedWindow != IntPtr.Zero && IsWindow(focusedWindow) &&
        (focusedWindow == target || IsChild(target, focusedWindow) || GetAncestor(focusedWindow, 2) == target);

    private static bool IsEligibleExternalWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || hwnd == _pythiaWindow || !IsWindow(hwnd) || !IsWindowVisible(hwnd)) return false;
        var root = GetAncestor(hwnd, 2);
        if (root == IntPtr.Zero || root == _pythiaWindow) return false;
        GetWindowThreadProcessId(root, out var processId);
        if (processId == Environment.ProcessId) return false;
        var className = new char[128];
        var length = GetClassName(root, className, className.Length);
        var windowClass = length > 0 ? new string(className, 0, length) : string.Empty;
        return windowClass is not ("Shell_TrayWnd" or "Shell_SecondaryTrayWnd" or "Progman" or "WorkerW");
    }

    private static bool PrefersClipboardCapture(IntPtr target)
    {
        if (target == IntPtr.Zero || !IsWindow(target)) return false;
        GetWindowThreadProcessId(target, out var processId);
        if (processId <= 0) return false;
        try
        {
            using var process = Process.GetProcessById(processId);
            return IsClipboardFirstProcessName(process.ProcessName);
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
        catch (Win32Exception) { return false; }
    }

    public static bool IsClipboardFirstProcessName(string processName) =>
        ClipboardFirstProcessNames.Contains(processName);

    private static Input Key(ushort virtualKey, bool up) => new()
    {
        Type = InputKeyboard,
        Union = new InputUnion { Keyboard = new KeyboardInput { VirtualKey = virtualKey, Flags = up ? Keyup : 0 } },
    };

    private sealed record PreActivationSelection(string Text, bool UsedClipboard);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputUnion Union; }
    [StructLayout(LayoutKind.Explicit, Size = 32)]
    private struct InputUnion
    {
        // INPUT contains a 32-byte native union on x64 (the mouse member sets
        // the union size even when the keyboard member is used). Without this
        // padding SendInput rejects the call with ERROR_INVALID_PARAMETER.
        [FieldOffset(0)] public KeyboardInput Keyboard;
        [FieldOffset(0)] public MouseInput Mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public uint Size;
        public uint Flags;
        public IntPtr ActiveWindow;
        public IntPtr FocusWindow;
        public IntPtr CaptureWindow;
        public IntPtr MenuOwnerWindow;
        public IntPtr MoveSizeWindow;
        public IntPtr CaretWindow;
        public NativeRect CaretRect;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void WinEventDelegate(IntPtr hook, uint eventType, IntPtr hwnd, int objectId, int childId, uint thread, uint time);

    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int virtualKey);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attachThread, uint attachToThread, bool attach);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsChild(IntPtr parent, IntPtr child);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, char[] className, int maximumCount);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int processId);
    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr module,
        WinEventDelegate callback, uint processId, uint threadId, uint flags);
    [DllImport("user32.dll")] private static extern bool UnhookWinEvent(IntPtr hook);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint { public int X; public int Y; }
}
