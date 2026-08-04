using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Pythia.Controls;

/// <summary>
/// Renders a packaged Fluent System Icon SVG without relying on an installed
/// Segoe Fluent/MDL2 icon font. Icon names map to Assets/FluentIcons/*.svg.
/// </summary>
public sealed class SvgIcon : ContentControl
{
    private readonly Image _image;

    public static readonly DependencyProperty IconProperty = DependencyProperty.Register(
        nameof(Icon),
        typeof(string),
        typeof(SvgIcon),
        new PropertyMetadata(string.Empty, IconChanged));

    public SvgIcon()
    {
        Width = 20;
        Height = 20;
        Padding = new Thickness(0);
        IsHitTestVisible = false;
        _image = new Image { Stretch = Stretch.Uniform };
        Content = _image;
    }

    public string Icon
    {
        get => (string)GetValue(IconProperty);
        set => SetValue(IconProperty, value);
    }

    private static void IconChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        if (sender is not SvgIcon icon) return;
        var name = args.NewValue as string;
        icon._image.Source = string.IsNullOrWhiteSpace(name)
            ? null
            : new SvgImageSource(new Uri($"ms-appx:///Assets/FluentIcons/{name}.svg"));
    }
}
