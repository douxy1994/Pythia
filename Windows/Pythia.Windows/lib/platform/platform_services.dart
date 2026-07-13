import 'package:flutter/services.dart';

typedef HotkeyActionHandler = Future<void> Function(String action);
typedef TrayActionHandler = Future<void> Function(String action);

abstract interface class GlobalHotkeyService {
  Future<void> register(String action, String accelerator);
  Future<void> unregisterAll();
  void setHotkeyHandler(HotkeyActionHandler? handler);
}

abstract interface class SelectedTextReader {
  Future<String> readSelectedText();
}

abstract interface class ScreenshotOcrService {
  Future<String> captureAndRecognize({required bool translateAfterRecognition});
}

abstract interface class TrayService {
  Future<void> install();
  Future<void> updateMenu();
  void setTrayActionHandler(TrayActionHandler? handler);
}

abstract interface class WindowBehaviorService {
  Future<void> showWindow();
  Future<void> setLaunchAtStartup(bool enabled);
  Future<void> setAlwaysOnTop(bool enabled);
  Future<void> setCloseToTray(bool enabled);
  Future<void> setHideOnBlur(bool enabled);
  Future<void> restoreWindowPlacement();
  Future<void> saveWindowPlacement();
}

abstract interface class UpdateInstallerService {
  Future<void> launchUpdateInstaller(String path);
}

enum WindowsNotificationLevel { info, error }

abstract interface class SystemNotificationService {
  Future<void> showNotification({
    required String title,
    required String body,
    WindowsNotificationLevel level = WindowsNotificationLevel.info,
  });
}

abstract interface class ApplicationLifecycleService {
  Future<void> quitApp();
}

class MethodChannelWindowsPlatformService
    implements
        GlobalHotkeyService,
        SelectedTextReader,
        ScreenshotOcrService,
        TrayService,
        WindowBehaviorService,
        UpdateInstallerService,
        SystemNotificationService,
        ApplicationLifecycleService {
  static const MethodChannel _channel = MethodChannel(
    'pythia/windows_platform',
  );
  static HotkeyActionHandler? _hotkeyHandler;
  static TrayActionHandler? _trayActionHandler;

  const MethodChannelWindowsPlatformService();

  static Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'hotkey.triggered') {
      final action = call.arguments;
      if (action is String && _hotkeyHandler != null) {
        await _hotkeyHandler!(action);
      }
      return;
    }
    if (call.method == 'tray.action') {
      final action = call.arguments;
      if (action is String && _trayActionHandler != null) {
        await _trayActionHandler!(action);
      }
      return;
    }
    throw MissingPluginException('No Dart handler for ${call.method}');
  }

  static void _updateNativeHandler() {
    final hasHandler = _hotkeyHandler != null || _trayActionHandler != null;
    _channel.setMethodCallHandler(hasHandler ? _handleNativeCall : null);
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException catch (error) {
      throw UnsupportedError('Windows 平台能力尚未注册：$method。$error');
    } on PlatformException catch (error) {
      throw StateError(error.message ?? '$method 执行失败。');
    }
  }

  @override
  Future<void> register(String action, String accelerator) async {
    await _invoke<void>('hotkey.register', {
      'action': action,
      'accelerator': accelerator,
    });
  }

  @override
  Future<void> unregisterAll() async {
    await _invoke<void>('hotkey.unregisterAll');
  }

  @override
  void setHotkeyHandler(HotkeyActionHandler? handler) {
    _hotkeyHandler = handler;
    _updateNativeHandler();
  }

  @override
  Future<String> readSelectedText() async {
    return await _invoke<String>('selection.readText') ?? '';
  }

  @override
  Future<String> captureAndRecognize(
      {required bool translateAfterRecognition}) async {
    return await _invoke<String>('screenshot.captureAndRecognize', {
          'translateAfterRecognition': translateAfterRecognition,
        }) ??
        '';
  }

  @override
  Future<void> install() async {
    await _invoke<void>('tray.install');
  }

  @override
  Future<void> updateMenu() async {
    await _invoke<void>('tray.updateMenu');
  }

  @override
  void setTrayActionHandler(TrayActionHandler? handler) {
    _trayActionHandler = handler;
    _updateNativeHandler();
  }

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {
    await _invoke<void>('startup.setLaunchAtStartup', {'enabled': enabled});
  }

  @override
  Future<void> showWindow() async {
    await _invoke<void>('window.show');
  }

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    await _invoke<void>('window.setAlwaysOnTop', {'enabled': enabled});
  }

  @override
  Future<void> setCloseToTray(bool enabled) async {
    await _invoke<void>('window.setCloseToTray', {'enabled': enabled});
  }

  @override
  Future<void> setHideOnBlur(bool enabled) async {
    await _invoke<void>('window.setHideOnBlur', {'enabled': enabled});
  }

  @override
  Future<void> restoreWindowPlacement() async {
    await _invoke<void>('window.restorePlacement');
  }

  @override
  Future<void> saveWindowPlacement() async {
    await _invoke<void>('window.savePlacement');
  }

  @override
  Future<void> launchUpdateInstaller(String path) async {
    await _invoke<void>('update.launchInstaller', {'path': path});
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    WindowsNotificationLevel level = WindowsNotificationLevel.info,
  }) async {
    await _invoke<void>('notification.show', {
      'title': title,
      'body': body,
      'level': level.name,
    });
  }

  @override
  Future<void> quitApp() async {
    await _invoke<void>('app.quit');
  }
}

class MissingWindowsPlatformService
    implements
        GlobalHotkeyService,
        SelectedTextReader,
        ScreenshotOcrService,
        TrayService,
        WindowBehaviorService,
        UpdateInstallerService,
        SystemNotificationService,
        ApplicationLifecycleService {
  const MissingWindowsPlatformService();

  Never _missing(String capability) {
    throw UnsupportedError(
      '$capability requires a Windows platform-channel implementation.',
    );
  }

  @override
  Future<void> register(String action, String accelerator) async {
    _missing('Global hotkeys');
  }

  @override
  Future<void> unregisterAll() async {
    _missing('Global hotkeys');
  }

  @override
  void setHotkeyHandler(HotkeyActionHandler? handler) {}

  @override
  Future<String> readSelectedText() async {
    _missing('Selected-text translation');
  }

  @override
  Future<String> captureAndRecognize(
      {required bool translateAfterRecognition}) async {
    _missing('Screenshot OCR');
  }

  @override
  Future<void> install() async {
    _missing('System tray');
  }

  @override
  Future<void> updateMenu() async {
    _missing('System tray');
  }

  @override
  void setTrayActionHandler(TrayActionHandler? handler) {}

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {
    _missing('Startup registration');
  }

  @override
  Future<void> showWindow() async {
    _missing('Window behavior');
  }

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    _missing('Window behavior');
  }

  @override
  Future<void> setCloseToTray(bool enabled) async {
    _missing('Window behavior');
  }

  @override
  Future<void> setHideOnBlur(bool enabled) async {
    _missing('Window behavior');
  }

  @override
  Future<void> restoreWindowPlacement() async {
    _missing('Window behavior');
  }

  @override
  Future<void> saveWindowPlacement() async {
    _missing('Window behavior');
  }

  @override
  Future<void> launchUpdateInstaller(String path) async {
    _missing('Update installer');
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    WindowsNotificationLevel level = WindowsNotificationLevel.info,
  }) async {
    _missing('System notifications');
  }

  @override
  Future<void> quitApp() async {
    _missing('Application lifecycle');
  }
}
