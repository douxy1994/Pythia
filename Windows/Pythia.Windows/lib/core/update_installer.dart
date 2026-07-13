import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'update_checker.dart';

typedef UpdateDownloadProgress = void Function(int received, int total);

class PythiaReleaseInstaller {
  static const maximumInstallerBytes = 512 * 1024 * 1024;

  final http.Client client;

  const PythiaReleaseInstaller({required this.client});

  Future<File> downloadVerified(
    PythiaInstallerAsset asset,
    Directory directory, {
    UpdateDownloadProgress? onProgress,
  }) async {
    _validateAsset(asset);
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${asset.name}',
    );
    try {
      final checksumResponse = await _sendTrusted(asset.checksumUrl);
      final checksumBytes = await _readSmallBody(checksumResponse, 4096);
      if (checksumResponse.statusCode != 200) {
        throw StateError('无法读取更新校验文件。');
      }
      final checksumBody = String.fromCharCodes(checksumBytes);
      final checksumMatch =
          RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(checksumBody);
      if (checksumMatch == null) {
        throw StateError('更新校验文件不包含有效 SHA-256。');
      }
      final expectedHash = checksumMatch.group(0)!.toLowerCase();

      final response = await _sendTrusted(asset.downloadUrl);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('更新下载失败（HTTP ${response.statusCode}）。');
      }
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 45),
        )) {
          received += chunk.length;
          if (received > asset.size || received > maximumInstallerBytes) {
            throw StateError('更新文件大小超过 Release 声明值。');
          }
          sink.add(chunk);
          onProgress?.call(received, asset.size);
        }
      } finally {
        await sink.close();
      }
      if (received != asset.size) {
        throw StateError('更新文件大小与 Release 声明不一致。');
      }
      final actualHash = await sha256.bind(file.openRead()).first;
      if (actualHash.toString().toLowerCase() != expectedHash) {
        throw StateError('更新文件 SHA-256 校验失败。');
      }
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  static void _validateAsset(PythiaInstallerAsset asset) {
    final lowerName = asset.name.toLowerCase();
    final safeName = !asset.name.contains('/') &&
        !asset.name.contains('\\') &&
        !asset.name.contains('..');
    final supportedName = lowerName.contains('pythia') &&
        lowerName.contains('windows') &&
        lowerName.contains('x64') &&
        (lowerName.endsWith('.exe') || lowerName.endsWith('.msix'));
    if (!safeName || !supportedName) {
      throw ArgumentError('Release 资产不是受支持的 Pythia Windows x64 安装器。');
    }
    if (!_isTrustedGitHubUrl(asset.downloadUrl) ||
        !_isTrustedGitHubUrl(asset.checksumUrl)) {
      throw ArgumentError('更新下载地址必须是 GitHub HTTPS 地址。');
    }
    if (asset.size <= 0 || asset.size > maximumInstallerBytes) {
      throw ArgumentError('更新文件大小无效。');
    }
  }

  static bool _isTrustedGitHubUrl(Uri url) {
    if (url.scheme != 'https') return false;
    final host = url.host.toLowerCase();
    return host == 'github.com' || host.endsWith('.githubusercontent.com');
  }

  Future<http.StreamedResponse> _sendTrusted(Uri initialUrl) async {
    var url = initialUrl;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount += 1) {
      if (!_isTrustedGitHubUrl(url)) {
        throw StateError('更新下载被重定向到非 GitHub 地址。');
      }
      final request = http.Request('GET', url)..followRedirects = false;
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      if (response.isRedirect) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) {
          throw StateError('更新下载重定向缺少目标地址。');
        }
        url = url.resolve(location);
        continue;
      }
      return response;
    }
    throw StateError('更新下载重定向次数过多。');
  }

  static Future<List<int>> _readSmallBody(
    http.StreamedResponse response,
    int maximumBytes,
  ) async {
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > maximumBytes) {
        throw StateError('更新校验文件过大。');
      }
    }
    return bytes;
  }
}
