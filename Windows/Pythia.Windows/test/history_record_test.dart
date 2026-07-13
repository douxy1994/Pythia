import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/history_record.dart';

void main() {
  test('favorite and sync status survive JSON round trip', () {
    final record = PythiaHistoryRecord(
      id: '1',
      sourceText: 'hello',
      translatedText: '你好',
      sourceLanguage: 'en',
      targetLanguage: 'zh-CN',
      service: 'OpenAI Compatible',
      model: 'gpt-4o-mini',
      createdAt: DateTime.parse('2026-07-07T00:00:00Z'),
      updatedAt: DateTime.parse('2026-07-07T00:01:00Z'),
      isFavorite: true,
      deviceId: 'device-a',
      syncStatus: PythiaSyncStatus.pendingUpload,
    );

    final restored = PythiaHistoryRecord.fromJson(record.toJson());

    expect(restored.isFavorite, isTrue);
    expect(restored.syncStatus, PythiaSyncStatus.pendingUpload);
    expect(restored.model, 'gpt-4o-mini');
  });

  test('logical deletion flag survives JSON round trip', () {
    final record = PythiaHistoryRecord(
      id: '1',
      sourceText: 'hello',
      translatedText: '你好',
      sourceLanguage: 'en',
      targetLanguage: 'zh-CN',
      service: 'Local',
      createdAt: DateTime.parse('2026-07-07T00:00:00Z'),
      updatedAt: DateTime.parse('2026-07-07T00:01:00Z'),
      deviceId: 'device-a',
      syncStatus: PythiaSyncStatus.pendingDelete,
      deletedAt: DateTime.parse('2026-07-07T00:02:00Z'),
    );

    final restored = PythiaHistoryRecord.fromJson(record.toJson());

    expect(restored.isDeleted, isTrue);
    expect(restored.syncStatus, PythiaSyncStatus.pendingDelete);
    expect(restored.deletedAt, DateTime.parse('2026-07-07T00:02:00Z'));
  });
}
