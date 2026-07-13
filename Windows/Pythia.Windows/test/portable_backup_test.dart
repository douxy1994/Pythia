import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/history_record.dart';
import 'package:pythia_windows/core/portable_backup.dart';
import 'package:pythia_windows/core/settings_model.dart';
import 'package:pythia_windows/core/webdav_sync.dart';

void main() {
  test('exports only portable non-secret settings and history', () async {
    final repository = _Repository([_record('local')]);
    final service = PortableBackupService(repository);
    const settings = PythiaSettings(
      sourceLanguage: 'en',
      targetLanguage: 'zh-CN',
      openAICompatibleEnabled: true,
      openAICompatibleName: 'Private provider',
      launchAtStartup: true,
      showWindowHotkey: 'Ctrl+Shift+P',
      webdavUrl: 'https://dav.example/private',
      webdavUsername: 'private-user',
    );

    final encoded = await service.create(settings);
    final json = jsonDecode(encoded) as Map<String, Object?>;
    final portable = json['settings'] as Map<String, Object?>;

    expect(json['product'], 'Pythia');
    expect(json['sensitiveFieldsOmitted'], isTrue);
    expect(portable['sourceLanguage'], 'en');
    expect(portable['openAICompatibleName'], 'Private provider');
    expect(portable, isNot(contains('launchAtStartup')));
    expect(portable, isNot(contains('showWindowHotkey')));
    expect(portable, isNot(contains('webdavUrl')));
    expect(portable, isNot(contains('webdavUsername')));
    expect(encoded, isNot(contains('dav.example')));
    expect((json['history'] as List<Object?>).length, 1);
  });

  test('restores portable settings while preserving device settings', () async {
    final local = _record('local');
    final imported = _record('imported');
    final repository = _Repository([local]);
    final service = PortableBackupService(repository);
    const current = PythiaSettings(
      sourceLanguage: 'auto',
      targetLanguage: 'en',
      launchAtStartup: true,
      closeToTray: false,
      showWindowHotkey: 'Ctrl+Shift+P',
      webdavUrl: 'https://dav.example',
      webdavUsername: 'user',
    );
    final backup = jsonEncode({
      'schemaVersion': 1,
      'product': 'Pythia',
      'createdAt': '2026-07-13T00:00:00Z',
      'sensitiveFieldsOmitted': true,
      'settings': {
        'sourceLanguage': 'zh-CN',
        'targetLanguage': 'ja',
        'saveHistory': false,
      },
      'history': [imported.toJson()],
    });

    final restored = await service.restore(backup, current);

    expect(restored.settings.sourceLanguage, 'zh-CN');
    expect(restored.settings.targetLanguage, 'ja');
    expect(restored.settings.saveHistory, isFalse);
    expect(restored.settings.launchAtStartup, isTrue);
    expect(restored.settings.closeToTray, isFalse);
    expect(restored.settings.showWindowHotkey, 'Ctrl+Shift+P');
    expect(restored.settings.webdavUrl, 'https://dav.example');
    expect(restored.settings.webdavUsername, 'user');
    expect(repository.backupCalls, 1);
    expect(repository.records.map((record) => record.id),
        containsAll(['local', 'imported']));
    expect(
      repository.records.where((record) => !record.isDeleted).every(
          (record) => record.syncStatus == PythiaSyncStatus.pendingUpload),
      isTrue,
    );
  });

  test('rejects foreign or malformed backup before changing history', () async {
    final repository = _Repository([_record('local')]);
    final service = PortableBackupService(repository);

    expect(
      () => service.restore(
        '{"schemaVersion":1,"product":"Other","settings":{},"history":[]}',
        const PythiaSettings(),
      ),
      throwsFormatException,
    );
    expect(repository.backupCalls, 0);
    expect(repository.records.single.id, 'local');
  });

  test('keeps supported canonical services and ignores unknown services',
      () async {
    final repository = _Repository([]);
    final backup = jsonEncode({
      'schemaVersion': 1,
      'product': 'Pythia',
      'createdAt': '2026-07-13T00:00:00Z',
      'sensitiveFieldsOmitted': true,
      'settings': {
        'enabledTranslateServices': ['google', 'caiyun', 'baidu', 'local'],
        'translateServiceOrder': ['google', 'caiyun', 'baidu', 'local'],
      },
      'history': <Object?>[],
    });

    final restored = await PortableBackupService(repository)
        .restore(backup, const PythiaSettings());

    expect(restored.settings.enabledTranslateServices,
        ['google', 'baidu', 'local']);
    expect(restored.settings.translateServiceOrder,
        ['google', 'baidu', 'local']);
  });
}

PythiaHistoryRecord _record(String id) {
  final time = DateTime.parse('2026-07-13T00:00:00Z');
  return PythiaHistoryRecord(
    id: id,
    sourceText: id,
    translatedText: '$id translated',
    sourceLanguage: 'en',
    targetLanguage: 'zh-CN',
    service: 'Local',
    createdAt: time,
    updatedAt: time,
    deviceId: 'test-device',
  );
}

class _Repository implements HistoryRepository {
  List<PythiaHistoryRecord> records;
  int backupCalls = 0;

  _Repository(this.records);

  @override
  Future<void> backupBeforeSync() async => backupCalls += 1;

  @override
  Future<String> deviceId() async => 'test-device';

  @override
  Future<List<PythiaHistoryRecord>> readAllForSync() async => List.of(records);

  @override
  Future<void> replaceAllFromSync(List<PythiaHistoryRecord> records) async {
    this.records = List.of(records);
  }
}
