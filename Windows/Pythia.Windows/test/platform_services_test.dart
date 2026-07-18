import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/platform/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pythia/windows_platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    const service = MethodChannelWindowsPlatformService();
    service.setHotkeyHandler(null);
    service.setTrayActionHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('window and startup methods use stable channel contract', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    const service = MethodChannelWindowsPlatformService();

    await service.setLaunchAtStartup(true);
    await service.setAlwaysOnTop(true);
    await service.setCloseToTray(false);
    await service.setHideOnBlur(true);
    await service.install();
    await service.updateMenu();
    await service.showWindow();
    await service.restoreWindowPlacement();
    await service.saveWindowPlacement();
    await service.unregisterAll();
    await service.register('selection.translate', 'Ctrl+Alt+E');
    await service.speak('你好');
    await service.quitApp();

    expect(calls.map((call) => call.method), [
      'startup.setLaunchAtStartup',
      'window.setAlwaysOnTop',
      'window.setCloseToTray',
      'window.setHideOnBlur',
      'tray.install',
      'tray.updateMenu',
      'window.show',
      'window.restorePlacement',
      'window.savePlacement',
      'hotkey.unregisterAll',
      'hotkey.register',
      'speech.speak',
      'app.quit',
    ]);
    expect(calls[0].arguments, {'enabled': true});
    expect(calls[1].arguments, {'enabled': true});
    expect(calls[2].arguments, {'enabled': false});
    expect(calls[3].arguments, {'enabled': true});
    expect(calls[4].arguments, isNull);
    expect(calls[5].arguments, isNull);
    expect(calls[6].arguments, isNull);
    expect(calls[7].arguments, isNull);
    expect(calls[8].arguments, isNull);
    expect(calls[9].arguments, isNull);
    expect(calls[10].arguments, {
      'action': 'selection.translate',
      'accelerator': 'Ctrl+Alt+E',
    });
    expect(calls[11].arguments, {'text': '你好'});
    expect(calls[12].arguments, isNull);
  });

  test('selection and screenshot methods return text', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'selection.readText' => 'selected text',
        'screenshot.captureAndRecognize' => 'ocr text',
        _ => null,
      };
    });
    const service = MethodChannelWindowsPlatformService();

    expect(await service.readSelectedText(), 'selected text');
    expect(
      await service.captureAndRecognize(translateAfterRecognition: true),
      'ocr text',
    );
  });

  test('system appearance methods use the stable native contract', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'theme.getSystemPreferences') {
        return <Object?, Object?>{
          'accentArgb': 0xFF0078D4,
          'animationsEnabled': false,
        };
      }
      return null;
    });
    const service = MethodChannelWindowsPlatformService();

    final preferences = await service.getSystemPreferences();
    await service.applyWindowAppearance(darkMode: true);

    expect(preferences.accentArgb, 0xFF0078D4);
    expect(preferences.animationsEnabled, isFalse);
    expect(calls.map((call) => call.method), [
      'theme.getSystemPreferences',
      'theme.applyWindowAppearance',
    ]);
    expect(calls.last.arguments, {'darkMode': true});
  });

  test('platform error codes remain available to OCR callers', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'ocr_cancelled',
        message: 'Capture cancelled.',
      );
    });
    const service = MethodChannelWindowsPlatformService();

    expect(
      service.captureAndRecognize(translateAfterRecognition: false),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'ocr_cancelled',
        ),
      ),
    );
  });

  test('update installer uses the native launch contract', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    const service = MethodChannelWindowsPlatformService();

    await service.launchUpdateInstaller(
      r'C:\Temp\Pythia-1.0.1-windows-x64.exe',
    );

    expect(received?.method, 'update.launchInstaller');
    expect(received?.arguments, {
      'path': r'C:\Temp\Pythia-1.0.1-windows-x64.exe',
    });
  });

  test('system notification uses the native notification contract', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    const service = MethodChannelWindowsPlatformService();

    await service.showNotification(
      title: 'Pythia 自动同步',
      body: '历史记录同步失败',
      level: WindowsNotificationLevel.error,
    );

    expect(received?.method, 'notification.show');
    expect(received?.arguments, {
      'title': 'Pythia 自动同步',
      'body': '历史记录同步失败',
      'level': 'error',
    });
  });

  test('hotkey callback dispatches native action to Dart handler', () async {
    final actions = <String>[];
    const service = MethodChannelWindowsPlatformService();
    service.setHotkeyHandler((action) async {
      actions.add(action);
    });

    final codec = const StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'pythia/windows_platform',
      codec.encodeMethodCall(
        const MethodCall('hotkey.triggered', 'selection.translate'),
      ),
      (_) {},
    );

    expect(actions, ['selection.translate']);
  });

  test('tray callback dispatches native action without replacing hotkeys',
      () async {
    final hotkeyActions = <String>[];
    final trayActions = <String>[];
    const service = MethodChannelWindowsPlatformService();
    service.setHotkeyHandler((action) async {
      hotkeyActions.add(action);
    });
    service.setTrayActionHandler((action) async {
      trayActions.add(action);
    });

    final codec = const StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'pythia/windows_platform',
      codec.encodeMethodCall(
        const MethodCall('tray.action', 'settings.open'),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      'pythia/windows_platform',
      codec.encodeMethodCall(
        const MethodCall('hotkey.triggered', 'selection.translate'),
      ),
      (_) {},
    );

    expect(trayActions, ['settings.open']);
    expect(hotkeyActions, ['selection.translate']);
  });

  test('removing hotkey handler keeps tray callback installed', () async {
    final trayActions = <String>[];
    const service = MethodChannelWindowsPlatformService();
    service.setHotkeyHandler((_) async {});
    service.setTrayActionHandler((action) async {
      trayActions.add(action);
    });
    service.setHotkeyHandler(null);

    final codec = const StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'pythia/windows_platform',
      codec.encodeMethodCall(
        const MethodCall('tray.action', 'history.sync'),
      ),
      (_) {},
    );

    expect(trayActions, ['history.sync']);
  });
}
