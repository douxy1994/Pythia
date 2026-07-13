import 'webdav_sync.dart';

typedef RetrySleep = Future<void> Function(Duration delay);

class WebDavSyncRetryPolicy {
  final int maxAttempts;
  final RetrySleep sleep;

  const WebDavSyncRetryPolicy({
    this.maxAttempts = 3,
    this.sleep = _defaultSleep,
  });

  Future<WebDavHistorySyncResult> run(
    Future<WebDavHistorySyncResult> Function() operation,
  ) async {
    WebDavHistorySyncResult result;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      result = await operation();
      if (!isTransient(result) || attempt == maxAttempts) return result;
      await sleep(Duration(seconds: attempt == 1 ? 1 : 3));
    }
    throw StateError('WebDAV retry loop completed without a result.');
  }

  static bool isTransient(WebDavHistorySyncResult result) {
    if (result.isSuccess) return false;
    if (result.errorMessage?.contains('远程历史文件损坏') == true) return false;
    return result.httpCode == -1 ||
        result.httpCode == 408 ||
        result.httpCode == 429 ||
        (result.httpCode >= 500 && result.httpCode <= 599);
  }

  static Future<void> _defaultSleep(Duration delay) =>
      Future<void>.delayed(delay);
}
