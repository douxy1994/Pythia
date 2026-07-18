using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Pythia.Services;

public sealed class StatusService : INotifyPropertyChanged
{
    private string _message = "已就绪";
    private bool _isBusy;

    public string Message
    {
        get => _message;
        private set { _message = value; OnPropertyChanged(); }
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set { _isBusy = value; OnPropertyChanged(); }
    }

    public void Report(string message, bool isBusy = false)
    {
        Message = message;
        IsBusy = isBusy;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
