import Foundation

final class HistoryStore {
    static let shared = HistoryStore()
    private let fileURL: URL
    private let deviceIdURL: URL
    private var allRecords: [TranslationRecord] = []
    private(set) var records: [TranslationRecord] = []
    private lazy var deviceId: String = loadOrCreateDeviceId()

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pythia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("history.json")
        deviceIdURL = directory.appendingPathComponent("device-id.txt")
        load()
    }

    func add(_ record: TranslationRecord) {
        guard !Preferences.shared.historyDisable else { return }
        var normalized = self.normalized(record)
        normalized.syncStatus = .pendingUpload
        normalized.schemaVersion = PythiaHistoryRecord.currentSchemaVersion
        allRecords.removeAll { $0.id == normalized.id }
        allRecords.insert(normalized, at: 0)
        enforceLimit()
        refreshVisibleRecords()
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    func clear() {
        let now = Date()
        allRecords = allRecords.map { record in
            var copy = record
            if copy.deletedAt == nil {
                copy.deletedAt = now
                copy.updatedAt = now
                copy.syncStatus = .pendingDelete
            }
            return copy
        }
        refreshVisibleRecords()
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    func delete(at index: Int) {
        guard records.indices.contains(index) else { return }
        let id = records[index].id
        let now = Date()
        if let allIndex = allRecords.firstIndex(where: { $0.id == id }) {
            allRecords[allIndex].deletedAt = now
            allRecords[allIndex].updatedAt = now
            allRecords[allIndex].syncStatus = .pendingDelete
        }
        refreshVisibleRecords()
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    func export(to url: URL) throws {
        let data = try historyEncoder().encode(allRecords)
        try data.write(to: url, options: [.atomic])
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = historyDecoder()
        if let decoded = try? decoder.decode([TranslationRecord].self, from: data) {
            allRecords = decoded.map(normalized)
            if allRecords != decoded {
                save()
            }
        } else if let legacy = try? decoder.decode([LegacyTranslationRecord].self, from: data) {
            allRecords = legacy.map { $0.toHistoryRecord(deviceId: deviceId) }
            save()
        } else {
            allRecords = []
        }
        enforceLimit()
        refreshVisibleRecords()
    }

    private func save() {
        guard let data = try? historyEncoder().encode(allRecords) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// Replaces all records with the given list (used when restoring a backup),
    /// caps to the 500-entry limit, persists, and notifies observers.
    func restore(_ newRecords: [TranslationRecord]) {
        allRecords = newRecords.map(normalized)
        enforceLimit()
        refreshVisibleRecords()
        save()
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    /// Parses an array of history record dictionaries (as stored in backups)
    /// into [TranslationRecord], skipping invalid entries.
    func records(fromJSONArray array: [[String: Any]]) -> [TranslationRecord] {
        array.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            if let record = try? historyDecoder().decode(TranslationRecord.self, from: data) {
                return normalized(record)
            }
            if let legacy = try? historyDecoder().decode(LegacyTranslationRecord.self, from: data) {
                return legacy.toHistoryRecord(deviceId: deviceId)
            }
            return nil
        }
    }

    func allRecordsForSync() -> [TranslationRecord] {
        allRecords
    }

    func deviceIdentifierForSync() -> String {
        deviceId
    }

    @discardableResult
    func backupBeforeSync() throws -> URL {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("history-before-sync-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        } else {
            let data = try historyEncoder().encode(allRecords)
            try data.write(to: backupURL, options: [.atomic])
        }
        return backupURL
    }

    private func refreshVisibleRecords() {
        records = allRecords
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func enforceLimit() {
        let active = allRecords.filter { $0.deletedAt == nil }
        guard active.count > 500 else { return }
        let keepIDs = Set(active
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(500)
            .map(\.id))
        allRecords.removeAll { record in
            record.deletedAt == nil && !keepIDs.contains(record.id)
        }
    }

    private func normalized(_ record: TranslationRecord) -> TranslationRecord {
        var copy = record
        if copy.deviceId.isEmpty { copy.deviceId = deviceId }
        if copy.schemaVersion <= 0 { copy.schemaVersion = PythiaHistoryRecord.currentSchemaVersion }
        return copy
    }

    private func historyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func historyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self),
               let date = ISO8601DateFormatter().date(from: text) {
                return date
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format")
        }
        return decoder
    }

    private func loadOrCreateDeviceId() -> String {
        if let value = try? String(contentsOf: deviceIdURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        let value = UUID().uuidString
        try? value.write(to: deviceIdURL, atomically: true, encoding: .utf8)
        return value
    }
}

private struct LegacyTranslationRecord: Codable {
    let id: UUID
    let date: Date
    let provider: String
    let sourceLanguage: String
    let targetLanguage: String
    let source: String
    let result: String

    func toHistoryRecord(deviceId: String) -> PythiaHistoryRecord {
        PythiaHistoryRecord(
            id: id.uuidString,
            sourceText: source,
            translatedText: result,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            service: provider,
            model: nil,
            createdAt: date,
            updatedAt: date,
            isFavorite: false,
            deviceId: deviceId,
            syncStatus: .local,
            deletedAt: nil,
            schemaVersion: PythiaHistoryRecord.currentSchemaVersion
        )
    }
}
