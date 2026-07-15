import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/credential_store.dart';
import 'translation_service.dart';

bool _isLikelySecretKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (const {'secret', 'password', 'passwd', 'token'}.contains(normalized)) {
    return true;
  }
  return normalized.endsWith('apikey') ||
      normalized.endsWith('appkey') ||
      normalized.contains('accesskey') ||
      normalized.endsWith('secretkey') ||
      normalized.endsWith('clientsecret') ||
      (normalized.endsWith('token') && !normalized.endsWith('tokens'));
}

enum PythiaPluginPackageFormat { pythia, potext }

class PythiaPluginConfigurationField {
  final String key;
  final String label;
  final String type;
  final bool required;
  final String? defaultValue;
  final Map<String, String>? options;

  const PythiaPluginConfigurationField({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    this.defaultValue,
    this.options,
  });

  factory PythiaPluginConfigurationField.fromJson(Map<String, Object?> json) {
    final rawOptions = json['options'];
    return PythiaPluginConfigurationField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      required: json['required'] as bool? ?? false,
      defaultValue: json['defaultValue']?.toString(),
      options: rawOptions is Map
          ? rawOptions.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : null,
    );
  }

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        'required': required,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (options != null) 'options': options,
      };
}

class PythiaPluginManifest {
  final String schemaVersion;
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String type;
  final String entry;
  final String minimumPythiaVersion;
  final List<String> supportedPlatforms;
  final List<String> permissions;
  final List<PythiaPluginConfigurationField> configuration;
  final List<String> capabilities;

  const PythiaPluginManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.type,
    required this.entry,
    required this.minimumPythiaVersion,
    required this.supportedPlatforms,
    required this.permissions,
    required this.configuration,
    required this.capabilities,
  });

  factory PythiaPluginManifest.fromJson(Map<String, Object?> json) {
    List<String> strings(String key) =>
        (json[key] as List<Object?>? ?? const []).whereType<String>().toList();
    return PythiaPluginManifest(
      schemaVersion: json['schemaVersion'] as String? ?? '',
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      type: json['type'] as String? ?? '',
      entry: json['entry'] as String? ?? '',
      minimumPythiaVersion: json['minimumPythiaVersion'] as String? ?? '',
      supportedPlatforms: strings('supportedPlatforms'),
      permissions: strings('permissions'),
      configuration: (json['configuration'] as List<Object?>? ?? const [])
          .whereType<Map>()
          .map((item) => PythiaPluginConfigurationField.fromJson(
                item.cast<String, Object?>(),
              ))
          .toList(),
      capabilities: strings('capabilities'),
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'author': author,
        'type': type,
        'entry': entry,
        'minimumPythiaVersion': minimumPythiaVersion,
        'supportedPlatforms': supportedPlatforms,
        'permissions': permissions,
        'configuration': configuration.map((field) => field.toJson()).toList(),
        'capabilities': capabilities,
      };

  void validate({required String platform}) {
    if (schemaVersion != '1.0') {
      throw const FormatException('仅支持插件 schemaVersion 1.0。');
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$').hasMatch(id)) {
      throw FormatException('插件 id 格式无效：$id。');
    }
    for (final entry in <String, String>{
      'name': name,
      'description': description,
      'author': author,
      'minimumPythiaVersion': minimumPythiaVersion,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw FormatException('插件 Manifest 缺少 ${entry.key}。');
      }
    }
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$')
        .hasMatch(version)) {
      throw FormatException('插件 version 格式无效：$version。');
    }
    if (type != 'translator') {
      throw FormatException('Pythia 1.0.0 不支持插件类型：$type。');
    }
    final normalizedEntry = entry.replaceAll('\\', '/');
    if (normalizedEntry.isEmpty ||
        p.isAbsolute(normalizedEntry) ||
        normalizedEntry.split('/').contains('..') ||
        p.extension(normalizedEntry).toLowerCase() != '.js') {
      throw FormatException('插件入口路径不安全：$entry。');
    }
    if (!supportedPlatforms
        .map((item) => item.toLowerCase())
        .contains(platform.toLowerCase())) {
      throw FormatException('插件不支持当前平台：$platform。');
    }
    const supportedPermissions = {'network'};
    for (final permission in permissions) {
      if (!supportedPermissions.contains(permission.toLowerCase())) {
        throw FormatException('插件权限不受支持：$permission。');
      }
    }
    final keys = <String>{};
    for (final field in configuration) {
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(field.key) ||
          !keys.add(field.key)) {
        throw FormatException('插件配置键无效或重复：${field.key}。');
      }
      if (!const {'text', 'secret', 'select'}.contains(field.type)) {
        throw FormatException('插件配置类型不受支持：${field.type}。');
      }
      if (field.type == 'secret' &&
          field.defaultValue != null &&
          field.defaultValue!.isNotEmpty) {
        throw FormatException('secret 配置不得包含默认值：${field.key}。');
      }
    }
    if (!capabilities.contains('translate')) {
      throw const FormatException('翻译插件必须声明 translate 能力。');
    }
  }
}

