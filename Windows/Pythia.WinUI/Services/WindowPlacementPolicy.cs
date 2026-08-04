using Windows.Graphics;

namespace Pythia.Services;

/// <summary>
/// Converts logical window sizes to physical pixels and keeps windows inside one
/// monitor's work area. AppWindow coordinates are physical pixels under PerMonitorV2.
/// </summary>
public static class WindowPlacementPolicy
{
    public const uint DefaultDpi = 96;

    public static int DipToPixels(double dips, uint dpi) =>
        Math.Max(1, (int)Math.Round(dips * NormalizeDpi(dpi) / DefaultDpi));

    public static RectInt32 CompactBounds(RectInt32 workArea, uint dpi, PointInt32? anchor = null)
    {
        var margin = DipToPixels(16, dpi);
        var availableWidth = Math.Max(1, workArea.Width - margin * 2);
        var availableHeight = Math.Max(1, workArea.Height - margin * 2);
        var width = Math.Min(DipToPixels(680, dpi), availableWidth);
        var height = Math.Min(DipToPixels(430, dpi), availableHeight);

        // Center by default. When selection came from another display, bias the
        // compact result toward the selection/cursor while still keeping it visible.
        var desiredX = anchor is { } point
            ? point.X - width / 2
            : workArea.X + (workArea.Width - width) / 2;
        var desiredY = anchor is { } pointY
            ? pointY.Y + DipToPixels(18, dpi)
            : workArea.Y + (workArea.Height - height) / 2;
        if (desiredY + height > workArea.Y + workArea.Height - margin && anchor is { } pointAbove)
            desiredY = pointAbove.Y - height - DipToPixels(18, dpi);

        return Clamp(new RectInt32(desiredX, desiredY, width, height), workArea, margin);
    }

    public static RectInt32 FullBounds(
        RectInt32 workArea,
        RectInt32? savedBounds,
        uint savedDpi,
        uint targetDpi)
    {
        var dpi = NormalizeDpi(targetDpi);
        int width;
        int height;
        int x;
        int y;
        if (savedBounds is { } saved)
        {
            // WindowDpi was added after physical bounds were already persisted.
            // A zero value therefore means legacy physical pixels and must not be
            // scaled on the first upgraded launch.
            var ratio = savedDpi == 0 ? 1d : (double)dpi / NormalizeDpi(savedDpi);
            width = Math.Max(1, (int)Math.Round(saved.Width * ratio));
            height = Math.Max(1, (int)Math.Round(saved.Height * ratio));
            x = saved.X;
            y = saved.Y;
        }
        else
        {
            width = Math.Min(DipToPixels(1180, dpi), (int)Math.Round(workArea.Width * 0.90));
            height = Math.Min(DipToPixels(780, dpi), (int)Math.Round(workArea.Height * 0.90));
            x = workArea.X + (workArea.Width - width) / 2;
            y = workArea.Y + (workArea.Height - height) / 2;
        }

        var minimumWidth = Math.Min(DipToPixels(960, dpi), workArea.Width);
        var minimumHeight = Math.Min(DipToPixels(680, dpi), workArea.Height);
        width = Math.Clamp(width, minimumWidth, workArea.Width);
        height = Math.Clamp(height, minimumHeight, workArea.Height);
        return Clamp(new RectInt32(x, y, width, height), workArea, 0);
    }

    public static RectInt32 Clamp(RectInt32 bounds, RectInt32 workArea, int margin)
    {
        margin = Math.Max(0, margin);
        var availableWidth = Math.Max(1, workArea.Width - margin * 2);
        var availableHeight = Math.Max(1, workArea.Height - margin * 2);
        var width = Math.Min(Math.Max(1, bounds.Width), availableWidth);
        var height = Math.Min(Math.Max(1, bounds.Height), availableHeight);
        var minX = workArea.X + margin;
        var minY = workArea.Y + margin;
        var maxX = workArea.X + workArea.Width - margin - width;
        var maxY = workArea.Y + workArea.Height - margin - height;
        return new RectInt32(
            Math.Clamp(bounds.X, minX, Math.Max(minX, maxX)),
            Math.Clamp(bounds.Y, minY, Math.Max(minY, maxY)),
            width,
            height);
    }

    private static uint NormalizeDpi(uint dpi) => dpi == 0 ? DefaultDpi : dpi;
}
