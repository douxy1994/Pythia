import 'dart:convert';

import 'package:http/http.dart' as http;

const pythiaCurrentVersion = '1.0.0';
const pythiaLatestReleaseApi =
    'https://api.github.com/repos/douxy1994/Pythia/releases/latest';
const pythiaReleasesUrl = 'https://github.com/douxy1994/Pythia/releases';

class PythiaUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final Uri releaseUrl;
  final PythiaInstallerAsset? installer;

  const PythiaUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseUrl,
    this.installer,
  });

  bool get isNewer =>
      PythiaUpdateChecker.compareVersions(latestVersion, currentVersion) > 0;
}

class PythiaInstallerAsset {
  final String name;
  final Uri downloadUrl;
  final Uri checksumUrl;
  final int size;

  const PythiaInstallerAsset({
    required this.name,
    required this.downloadUrl,
    required this.checksumUrl,
    required this.size,
  });
}

class PythiaUpdateChecker {
  final http.Client client;
  final String latestReleaseApi;
  final String currentVersion;

  const PythiaUpdateChecker({
    required this.client,
    this.latestReleaseApi = pythiaLatestReleaseApi,
    this.currentVersion = pythiaCurrentVersion,
  });

  Future<PythiaUpdateInfo> check() async {
    final response = await client.get(
      Uri.parse(latestReleaseApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Pythia-Windows/1.0.0',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('更新检查失败（HTTP ${response.statusCode}）。');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final tag = payload['tag_name'] as String? ?? '';
    final latest = normalizedVersion(tag);
    if (latest.isEmpty) {
      throw StateError('GitHub Release 没有有效版本号。');
    }
    final htmlUrl = Uri.tryParse(payload['html_url'] as String? ?? '') ??
        Uri.parse(pythiaReleasesUrl);
    final installer = _installerFromAssets(payload['assets']);
    return PythiaUpdateInfo(
      currentVersion: normalizedVersion(currentVersion),
      latestVersion: latest,
      releaseName: payload['name'] as String? ?? tag,
      releaseUrl: htmlUrl,
      installer: installer,
    );
  }

  static PythiaInstallerAsset? _installerFromAssets(Object? rawAssets) {
    if (rawAssets is! List<Object?>) return null;
    final assets = <String, Map<String, Object?>>{};
    for (final raw in rawAssets) {
      if (raw is! Map<String, Object?>) continue;
      final name = raw['name'] as String? ?? '';
      if (name.isNotEmpty) assets[name.toLowerCase()] = raw;
    }
    final candidates = assets.values.where((asset) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      return name.contains('pythia') &&
          name.contains('windows') &&
          name.contains('x64') &&
          (name.endsWith('.exe') || name.endsWith('.msix'));
    }).toList()
      ..sort((left, right) =>
          (left['name'] as String).compareTo(right['name'] as String));
    for (final candidate in candidates) {
      final name = candidate['name'] as String;
      final checksum = assets['${name.toLowerCase()}.sha256'];
      if (checksum == null) continue;
      final downloadUrl = Uri.tryParse(
        candidate['browser_download_url'] as String? ?? '',
      );
      final checksumUrl = Uri.tryParse(
        checksum['browser_download_url'] as String? ?? '',
      );
      final size = candidate['size'] as int? ?? 0;
      if (downloadUrl == null || checksumUrl == null || size <= 0) continue;
      return PythiaInstallerAsset(
        name: name,
        downloadUrl: downloadUrl,
        checksumUrl: checksumUrl,
        size: size,
      );
    }
    return null;
  }

  static String normalizedVersion(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  static int compareVersions(String lhs, String rhs) {
    final left = _versionParts(lhs);
    final right = _versionParts(rhs);
    final count = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < count; index += 1) {
      final l = index < left.length ? left[index] : 0;
      final r = index < right.length ? right[index] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    return normalizedVersion(version)
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}
