import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/settings_model.dart';

void main() {
  test('persists the Windows notification preference', () {
    const settings = PythiaSettings(notificationsEnabled: false);

    final restored = PythiaSettings.fromJson(settings.toJson());

    expect(restored.notificationsEnabled, isFalse);
    expect(const PythiaSettings().notificationsEnabled, isTrue);
  });

  test('disabled OpenAI-compatible service is removed from enabled services',
      () {
    final settings = const PythiaSettings(
      openAICompatibleEnabled: false,
      enabledTranslateServices: [
        PythiaSettings.openAICompatibleServiceId,
        'local',
      ],
      translateServiceOrder: [
        PythiaSettings.openAICompatibleServiceId,
        'local',
      ],
    ).normalized();

    expect(
      settings.enabledTranslateServices,
      isNot(contains(PythiaSettings.openAICompatibleServiceId)),
    );
    expect(settings.enabledTranslateServices, contains('local'));
  });

  test('enabled OpenAI-compatible service is not forced into active list', () {
    final settings = const PythiaSettings(
      openAICompatibleEnabled: true,
      enabledTranslateServices: ['local'],
      translateServiceOrder: ['local'],
    ).normalized();

    expect(settings.enabledTranslateServices, ['local']);
  });

  test('disabled built-in providers are removed from enabled services', () {
    final settings = const PythiaSettings(
      deepLEnabled: false,
      libreTranslateEnabled: false,
      enabledTranslateServices: [
        PythiaSettings.deepLServiceId,
        PythiaSettings.libreTranslateServiceId,
        'local',
      ],
      translateServiceOrder: [
        PythiaSettings.deepLServiceId,
        PythiaSettings.libreTranslateServiceId,
        'local',
      ],
    ).normalized();

    expect(settings.enabledTranslateServices, ['local']);
    expect(settings.translateServiceOrder, ['local']);
  });

  test('built-in provider settings survive JSON round trip', () {
    final settings = const PythiaSettings(
      googleEnabled: true,
      baiduEnabled: true,
      youdaoEnabled: true,
      deepLEnabled: true,
      deepLBaseUrl: 'https://api.deepl.com/v2',
      libreTranslateEnabled: true,
      libreTranslateBaseUrl: 'https://libre.example',
    );

    final restored = PythiaSettings.fromJson(settings.toJson());

    expect(restored.googleEnabled, isTrue);
    expect(restored.baiduEnabled, isTrue);
    expect(restored.youdaoEnabled, isTrue);
    expect(restored.deepLEnabled, isTrue);
    expect(restored.deepLBaseUrl, 'https://api.deepl.com/v2');
    expect(restored.libreTranslateEnabled, isTrue);
    expect(restored.libreTranslateBaseUrl, 'https://libre.example');
  });

  test('WebDAV sync status fields survive JSON round trip', () {
    final settings = const PythiaSettings(
      webdavLastSyncAt: '2026-07-07T00:00:00Z',
      webdavLastSyncStatus: '自动同步成功',
      webdavLastSyncError: '',
      showWindowHotkey: 'Ctrl+Alt+P',
      selectionTranslateHotkey: 'Ctrl+Shift+E',
      screenshotTranslateHotkey: 'Ctrl+Shift+S',
    );

    final restored = PythiaSettings.fromJson(settings.toJson());

    expect(restored.webdavLastSyncAt, '2026-07-07T00:00:00Z');
    expect(restored.webdavLastSyncStatus, '自动同步成功');
    expect(restored.webdavLastSyncError, '');
    expect(restored.showWindowHotkey, 'Ctrl+Alt+P');
    expect(restored.selectionTranslateHotkey, 'Ctrl+Shift+E');
    expect(restored.screenshotTranslateHotkey, 'Ctrl+Shift+S');
  });
}
