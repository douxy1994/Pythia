import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/webdav_sync.dart';
import 'package:pythia_windows/core/webdav_sync_retry.dart';

void main() {
  WebDavHistorySyncResult result(int code, {String? error}) {
    return WebDavHistorySyncResult(
      downloadedCount: 0,
      uploadedCount: 0,
      visibleCount: 0,
      conflictCount: 0,
      httpCode: code,
      errorMessage: error,
    );
  }

  test('retries transient failures and returns the successful result',
      () async {
    var attempts = 0;
    final delays = <Duration>[];
    final policy = WebDavSyncRetryPolicy(
      sleep: (delay) async => delays.add(delay),
    );

    final actual = await policy.run(() async {
      attempts += 1;
      return attempts < 3 ? result(-1, error: 'timeout') : result(204);
    });

    expect(actual.isSuccess, isTrue);
    expect(attempts, 3);
    expect(delays, const [Duration(seconds: 1), Duration(seconds: 3)]);
  });

  test('does not retry authentication or corrupt-data failures', () async {
    var attempts = 0;
    const policy = WebDavSyncRetryPolicy();

    final auth = await policy.run(() async {
      attempts += 1;
      return result(401, error: 'unauthorized');
    });

    expect(auth.httpCode, 401);
    expect(attempts, 1);
    expect(
        WebDavSyncRetryPolicy.isTransient(result(
          200,
          error: '远程历史文件损坏，已停止同步以保护本地数据',
        )),
        isFalse);
  });
}
