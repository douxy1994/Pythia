import 'dart:convert';

import 'package:http/http.dart' as http;

import 'history_record.dart';
import 'history_sync.dart';

class WebDavCredentials {
  final String baseUrl;
  final String username;
  final String password;

  const WebDavCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  bool get isUsable => baseUrl.trim().isNotEmpty;
}

class WebDavHistorySyncResult {
  final int downloadedCount;
  final int uploadedCount;
  final int visibleCount;
  final int conflictCount;
  final int httpCode;
  final String? errorMessage;

  const WebDavHistorySyncResult({
    required this.downloadedCount,
    required this.uploadedCount,
    required this.visibleCount,
    required this.conflictCount,
    required this.httpCode,
    this.errorMessage,
  });

  bool get isSuccess =>
      errorMessage == null && httpCode >= 200 && httpCode < 300;
}

class WebDavConnectionTestResult {
  final bool isSuccess;
  final int httpCode;
  final String message;
  final int remoteRecordCount;

  const WebDavConnectionTestResult({
    required this.isSuccess,
    required this.httpCode,
    required this.message,
    this.remoteRecordCount = 0,
  });
}

abstract interface class HistoryRepository {
  Future<List<PythiaHistoryRecord>> readAllForSync();
  Future<void> backupBeforeSync();
  Future<void> replaceAllFromSync(List<PythiaHistoryRecord> records);
  Future<String> deviceId();
}

class WebDavHistorySyncService {
  final http.Client client;
  final HistoryRepository historyRepository;

  const WebDavHistorySyncService({
    required this.client,
    required this.historyRepository,
  });

  Future<WebDavHistorySyncResult> sync(WebDavCredentials credentials) async {
    if (!credentials.isUsable) {
      return const WebDavHistorySyncResult(
        downloadedCount: 0,
        uploadedCount: 0,
        visibleCount: 0,
        conflictCount: 0,
        httpCode: -1,
        errorMessage: '请先填写 WebDAV 地址。',
      );
    }

    final rootUrl = _syncRootUrl(credentials.baseUrl);
    final historyUrl = rootUrl.resolve('history/');
    final historyFileUrl = historyUrl.resolve('history.json');
    final auth = _authHeader(credentials);

    try {
      final root = await _ensureFolder(rootUrl, auth);
      if (!_isFolderOk(root.statusCode)) {
        return _httpFailure(root.statusCode);
      }
      final historyFolder = await _ensureFolder(historyUrl, auth);
      if (!_isFolderOk(historyFolder.statusCode)) {
        return _httpFailure(historyFolder.statusCode);
      }

      final remote = await _fetchRemoteHistory(historyFileUrl, auth);
      if (remote.error != null) {
        return WebDavHistorySyncResult(
          downloadedCount: 0,
          uploadedCount: 0,
          visibleCount: 0,
          conflictCount: 0,
          httpCode: remote.httpCode,
          errorMessage: remote.error,
        );
      }

      await historyRepository.backupBeforeSync();
      final localRecords = await historyRepository.readAllForSync();
      final merged = PythiaHistoryMerger.merge(
        local: localRecords,
        remote: remote.records,
      );
      await historyRepository.replaceAllFromSync(merged.merged);
      final recordsToUpload = await historyRepository.readAllForSync();
      final collection = PythiaHistoryCollection(
        deviceId: await historyRepository.deviceId(),
        updatedAt: DateTime.now().toUtc(),
        records: recordsToUpload,
      );
      final upload = await client
          .put(
            historyFileUrl,
            headers: {
              if (auth != null) 'Authorization': auth,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(collection.toJson()),
          )
          .timeout(const Duration(seconds: 45));
      if (upload.statusCode < 200 || upload.statusCode >= 300) {
        return _httpFailure(
          upload.statusCode,
          downloadedCount: remote.records.length,
          conflictCount: merged.conflicts.length,
        );
      }
      return WebDavHistorySyncResult(
        downloadedCount: remote.records.length,
        uploadedCount: recordsToUpload.length,
        visibleCount:
            recordsToUpload.where((record) => !record.isDeleted).length,
        conflictCount: merged.conflicts.length,
        httpCode: upload.statusCode,
      );
    } catch (error) {
      return WebDavHistorySyncResult(
        downloadedCount: 0,
        uploadedCount: 0,
        visibleCount: 0,
        conflictCount: 0,
        httpCode: -1,
        errorMessage: error.toString(),
      );
    }
  }

  Future<WebDavConnectionTestResult> testConnection(
    WebDavCredentials credentials,
  ) async {
    if (!credentials.isUsable) {
      return const WebDavConnectionTestResult(
        isSuccess: false,
        httpCode: -1,
        message: '请先填写 WebDAV 地址。',
      );
    }

    final rootUrl = _syncRootUrl(credentials.baseUrl);
    final historyUrl = rootUrl.resolve('history/');
    final historyFileUrl = historyUrl.resolve('history.json');
    final auth = _authHeader(credentials);

    try {
      final root = await _ensureFolder(rootUrl, auth);
      if (!_isFolderOk(root.statusCode)) {
        return WebDavConnectionTestResult(
          isSuccess: false,
          httpCode: root.statusCode,
          message: _errorHint(root.statusCode),
        );
      }
      final historyFolder = await _ensureFolder(historyUrl, auth);
      if (!_isFolderOk(historyFolder.statusCode)) {
        return WebDavConnectionTestResult(
          isSuccess: false,
          httpCode: historyFolder.statusCode,
          message: _errorHint(historyFolder.statusCode),
        );
      }

      final remote = await _fetchRemoteHistory(historyFileUrl, auth);
      if (remote.error != null) {
        return WebDavConnectionTestResult(
          isSuccess: false,
          httpCode: remote.httpCode,
          message: remote.error!,
        );
      }
      return WebDavConnectionTestResult(
        isSuccess: true,
        httpCode: remote.httpCode == 404 ? 200 : remote.httpCode,
        message: remote.records.isEmpty
            ? '连接正常，远程历史为空。'
            : '连接正常，远程历史 ${remote.records.length} 条。',
        remoteRecordCount: remote.records.length,
      );
    } catch (error) {
      return WebDavConnectionTestResult(
        isSuccess: false,
        httpCode: -1,
        message: 'WebDAV 请求超时或无法连接：$error',
      );
    }
  }

  Future<http.Response> _ensureFolder(Uri url, String? auth) {
    return client
        .send(http.Request('MKCOL', url)
          ..headers.addAll({if (auth != null) 'Authorization': auth}))
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
  }

  Future<_RemoteHistory> _fetchRemoteHistory(Uri url, String? auth) async {
    final response = await client.get(url, headers: {
      if (auth != null) 'Authorization': auth
    }).timeout(const Duration(seconds: 45));
    if (response.statusCode == 404) {
      return _RemoteHistory(httpCode: response.statusCode, records: const []);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _RemoteHistory(
        httpCode: response.statusCode,
        records: const [],
        error: _errorHint(response.statusCode),
      );
    }
    if (response.body.trim().isEmpty) {
      return _RemoteHistory(httpCode: response.statusCode, records: const []);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return _RemoteHistory(
          httpCode: response.statusCode,
          records: decoded
              .cast<Map<String, Object?>>()
              .map(PythiaHistoryRecord.fromJson)
              .toList(),
        );
      }
      final collection =
          PythiaHistoryCollection.fromJson(decoded as Map<String, Object?>);
      return _RemoteHistory(
        httpCode: response.statusCode,
        records: collection.records,
      );
    } catch (error) {
      return _RemoteHistory(
        httpCode: response.statusCode,
        records: const [],
        error: '远程历史文件损坏，已停止同步以保护本地数据：$error',
      );
    }
  }

