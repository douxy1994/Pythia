using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Pythia.Models;

namespace Pythia.Services;

public enum PythiaHotkeyAction
{
    ShowWindow = 1,
    SelectionTranslate = 2,
    ScreenshotTranslate = 3,
    ScreenshotOcr = 4,
}

public enum PythiaTrayAction
{
    QuickTranslate,
    History,
    SyncHistory,
    Settings,
}

public sealed class WindowsShellService : IDisposable
{
    private const uint WmSysCommand = 0x0112;
    private const uint WmHotkey = 0x0312;
    private const uint WmAppTray = 0x8001;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmRButtonUp = 0x0205;
    private const uint WmContextMenu = 0x007B;
    private const uint WmMouseActivate = 0x0021;
    private const uint NinSelect = 0x0400;
    private const uint NimAdd = 0;
    private const uint NimModify = 1;
    private const uint NimDelete = 2;
    private const uint NimSetVersion = 4;
    private const uint NifMessage = 1;
    private const uint NifIcon = 2;
    private const uint NifTip = 4;
    private const uint NifInfo = 0x0010; // balloon
    private const uint NotifyIconVersion4 = 4;
    private const uint ImageIcon = 1;
    private const uint LrLoadFromFile = 0x0010;
    private const uint LrDefaultSize = 0x0040;
    private const uint MfString = 0;
    private const uint MfSeparator = 0x0800;
    private const uint TpmRightButton = 0x0002;
    private const uint TpmReturnCommand = 0x0100;
    private const uint TpmNonotify = 0x0080;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModWin = 0x0008;
    private const uint ModNoRepeat = 0x4000;
    private const uint ScClose = 0xF060;

    private readonly Window _window;
    private readonly IntPtr _hwnd;
    private readonly SubclassProc _subclassProc;
    private IntPtr _icon;
    private bool _trayAdded;
    private bool _exitRequested;
    private readonly Dictionary<int, (uint Modifiers, uint Key, string Expression)> _registeredHotkeys = [];

