import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ReleasePackageIssue {
  final String path;
  final String message;

  const ReleasePackageIssue({
    required this.path,
    required this.message,
  });

  @override
  String toString() => '$path: $message';
}

class ReleasePackageVerifier {
  static final List<_ForbiddenFileName> _forbiddenFileNames = [
    _ForbiddenFileName('legacy-plugin-runner.cjs', 'legacy Pot plugin runner'),
    _ForbiddenFileName('plugin-config.json', 'plugin configuration payload'),
    _ForbiddenFileName('plugin-configs.json', 'plugin configuration payload'),
    _ForbiddenFileName('tauri.conf.json', 'legacy Tauri application config'),
    _ForbiddenFileName('package.json', 'legacy web/Tauri package manifest'),
  ];

  static final List<_ContentPattern> _secretPatterns = [
    _ContentPattern(RegExp(r'TAURI_PRIVATE_KEY'), 'Tauri private key marker'),
    _ContentPattern(
      RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
      'private key block',
    ),
    _ContentPattern(
        RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b'), 'OpenAI-style API key'),
    _ContentPattern(RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b'), 'Slack token'),
    _ContentPattern(RegExp(r'\bAIza[0-9A-Za-z_-]{20,}\b'), 'Google API key'),
  ];

  Future<List<ReleasePackageIssue>> verify(Directory root) async {
    if (!await root.exists()) {
      return [
        ReleasePackageIssue(
          path: root.path,
          message: 'release package path does not exist',
        ),
      ];
    }

    final issues = <ReleasePackageIssue>[];
    issues.addAll(await _verifyX64Executable(
      File('${root.path}${Platform.pathSeparator}Pythia.exe'),
      'Pythia.exe',
    ));
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final relativePath = _relativePath(root, entity);
      issues.addAll(_verifyPath(relativePath));
      issues.addAll(await _verifyTextContent(entity, relativePath));
    }
    return issues;
  }

  Future<List<ReleasePackageIssue>> _verifyX64Executable(
    File executable,
    String relativePath,
  ) async {
    if (!await executable.exists()) {
      return [
        ReleasePackageIssue(
          path: relativePath,
          message: 'Pythia.exe is missing from the release package root',
        ),
      ];
    }

    final bytes = await executable.readAsBytes();
    if (bytes.length < 0x46 || bytes[0] != 0x4d || bytes[1] != 0x5a) {
      return [
        ReleasePackageIssue(
          path: relativePath,
          message: 'Pythia.exe has an invalid DOS/PE header',
        ),
      ];
    }

    final data = ByteData.sublistView(bytes);
    final peOffset = data.getUint32(0x3c, Endian.little);
    if (peOffset + 6 > bytes.length ||
        bytes[peOffset] != 0x50 ||
        bytes[peOffset + 1] != 0x45 ||
        bytes[peOffset + 2] != 0 ||
        bytes[peOffset + 3] != 0) {
      return [
        ReleasePackageIssue(
          path: relativePath,
          message: 'Pythia.exe has an invalid PE signature',
        ),
      ];
    }

    final machine = data.getUint16(peOffset + 4, Endian.little);
    if (machine != 0x8664) {
      final detected = machine.toRadixString(16).padLeft(4, '0');
      return [
        ReleasePackageIssue(
          path: relativePath,
          message:
              'Pythia.exe must target x64 AMD64 (PE machine 0x8664); detected 0x$detected',
        ),
      ];
    }
    return const [];
  }

  List<ReleasePackageIssue> _verifyPath(String relativePath) {
    final issues = <ReleasePackageIssue>[];
    final normalized = relativePath.replaceAll('\\', '/');
    final segments =
        normalized.split('/').where((segment) => segment.isNotEmpty).toList();
    final fileName = segments.isEmpty ? normalized : segments.last;
    final lowerFileName = fileName.toLowerCase();

    if (lowerFileName.endsWith('.potext')) {
      issues.add(
        ReleasePackageIssue(
          path: relativePath,
          message:
              'bundled .potext plugins are not allowed in release packages',
        ),
      );
    }

    for (final forbidden in _forbiddenFileNames) {
      if (lowerFileName == forbidden.name) {
        issues.add(
          ReleasePackageIssue(
            path: relativePath,
            message: '${forbidden.reason} must not be bundled',
          ),
        );
      }
    }

    if (_containsSegment(segments, 'src-tauri')) {
      issues.add(
        ReleasePackageIssue(
          path: relativePath,
          message: 'legacy Tauri source tree must not be bundled',
        ),
      );
    }

    if (_containsLegacyServiceTree(segments)) {
      issues.add(
        ReleasePackageIssue(
          path: relativePath,
          message: 'legacy Pot service/plugin source tree must not be bundled',
        ),
      );
    }

    return issues;
  }

  Future<List<ReleasePackageIssue>> _verifyTextContent(
    File file,
    String relativePath,
  ) async {
    final issues = <ReleasePackageIssue>[];
    final stat = await file.stat();
    if (stat.size == 0 || stat.size > 5 * 1024 * 1024) {
      return issues;
    }

    final bytes = await file.readAsBytes();
    if (_looksBinary(bytes)) {
      return issues;
    }

    final content = utf8.decode(bytes, allowMalformed: true);
    for (final pattern in _secretPatterns) {
      if (pattern.regex.hasMatch(content)) {
        issues.add(
          ReleasePackageIssue(
            path: relativePath,
            message: '${pattern.description} found in release package',
          ),
        );
      }
    }
    return issues;
  }

  static bool _containsSegment(List<String> segments, String target) {
    final lowerTarget = target.toLowerCase();
    return segments.any((segment) => segment.toLowerCase() == lowerTarget);
  }

  static bool _containsLegacyServiceTree(List<String> segments) {
    final lower = segments.map((segment) => segment.toLowerCase()).toList();
    for (var i = 0; i < lower.length - 2; i += 1) {
      if (lower[i] == 'src' &&
          lower[i + 1] == 'services' &&
          const {'translate', 'recognize', 'tts', 'collection'}
              .contains(lower[i + 2])) {
        return true;
      }
    }
    for (var i = 0; i < lower.length - 1; i += 1) {
      if (lower[i] == 'plugins' &&
          const {'translate', 'recognize', 'tts', 'collection'}
              .contains(lower[i + 1])) {
        return true;
      }
    }
    return false;
  }

  static bool _looksBinary(List<int> bytes) {
    final sampleLength = bytes.length < 4096 ? bytes.length : 4096;
    for (var i = 0; i < sampleLength; i += 1) {
      if (bytes[i] == 0) {
        return true;
      }
    }
    return false;
  }

  static String _relativePath(Directory root, File file) {
    final rootPath = root.absolute.path.replaceAll('\\', '/');
    final filePath = file.absolute.path.replaceAll('\\', '/');
    if (filePath == rootPath) {
      return '.';
    }
    if (filePath.startsWith('$rootPath/')) {
      return filePath.substring(rootPath.length + 1);
    }
    return file.path;
  }
}

class _ForbiddenFileName {
  final String name;
  final String reason;

  const _ForbiddenFileName(this.name, this.reason);
}

class _ContentPattern {
  final RegExp regex;
  final String description;

  const _ContentPattern(this.regex, this.description);
}
