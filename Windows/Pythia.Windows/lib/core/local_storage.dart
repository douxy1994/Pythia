import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'history_record.dart';
import 'settings_model.dart';
import 'webdav_sync.dart';

class PythiaLocalStore implements HistoryRepository {
  Directory? _baseDirectory;

  Future<Directory> _directory() async {
    if (_baseDirectory != null) return _baseDirectory!;
    final support = await getApplicationSupportDirectory();
    final directory =
        Directory('${support.path}${Platform.pathSeparator}Pythia');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    _baseDirectory = directory;
    return directory;
  }

  Future<File> _historyFile() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}history.json');
  }

  Future<File> _settingsFile() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}settings.json');
  }

  Future<File> _deviceIdFile() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}device-id.txt');
  }

  @override
  Future<String> deviceId() async {
    final file = await _deviceIdFile();
    if (file.existsSync()) {
      final value = file.readAsStringSync().trim();
      if (value.isNotEmpty) return value;
    }
    final value = _randomId();
    file.writeAsStringSync(value, flush: true);
    return value;
  }

  Future<PythiaSettings> readSettings() async {
    final file = await _settingsFile();
    if (!file.existsSync()) return const PythiaSettings();
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return PythiaSettings.fromJson(decoded);
  }

  Future<void> writeSettings(PythiaSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
  }

  @override
  Future<List<PythiaHistoryRecord>> readAllForSync() async {
    final file = await _historyFile();
    if (!file.existsSync()) return const [];
    final body = await file.readAsString();
    if (body.trim().isEmpty) return const [];
    final decoded = jsonDecode(body) as List<Object?>;
    return decoded
        .cast<Map<String, Object?>>()
        .map(PythiaHistoryRecord.fromJson)
        .toList();
  }

  Future<List<PythiaHistoryRecord>> readVisibleHistory() async {
    final all = await readAllForSync();
    return all.where((record) => !record.isDeleted).toList()
      ..sort(_historySort);
  }

  Future<void> addHistory(PythiaHistoryRecord record) async {
    final all = await readAllForSync();
    all.removeWhere((item) => item.id == record.id);
    all.insert(
        0,
        record.copyWith(
          deviceId:
              record.deviceId.isEmpty ? await deviceId() : record.deviceId,
          syncStatus: PythiaSyncStatus.pendingUpload,
          schemaVersion: PythiaHistoryRecord.currentSchemaVersion,
        ));
    await _writeHistory(all);
  }

  Future<void> markDeleted(String id) async {
    final now = DateTime.now().toUtc();
    final all = await readAllForSync();
    final updated = [
      for (final record in all)
        if (record.id == id)
          record.copyWith(
            deletedAt: now,
            updatedAt: now,
            syncStatus: PythiaSyncStatus.pendingDelete,
          )
        else
          record,
    ];
    await _writeHistory(updated);
  }

  Future<void> clearVisibleHistory() async {
    final now = DateTime.now().toUtc();
    final all = await readAllForSync();
    final updated = [
      for (final record in all)
        if (record.isDeleted)
          record
        else
          record.copyWith(
            deletedAt: now,
            updatedAt: now,
            syncStatus: PythiaSyncStatus.pendingDelete,
          ),
    ];
    await _writeHistory(updated);
  }

  Future<void> setFavorite(String id, bool isFavorite) async {
    final now = DateTime.now().toUtc();
    final all = await readAllForSync();
    final updated = [
      for (final record in all)
        if (record.id == id)
          record.copyWith(
            isFavorite: isFavorite,
            updatedAt: now,
            syncStatus: PythiaSyncStatus.pendingUpload,
          )
        else
          record,
    ];
    await _writeHistory(updated);
  }

  Future<List<PythiaHistoryRecord>> searchVisibleHistory(String query) async {
    final trimmed = query.trim().toLowerCase();
    final visible = await readVisibleHistory();
    if (trimmed.isEmpty) return visible;
    return visible
        .where((record) =>
            record.sourceText.toLowerCase().contains(trimmed) ||
            record.translatedText.toLowerCase().contains(trimmed) ||
            record.service.toLowerCase().contains(trimmed))
        .toList();
  }

  @override
  Future<void> backupBeforeSync() async {
    final file = await _historyFile();
    final directory = await _directory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final backup = File(
      '${directory.path}${Platform.pathSeparator}history-before-sync-$stamp-${_randomId().substring(0, 8)}.json',
    );
    if (file.existsSync()) {
      await file.copy(backup.path);
    } else {
      await backup.writeAsString('[]', flush: true);
    }
  }

  @override
  Future<void> replaceAllFromSync(List<PythiaHistoryRecord> records) {
    return _writeHistory(records);
  }

  Future<void> _writeHistory(List<PythiaHistoryRecord> records) async {
    final file = await _historyFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(records.map((record) => record.toJson()).toList()),
      flush: true,
    );
  }

  static int _historySort(PythiaHistoryRecord a, PythiaHistoryRecord b) {
    if (a.isFavorite != b.isFavorite) {
      return a.isFavorite ? -1 : 1;
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    return bytes.map(hex).join();
  }
}
