import 'dart:convert';

import 'package:http/http.dart' as http;

import 'webdav_sync.dart';

class WebDavPortableBackupService {
  final http.Client client;

  const WebDavPortableBackupService({required this.client});

  Future<void> upload(
    String encoded,
    WebDavCredentials credentials,
  ) async {
    _requireCredentials(credentials);
    final root = _rootUrl(credentials.baseUrl);
    final settingsFolder = root.resolve('settings/');
    final temporary = settingsFolder.resolve('portable-backup.tmp.json');
    final destination = settingsFolder.resolve('portable-backup.json');
    final headers = _headers(credentials);

    await _ensureFolder(root, headers);
    await _ensureFolder(settingsFolder, headers);
    final temporaryUpload = await client
        .put(
          temporary,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: encoded,
        )
        .timeout(const Duration(seconds: 45));
    _requireSuccess(temporaryUpload, '上传临时备份失败');

    final move = http.Request('MOVE', temporary)
      ..headers.addAll({
        ...headers,
        'Destination': destination.toString(),
        'Overwrite': 'T',
      });
    final moveResponse = await client
        .send(move)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    if (_isSuccess(moveResponse.statusCode)) return;

    final finalUpload = await client
        .put(
          destination,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: encoded,
        )
        .timeout(const Duration(seconds: 45));
    _requireSuccess(finalUpload, '上传正式备份失败');
    try {
      await client.delete(temporary, headers: headers).timeout(
            const Duration(seconds: 15),
          );
    } catch (_) {
      // The final backup already exists; temporary-file cleanup is best effort.
    }
  }

  Future<String> download(WebDavCredentials credentials) async {
    _requireCredentials(credentials);
    final file =
        _rootUrl(credentials.baseUrl).resolve('settings/portable-backup.json');
    final response = await client
        .get(file, headers: _headers(credentials))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode == 404) {
      throw StateError('远程没有可恢复的 Pythia 备份。');
    }
    _requireSuccess(response, '下载远程备份失败');
    if (response.body.trim().isEmpty) {
      throw StateError('远程备份为空。');
    }
    return response.body;
  }

  Future<void> _ensureFolder(
    Uri folder,
    Map<String, String> headers,
  ) async {
    final request = http.Request('MKCOL', folder)..headers.addAll(headers);
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (_isSuccess(response.statusCode) ||
        response.statusCode == 405 ||
        response.statusCode == 409) {
      return;
    }
    throw StateError('创建 WebDAV 备份目录失败（HTTP ${response.statusCode}）。');
  }

  static Uri _rootUrl(String baseUrl) {
    var value = baseUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (!value.startsWith('https://') && !value.startsWith('http://')) {
      value = 'https://$value';
    }
    final parsed = Uri.parse(value);
    if (parsed.pathSegments.isNotEmpty &&
        parsed.pathSegments.last.toLowerCase() == 'pythia') {
      return Uri.parse('$value/');
    }
    return Uri.parse('$value/Pythia/');
  }

  static Map<String, String> _headers(WebDavCredentials credentials) {
    if (credentials.username.isEmpty) return const {};
    final encoded = base64Encode(
      utf8.encode('${credentials.username}:${credentials.password}'),
    );
    return {'Authorization': 'Basic $encoded'};
  }

  static void _requireCredentials(WebDavCredentials credentials) {
    if (!credentials.isUsable) {
      throw StateError('请先配置 WebDAV 地址。');
    }
  }

  static bool _isSuccess(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  static void _requireSuccess(http.Response response, String action) {
    if (!_isSuccess(response.statusCode)) {
      throw StateError('$action（HTTP ${response.statusCode}）。');
    }
  }
}
