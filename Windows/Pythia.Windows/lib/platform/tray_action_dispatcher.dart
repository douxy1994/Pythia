typedef TrayActionCallback = Future<void> Function();

abstract final class TrayActions {
  static const inputTranslate = 'translate.input';
  static const openSettings = 'settings.open';
  static const openHistory = 'history.open';
  static const syncHistory = 'history.sync';
  static const quit = 'app.quitRequested';
}

class TrayActionDispatcher {
  final TrayActionCallback onInputTranslate;
  final TrayActionCallback onOpenSettings;
  final TrayActionCallback onOpenHistory;
  final TrayActionCallback onSyncHistory;
  final TrayActionCallback onQuit;

  const TrayActionDispatcher({
    required this.onInputTranslate,
    required this.onOpenSettings,
    required this.onOpenHistory,
    required this.onSyncHistory,
    required this.onQuit,
  });

  Future<bool> dispatch(String action) async {
    final callback = switch (action) {
      TrayActions.inputTranslate => onInputTranslate,
      TrayActions.openSettings => onOpenSettings,
      TrayActions.openHistory => onOpenHistory,
      TrayActions.syncHistory => onSyncHistory,
      TrayActions.quit => onQuit,
      _ => null,
    };
    if (callback == null) return false;
    await callback();
    return true;
  }
}