class PotextConversionResult {
  final PythiaPluginManifest manifest;
  final String mainJavaScript;
  final List<String> warnings;

  const PotextConversionResult({
    required this.manifest,
    required this.mainJavaScript,
    required this.warnings,
  });
}

typedef PotextConverter = PotextConversionResult Function(
  Map<String, Object?> info,
  String mainJavaScript,
  String fallbackIdentifier,
);

class PotextPluginConverter {
  static PotextConversionResult convert(
    Map<String, Object?> info,
    String mainJavaScript,
    String fallbackIdentifier,
  ) {
    final legacyType = info['plugin_type']?.toString() ?? '';
    if (legacyType != 'translate') {
      throw FormatException('不支持旧插件类型：$legacyType。');
    }
    final rawID = (info['id']?.toString().trim().isNotEmpty ?? false)
        ? info['id'].toString()
        : fallbackIdentifier;
    final id = normalizeIdentifier(rawID);
    final name = _firstNonEmpty([
      info['display']?.toString(),
      info['name']?.toString(),
      id,
    ]);
    final declaredVersion = info['version']?.toString() ?? '';
    final validVersion = RegExp(
      r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$',
    ).hasMatch(declaredVersion);
    final warnings = <String>[];
    if (declaredVersion.isEmpty) {
      warnings.add('原插件未声明版本，转换后使用 1.0.0。');
    } else if (!validVersion) {
      warnings.add('原插件版本格式不兼容，转换后使用 1.0.0。');
    }
    final fields = <PythiaPluginConfigurationField>[];
    for (final raw in (info['needs'] as List<Object?>? ?? const [])) {
      if (raw is! Map) continue;
      final need = raw.cast<String, Object?>();
      final key = need['key']?.toString().trim() ?? '';
      if (key.isEmpty) {
        warnings.add('已忽略缺少 key 的配置项。');
        continue;
      }
      final legacyInputType = need['type']?.toString() ?? '';
      final isSecret = need['secret'] == true ||
          const {'password', 'secret'}
              .contains(legacyInputType.toLowerCase()) ||
          _isLikelySecretKey(key);
      final rawOptions = need['options'];
      fields.add(PythiaPluginConfigurationField(
        key: key,
        label: _firstNonEmpty([need['display']?.toString(), key]),
        type: isSecret
            ? 'secret'
            : (legacyInputType == 'select' ? 'select' : 'text'),
        required: isSecret && (need['default']?.toString().isEmpty ?? true),
        defaultValue: isSecret ? null : need['default']?.toString(),
        options: rawOptions is Map
            ? rawOptions.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
            : null,
      ));
    }
    final needsNetwork = RegExp(
      r'tauriFetch|utils\.http|\bfetch\s*\(',
    ).hasMatch(mainJavaScript);
    final manifest = PythiaPluginManifest(
      schemaVersion: '1.0',
      id: id,
      name: name,
      version: validVersion ? declaredVersion : '1.0.0',
      description: _firstNonEmpty([
        info['description']?.toString(),
        '由 Pythia 从 Pot 插件自动转换。',
      ]),
      author: _authorFromHomepage(info['homepage']?.toString() ?? ''),
      type: 'translator',
      entry: 'main.js',
      minimumPythiaVersion: '1.0.0',
      supportedPlatforms: const ['macos', 'windows'],
      permissions: needsNetwork ? const ['network'] : const [],
      configuration: fields,
      capabilities: const ['translate'],
    );
    manifest.validate(platform: 'windows');
    warnings.add('已保留原 main.js，并通过统一请求与响应适配层运行。');
    return PotextConversionResult(
      manifest: manifest,
      mainJavaScript:
          '$_compatibilityPrelude\n$mainJavaScript\n$_compatibilityPostlude',
      warnings: warnings,
    );
  }

  static String normalizeIdentifier(String raw) {
    var value = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    value = value.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
    if (value.length < 3) {
      value = 'plugin.${value.isEmpty ? 'converted' : value}';
    }
    return value.substring(0, min(value.length, 128));
  }

