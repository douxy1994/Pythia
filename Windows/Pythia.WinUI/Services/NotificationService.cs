namespace Pythia.Services;

/// <summary>
/// Kinds of system balloon notification. Map to the classic Shell_NotifyIcon
/// NIIF_* icon flags so the balloon is visually consistent with its severity.
/// </summary>
public enum NotificationKind
{
    Info = 0,
    Warning = 2,
    Error = 3,
}

/// <summary>
/// Self-contained balloon payload handed to the platform sender.
/// </summary>
public readonly record struct NotifyBalloon(string Title, string Body, NotificationKind Kind);

/// <summary>
/// Facade over the platform balloon sender. Holds the user-facing concerns that
/// the Win32 layer should not own: honoring <see cref="Pythia.Models.PythiaSettings.NotificationsEnabled"/>
/// and suppressing identical back-to-back balloons (avoids notification bombing).
///
/// The platform side (<see cref="WindowsShellService.ShowBalloon"/>) is injected as a
/// callback so this type stays unit-testable without an HWND, and so callers in
/// <c>AppServices</c>/pages do not depend on the shell service.
/// </summary>
public sealed class NotificationService
{
    private readonly Func<NotifyBalloon, bool> _send;
    private readonly Func<bool> _enabled;
    private NotifyBalloon _last;

    public NotificationService(Func<NotifyBalloon, bool> send, Func<bool> enabled)
    {
        _send = send ?? throw new ArgumentNullException(nameof(send));
        _enabled = enabled ?? throw new ArgumentNullException(nameof(enabled));
    }

    /// <summary>
    /// Shows a balloon unless notifications are disabled or the payload is identical
    /// to the most recent one. Returns true when a balloon was actually sent.
    /// </summary>
    public bool Show(string title, string body, NotificationKind kind = NotificationKind.Info)
    {
        if (!_enabled()) return false;
        var balloon = new NotifyBalloon(title ?? string.Empty, body ?? string.Empty, kind);
        if (balloon == _last) return false;
        _last = balloon;
        return _send(balloon);
    }
}
