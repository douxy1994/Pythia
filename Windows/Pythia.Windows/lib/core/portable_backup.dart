import 'dart:convert';

import 'history_record.dart';
import 'history_sync.dart';
import 'settings_model.dart';
import 'webdav_sync.dart';

class PortableBackupRestoreResult {
  final PythiaSettings settings;
  final int importedHistoryCount;
  final int mergedHistoryCount;
  final int conflictCount;

  const PortableBackupRestoreResult({
    required this.settings,
    required this.importedHistoryCount,
    required this.mergedHistoryCount,
    required this.conflictCount,
  });
}

class PortableBackupService {
  static const schemaVersion = 1;

  static const _portableSettingKeys = <String>{
    'sourceLanguage',
    'targetLanguage',
    'enabledTranslateServices',
    'translateServiceOrder',
    'openAICompatibleEnabled',
    'openAICompatibleName',
    'openAICompatibleBaseUrl',
    'openAICompatibleModel',
    'deepLEnabled',
    'deepLBaseUrl',
    'libreTranslateEnabled',
    'libreTranslateBaseUrl',
    'saveHistory',
    'themeMode',
  };

  final HistoryRepository historyRepository;

  const PortableBackupService(this.historyRepository);

  Future<String> create(PythiaSettings settings) async {
    final allSettings = settings.toJson();
    final portableSettings = <String, Object?>{
      for (final key in _portableSettingKeys) key: allSettings[key],
    };
    final history = await historyRepository.readAllForSync();
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': schemaVersion,
      'product': 'Pythia',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'sensitiveFieldsOmitted': true,
      'settings': portableSettings,
      'history': history.map((record) => record.toJson()).toList(),
    });
  }

  Future<PortableBackupRestoreResult> restore(
    String encoded,
    PythiaSettings currentSettings,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } catch (error) {
      throw FormatException('备份不是有效的 JSON：$error');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('备份根节点必须是对象。');
    }
    if (decoded['product'] != 'Pythia') {
      throw const FormatException('这不是 Pythia 备份文件。');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('不支持该备份格式版本。');
    }
    final rawSettings = decoded['settings'];
    final rawHistory = decoded['history'];
    if (rawSettings is! Map<String, Object?> || rawHistory is! List<Object?>) {
      throw const FormatException('备份缺少有效的设置或历史记录。');
    }

    final portableSettings = <String, Object?>{
      for (final entry in rawSettings.entries)
        if (_portableSettingKeys.contains(entry.key)) entry.key: entry.value,
    };
    final importedServiceIds =
        (portableSettings['enabledTranslateServices'] as List<Object?>?)
                ?.whereType<String>()
                .toSet() ??
            const <String>{};
    if (portableSettings.containsKey('enabledTranslateServices')) {
      portableSettings['googleEnabled'] =
          importedServiceIds.contains(PythiaSettings.googleServiceId);
      portableSettings['baiduEnabled'] =
          importedServiceIds.contains(PythiaSettings.baiduServiceId);
      portableSettings['youdaoEnabled'] =
          importedServiceIds.contains(PythiaSettings.youdaoServiceId);
    }
    final decodedSettings = PythiaSettings.fromJson({
      ...currentSettings.toJson(),
      ...portableSettings,
    }).normalized();
    final availableServices = <String>{
      'local',
      if (decodedSettings.googleEnabled) PythiaSettings.googleServiceId,
      if (decodedSettings.baiduEnabled) PythiaSettings.baiduServiceId,
      if (decodedSettings.youdaoEnabled) PythiaSettings.youdaoServiceId,
      if (decodedSettings.openAICompatibleEnabled)
        PythiaSettings.openAICompatibleServiceId,
      if (decodedSettings.deepLEnabled) PythiaSettings.deepLServiceId,
      if (decodedSettings.libreTranslateEnabled)
        PythiaSettings.libreTranslateServiceId,
    };
    final enabledServices = decodedSettings.enabledTranslateServices
        .where(availableServices.contains)
        .toList();
    if (enabledServices.isEmpty) enabledServices.add('local');
    final serviceOrder = <String>[
      for (final id in decodedSettings.translateServiceOrder)
        if (enabledServices.contains(id)) id,
      for (final id in enabledServices)
        if (!decodedSettings.translateServiceOrder.contains(id)) id,
    ];
    final restoredSettings = decodedSettings.copyWith(
      enabledTranslateServices: enabledServices,
      translateServiceOrder: serviceOrder,
    );
    final imported = <PythiaHistoryRecord>[];
    try {
      for (final item in rawHistory) {
        if (item is! Map<String, Object?>) {
          throw const FormatException('历史记录条目格式错误。');
        }
        imported.add(PythiaHistoryRecord.fromJson(item));
      }
    } catch (error) {
      if (error is FormatException) rethrow;
      throw FormatException('历史记录解析失败：$error');
    }

    final local = await historyRepository.readAllForSync();
    final merged = PythiaHistoryMerger.merge(local: local, remote: imported);
    final pending = [
      for (final record in merged.merged)
        if (record.syncStatus == PythiaSyncStatus.conflict)
          record
        else
          record.copyWith(
            syncStatus: record.isDeleted
                ? PythiaSyncStatus.pendingDelete
                : PythiaSyncStatus.pendingUpload,
          ),
    ];

    await historyRepository.backupBeforeSync();
    await historyRepository.replaceAllFromSync(pending);
    return PortableBackupRestoreResult(
      settings: restoredSettings,
      importedHistoryCount: imported.length,
      mergedHistoryCount: pending.length,
      conflictCount: merged.conflicts.length,
    );
  }
}
