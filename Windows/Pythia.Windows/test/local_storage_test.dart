import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/history_record.dart';
import 'package:pythia_windows/core/local_storage.dart';

void main() {
  test('first history record can be added to a new profile', () async {
    final directory = await Directory.systemTemp.createTemp('pythia-store-');
    addTearDown(() => directory.delete(recursive: true));
    final store = PythiaLocalStore(baseDirectory: directory);
    final now = DateTime.utc(2026, 7, 16);

    await store.addHistory(PythiaHistoryRecord(
      id: 'first',
      sourceText: 'hello',
      translatedText: '你好',
      sourceLanguage: 'en',
      targetLanguage: 'zh-CN',
      service: 'Local',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test-device',
    ));

    final records = await store.readVisibleHistory();
    expect(records, hasLength(1));
    expect(records.single.sourceText, 'hello');
    expect(records.single.syncStatus, PythiaSyncStatus.pendingUpload);
  });
}
