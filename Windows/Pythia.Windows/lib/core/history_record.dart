enum PythiaSyncStatus {
  local,
  pendingUpload,
  pendingDelete,
  synced,
  conflict,
}

PythiaSyncStatus syncStatusFromJson(String? raw) {
  switch (raw) {
    case 'pendingUpload':
      return PythiaSyncStatus.pendingUpload;
    case 'pendingDelete':
      return PythiaSyncStatus.pendingDelete;
    case 'synced':
      return PythiaSyncStatus.synced;
    case 'conflict':
      return PythiaSyncStatus.conflict;
    case 'local':
    default:
      return PythiaSyncStatus.local;
  }
}

String syncStatusToJson(PythiaSyncStatus status) => switch (status) {
      PythiaSyncStatus.pendingUpload => 'pendingUpload',
      PythiaSyncStatus.pendingDelete => 'pendingDelete',
      PythiaSyncStatus.synced => 'synced',
      PythiaSyncStatus.conflict => 'conflict',
      PythiaSyncStatus.local => 'local',
    };

class PythiaHistoryRecord {
  static const currentSchemaVersion = 1;

  final String id;
  final String sourceText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final String service;
  final String? model;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final String deviceId;
  final PythiaSyncStatus syncStatus;
  final DateTime? deletedAt;
  final int schemaVersion;

  const PythiaHistoryRecord({
    required this.id,
    required this.sourceText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.service,
    this.model,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    required this.deviceId,
    this.syncStatus = PythiaSyncStatus.local,
    this.deletedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  bool get isDeleted => deletedAt != null;

  PythiaHistoryRecord copyWith({
    String? id,
    String? sourceText,
    String? translatedText,
    String? sourceLanguage,
    String? targetLanguage,
    String? service,
    String? model,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    String? deviceId,
    PythiaSyncStatus? syncStatus,
    DateTime? deletedAt,
    int? schemaVersion,
    bool clearModel = false,
    bool clearDeletedAt = false,
  }) {
    return PythiaHistoryRecord(
      id: id ?? this.id,
      sourceText: sourceText ?? this.sourceText,
      translatedText: translatedText ?? this.translatedText,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      service: service ?? this.service,
      model: clearModel ? null : (model ?? this.model),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      deviceId: deviceId ?? this.deviceId,
      syncStatus: syncStatus ?? this.syncStatus,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  factory PythiaHistoryRecord.fromJson(Map<String, Object?> json) {
    return PythiaHistoryRecord(
      id: json['id'] as String,
      sourceText: json['sourceText'] as String,
      translatedText: json['translatedText'] as String,
      sourceLanguage: json['sourceLanguage'] as String,
      targetLanguage: json['targetLanguage'] as String,
      service: json['service'] as String,
      model: json['model'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
      deviceId: json['deviceId'] as String? ?? '',
      syncStatus: syncStatusFromJson(json['syncStatus'] as String?),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      schemaVersion: json['schemaVersion'] as int? ??
          PythiaHistoryRecord.currentSchemaVersion,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'sourceText': sourceText,
        'translatedText': translatedText,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'service': service,
        if (model != null) 'model': model,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'isFavorite': isFavorite,
        'deviceId': deviceId,
        'syncStatus': syncStatusToJson(syncStatus),
        if (deletedAt != null)
          'deletedAt': deletedAt!.toUtc().toIso8601String(),
        'schemaVersion': schemaVersion,
      };
}

class PythiaHistoryCollection {
  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final String deviceId;
  final DateTime updatedAt;
  final List<PythiaHistoryRecord> records;

  const PythiaHistoryCollection({
    this.schemaVersion = currentSchemaVersion,
    required this.deviceId,
    required this.updatedAt,
    required this.records,
  });

  factory PythiaHistoryCollection.fromJson(Map<String, Object?> json) {
    final rawRecords = json['records'] as List<Object?>? ?? const [];
    return PythiaHistoryCollection(
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      deviceId: json['deviceId'] as String? ?? 'unknown',
      updatedAt: json['updatedAt'] == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.parse(json['updatedAt'] as String),
      records: rawRecords
          .cast<Map<String, Object?>>()
          .map(PythiaHistoryRecord.fromJson)
          .toList(),
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'deviceId': deviceId,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'records': records.map((record) => record.toJson()).toList(),
      };
}
