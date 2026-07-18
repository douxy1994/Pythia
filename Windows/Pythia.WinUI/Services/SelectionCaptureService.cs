using System.Runtime.InteropServices;
using Windows.ApplicationModel.DataTransfer;

namespace Pythia.Services;

public static class SelectionCaptureService
{
    private const ushort VkControl = 0x11;
    private const ushort VkC = 0x43;
    private const uint InputKeyboard = 1;
    private const uint Keyup = 0x0002;

    public static async Task<string?> CaptureAsync()
    {
        var sequence = GetClipboardSequenceNumber();
        var inputs = new[]
        {
            Key(VkControl, false), Key(VkC, false), Key(VkC, true), Key(VkControl, true),
        };
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) != inputs.Length)
            throw new InvalidOperationException("无法发送复制快捷键。");
        for (var attempt = 0; attempt < 10 && GetClipboardSequenceNumber() == sequence; attempt++)
            await Task.Delay(40);
        try
        {
            var content = Clipboard.GetContent();
            return content.Contains(StandardDataFormats.Text) ? (await content.GetTextAsync()).Trim() : null;
        }
        catch { return null; }
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

    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
}
