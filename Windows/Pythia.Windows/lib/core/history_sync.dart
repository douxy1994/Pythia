import 'history_record.dart';

class PythiaHistorySyncResult {
  final List<PythiaHistoryRecord> merged;
  final List<PythiaHistoryRecord> conflicts;

  const PythiaHistorySyncResult({
    required this.merged,
    required this.conflicts,
  });
}

class PythiaHistoryMerger {
  const PythiaHistoryMerger._();

  static PythiaHistorySyncResult merge({
    required List<PythiaHistoryRecord> local,
    required List<PythiaHistoryRecord> remote,
  }) {
    final recordsById = <String, PythiaHistoryRecord>{};
    final conflicts = <PythiaHistoryRecord>[];

    for (final record in [...local, ...remote].map(_normalized)) {
      final current = recordsById[record.id];
      if (current == null) {
        recordsById[record.id] = record;
        continue;
      }
      final merged = _mergeSameId(current, record);
      recordsById[record.id] = merged;
      if (_isContentConflict(current, record)) {
        conflicts.add(merged.copyWith(syncStatus: PythiaSyncStatus.conflict));
      }
    }

    final merged = recordsById.values.map((record) {
      if (record.syncStatus == PythiaSyncStatus.pendingDelete ||
          record.syncStatus == PythiaSyncStatus.conflict) {
        return record;
      }
      return record.copyWith(syncStatus: PythiaSyncStatus.synced);
    }).toList()
      ..sort((a, b) {
        final created = b.createdAt.compareTo(a.createdAt);
        return created == 0 ? b.updatedAt.compareTo(a.updatedAt) : created;
      });

    return PythiaHistorySyncResult(merged: merged, conflicts: conflicts);
  }

  static PythiaHistoryRecord _normalized(PythiaHistoryRecord record) {
    final schemaVersion = record.schemaVersion <= 0
        ? PythiaHistoryRecord.currentSchemaVersion
        : record.schemaVersion;
    return record.copyWith(schemaVersion: schemaVersion);
  }

  static PythiaHistoryRecord _mergeSameId(
    PythiaHistoryRecord lhs,
    PythiaHistoryRecord rhs,
  ) {
    if (lhs.deletedAt != null || rhs.deletedAt != null) {
      return _newestDeletionFirst(lhs, rhs);
    }
    if (rhs.updatedAt.isAfter(lhs.updatedAt)) return rhs;
    if (lhs.updatedAt.isAfter(rhs.updatedAt)) return lhs;
    if (_isContentConflict(lhs, rhs)) {
      return lhs.copyWith(syncStatus: PythiaSyncStatus.conflict);
    }
    return lhs;
  }

  static PythiaHistoryRecord _newestDeletionFirst(
    PythiaHistoryRecord lhs,
    PythiaHistoryRecord rhs,
  ) {
    if (lhs.deletedAt != null && rhs.deletedAt != null) {
      return rhs.updatedAt.isAfter(lhs.updatedAt) ? rhs : lhs;
    }
    if (lhs.deletedAt != null) return lhs;
    return rhs;
  }

  static bool _isContentConflict(
    PythiaHistoryRecord lhs,
    PythiaHistoryRecord rhs,
  ) {
    if (lhs.updatedAt != rhs.updatedAt) return false;
    return lhs.sourceText != rhs.sourceText ||
        lhs.translatedText != rhs.translatedText ||
        lhs.sourceLanguage != rhs.sourceLanguage ||
        lhs.targetLanguage != rhs.targetLanguage ||
        lhs.service != rhs.service ||
        lhs.model != rhs.model ||
        lhs.isFavorite != rhs.isFavorite ||
        lhs.deletedAt != rhs.deletedAt;
  }
}