  static String _firstNonEmpty(List<String?> values) => values
      .whereType<String>()
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => 'Unknown');

  static String _authorFromHomepage(String homepage) {
    final uri = Uri.tryParse(homepage);
    if (uri == null || uri.host.isEmpty) return 'Unknown';
    if (uri.host.toLowerCase().contains('github.com') &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return uri.host;
  }

  static const _compatibilityPrelude = r'''
globalThis.ResponseType = Object.freeze({ Text: "Text", Json: "Json", JSON: "Json" });
globalThis.Body = Object.freeze({
  json: (payload) => ({ type: "Json", payload }),
  form: (payload) => ({ type: "Form", payload }),
  text: (payload) => ({ type: "Text", payload })
});
''';

  static const _compatibilityPostlude = r'''
const __pythiaLegacyTranslate = translate;

async function __pythiaCompatFetch(context, url, options = {}) {
  const headers = { ...(options.headers || {}) };
  let body = options.body;
  if (body && typeof body === "object" && Object.prototype.hasOwnProperty.call(body, "type")) {
    if (body.type === "Json") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) headers["Content-Type"] = "application/json";
      body = JSON.stringify(body.payload);
    } else if (body.type === "Form") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) headers["Content-Type"] = "application/x-www-form-urlencoded";
      body = new URLSearchParams(body.payload || {}).toString();
    } else {
      body = String(body.payload ?? "");
    }
  } else if (body && typeof body === "object") {
    if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) headers["Content-Type"] = "application/json";
    body = JSON.stringify(body);
  }
  const response = await context.fetch(url, { method: options.method || "GET", headers, body });
  const responseText = await response.text();
  const wantsText = options.responseType === "Text" || options.responseType === "text";
  let data = responseText;
  if (!wantsText) { try { data = responseText ? JSON.parse(responseText) : null; } catch (_) {} }
  return { ok: response.ok, status: response.status, url: response.url, data, headers: Object.fromEntries(response.headers.entries()) };
}

module.exports.translate = async function pythiaConvertedTranslate(request, context) {
  const input = request && request.input ? request.input : {};
  const compatFetch = (url, options) => __pythiaCompatFetch(context, url, options);
  const utils = { tauriFetch: compatFetch, http: { fetch: compatFetch, Body: globalThis.Body } };
  return await __pythiaLegacyTranslate(
    String(input.text || ""),
    String(input.sourceLanguage || "auto"),
    String(input.targetLanguage || "zh-CN"),
    { config: context.config || {}, detect: input.detectedLanguage || input.sourceLanguage || "auto", utils, setResult: () => {} }
  );
};
''';
}

class InstalledPythiaPlugin {
  final PythiaPluginManifest manifest;
  final Directory directory;
  final PythiaPluginPackageFormat format;
  final String conversionStatus;
  final List<String> conversionWarnings;
  final bool enabled;
  final String lastError;

  const InstalledPythiaPlugin({
    required this.manifest,
    required this.directory,
    required this.format,
    required this.conversionStatus,
    required this.conversionWarnings,
    required this.enabled,
    required this.lastError,
  });

  String get serviceId => 'plugin:${manifest.id}';
}

class PluginInstallResult {
  final InstalledPythiaPlugin plugin;
  final bool converted;
  final bool compatibilityFallback;
  final String message;

  const PluginInstallResult({
    required this.plugin,
    required this.converted,
    required this.compatibilityFallback,
    required this.message,
  });
}

class PythiaPluginManager {
  static const guideUrl =
      'https://github.com/douxy1994/Pythia/blob/master/Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md';
  static const maxArchiveBytes = 64 * 1024 * 1024;
  static const maxArchiveEntries = 2048;

  final Directory rootDirectory;
  final Directory legacyDirectory;
  final Directory backupDirectory;
  final Directory compatibilityDirectory;
  final File runnerFile;
  final String? nodeExecutable;
  final CredentialStore credentialStore;
  final PotextConverter convertPotext;
  final Duration Function(String text) timeoutForText;

  PythiaPluginManager({
    required this.rootDirectory,
    required this.runnerFile,
    required this.nodeExecutable,
    required this.credentialStore,
    PotextConverter? convertPotext,
    Duration Function(String text)? timeoutForText,
  })  : legacyDirectory = Directory(p.join(rootDirectory.path, 'Legacy')),
        backupDirectory =
            Directory(p.join(rootDirectory.path, 'Legacy Backups')),
        compatibilityDirectory =
            Directory(p.join(rootDirectory.path, 'Compatibility')),
        convertPotext = convertPotext ?? PotextPluginConverter.convert,
        timeoutForText = timeoutForText ?? _timeoutForText;

