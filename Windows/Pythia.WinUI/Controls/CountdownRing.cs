using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using XamlPath = Microsoft.UI.Xaml.Shapes.Path;

namespace Pythia.Controls;

public sealed class CountdownRing : Canvas
{
    public static readonly DependencyProperty RingBrushProperty = DependencyProperty.Register(
        nameof(RingBrush),
        typeof(Brush),
        typeof(CountdownRing),
        new PropertyMetadata(null, OnRingBrushChanged));

    private readonly XamlPath _path;
    private readonly DispatcherTimer _timer;
    private DateTimeOffset _deadline;
    private TimeSpan _duration;
    private double _fraction;

    public CountdownRing()
    {
        _path = new XamlPath
        {
            Fill = null,
            StrokeThickness = 2,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
            IsHitTestVisible = false,
        };
        Children.Add(_path);

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
        _timer.Tick += Timer_Tick;
        SizeChanged += (_, _) => UpdateGeometry(_fraction);
    }

    public Brush? RingBrush
    {
        get => (Brush?)GetValue(RingBrushProperty);
        set => SetValue(RingBrushProperty, value);
    }

    public void Start(TimeSpan duration)
    {
        _timer.Stop();
        _duration = duration <= TimeSpan.Zero ? TimeSpan.FromSeconds(5) : duration;
        _deadline = DateTimeOffset.UtcNow.Add(_duration);
        Visibility = Visibility.Visible;
        UpdateGeometry(1);
        _timer.Start();
    }

    public void Stop()
    {
        _timer.Stop();
        _fraction = 0;
        UpdateGeometry(0);
        Visibility = Visibility.Collapsed;
    }

    private static void OnRingBrushChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        if (sender is CountdownRing ring)
            ring._path.Stroke = args.NewValue as Brush;
    }

    private void Timer_Tick(object? sender, object e)
    {
        var remaining = _deadline - DateTimeOffset.UtcNow;
        if (remaining <= TimeSpan.Zero)
        {
            _timer.Stop();
            UpdateGeometry(0);
            return;
        }

        UpdateGeometry(Math.Clamp(remaining.TotalMilliseconds / _duration.TotalMilliseconds, 0, 1));
    }

    private void UpdateGeometry(double fraction)
    {
        _fraction = Math.Clamp(fraction, 0, 1);
        var width = ActualWidth > 0 ? ActualWidth : Width;
        var height = ActualHeight > 0 ? ActualHeight : Height;
        if (double.IsNaN(width) || double.IsInfinity(width) || width <= 0 ||
            double.IsNaN(height) || double.IsInfinity(height) || height <= 0)
        {
            _path.Data = null;
            return;
        }

        var size = Math.Min(width, height);
        var radius = Math.Max(0, size / 2 - _path.StrokeThickness / 2);
        var center = new Point(width / 2, height / 2);
        if (_fraction <= 0 || radius <= 0)
        {
            _path.Data = null;
            return;
        }

        _path.Stroke = RingBrush;
        if (_fraction >= 0.9999)
        {
            _path.Data = new EllipseGeometry { Center = center, RadiusX = radius, RadiusY = radius };
            return;
        }

        const double startAngle = -Math.PI / 2;
        var endAngle = startAngle + Math.Tau * _fraction;
        var start = new Point(
            center.X + radius * Math.Cos(startAngle),
            center.Y + radius * Math.Sin(startAngle));
        var end = new Point(
            center.X + radius * Math.Cos(endAngle),
            center.Y + radius * Math.Sin(endAngle));
        var figure = new PathFigure
        {
            StartPoint = start,
            IsClosed = false,
            IsFilled = false,
        };
        figure.Segments.Add(new ArcSegment
        {
            Point = end,
            Size = new Size(radius, radius),
            IsLargeArc = _fraction > 0.5,
            SweepDirection = SweepDirection.Clockwise,
        });
        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);
        _path.Data = geometry;
    }
}