  static Uri _syncRootUrl(String baseUrl) {
    var trimmed = baseUrl.trim();
    while (trimmed.endsWith('//')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.parse(trimmed);
    if (uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last.toLowerCase() == 'pythia') {
      return Uri.parse('$trimmed/');
    }
    return Uri.parse('$trimmed/Pythia/');
  }

  static String? _authHeader(WebDavCredentials credentials) {
    if (credentials.username.isEmpty) return null;
    final token = base64Encode(
        utf8.encode('${credentials.username}:${credentials.password}'));
    return 'Basic $token';
  }

  static bool _isFolderOk(int statusCode) {
    return (statusCode >= 200 && statusCode < 300) ||
        statusCode == 405 ||
        statusCode == 409;
  }

  static WebDavHistorySyncResult _httpFailure(
    int code, {
    int downloadedCount = 0,
    int conflictCount = 0,
  }) {
    return WebDavHistorySyncResult(
      downloadedCount: downloadedCount,
      uploadedCount: 0,
      visibleCount: 0,
      conflictCount: conflictCount,
      httpCode: code,
      errorMessage: _errorHint(code),
    );
  }

  static String _errorHint(int code) {
    return switch (code) {
      401 => '账号或密码错误；坚果云需用应用专属密码。',
      403 => '无权限，请检查账号或目录权限。',
      404 => '地址不存在。',
      405 => '服务器不允许该 WebDAV 方法。',
      409 => '父目录不存在。',
      -1 => 'WebDAV 请求超时或无法连接。',
      _ => 'WebDAV 请求失败（HTTP $code）。',
    };
  }
}

class _RemoteHistory {
  final int httpCode;
  final List<PythiaHistoryRecord> records;
  final String? error;

  const _RemoteHistory({
    required this.httpCode,
    required this.records,
    this.error,
  });
}
