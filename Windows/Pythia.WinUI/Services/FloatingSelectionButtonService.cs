using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Windows.Graphics;

namespace Pythia.Services;

public static class FloatingSelectionButtonPolicy
{
    private static readonly HashSet<string> DragFallbackProcesses = new(
        [
            // Office and PDF readers.
            "winword", "acrord32", "acrobat", "foxitpdfreader", "sumatrapdf",
            "wps", "et", "wpp", "wpspdf",
            // Browsers and browser-hosted desktop clients.
            "msedge", "chrome", "firefox", "brave", "opera", "vivaldi",
            // Common chat clients.
            "chatgpt", "slack", "teams", "ms-teams", "discord", "telegram",
            "wechat", "weixin", "qq", "feishu", "lark", "dingtalk", "zoom",
        ],
        StringComparer.OrdinalIgnoreCase);

    public static bool IsSelectionDrag(PointInt32 start, PointInt32 end, long elapsedMilliseconds)
    {
        if (elapsedMilliseconds is < 70 or > 15_000) return false;
        var x = (long)end.X - start.X;
        var y = (long)end.Y - start.Y;
        return x * x + y * y >= 36;
    }

    public static bool SupportsDragFallback(string processName) =>
        DragFallbackProcesses.Contains(processName);
}

/// <summary>
/// Experimental non-activating selection affordance. A low-level mouse hook only
/// records drag completion; UI Automation probing and all UI work run asynchronously.
/// No clipboard content is touched until the user explicitly clicks the button.
/// </summary>
public sealed class FloatingSelectionButtonService : IDisposable
{
    private const int WhMouseLl = 14;
    private const uint WmLButtonDown = 0x0201;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmRButtonDown = 0x0204;
    private const uint WmMButtonDown = 0x0207;
    private const uint WmMouseWheel = 0x020A;
    private const uint WmPaint = 0x000F;
    private const uint WmEraseBackground = 0x0014;
    private const uint WmMouseActivate = 0x0021;
    private const uint WmNcHitTest = 0x0084;
    private const uint WsPopup = 0x80000000;
    private const uint WsExToolWindow = 0x00000080;
    private const uint WsExNoActivate = 0x08000000;
    private const int SwHide = 0;
    private const int SwShowNoActivate = 4;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private const int ImageIcon = 1;
    private const uint LrLoadFromFile = 0x0010;
    private const int DiNormal = 0x0003;
    private const int MaNoActivate = 3;
    private const int HtClient = 1;
    private static readonly IntPtr HwndTopmost = new(-1);

    private readonly IntPtr _ownerWindow;
    private readonly DispatcherQueue _dispatcher;
    private readonly Action<string?, PointInt32> _clicked;
    private readonly HookProc _hookProc;
    private readonly WindowProc _windowProc;
    private readonly string _windowClassName = $"Pythia.FloatingSelection.{Environment.ProcessId}";
    private readonly DispatcherQueueTimer _hideTimer;
    private IntPtr _hook;
    private IntPtr _buttonWindow;
    private IntPtr _icon;
    private PointInt32 _mouseDown;
    private long _mouseDownAt;
    private IntPtr _mouseDownTarget;
    private CancellationTokenSource? _probeCancellation;
    private string? _capturedText;
    private PointInt32 _anchor;
    private bool _enabled;
    private bool _disposed;

    public FloatingSelectionButtonService(
        IntPtr ownerWindow,
        DispatcherQueue dispatcher,
        Action<string?, PointInt32> clicked)
    {
        _ownerWindow = ownerWindow;
        _dispatcher = dispatcher;
        _clicked = clicked;
        _hookProc = MouseHook;
        _windowProc = ButtonWindowProc;
        _hideTimer = dispatcher.CreateTimer();
        _hideTimer.Interval = TimeSpan.FromSeconds(5);
        _hideTimer.IsRepeating = false;
        _hideTimer.Tick += (_, _) => Hide();
    }

