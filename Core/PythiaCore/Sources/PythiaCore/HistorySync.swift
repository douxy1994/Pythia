import Foundation

public enum PythiaSyncStatus: String, Codable, Sendable {
    case local
    case synced
    case pendingUpload
    case pendingDelete
    case conflict
}

public struct PythiaHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var id: String
    public var sourceText: String
    public var translatedText: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var service: String
    public var model: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var isFavorite: Bool
    public var deviceId: String
    public var syncStatus: PythiaSyncStatus
    public var deletedAt: Date?
    public var schemaVersion: Int

    public init(
        id: String = UUID().uuidString,
        sourceText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        service: String,
        model: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        deviceId: String,
        syncStatus: PythiaSyncStatus = .local,
        deletedAt: Date? = nil,
        schemaVersion: Int = PythiaHistoryRecord.currentSchemaVersion
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.service = service
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.deviceId = deviceId
        self.syncStatus = syncStatus
        self.deletedAt = deletedAt
        self.schemaVersion = schemaVersion
    }
}

public struct PythiaHistorySyncResult: Equatable, Sendable {
    public var merged: [PythiaHistoryRecord]
    public var conflicts: [PythiaHistoryRecord]

    public init(merged: [PythiaHistoryRecord], conflicts: [PythiaHistoryRecord]) {
        self.merged = merged
        self.conflicts = conflicts
    }
}

public struct PythiaHistoryCollection: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var updatedAt: Date
    public var deviceId: String
    public var records: [PythiaHistoryRecord]

    public init(
        schemaVersion: Int = PythiaHistoryCollection.currentSchemaVersion,
        updatedAt: Date = Date(),
        deviceId: String,
        records: [PythiaHistoryRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.deviceId = deviceId
        self.records = records
    }
}

public enum PythiaHistoryMerger {
    public static func merge(
        local: [PythiaHistoryRecord],
        remote: [PythiaHistoryRecord],
        maxRecords: Int = 5_000
    ) -> PythiaHistorySyncResult {
        var recordsByID: [String: PythiaHistoryRecord] = [:]
        var conflicts: [PythiaHistoryRecord] = []

        for record in local {
            recordsByID[record.id] = normalized(record)
        }

        for remoteRecord in remote.map(normalized) {
            guard let localRecord = recordsByID[remoteRecord.id] else {
                recordsByID[remoteRecord.id] = remoteRecord
                continue
            }

            let merged = mergeSameID(local: localRecord, remote: remoteRecord)
            recordsByID[remoteRecord.id] = merged

            if isContentConflict(local: localRecord, remote: remoteRecord) {
                var conflict = merged
                conflict.syncStatus = .conflict
                conflicts.append(conflict)
            }
        }

        let merged = recordsByID.values
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.createdAt > rhs.createdAt }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(maxRecords)
            .map { record -> PythiaHistoryRecord in
                var copy = record
                if copy.syncStatus != .pendingDelete && copy.syncStatus != .conflict {
                    copy.syncStatus = .synced
                }
                return copy
            }

        return PythiaHistorySyncResult(merged: Array(merged), conflicts: conflicts)
    }

    private static func normalized(_ record: PythiaHistoryRecord) -> PythiaHistoryRecord {
        var copy = record
        if copy.schemaVersion <= 0 {
            copy.schemaVersion = PythiaHistoryRecord.currentSchemaVersion
        }
        return copy
    }

    private static func mergeSameID(local: PythiaHistoryRecord, remote: PythiaHistoryRecord) -> PythiaHistoryRecord {
        if local.deletedAt != nil || remote.deletedAt != nil {
            return newestDeletionFirst(local: local, remote: remote)
        }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }

        var merged = local
        merged.isFavorite = local.isFavorite || remote.isFavorite
        merged.schemaVersion = max(local.schemaVersion, remote.schemaVersion)
        return merged
    }

    private static func newestDeletionFirst(local: PythiaHistoryRecord, remote: PythiaHistoryRecord) -> PythiaHistoryRecord {
        switch (local.deletedAt, remote.deletedAt) {
        case let (lhs?, rhs?):
            return lhs >= rhs ? local : remote
        case (.some, .none):
            return local
        case (.none, .some):
            return remote
        case (.none, .none):
            return local.updatedAt >= remote.updatedAt ? local : remote
        }
    }

    private static func isContentConflict(local: PythiaHistoryRecord, remote: PythiaHistoryRecord) -> Bool {
        guard local.id == remote.id, local.deletedAt == nil, remote.deletedAt == nil else { return false }
        guard local.updatedAt == remote.updatedAt else { return false }
        return local.sourceText != remote.sourceText
            || local.translatedText != remote.translatedText
            || local.sourceLanguage != remote.sourceLanguage
            || local.targetLanguage != remote.targetLanguage
            || local.service != remote.service
            || local.model != remote.model
    }
}