  static Future<PythiaPluginManager> create({
    required CredentialStore credentialStore,
  }) async {
    final support = await getApplicationSupportDirectory();
    final appRoot = Directory(p.join(support.path, 'Pythia'));
    final runtime = Directory(p.join(appRoot.path, 'Runtime'));
    await runtime.create(recursive: true);
    final runner = File(p.join(runtime.path, 'pythia-plugin-runner.cjs'));
    final bundledRunner = await rootBundle.loadString(
      'assets/pythia-plugin-runner.cjs',
    );
    if (!await runner.exists() ||
        await runner.readAsString() != bundledRunner) {
      await runner.writeAsString(bundledRunner, flush: true);
    }
    final manager = PythiaPluginManager(
      rootDirectory: Directory(p.join(appRoot.path, 'Plugins')),
      runnerFile: runner,
      nodeExecutable: await _resolveNodeExecutable(),
      credentialStore: credentialStore,
    );
    await manager.initialize();
    return manager;
  }

  File get _stateFile => File(p.join(rootDirectory.path, 'plugin-state.json'));

  Future<void> initialize() async {
    for (final directory in [
      rootDirectory,
      legacyDirectory,
      backupDirectory,
      compatibilityDirectory,
    ]) {
      await directory.create(recursive: true);
    }
  }

