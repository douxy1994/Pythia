using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml.Controls;

namespace Pythia.Models;

public sealed class HistoryRecord : INotifyPropertyChanged
{
    private bool _isFavorite;

    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string SourceText { get; set; } = string.Empty;
    public string TranslatedText { get; set; } = string.Empty;
    public string SourceLanguage { get; set; } = "auto";
    public string TargetLanguage { get; set; } = "zh-CN";
    public string Service { get; set; } = "google";
    public string? Model { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public bool IsFavorite
    {
        get => _isFavorite;
        set
        {
            if (_isFavorite == value) return;
            _isFavorite = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(FavoriteSymbol));
        }
    }
    public string DeviceId { get; set; } = string.Empty;
    public string SyncStatus { get; set; } = "local";
    public DateTimeOffset? DeletedAt { get; set; }
    public int SchemaVersion { get; set; } = 1;

    public Symbol FavoriteSymbol => IsFavorite ? Symbol.SolidStar : Symbol.OutlineStar;
    public string ServiceDisplayName => ServiceCatalog.DisplayName(Service);
    public string CreatedDisplay => CreatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm");

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