    public void SetEnabled(bool enabled)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_enabled == enabled) return;
        if (enabled)
        {
            EnsureButtonWindow();
            _hook = SetWindowsHookEx(WhMouseLl, _hookProc, IntPtr.Zero, 0);
            if (_hook == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "无法安装悬浮划词鼠标监听");
            _enabled = true;
        }
        else
        {
            _enabled = false;
            StopProbe();
            Hide();
            if (_hook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hook);
                _hook = IntPtr.Zero;
            }
        }
    }

    private IntPtr MouseHook(int code, IntPtr message, IntPtr data)
    {
        if (code < 0 || !_enabled) return CallNextHookEx(_hook, code, message, data);
        var mouse = Marshal.PtrToStructure<LowLevelMouseInfo>(data);
        var point = new PointInt32(mouse.Point.X, mouse.Point.Y);
        var windowAtPoint = WindowFromPoint(mouse.Point);
        if (windowAtPoint == _buttonWindow)
            return CallNextHookEx(_hook, code, message, data);

        switch ((uint)message.ToInt64())
        {
            case WmLButtonDown:
                Hide();
                StopProbe();
                _mouseDown = point;
                _mouseDownAt = Environment.TickCount64;
                _mouseDownTarget = ExternalRootAt(mouse.Point);
                break;
            case WmLButtonUp:
                var target = ExternalRootAt(mouse.Point);
                var elapsed = Environment.TickCount64 - _mouseDownAt;
                if (target != IntPtr.Zero && target == _mouseDownTarget &&
                    FloatingSelectionButtonPolicy.IsSelectionDrag(_mouseDown, point, elapsed))
                    ScheduleProbe(target, point);
                break;
            case WmRButtonDown:
            case WmMButtonDown:
            case WmMouseWheel:
                Hide();
                StopProbe();
                break;
        }
        return CallNextHookEx(_hook, code, message, data);
    }

    private void ScheduleProbe(IntPtr target, PointInt32 anchor)
    {
        StopProbe();
        var cancellation = new CancellationTokenSource();
        _probeCancellation = cancellation;
        _dispatcher.TryEnqueue(async () =>
        {
            try
            {
                await Task.Delay(130, cancellation.Token);
                if (!_enabled || Root(GetForegroundWindow()) != target) return;
                var text = await SelectionCaptureService.TryReadSelectionForFloatingButtonAsync(
                    target, cancellation.Token);
                if (string.IsNullOrWhiteSpace(text) && !SupportsFallback(target)) return;
                _capturedText = string.IsNullOrWhiteSpace(text) ? null : text.Trim();
                _anchor = anchor;
                Show(anchor, target);
            }
            catch (OperationCanceledException) { }
            finally
            {
                if (ReferenceEquals(_probeCancellation, cancellation))
                    _probeCancellation = null;
                cancellation.Dispose();
            }
        });
    }

    private static bool SupportsFallback(IntPtr target)
    {
        GetWindowThreadProcessId(target, out var processId);
        if (processId <= 0) return false;
        try
        {
            using var process = Process.GetProcessById(processId);
            return FloatingSelectionButtonPolicy.SupportsDragFallback(process.ProcessName);
        }
        catch { return false; }
    }

    private void Show(PointInt32 anchor, IntPtr target)
    {
        var dpi = GetDpiForWindow(target);
        if (dpi == 0) dpi = WindowPlacementPolicy.DefaultDpi;
        var size = WindowPlacementPolicy.DipToPixels(34, dpi);
        var offset = WindowPlacementPolicy.DipToPixels(7, dpi);
        var monitor = MonitorFromPoint(new NativePoint(anchor.X, anchor.Y), 2);
        var info = new MonitorInfo { Size = (uint)Marshal.SizeOf<MonitorInfo>() };
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) return;
        var work = info.WorkArea;
        var x = anchor.X + offset;
        var y = anchor.Y + offset;
        if (x + size > work.Right) x = anchor.X - size - offset;
        if (y + size > work.Bottom) y = anchor.Y - size - offset;
        x = Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - size));
        y = Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - size));

        var region = CreateRoundRectRgn(0, 0, size + 1, size + 1, size / 2, size / 2);
        if (SetWindowRgn(_buttonWindow, region, false) == 0)
            DeleteObject(region);
        SetWindowPos(_buttonWindow, HwndTopmost, x, y, size, size, SwpNoActivate | SwpShowWindow);
        InvalidateRect(_buttonWindow, IntPtr.Zero, true);
        ShowWindow(_buttonWindow, SwShowNoActivate);
        _hideTimer.Stop();
        _hideTimer.Start();
    }

    private void Hide()
    {
        _hideTimer.Stop();
        if (_buttonWindow != IntPtr.Zero) ShowWindow(_buttonWindow, SwHide);
        _capturedText = null;
    }

    private void StopProbe()
    {
        var cancellation = Interlocked.Exchange(ref _probeCancellation, null);
        cancellation?.Cancel();
    }

    private IntPtr ExternalRootAt(NativePoint point)
    {
        var root = Root(WindowFromPoint(point));
        if (root == IntPtr.Zero || root == _ownerWindow || root == _buttonWindow || !IsWindowVisible(root))
            return IntPtr.Zero;
        GetWindowThreadProcessId(root, out var processId);
        return processId == Environment.ProcessId ? IntPtr.Zero : root;
    }

    private static IntPtr Root(IntPtr window) =>
        window == IntPtr.Zero ? IntPtr.Zero : GetAncestor(window, 2);

    private void EnsureButtonWindow()
    {
        if (_buttonWindow != IntPtr.Zero) return;
        var instance = GetModuleHandle(null);
        var windowClass = new WindowClass
        {
            Size = (uint)Marshal.SizeOf<WindowClass>(),
            WindowProc = Marshal.GetFunctionPointerForDelegate(_windowProc),
            Instance = instance,
            Cursor = LoadCursor(IntPtr.Zero, new IntPtr(32512)),
            ClassName = _windowClassName,
        };
        if (RegisterClassEx(ref windowClass) == 0 && Marshal.GetLastWin32Error() != 1410)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法注册悬浮按钮窗口");
        _buttonWindow = CreateWindowEx(
            WsExToolWindow | WsExNoActivate,
            _windowClassName,
            "Pythia 悬浮翻译",
            WsPopup,
            0, 0, 1, 1,
            IntPtr.Zero,
            IntPtr.Zero,
            instance,
            IntPtr.Zero);
        if (_buttonWindow == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法创建悬浮按钮窗口");
        _icon = LoadImage(IntPtr.Zero,
            Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"),
            ImageIcon, 0, 0, LrLoadFromFile);
    }

    private IntPtr ButtonWindowProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam)
    {
        switch (message)
        {
            case WmMouseActivate:
                return new IntPtr(MaNoActivate);
            case WmNcHitTest:
                return new IntPtr(HtClient);
            case WmEraseBackground:
                return new IntPtr(1);
            case WmLButtonUp:
                var text = _capturedText;
                var anchor = _anchor;
                Hide();
                _dispatcher.TryEnqueue(() => _clicked(text, anchor));
                return IntPtr.Zero;
            case WmPaint:
                PaintButton(window);
                return IntPtr.Zero;
            default:
                return DefWindowProc(window, message, wParam, lParam);
        }
    }

    private void PaintButton(IntPtr window)
    {
        var paint = new PaintStruct { Reserved = new byte[32] };
        var dc = BeginPaint(window, ref paint);
        try
        {
            GetClientRect(window, out var bounds);
            var brush = CreateSolidBrush(0x00F7F7F7);
            FillRect(dc, ref bounds, brush);
            DeleteObject(brush);
            if (_icon != IntPtr.Zero)
            {
                var inset = Math.Max(4, (bounds.Right - bounds.Left) / 6);
                DrawIconEx(dc, inset, inset, _icon,
                    bounds.Right - inset * 2, bounds.Bottom - inset * 2,
                    0, IntPtr.Zero, DiNormal);
            }
        }
        finally { EndPaint(window, ref paint); }
    }

    public void Dispose()
    {
        if (_disposed) return;
        SetEnabled(false);
        _disposed = true;
        if (_buttonWindow != IntPtr.Zero)
        {
            DestroyWindow(_buttonWindow);
            _buttonWindow = IntPtr.Zero;
        }
        if (_icon != IntPtr.Zero)
        {
            DestroyIcon(_icon);
            _icon = IntPtr.Zero;
        }
        UnregisterClass(_windowClassName, GetModuleHandle(null));
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate IntPtr WindowProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint { public int X; public int Y; public NativePoint(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)]
    private struct LowLevelMouseInfo { public NativePoint Point; public uint MouseData; public uint Flags; public uint Time; public IntPtr ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo { public uint Size; public NativeRect Monitor; public NativeRect WorkArea; public uint Flags; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public uint Size;
        public uint Style;
        public IntPtr WindowProc;
        public int ClassExtra;
        public int WindowExtra;
        public IntPtr Instance;
        public IntPtr Icon;
        public IntPtr Cursor;
        public IntPtr Background;
        public string? MenuName;
        public string ClassName;
        public IntPtr SmallIcon;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct PaintStruct
    {
        public IntPtr DeviceContext;
        public bool Erase;
        public NativeRect Paint;
        public bool Restore;
        public bool IncrementalUpdate;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Reserved;
    }

    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc callback, IntPtr module, uint threadId);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(NativePoint point);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out int processId);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr window, IntPtr rect, bool erase);
    [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr window, IntPtr region, bool redraw);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int left, int top, int right, int bottom, int ellipseWidth, int ellipseHeight);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? moduleName);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern ushort RegisterClassEx(ref WindowClass windowClass);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool UnregisterClass(string className, IntPtr instance);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr CreateWindowEx(uint exStyle, string className, string name, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr DefWindowProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr LoadCursor(IntPtr instance, IntPtr cursorName);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr LoadImage(IntPtr instance, string name, int type, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] private static extern IntPtr BeginPaint(IntPtr window, ref PaintStruct paint);
    [DllImport("user32.dll")] private static extern bool EndPaint(IntPtr window, ref PaintStruct paint);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out NativeRect rect);
    [DllImport("user32.dll")] private static extern int FillRect(IntPtr dc, ref NativeRect rect, IntPtr brush);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateSolidBrush(uint color);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
    [DllImport("user32.dll")] private static extern bool DrawIconEx(IntPtr dc, int x, int y, IntPtr icon, int width, int height, uint step, IntPtr brush, int flags);
}
