import Foundation

public struct PythiaPortableSettings: Codable, Equatable, Sendable {
    public var sourceLanguage: String?
    public var targetLanguage: String?
    public var enabledTranslateServices: [String]?
    public var translateServiceOrder: [String]?
    public var openAICompatibleEnabled: Bool?
    public var openAICompatibleName: String?
    public var openAICompatibleBaseUrl: String?
    public var openAICompatibleModel: String?
    public var deepLEnabled: Bool?
    public var deepLBaseUrl: String?
    public var libreTranslateEnabled: Bool?
    public var libreTranslateBaseUrl: String?
    public var saveHistory: Bool?
    public var themeMode: String?

    public init(
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        enabledTranslateServices: [String]? = nil,
        translateServiceOrder: [String]? = nil,
        openAICompatibleEnabled: Bool? = nil,
        openAICompatibleName: String? = nil,
        openAICompatibleBaseUrl: String? = nil,
        openAICompatibleModel: String? = nil,
        deepLEnabled: Bool? = nil,
        deepLBaseUrl: String? = nil,
        libreTranslateEnabled: Bool? = nil,
        libreTranslateBaseUrl: String? = nil,
        saveHistory: Bool? = nil,
        themeMode: String? = nil
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.enabledTranslateServices = enabledTranslateServices
        self.translateServiceOrder = translateServiceOrder
        self.openAICompatibleEnabled = openAICompatibleEnabled
        self.openAICompatibleName = openAICompatibleName
        self.openAICompatibleBaseUrl = openAICompatibleBaseUrl
        self.openAICompatibleModel = openAICompatibleModel
        self.deepLEnabled = deepLEnabled
        self.deepLBaseUrl = deepLBaseUrl
        self.libreTranslateEnabled = libreTranslateEnabled
        self.libreTranslateBaseUrl = libreTranslateBaseUrl
        self.saveHistory = saveHistory
        self.themeMode = themeMode
    }
}

public struct PythiaPortableBackup: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var product: String
    public var createdAt: Date
    public var sensitiveFieldsOmitted: Bool
    public var settings: PythiaPortableSettings
    public var history: [PythiaHistoryRecord]

    public init(
        schemaVersion: Int = PythiaPortableBackup.currentSchemaVersion,
        product: String = "Pythia",
        createdAt: Date = Date(),
        sensitiveFieldsOmitted: Bool = true,
        settings: PythiaPortableSettings,
        history: [PythiaHistoryRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.createdAt = createdAt
        self.sensitiveFieldsOmitted = sensitiveFieldsOmitted
        self.settings = settings
        self.history = history
    }
}

public enum PythiaPortableBackupError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case foreignProduct(String)
    case unsafePayload

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "不支持 Pythia 备份格式版本 \(version)。"
        case let .foreignProduct(product):
            return "这不是 Pythia 备份文件（product: \(product)）。"
        case .unsafePayload:
            return "备份未声明已排除敏感字段。"
        }
    }
}

public enum PythiaPortableBackupCodec {
    public static func encode(_ backup: PythiaPortableBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> PythiaPortableBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PythiaPortableBackup.self, from: data)
        guard backup.schemaVersion == PythiaPortableBackup.currentSchemaVersion else {
            throw PythiaPortableBackupError.unsupportedSchema(backup.schemaVersion)
        }
        guard backup.product == "Pythia" else {
            throw PythiaPortableBackupError.foreignProduct(backup.product)
        }
        guard backup.sensitiveFieldsOmitted else {
            throw PythiaPortableBackupError.unsafePayload
        }
        return backup
    }
}