    public WindowsShellService(Window window)
    {
        _window = window;
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
        _subclassProc = WindowProc;
        if (!SetWindowSubclass(_hwnd, _subclassProc, 1, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        AddTrayIcon();
        if (!TryRegisterHotkeys(App.Services.Settings, out var error) && error is not null)
            App.Services.Status.Report(error);
    }

    public event EventHandler<PythiaHotkeyAction>? HotkeyInvoked;
    public event EventHandler? ShowRequested;
    public event EventHandler<PythiaTrayAction>? TrayActionInvoked;
    public Func<int, int, bool>? IsSelectionActionPoint { get; set; }

    public void ExitApplication()
    {
        _exitRequested = true;
        _window.Close();
    }

    /// <summary>
    /// Displays a classic tray balloon via <c>NIM_MODIFY</c> + <c>NIF_INFO</c>.
    /// Safe to call whether or not the tray icon was added; returns false if the
    /// underlying <see cref="Shell_NotifyIcon"/> call rejects the modify (for example
    /// when no icon is present). The balloon lifetime is owned by the shell.
    /// </summary>
    public bool ShowBalloon(NotifyBalloon balloon)
    {
        if (!_trayAdded) return false;
        var data = new NotifyIconData
        {
            Size = (uint)Marshal.SizeOf<NotifyIconData>(),
            Window = _hwnd,
            Id = 1,
            Flags = NifInfo,
            Info = balloon.Body,
            InfoTitle = balloon.Title,
            InfoFlags = (uint)balloon.Kind,
        };
        return Shell_NotifyIcon(NimModify, ref data);
    }

    /// <summary>
    /// True when the Pythia window is the current foreground window. Callers use this
    /// to avoid firing a balloon for an event the user is already looking at.
    /// </summary>
    public bool IsWindowForeground() => GetForegroundWindow() == _hwnd;

    public void BringWindowToFront()
    {
        if (!IsWindowVisible(_hwnd)) ShowWindow(_hwnd, 5);
        BringWindowToTop(_hwnd);
        SetForegroundWindow(_hwnd);
    }

    public bool TryRegisterHotkeys(PythiaSettings settings, out string? error)
    {
        var requested = new[]
        {
            ((int)PythiaHotkeyAction.ShowWindow, settings.ShowWindowHotkey),
            ((int)PythiaHotkeyAction.SelectionTranslate, settings.SelectionTranslateHotkey),
            ((int)PythiaHotkeyAction.ScreenshotTranslate, settings.ScreenshotTranslateHotkey),
            ((int)PythiaHotkeyAction.ScreenshotOcr, settings.ScreenshotOcrHotkey),
        };
        var parsed = new List<(int Id, uint Modifiers, uint Key, string Expression)>();
        var combinations = new HashSet<(uint Modifiers, uint Key)>();
        foreach (var item in requested)
        {
            if (!TryParseHotkey(item.Item2, out var modifiers, out var key))
            {
                error = $"快捷键格式无效：{item.Item2}";
                return false;
            }
            if (!combinations.Add((modifiers, key)))
            {
                error = $"快捷键重复：{item.Item2}";
                return false;
            }
            parsed.Add((item.Item1, modifiers, key, item.Item2));
        }

        var previous = _registeredHotkeys.ToDictionary(item => item.Key, item => item.Value);
        foreach (var id in previous.Keys) UnregisterHotKey(_hwnd, id);
        var registeredIds = new List<int>();
        foreach (var item in parsed)
        {
            if (RegisterHotKey(_hwnd, item.Id, item.Modifiers | ModNoRepeat, item.Key))
            {
                registeredIds.Add(item.Id);
                continue;
            }
            foreach (var id in registeredIds) UnregisterHotKey(_hwnd, id);
            _registeredHotkeys.Clear();
            foreach (var old in previous)
            {
                if (RegisterHotKey(_hwnd, old.Key, old.Value.Modifiers | ModNoRepeat, old.Value.Key))
                    _registeredHotkeys[old.Key] = old.Value;
            }
            error = $"快捷键已被其他程序占用：{item.Expression}；原快捷键已恢复。";
            return false;
        }

        _registeredHotkeys.Clear();
        foreach (var item in parsed)
            _registeredHotkeys[item.Id] = (item.Modifiers, item.Key, item.Expression);
        error = null;
        return true;
    }

    private IntPtr WindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam, nuint id, IntPtr data)
    {
        if (message == WmMouseActivate && GetForegroundWindow() != _hwnd &&
            GetCursorPos(out var cursor) && ScreenToClient(_hwnd, ref cursor) &&
            IsSelectionActionPoint?.Invoke(cursor.X, cursor.Y) == true)
        {
            SelectionCaptureService.BeginCaptureBeforePythiaActivation();
        }
        if (message == WmHotkey)
        {
            var action = (PythiaHotkeyAction)wParam.ToInt32();
            _window.DispatcherQueue.TryEnqueue(() => HotkeyInvoked?.Invoke(this, action));
            return IntPtr.Zero;
        }
        if (message == WmSysCommand && ((uint)wParam.ToInt64() & 0xFFF0) == ScClose &&
            App.Services.Settings.CloseToTray && !_exitRequested)
        {
            _window.AppWindow.Hide();
            App.Services.Status.Report("Pythia 正在系统托盘中运行");
            return IntPtr.Zero;
        }
        if (message == WmAppTray)
        {
            var notification = (uint)(lParam.ToInt64() & 0xFFFF);
            if (notification is WmLButtonUp or NinSelect)
                _window.DispatcherQueue.TryEnqueue(() => ShowRequested?.Invoke(this, EventArgs.Empty));
            else if (notification is WmRButtonUp or WmContextMenu)
                ShowTrayMenu();
            return IntPtr.Zero;
        }
        return DefSubclassProc(hwnd, message, wParam, lParam);
    }

    private void AddTrayIcon()
    {
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        _icon = LoadImage(IntPtr.Zero, iconPath, ImageIcon, 0, 0, LrLoadFromFile | LrDefaultSize);
        if (_icon == IntPtr.Zero) return;
        var data = CreateNotifyData();
        _trayAdded = Shell_NotifyIcon(NimAdd, ref data);
        if (_trayAdded)
        {
            data.VersionOrTimeout = NotifyIconVersion4;
            Shell_NotifyIcon(NimSetVersion, ref data);
        }
    }

    private NotifyIconData CreateNotifyData() => new()
    {
        Size = (uint)Marshal.SizeOf<NotifyIconData>(),
        Window = _hwnd,
        Id = 1,
        Flags = NifMessage | NifIcon | NifTip,
        CallbackMessage = WmAppTray,
        Icon = _icon,
        Tip = "Pythia · AI 效率助手",
        Info = string.Empty,
        InfoTitle = string.Empty,
    };

    private void ShowTrayMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero) return;
        try
        {
            AppendMenu(menu, MfString, 1001, "显示 Pythia");
            AppendMenu(menu, MfSeparator, 0, string.Empty);
            AppendMenu(menu, MfString, 1002, "快速输入翻译");
            AppendMenu(menu, MfString, 1003, "历史记录");
            AppendMenu(menu, MfString, 1004, "同步历史");
            AppendMenu(menu, MfString, 1005, "设置");
            AppendMenu(menu, MfSeparator, 0, string.Empty);
            AppendMenu(menu, MfString, 1006, "退出");
            GetCursorPos(out var point);
            SetForegroundWindow(_hwnd);
            var command = TrackPopupMenuEx(menu, TpmRightButton | TpmReturnCommand | TpmNonotify,
                point.X, point.Y, _hwnd, IntPtr.Zero);
            if (command == 1001)
                _window.DispatcherQueue.TryEnqueue(() => ShowRequested?.Invoke(this, EventArgs.Empty));
            else if (command == 1002)
                _window.DispatcherQueue.TryEnqueue(() => TrayActionInvoked?.Invoke(this, PythiaTrayAction.QuickTranslate));
            else if (command == 1003)
                _window.DispatcherQueue.TryEnqueue(() => TrayActionInvoked?.Invoke(this, PythiaTrayAction.History));
            else if (command == 1004)
                _window.DispatcherQueue.TryEnqueue(() => TrayActionInvoked?.Invoke(this, PythiaTrayAction.SyncHistory));
            else if (command == 1005)
                _window.DispatcherQueue.TryEnqueue(() => TrayActionInvoked?.Invoke(this, PythiaTrayAction.Settings));
            else if (command == 1006)
                _window.DispatcherQueue.TryEnqueue(ExitApplication);
        }
        finally { DestroyMenu(menu); }
    }

    public static bool TryParseHotkey(string expression, out uint modifiers, out uint key)
    {
        modifiers = 0;
        key = 0;
        foreach (var raw in expression.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            var part = raw.ToUpperInvariant();
            switch (part)
            {
                case "CTRL": case "CONTROL": modifiers |= ModControl; continue;
                case "ALT": modifiers |= ModAlt; continue;
                case "SHIFT": modifiers |= ModShift; continue;
                case "WIN": case "WINDOWS": modifiers |= ModWin; continue;
            }
            if (part.Length == 1 && char.IsLetterOrDigit(part[0])) { key = part[0]; continue; }
            if (part.StartsWith('F') && int.TryParse(part[1..], out var number) && number is >= 1 and <= 24)
            {
                key = (uint)(0x70 + number - 1);
                continue;
            }
            return false;
        }
        return key != 0 && modifiers != 0;
    }

    public void Dispose()
    {
        for (var id = 1; id <= 4; id++) UnregisterHotKey(_hwnd, id);
        if (_trayAdded)
        {
            var data = CreateNotifyData();
            Shell_NotifyIcon(NimDelete, ref data);
        }
        RemoveWindowSubclass(_hwnd, _subclassProc, 1);
        if (_icon != IntPtr.Zero) DestroyIcon(_icon);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public uint Size;
        public IntPtr Window;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State;
        public uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint VersionOrTimeout;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags;
        public Guid GuidItem;
        public IntPtr BalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X; public int Y; }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate IntPtr SubclassProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam, nuint id, IntPtr data);

    [DllImport("comctl32.dll", SetLastError = true)] private static extern bool SetWindowSubclass(IntPtr hwnd, SubclassProc proc, nuint id, IntPtr data);
    [DllImport("comctl32.dll", SetLastError = true)] private static extern bool RemoveWindowSubclass(IntPtr hwnd, SubclassProc proc, nuint id);
    [DllImport("comctl32.dll")] private static extern IntPtr DefSubclassProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern bool Shell_NotifyIcon(uint message, ref NotifyIconData data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr LoadImage(IntPtr instance, string name, uint type, int cx, int cy, uint load);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool AppendMenu(IntPtr menu, uint flags, uint id, string text);
    [DllImport("user32.dll")] private static extern uint TrackPopupMenuEx(IntPtr menu, uint flags, int x, int y, IntPtr hwnd, IntPtr parameters);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr hwnd, ref Point point);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
}
