import Foundation

enum PythiaProvider: String, CaseIterable {
    case local = "Local"
    case google = "Google"
    case openAI = "OpenAI"
    case deepL = "DeepL"
    case baidu = "Baidu"
    case youdao = "Youdao"
    case libreTranslate = "LibreTranslate"
    case plugin = "Plugin"
}

typealias TranslationRecord = PythiaHistoryRecord

extension PythiaHistoryRecord {
    var date: Date { createdAt }
    var provider: String { service }
    var source: String { sourceText }
    var result: String { translatedText }
}

struct CommandPlugin: Codable {
    let name: String
    let command: String
    let arguments: [String]?
    let environment: [String: String]?
    let legacyDirectory: String?
    let legacyType: String?
    let displayName: String?

    init(
        name: String,
        command: String,
        arguments: [String]? = nil,
        environment: [String: String]? = nil,
        legacyDirectory: String? = nil,
        legacyType: String? = nil,
        displayName: String? = nil
    ) {
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.legacyDirectory = legacyDirectory
        self.legacyType = legacyType
        self.displayName = displayName
    }

    var title: String {
        displayName?.isEmpty == false ? displayName! : name
    }

    var serviceIdentifier: String {
        "plugin:\(name)"
    }
}

enum TranslationError: LocalizedError {
    case emptyInput
    case missingKey(String)
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "没有可翻译的文本。"
        case .missingKey(let name):
            return "请先在设置里填写 \(name)。"
        case .invalidResponse:
            return "翻译服务返回了无法解析的响应。"
        case .requestFailed(let message):
            return message
        }
    }
}
