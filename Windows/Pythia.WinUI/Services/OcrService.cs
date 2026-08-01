using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Runtime.InteropServices;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Pickers;
using Pythia.Models;

namespace Pythia.Services;

public static class OcrService
{
    /// <summary>
    /// Set when an OCR call succeeded but had to fall back to a non-preferred language
    /// pack (for example: Chinese requested but only English installed). Null on a clean
    /// run. Callers surface this as a non-blocking warning. Reset at the start of each call.
    /// </summary>
    public static OcrUnavailableReason? LastWarning { get; private set; }

    public static async Task<string?> RecognizeFromFileAsync(FrameworkElement owner)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".png");
        picker.FileTypeFilter.Add(".jpg");
        picker.FileTypeFilter.Add(".jpeg");
        picker.FileTypeFilter.Add(".bmp");
        picker.FileTypeFilter.Add(".tif");
        picker.FileTypeFilter.Add(".tiff");
        picker.SuggestedStartLocation = PickerLocationId.PicturesLibrary;
        if (App.MainAppWindow is null) return null;
        WinRT.Interop.InitializeWithWindow.Initialize(picker,
            WinRT.Interop.WindowNative.GetWindowHandle(App.MainAppWindow));
        var file = await picker.PickSingleFileAsync();
        if (file is null) throw new OperationCanceledException();
        await using var stream = await file.OpenStreamForReadAsync();
        var randomAccess = stream.AsRandomAccessStream();
        var decoder = await BitmapDecoder.CreateAsync(randomAccess);
        using var bitmap = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
        var engine = CreateEngine(App.Services.Settings.TargetLanguage);
        var result = await engine.RecognizeAsync(bitmap);
        return result.Text.Trim();
    }

    public static async Task<string> RecognizeScreenAsync()
    {
        var region = ScreenRegionSelector.Select();
        if (region is null) throw new OperationCanceledException();
        using var bitmap = CaptureScreen(region.Value.Left, region.Value.Top, region.Value.Width, region.Value.Height);
        var engine = CreateEngine(App.Services.Settings.TargetLanguage);
        var result = await engine.RecognizeAsync(bitmap);
        return result.Text.Trim();
    }

    /// <summary>
    /// Builds an OCR engine preferring the language that matches <paramref name="targetLanguage"/>
    /// (zh when translating to Chinese, otherwise English). Falls back to the other available
    /// pack with a <see cref="LastWarning"/>; throws <see cref="OcrUnavailableException"/> only
    /// when no OCR language pack is installed at all. Replaces the previous reliance on
    /// <c>TryCreateFromUserProfileLanguages</c>, which silently depended on profile languages.
    /// </summary>
    private static OcrEngine CreateEngine(string targetLanguage)
    {
        LastWarning = null;
        var preferred = IsChineseTarget(targetLanguage) ? "zh" : "en";
        var available = OcrEngine.AvailableRecognizerLanguages;
        var selected = SelectLanguage(available, preferred);

        if (selected is not null && OcrEngine.TryCreateFromLanguage(selected) is { } engine)
            return engine;

        // Preferred pack missing — try the other one before giving up entirely.
        var fallback = SelectLanguage(available, preferred == "zh" ? "en" : "zh");
        if (fallback is not null && OcrEngine.TryCreateFromLanguage(fallback) is { } fallbackEngine)
        {
            LastWarning = preferred == "zh" ? OcrUnavailableReason.NoChinesePack : OcrUnavailableReason.NoEnglishPack;
            return fallbackEngine;
        }

        throw new OcrUnavailableException(OcrUnavailableReason.NoLanguagePack,
            OcrUnavailableException.Describe(OcrUnavailableReason.NoLanguagePack));
    }

    /// <summary>
    /// Pure language-tag matcher (testable without a real bitmap). Returns the first
    /// available language whose primary tag (before '-') equals <paramref name="primaryTag"/>,
    /// or null. Treats the empty list as "no pack installed".
    /// </summary>
    public static Language? SelectLanguage(IReadOnlyList<Language> available, string primaryTag)
    {
        if (available is null || available.Count == 0) return null;
        foreach (var language in available)
        {
            var tag = language.LanguageTag ?? string.Empty;
            if (tag.Equals(primaryTag, StringComparison.OrdinalIgnoreCase)) return language;
            var primary = tag.Split('-')[0];
            if (primary.Equals(primaryTag, StringComparison.OrdinalIgnoreCase)) return language;
        }
        return null;
    }

    private static bool IsChineseTarget(string targetLanguage) =>
        !string.IsNullOrWhiteSpace(targetLanguage) &&
        targetLanguage.StartsWith("zh", StringComparison.OrdinalIgnoreCase);

    private static SoftwareBitmap CaptureScreen(int left, int top, int width, int height)
    {
        if (width <= 0 || height <= 0) throw new InvalidOperationException("无法获取屏幕尺寸。");
        var screen = GetDC(IntPtr.Zero);
        var memory = CreateCompatibleDC(screen);
        var bitmap = CreateCompatibleBitmap(screen, width, height);
        var previous = SelectObject(memory, bitmap);
        try
        {
            if (!BitBlt(memory, 0, 0, width, height, screen, left, top, 0x00CC0020 | 0x40000000))
                throw new InvalidOperationException("无法捕获屏幕画面。");
            var info = new BitmapInfo
            {
                Header = new BitmapInfoHeader
                {
                    Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                    Width = width,
                    Height = -height,
                    Planes = 1,
                    BitCount = 32,
                    Compression = 0,
                },
            };
            var pixels = new byte[checked(width * height * 4)];
            if (GetDIBits(memory, bitmap, 0, (uint)height, pixels, ref info, 0) == 0)
                throw new InvalidOperationException("无法读取屏幕像素。");
            return SoftwareBitmap.CreateCopyFromBuffer(
                System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions.AsBuffer(pixels),
                BitmapPixelFormat.Bgra8, width, height, BitmapAlphaMode.Premultiplied);
        }
        finally
        {
            SelectObject(memory, previous);
            DeleteObject(bitmap);
            DeleteDC(memory);
            ReleaseDC(IntPtr.Zero, screen);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public uint Compression;
        public uint SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ClrUsed;
        public uint ClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader Header;
        public uint Colors;
    }

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int width, int height);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool BitBlt(IntPtr destination, int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, uint operation);
    [DllImport("gdi32.dll")] private static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint start, uint lines, byte[] bits, ref BitmapInfo info, uint usage);
}