  Future<List<InstalledPythiaPlugin>> listInstalled() async {
    await initialize();
    final state = await _readState();
    final plugins = <InstalledPythiaPlugin>[];
    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is! Directory ||
          p.extension(entity.path).toLowerCase() != '.pythia') {
        continue;
      }
      try {
        final plugin = await _loadInstalled(
          entity,
          PythiaPluginPackageFormat.pythia,
          state,
        );
        plugins.add(plugin);
      } catch (_) {
        // Invalid packages remain isolated and are not exposed as services.
      }
    }
    await for (final entity
        in compatibilityDirectory.list(followLinks: false)) {
      if (entity is! Directory ||
          p.extension(entity.path).toLowerCase() != '.pythia') {
        continue;
      }
      try {
        final plugin = await _loadInstalled(
          entity,
          PythiaPluginPackageFormat.potext,
          state,
        );
        if (!plugins.any((item) => item.manifest.id == plugin.manifest.id)) {
          plugins.add(plugin);
        }
      } catch (_) {}
    }
    plugins.sort((a, b) =>
        a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
    return plugins;
  }

  Future<InstalledPythiaPlugin> _loadInstalled(
    Directory directory,
    PythiaPluginPackageFormat format,
    Map<String, Object?> state,
  ) async {
    final manifest = await _readManifest(directory);
    final pluginState = _pluginState(state, manifest.id);
    final conversion = await _readConversion(directory);
    return InstalledPythiaPlugin(
      manifest: manifest,
      directory: directory,
      format: format,
      conversionStatus: conversion.$1,
      conversionWarnings: conversion.$2,
      enabled: pluginState['enabled'] as bool? ?? true,
      lastError: pluginState['lastError'] as String? ?? '',
    );
  }

  Future<PluginInstallResult> install(FileSystemEntity source) async {
    final extension = p.extension(source.path).toLowerCase();
    if (extension == '.pythia') return _installPythia(source);
    if (extension == '.potext') return _installPotext(source);
    throw const FormatException('请选择 .pythia 或 .potext 插件。');
  }

  Future<PluginInstallResult> _installPythia(FileSystemEntity source) async {
    final staged = await _stagePackage(source, 'manifest.json');
    try {
      final packageRoot = await _locatePackageRoot(staged, 'manifest.json');
      final manifest = await _readManifest(packageRoot);
      final target =
          Directory(p.join(rootDirectory.path, '${manifest.id}.pythia'));
      await _atomicReplaceDirectory(packageRoot, target);
      await _ensurePluginState(manifest.id);
      final plugin = (await listInstalled())
          .firstWhere((item) => item.manifest.id == manifest.id);
      return PluginInstallResult(
        plugin: plugin,
        converted: false,
        compatibilityFallback: false,
        message: '已安装 ${manifest.name}（.pythia ${manifest.version}）。',
      );
    } finally {
      await _deleteIfExists(staged);
    }
  }

  Future<PluginInstallResult> _installPotext(FileSystemEntity source) async {
    final staged = await _stagePackage(source, 'info.json');
    try {
      final packageRoot = await _locatePackageRoot(staged, 'info.json');
      final infoFile = File(p.join(packageRoot.path, 'info.json'));
      final mainFile = File(p.join(packageRoot.path, 'main.js'));
      if (!await mainFile.exists()) {
        throw const FormatException('.potext 插件缺少 main.js。');
      }
      final info = (jsonDecode(await infoFile.readAsString()) as Map)
          .cast<String, Object?>();
      if (info['plugin_type']?.toString() != 'translate') {
        throw FormatException(
          'Pythia 1.0.0 只支持 translate 类型 .potext 插件。',
        );
      }
      final sourceName = p.basenameWithoutExtension(source.path);
      final legacyTarget =
          Directory(p.join(legacyDirectory.path, '$sourceName.potext'));
      await _atomicReplaceDirectory(packageRoot, legacyTarget);
      await _preserveOriginal(source, sourceName);
      final legacyMain =
          await File(p.join(legacyTarget.path, 'main.js')).readAsString();
      try {
        final conversion = convertPotext(info, legacyMain, sourceName);
        final target = await _writeConvertedPackage(
          legacyTarget,
          conversion,
          status: 'converted',
        );
        await _ensurePluginState(conversion.manifest.id);
        final plugin = (await listInstalled()).firstWhere(
          (item) => item.directory.path == target.path,
        );
        return PluginInstallResult(
          plugin: plugin,
          converted: true,
          compatibilityFallback: false,
          message: '已安装并转换 ${plugin.manifest.name}；原 .potext 已保留为备份。',
        );
      } catch (error) {
        final fallback = await _writeCompatibilityFallback(
          legacyTarget,
          info,
          legacyMain,
          sourceName,
          error,
        );
        await _ensurePluginState(fallback.manifest.id);
        return PluginInstallResult(
          plugin: fallback,
          converted: false,
          compatibilityFallback: true,
          message: '自动转换失败，已启用 .potext 兼容模式：$error',
        );
      }
    } finally {
      await _deleteIfExists(staged);
    }
  }

  Future<InstalledPythiaPlugin> _writeCompatibilityFallback(
    Directory legacy,
    Map<String, Object?> info,
    String legacyMain,
    String fallbackID,
    Object conversionError,
  ) async {
    final safeInfo = Map<String, Object?>.from(info)
      ..['id'] = PotextPluginConverter.normalizeIdentifier(
        info['id']?.toString() ?? fallbackID,
      )
      ..['version'] = '1.0.0';
    final conversion = PotextPluginConverter.convert(
      safeInfo,
      legacyMain,
      fallbackID,
    );
    final warning = '严格转换失败，使用兼容模式：$conversionError';
    final compatible = PotextConversionResult(
      manifest: conversion.manifest,
      mainJavaScript: conversion.mainJavaScript,
      warnings: [warning, ...conversion.warnings],
    );
    final target = await _writeConvertedPackage(
      legacy,
      compatible,
      status: 'compatibility',
      destinationRoot: compatibilityDirectory,
    );
    final state = await _readState();
    return _loadInstalled(
      target,
      PythiaPluginPackageFormat.potext,
      state,
    );
  }

  Future<Directory> _writeConvertedPackage(
    Directory legacy,
    PotextConversionResult conversion, {
    required String status,
    Directory? destinationRoot,
    bool replaceExisting = false,
  }) async {
    final root = destinationRoot ?? rootDirectory;
    final target = Directory(
      p.join(root.path, '${conversion.manifest.id}.pythia'),
    );
    if (!replaceExisting && await target.exists()) return target;
    final staging = Directory(
      p.join(root.path, '.convert-${_randomID()}.pythia'),
    );
    await _copyDirectory(legacy, staging);
    await File(p.join(staging.path, 'legacy-main.js')).writeAsString(
        await File(p.join(legacy.path, 'main.js')).readAsString());
    await File(p.join(staging.path, 'main.js'))
        .writeAsString(conversion.mainJavaScript);
    await File(p.join(staging.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(conversion.manifest.toJson()),
    );
    await File(p.join(staging.path, 'conversion.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'sourceFormat': 'potext',
        'sourcePlugin': p.basename(legacy.path),
        'convertedAt': DateTime.now().toUtc().toIso8601String(),
        'status': status,
        'warnings': conversion.warnings,
        'originalBackup': '${p.basenameWithoutExtension(legacy.path)}.potext',
      }),
    );
    await _atomicReplaceDirectory(staging, target, moveSource: true);
    return target;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final state = await _readState();
    final item = _pluginState(state, id);
    item['enabled'] = enabled;
    item['lastError'] = '';
    state[id] = item;
    await _writeState(state);
  }

  Future<Map<String, String>> configurationFor(
    PythiaPluginManifest manifest,
  ) async {
    final state = await _readState();
    final item = _pluginState(state, manifest.id);
    final publicConfig = (item['configuration'] as Map?)
            ?.map((key, value) => MapEntry(key.toString(), value.toString())) ??
        <String, String>{};
    final result = <String, String>{};
    for (final field in manifest.configuration) {
      if (field.defaultValue != null) result[field.key] = field.defaultValue!;
      if (field.type == 'secret') {
        final secret = await credentialStore.readSecret(
          _secretKey(manifest.id, field.key),
        );
        if (secret != null && secret.isNotEmpty) result[field.key] = secret;
      } else if (publicConfig[field.key]?.isNotEmpty ?? false) {
        result[field.key] = publicConfig[field.key]!;
      }
    }
    return result;
  }

  Future<void> saveConfiguration(
    PythiaPluginManifest manifest,
    Map<String, String> values,
  ) async {
    final state = await _readState();
    final item = _pluginState(state, manifest.id);
    final publicConfig = <String, String>{};
    for (final field in manifest.configuration) {
      final value = values[field.key]?.trim() ?? '';
      if (field.type == 'secret') {
        if (value.isEmpty) {
          await credentialStore
              .deleteSecret(_secretKey(manifest.id, field.key));
        } else {
          await credentialStore.writeSecret(
            _secretKey(manifest.id, field.key),
            values[field.key]!,
          );
        }
      } else if (value.isNotEmpty) {
        publicConfig[field.key] = values[field.key]!;
      }
    }
    item['configuration'] = publicConfig;
    state[manifest.id] = item;
    await _writeState(state);
  }

  Future<void> deletePlugin(InstalledPythiaPlugin plugin) async {
    for (final field in plugin.manifest.configuration
        .where((field) => field.type == 'secret')) {
      await credentialStore.deleteSecret(
        _secretKey(plugin.manifest.id, field.key),
      );
    }
    await _deleteIfExists(plugin.directory);
    await _deleteIfExists(Directory(
      p.join(rootDirectory.path, '${plugin.manifest.id}.pythia'),
    ));
    await _deleteIfExists(Directory(
      p.join(compatibilityDirectory.path, '${plugin.manifest.id}.pythia'),
    ));
    final state = await _readState()
      ..remove(plugin.manifest.id);
    await _writeState(state);
  }

  Future<InstalledPythiaPlugin> reconvert(InstalledPythiaPlugin plugin) async {
    Directory? legacy;
    await for (final entity in legacyDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final info = (jsonDecode(
          await File(p.join(entity.path, 'info.json')).readAsString(),
        ) as Map)
            .cast<String, Object?>();
        final id = PotextPluginConverter.normalizeIdentifier(
          info['id']?.toString() ?? p.basenameWithoutExtension(entity.path),
        );
        if (id == plugin.manifest.id) legacy = entity;
      } catch (_) {}
    }
    if (legacy == null) {
      throw const FormatException('没有找到该插件保留的原始 .potext。');
    }
    final info = (jsonDecode(
      await File(p.join(legacy.path, 'info.json')).readAsString(),
    ) as Map)
        .cast<String, Object?>();
    final source = await File(p.join(legacy.path, 'main.js')).readAsString();
    final conversion = convertPotext(info, source, plugin.manifest.id);
    final target = await _writeConvertedPackage(
      legacy,
      conversion,
      status: 'converted',
      replaceExisting: true,
    );
    final state = await _readState();
    return _loadInstalled(target, PythiaPluginPackageFormat.pythia, state);
  }

  Future<String> translate(
    InstalledPythiaPlugin plugin,
    PythiaTranslationRequest translationRequest,
  ) async {
    if (!plugin.enabled) throw StateError('${plugin.manifest.name} 已禁用。');
    if (nodeExecutable == null || nodeExecutable!.isEmpty) {
      throw StateError('Pythia 插件运行时缺少 node.exe。');
    }
    final requestID = _randomID();
    final timeout = timeoutForText(translationRequest.text);
    final request = {
      'schemaVersion': '1.0',
      'requestId': requestID,
      'type': 'translate',
      'input': {
        'text': translationRequest.text,
        'sourceLanguage': translationRequest.sourceLanguage,
        'targetLanguage': translationRequest.targetLanguage,
        'detectedLanguage': translationRequest.sourceLanguage,
      },
      'context': {'platform': 'windows', 'pythiaVersion': '1.0.0'},
    };
    final config = await configurationFor(plugin.manifest);
    final environment = Map<String, String>.from(Platform.environment)
      ..['PYTHIA_PLUGIN_REQUEST'] = jsonEncode(request)
      ..['PYTHIA_PLUGIN_CONFIG'] = jsonEncode(config)
      ..['PYTHIA_PLUGIN_TIMEOUT_MS'] = '${timeout.inMilliseconds}';
    final process = await Process.start(
      nodeExecutable!,
      [runnerFile.path, plugin.directory.path, plugin.manifest.entry],
      environment: environment,
      runInShell: false,
    );
    var timedOut = false;
    final timer = Timer(timeout + const Duration(seconds: 2), () {
      timedOut = true;
      process.kill();
    });
    try {
      final streams = await Future.wait([
        _readLimited(process.stdout, 8 * 1024 * 1024),
        _readLimited(process.stderr, 1024 * 1024),
        process.exitCode.then((value) => <int>[value]),
      ]);
      if (timedOut) throw StateError('插件执行超时，已终止。');
      final exitCode = streams[2].first;
      final stdout = utf8.decode(streams[0], allowMalformed: true);
      final stderr = _redact(
        utf8.decode(streams[1], allowMalformed: true),
        config,
      );
      if (exitCode != 0) {
        throw StateError(stderr.trim().isEmpty ? '插件执行失败。' : stderr.trim());
      }
      final response = (jsonDecode(stdout) as Map).cast<String, Object?>();
      if (response['requestId'] != requestID || response['success'] is! bool) {
        throw const FormatException('插件返回了无效的统一响应。');
      }
      if (response['success'] != true) {
        final error = response['error'] is Map
            ? (response['error'] as Map).cast<String, Object?>()
            : const <String, Object?>{};
        throw StateError(
          '${error['code'] ?? 'RUNTIME_ERROR'}：${_redact(error['message']?.toString() ?? '插件执行失败。', config)}',
        );
      }
      final data = response['data'] is Map
          ? (response['data'] as Map).cast<String, Object?>()
          : const <String, Object?>{};
      final text = data['text']?.toString().trim() ?? '';
      if (text.isEmpty) throw const FormatException('插件响应缺少非空 data.text。');
      await _recordError(plugin.manifest.id, '');
      return text;
    } catch (error) {
      await _recordError(plugin.manifest.id, error.toString());
      rethrow;
    } finally {
      timer.cancel();
      if (process.kill()) await process.exitCode;
    }
  }

  Future<Directory> _stagePackage(
    FileSystemEntity source,
    String manifestName,
  ) async {
    final stage = Directory(p.join(
      Directory.systemTemp.path,
      'pythia-plugin-${_randomID()}',
    ));
    await stage.create(recursive: true);
    if (source is Directory) {
      final child = Directory(p.join(stage.path, p.basename(source.path)));
      await _copyDirectory(source, child);
      return stage;
    }
    if (source is! File || !await source.exists()) {
      throw const FormatException('找不到所选插件。');
    }
    final bytes = await source.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > maxArchiveEntries) {
      throw const FormatException('插件压缩包文件数量超过限制。');
    }
    var total = 0;
    for (final file in archive.files) {
      final normalized = file.name.replaceAll('\\', '/');
      total += max(file.size, 0);
      if (normalized.startsWith('/') ||
          RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
          normalized.split('/').contains('..') ||
          file.isSymbolicLink) {
        throw FormatException('插件压缩包包含不安全路径：${file.name}。');
      }
    }
    if (total > maxArchiveBytes) {
      throw const FormatException('插件解压后超过 64 MiB 限制。');
    }
    await extractArchiveToDisk(archive, stage.path);
    if (!await _containsManifest(stage, manifestName)) {
      throw FormatException('插件包缺少 $manifestName。');
    }
    return stage;
  }

  Future<Directory> _locatePackageRoot(
    Directory stage,
    String manifestName,
  ) async {
    if (await File(p.join(stage.path, manifestName)).exists()) return stage;
    final candidates = <Directory>[];
    await for (final entity in stage.list(followLinks: false)) {
      if (entity is Directory &&
          await File(p.join(entity.path, manifestName)).exists()) {
        candidates.add(entity);
      }
    }
    if (candidates.length != 1) {
      throw FormatException(
        '插件包必须在根目录或唯一顶层目录中包含 $manifestName。',
      );
    }
    return candidates.single;
  }

  Future<PythiaPluginManifest> _readManifest(Directory directory) async {
    final file = File(p.join(directory.path, 'manifest.json'));
    final decoded =
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
    final manifest = PythiaPluginManifest.fromJson(decoded);
    manifest.validate(platform: 'windows');
    final entry = File(p.normalize(p.join(directory.path, manifest.entry)));
    if (!p.isWithin(directory.path, entry.path) || !await entry.exists()) {
      throw FormatException('插件入口不存在：${manifest.entry}。');
    }
    return manifest;
  }

  Future<(String, List<String>)> _readConversion(Directory directory) async {
    final file = File(p.join(directory.path, 'conversion.json'));
    if (!await file.exists()) return ('native', <String>[]);
    try {
      final data = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
      return (
        data['status']?.toString() ?? 'converted',
        (data['warnings'] as List<Object?>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
    } catch (_) {
      return ('invalid-report', <String>['conversion.json 无法读取。']);
    }
  }

  Future<void> _preserveOriginal(
    FileSystemEntity source,
    String sourceName,
  ) async {
    final target = File(p.join(backupDirectory.path, '$sourceName.potext'));
    if (await target.exists()) return;
    if (source is File) {
      await source.copy(target.path);
    } else if (source is Directory) {
      await ZipFileEncoder().zipDirectoryAsync(
        source,
        filename: target.path,
      );
    }
  }

  Future<Map<String, Object?>> _readState() async {
    if (!await _stateFile.exists()) return <String, Object?>{};
    try {
      return (jsonDecode(await _stateFile.readAsString()) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Future<void> _writeState(Map<String, Object?> state) async {
    await _stateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state),
      flush: true,
    );
  }

  Map<String, Object?> _pluginState(Map<String, Object?> state, String id) {
    final raw = state[id];
    return raw is Map
        ? Map<String, Object?>.from(raw)
        : <String, Object?>{
            'enabled': true,
            'lastError': '',
            'configuration': <String, String>{},
          };
  }

  Future<void> _ensurePluginState(String id) async {
    final state = await _readState();
    state.putIfAbsent(id, () => _pluginState(state, id));
    await _writeState(state);
  }

  Future<void> _recordError(String id, String error) async {
    final state = await _readState();
    final item = _pluginState(state, id);
    item['lastError'] = error.length > 2000 ? error.substring(0, 2000) : error;
    state[id] = item;
    await _writeState(state);
  }

  static String _secretKey(String id, String key) => 'plugin.$id.$key';

  static Future<String?> _resolveNodeExecutable() async {
    final explicit = Platform.environment['PYTHIA_NODE_RUNTIME'];
    if (explicit != null && await File(explicit).exists()) return explicit;
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final bundledName = Platform.isWindows ? 'node.exe' : 'node';
    final bundled = File(p.join(
      executableDirectory.path,
      'runtime',
      bundledName,
    ));
    if (await bundled.exists()) return bundled.path;
    final command = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(command, [bundledName]);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().split(RegExp(r'\r?\n')).first;
        if (path.trim().isNotEmpty) return path.trim();
      }
    } catch (_) {}
    return null;
  }

  static Duration _timeoutForText(String text) {
    final seconds = 45 + (text.runes.length / 120).ceil();
    return Duration(seconds: min(max(seconds, 45), 300));
  }

  static Future<List<int>> _readLimited(
    Stream<List<int>> stream,
    int maximum,
  ) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length > maximum) {
        throw const FormatException('插件输出超过大小限制。');
      }
    }
    return bytes;
  }

  static String _redact(String message, Map<String, String> config) {
    var result = message;
    for (final entry in config.entries) {
      if (RegExp(r'key|secret|token|password', caseSensitive: false)
              .hasMatch(entry.key) &&
          entry.value.length >= 4) {
        result = result.replaceAll(entry.value, '[REDACTED]');
      }
    }
    return result;
  }

  static String _randomID() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(target);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else {
        throw const FormatException('插件包不得包含符号链接。');
      }
    }
  }

  static Future<void> _atomicReplaceDirectory(
    Directory source,
    Directory target, {
    bool moveSource = false,
  }) async {
    final staging = moveSource
        ? source
        : Directory('${target.path}.install-${_randomID()}');
    if (!moveSource) await _copyDirectory(source, staging);
    final old = Directory('${target.path}.old-${_randomID()}');
    if (await target.exists()) await target.rename(old.path);
    try {
      await staging.rename(target.path);
      await _deleteIfExists(old);
    } catch (_) {
      if (await old.exists() && !await target.exists()) {
        await old.rename(target.path);
      }
      rethrow;
    }
  }

  static Future<bool> _containsManifest(
    Directory directory,
    String manifestName,
  ) async {
    if (await File(p.join(directory.path, manifestName)).exists()) return true;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory &&
          await File(p.join(entity.path, manifestName)).exists()) {
        return true;
      }
    }
    return false;
  }

  static Future<void> _deleteIfExists(FileSystemEntity entity) async {
    if (await entity.exists()) await entity.delete(recursive: true);
  }
}

class PythiaPluginTranslationProvider implements TranslationProvider {
  final PythiaPluginManager manager;
  final InstalledPythiaPlugin plugin;

  const PythiaPluginTranslationProvider({
    required this.manager,
    required this.plugin,
  });

  @override
  String get id => plugin.serviceId;

  @override
  String get displayName => plugin.manifest.name;

  @override
  Future<PythiaTranslationResult> translate(
    PythiaTranslationRequest request,
  ) async {
    final text = await manager.translate(plugin, request);
    return PythiaTranslationResult(
      serviceId: id,
      serviceName: displayName,
      text: text,
    );
  }
}
