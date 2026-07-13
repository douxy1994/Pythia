import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pythia_windows/core/history_record.dart';
import 'package:pythia_windows/core/history_sync.dart';
import 'package:pythia_windows/core/webdav_sync.dart';

void main() {
  test('remote new record is added', () {
    final local = [record(id: '1', text: 'hello', updatedAt: 10)];
    final remote = [record(id: '2', text: 'world', updatedAt: 20)];

    final result = PythiaHistoryMerger.merge(local: local, remote: remote);

    expect(result.merged.map((record) => record.id), ['2', '1']);
    expect(result.conflicts, isEmpty);
  });

  test('newer update wins for the same id', () {
    final local = [record(id: '1', text: 'old', updatedAt: 10)];
    final remote = [record(id: '1', text: 'new', updatedAt: 20)];

    final result = PythiaHistoryMerger.merge(local: local, remote: remote);

    expect(result.merged.first.sourceText, 'new');
    expect(result.merged.first.syncStatus, PythiaSyncStatus.synced);
  });

  test('logical deletion wins over a newer non-deleted record', () {
    final local = [
      record(
        id: '1',
        text: 'deleted',
        updatedAt: 10,
        deletedAt: 11,
        status: PythiaSyncStatus.pendingDelete,
      ),
    ];
    final remote = [record(id: '1', text: 'remote edit', updatedAt: 20)];

    final result = PythiaHistoryMerger.merge(local: local, remote: remote);

    expect(result.merged.first.deletedAt, isNotNull);
    expect(result.merged.first.syncStatus, PythiaSyncStatus.pendingDelete);
  });

  test('same timestamp different content reports conflict', () {
    final local = [record(id: '1', text: 'local', updatedAt: 10)];
    final remote = [record(id: '1', text: 'remote', updatedAt: 10)];

    final result = PythiaHistoryMerger.merge(local: local, remote: remote);

    expect(result.conflicts, hasLength(1));
    expect(result.conflicts.first.syncStatus, PythiaSyncStatus.conflict);
  });

  test('corrupt remote history does not replace local data', () async {
    final repository = MemoryHistoryRepository([
      record(id: '1', text: 'local', updatedAt: 10),
    ]);
    final client = MockClient((request) async {
      if (request.method == 'MKCOL') {
        return http.Response('', 405);
      }
      if (request.method == 'GET') {
        return http.Response('{broken-json', 200);
      }
      return http.Response('', 500);
    });
    final sync = WebDavHistorySyncService(
      client: client,
      historyRepository: repository,
    );

    final result = await sync.sync(const WebDavCredentials(
      baseUrl: 'https://example.com/dav',
      username: 'user',
      password: 'pass',
    ));

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('远程历史文件损坏'));
    expect(repository.replaceCalls, 0);
    expect(repository.records.single.sourceText, 'local');
  });

  test('WebDAV connection test accepts missing remote history file', () async {
    final repository = MemoryHistoryRepository(<PythiaHistoryRecord>[]);
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add('${request.method} ${request.url.path}');
      if (request.method == 'MKCOL') {
        return http.Response('', 405);
      }
      if (request.method == 'GET') {
        return http.Response('', 404);
      }
      return http.Response('', 500);
    });
    final sync = WebDavHistorySyncService(
      client: client,
      historyRepository: repository,
    );

    final result = await sync.testConnection(const WebDavCredentials(
      baseUrl: 'https://example.com/dav',
      username: 'user',
      password: 'pass',
    ));

    expect(result.isSuccess, isTrue);
    expect(result.message, contains('连接正常'));
    expect(requested, [
      'MKCOL /dav/Pythia/',
      'MKCOL /dav/Pythia/history/',
      'GET /dav/Pythia/history/history.json',
    ]);
    expect(repository.backupCalls, 0);
    expect(repository.replaceCalls, 0);
  });

  test('WebDAV connection test reports authentication failure', () async {
    final repository = MemoryHistoryRepository(<PythiaHistoryRecord>[]);
    final client = MockClient((request) async => http.Response('', 401));
    final sync = WebDavHistorySyncService(
      client: client,
      historyRepository: repository,
    );

    final result = await sync.testConnection(const WebDavCredentials(
      baseUrl: 'https://example.com/dav',
      username: 'user',
      password: 'bad-pass',
    ));

    expect(result.isSuccess, isFalse);
    expect(result.httpCode, 401);
    expect(result.message, contains('账号或密码错误'));
    expect(repository.backupCalls, 0);
    expect(repository.replaceCalls, 0);
  });
}

PythiaHistoryRecord record({
  required String id,
  required String text,
  required num updatedAt,
  num? deletedAt,
  PythiaSyncStatus status = PythiaSyncStatus.local,
}) {
  return PythiaHistoryRecord(
    id: id,
    sourceText: text,
    translatedText: 'translated $text',
    sourceLanguage: 'auto',
    targetLanguage: 'zh-CN',
    service: 'Google',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (updatedAt * 1000).round(),
      isUtc: true,
    ),
    deviceId: 'test-device',
    syncStatus: status,
    deletedAt: deletedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (deletedAt * 1000).round(),
            isUtc: true,
          ),
  );
}

class MemoryHistoryRepository implements HistoryRepository {
  List<PythiaHistoryRecord> records;
  int backupCalls = 0;
  int replaceCalls = 0;

  MemoryHistoryRepository(this.records);

  @override
  Future<void> backupBeforeSync() async {
    backupCalls += 1;
  }

  @override
  Future<String> deviceId() async => 'test-device';

  @override
  Future<List<PythiaHistoryRecord>> readAllForSync() async => records;

  @override
  Future<void> replaceAllFromSync(List<PythiaHistoryRecord> records) async {
    replaceCalls += 1;
    this.records = records;
  }
}
