import Foundation

public enum PluginPackageFormat: String, Codable, CaseIterable, Sendable {
    case pythia
    case potext

    public init?(fileName: String) {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        self.init(rawValue: fileExtension)
    }
}

public struct PythiaPluginConfigurationField: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let type: String
    public let required: Bool?
    public let defaultValue: String?
    public let options: [String: String]?

    public init(
        key: String,
        label: String,
        type: String,
        required: Bool? = nil,
        defaultValue: String? = nil,
        options: [String: String]? = nil
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.options = options
    }
}

public enum PythiaPluginSecretPolicy {
    public static func isLikelySecretKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        if ["secret", "password", "passwd", "token"].contains(normalized) {
            return true
        }
        return normalized.hasSuffix("apikey")
            || normalized.hasSuffix("appkey")
            || normalized.contains("accesskey")
            || normalized.hasSuffix("secretkey")
            || normalized.hasSuffix("clientsecret")
            || (normalized.hasSuffix("token") && !normalized.hasSuffix("tokens"))
    }
}

public struct PythiaPluginManifest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let author: String
    public let type: String
    public let entry: String
    public let minimumPythiaVersion: String
    public let supportedPlatforms: [String]
    public let permissions: [String]
    public let configuration: [PythiaPluginConfigurationField]
    public let capabilities: [String]

    public init(
        schemaVersion: String,
        id: String,
        name: String,
        version: String,
        description: String,
        author: String,
        type: String,
        entry: String,
        minimumPythiaVersion: String,
        supportedPlatforms: [String],
        permissions: [String],
        configuration: [PythiaPluginConfigurationField],
        capabilities: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.type = type
        self.entry = entry
        self.minimumPythiaVersion = minimumPythiaVersion
        self.supportedPlatforms = supportedPlatforms
        self.permissions = permissions
        self.configuration = configuration
        self.capabilities = capabilities
    }
}

public enum PythiaPluginValidationError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(String)
    case invalidIdentifier(String)
    case missingField(String)
    case invalidVersion(String)
    case unsupportedType(String)
    case unsafeEntry(String)
    case unsupportedPlatform(String)
    case invalidPermission(String)
    case invalidConfigurationKey(String)
    case invalidConfigurationType(String)
    case secretDefaultValue(String)
    case missingCapability(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let value):
            return "不支持插件 schemaVersion：\(value)。"
        case .invalidIdentifier(let value):
            return "插件 id 格式无效：\(value)。"
        case .missingField(let field):
            return "插件 Manifest 缺少有效的 \(field)。"
        case .invalidVersion(let value):
            return "插件 version 格式无效：\(value)。"
        case .unsupportedType(let value):
            return "Pythia 1.0.0 暂不支持插件类型：\(value)。"
        case .unsafeEntry(let value):
            return "插件入口路径不安全：\(value)。"
        case .unsupportedPlatform(let value):
            return "插件不支持当前平台：\(value)。"
        case .invalidPermission(let value):
            return "插件声明了不支持的权限：\(value)。"
        case .invalidConfigurationKey(let value):
            return "插件配置键格式无效或重复：\(value)。"
        case .invalidConfigurationType(let value):
            return "插件配置类型不受支持：\(value)。"
        case .secretDefaultValue(let value):
            return "secret 配置不得包含默认值：\(value)。"
        case .missingCapability(let value):
            return "插件缺少必要能力：\(value)。"
        }
    }
}

public struct PotextConversionResult: Sendable {
    public let manifest: PythiaPluginManifest
    public let mainJavaScript: String
    public let warnings: [String]

    public init(manifest: PythiaPluginManifest, mainJavaScript: String, warnings: [String]) {
        self.manifest = manifest
        self.mainJavaScript = mainJavaScript
        self.warnings = warnings
    }
}

public enum PotextPluginConverter {
    public static func convert(
        infoData: Data,
        mainJavaScript: String,
        fallbackIdentifier: String
    ) throws -> PotextConversionResult {
        guard let info = try JSONSerialization.jsonObject(with: infoData) as? [String: Any] else {
            throw PythiaPluginValidationError.missingField("info.json")
        }
        let legacyType = stringValue(info["plugin_type"])
        guard legacyType == "translate" else {
            throw PythiaPluginValidationError.unsupportedType(legacyType)
        }

        let rawIdentifier = stringValue(info["id"]).isEmpty ? fallbackIdentifier : stringValue(info["id"])
        let identifier = normalizedIdentifier(rawIdentifier)
        let name = firstNonEmpty(
            stringValue(info["display"]),
            stringValue(info["name"]),
            identifier
        )
        let declaredVersion = stringValue(info["version"])
        let versionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$"#
        let version = declaredVersion.range(of: versionPattern, options: .regularExpression) == nil
            ? "1.0.0"
            : declaredVersion
        var warnings: [String] = []
        if declaredVersion.isEmpty {
            warnings.append("原插件未声明版本，转换后使用 1.0.0。")
        } else if version != declaredVersion {
            warnings.append("原插件版本格式不兼容，转换后使用 1.0.0。")
        }

        let needs = info["needs"] as? [[String: Any]] ?? []
        let configuration = needs.compactMap { need -> PythiaPluginConfigurationField? in
            let key = stringValue(need["key"])
            guard !key.isEmpty else {
                warnings.append("已忽略缺少 key 的配置项。")
                return nil
            }
            let label = firstNonEmpty(stringValue(need["display"]), key)
            let legacyInputType = stringValue(need["type"])
            let isSecret = need["secret"] as? Bool == true
                || ["password", "secret"].contains(legacyInputType.lowercased())
                || PythiaPluginSecretPolicy.isLikelySecretKey(key)
            let type = isSecret ? "secret" : (legacyInputType == "select" ? "select" : "text")
            let defaultValue = optionalStringValue(need["default"])
            let options = need["options"] as? [String: String]
            return PythiaPluginConfigurationField(
                key: key,
                label: label,
                type: type,
                required: isSecret && (defaultValue?.isEmpty != false),
                defaultValue: defaultValue,
                options: options
            )
        }
        let needsNetwork = mainJavaScript.range(
            of: #"tauriFetch|utils\.http|\bfetch\s*\("#,
            options: [.regularExpression]
        ) != nil
        let homepage = stringValue(info["homepage"])
        let author = inferredAuthor(from: homepage)
        let manifest = PythiaPluginManifest(
            schemaVersion: "1.0",
            id: identifier,
            name: name,
            version: version,
            description: firstNonEmpty(
                stringValue(info["description"]),
                "由 Pythia 从 Pot 插件自动转换。"
            ),
            author: author,
            type: "translator",
            entry: "main.js",
            minimumPythiaVersion: "1.0.0",
            supportedPlatforms: ["macos", "windows"],
            permissions: needsNetwork ? ["network"] : [],
            configuration: configuration,
            capabilities: ["translate"]
        )
        try PluginPackagePolicy.validate(manifest, platform: "macos")
        let convertedSource = compatibilityPrelude + "\n" + mainJavaScript + "\n" + compatibilityPostlude
        warnings.append("已保留原 main.js，并通过 Pythia 统一请求/响应适配层运行。")
        return PotextConversionResult(manifest: manifest, mainJavaScript: convertedSource, warnings: warnings)
    }

    private static func normalizedIdentifier(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        var value = rawValue.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        if value.count < 3 { value = "plugin.\(value.isEmpty ? "converted" : value)" }
        return String(value.prefix(128))
    }

    private static func inferredAuthor(from homepage: String) -> String {
        guard let url = URL(string: homepage), let host = url.host else { return "Unknown" }
        if host.lowercased().contains("github.com") {
            let owner = url.pathComponents.dropFirst().first ?? ""
            if !owner.isEmpty { return owner }
        }
        return host
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    private static func stringValue(_ value: Any?) -> String {
        optionalStringValue(value) ?? ""
    }

    private static func optionalStringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static let compatibilityPrelude = #"""
globalThis.ResponseType = Object.freeze({ Text: "Text", Json: "Json", JSON: "Json" });
globalThis.Body = Object.freeze({
  json: (payload) => ({ type: "Json", payload }),
  form: (payload) => ({ type: "Form", payload }),
  text: (payload) => ({ type: "Text", payload })
});
"""#

    private static let compatibilityPostlude = #"""

const __pythiaLegacyTranslate = translate;

async function __pythiaCompatFetch(context, url, options = {}) {
  const headers = { ...(options.headers || {}) };
  let body = options.body;
  if (body && typeof body === "object" && Object.prototype.hasOwnProperty.call(body, "type")) {
    if (body.type === "Json") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) {
        headers["Content-Type"] = "application/json";
      }
      body = JSON.stringify(body.payload);
    } else if (body.type === "Form") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) {
        headers["Content-Type"] = "application/x-www-form-urlencoded";
      }
      body = new URLSearchParams(body.payload || {}).toString();
    } else {
      body = String(body.payload ?? "");
    }
  } else if (body && typeof body === "object") {
    if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) {
      headers["Content-Type"] = "application/json";
    }
    body = JSON.stringify(body);
  }
  const response = await context.fetch(url, { method: options.method || "GET", headers, body });
  const responseText = await response.text();
  const wantsText = options.responseType === "Text" || options.responseType === "text";
  let data = responseText;
  if (!wantsText) {
    try { data = responseText ? JSON.parse(responseText) : null; } catch (_) {}
  }
  return {
    ok: response.ok,
    status: response.status,
    url: response.url,
    data,
    headers: Object.fromEntries(response.headers.entries())
  };
}

module.exports.translate = async function pythiaConvertedTranslate(request, context) {
  const input = request && request.input ? request.input : {};
  const compatFetch = (url, options) => __pythiaCompatFetch(context, url, options);
  const utils = {
    tauriFetch: compatFetch,
    http: { fetch: compatFetch, Body: globalThis.Body }
  };
  return await __pythiaLegacyTranslate(
    String(input.text || ""),
    String(input.sourceLanguage || "auto"),
    String(input.targetLanguage || "zh-CN"),
    {
      config: context.config || {},
      detect: input.detectedLanguage || input.sourceLanguage || "auto",
      utils,
      setResult: () => {}
    }
  );
};
"""#
}

public enum PluginPackagePolicy {
    public static func accepts(fileName: String) -> Bool {
        PluginPackageFormat(fileName: fileName) != nil
    }

    public static func format(fileName: String) -> PluginPackageFormat? {
        PluginPackageFormat(fileName: fileName)
    }

    public static func decodeAndValidateManifest(
        _ data: Data,
        platform: String
    ) throws -> PythiaPluginManifest {
        let manifest = try JSONDecoder().decode(PythiaPluginManifest.self, from: data)
        try validate(manifest, platform: platform)
        return manifest
    }

    public static func validate(_ manifest: PythiaPluginManifest, platform: String) throws {
        guard manifest.schemaVersion == "1.0" else {
            throw PythiaPluginValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        let identifierPattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$"#
        guard manifest.id.range(of: identifierPattern, options: .regularExpression) != nil else {
            throw PythiaPluginValidationError.invalidIdentifier(manifest.id)
        }
        for (field, value) in [
            ("name", manifest.name),
            ("description", manifest.description),
            ("author", manifest.author),
            ("minimumPythiaVersion", manifest.minimumPythiaVersion),
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PythiaPluginValidationError.missingField(field)
        }
        let versionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$"#
        guard manifest.version.range(of: versionPattern, options: .regularExpression) != nil else {
            throw PythiaPluginValidationError.invalidVersion(manifest.version)
        }
        guard manifest.type == "translator" else {
            throw PythiaPluginValidationError.unsupportedType(manifest.type)
        }

        let entry = manifest.entry.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryComponents = NSString(string: entry).pathComponents
        guard !entry.isEmpty,
              !entry.hasPrefix("/"),
              !entryComponents.contains(".."),
              URL(fileURLWithPath: entry).pathExtension.lowercased() == "js"
        else {
            throw PythiaPluginValidationError.unsafeEntry(manifest.entry)
        }

        let normalizedPlatform = platform.lowercased()
        guard manifest.supportedPlatforms.map({ $0.lowercased() }).contains(normalizedPlatform) else {
            throw PythiaPluginValidationError.unsupportedPlatform(platform)
        }
        let supportedPermissions = Set(["network"])
        if let unsupported = manifest.permissions.first(where: { !supportedPermissions.contains($0.lowercased()) }) {
            throw PythiaPluginValidationError.invalidPermission(unsupported)
        }

        let configurationKeyPattern = #"^[A-Za-z][A-Za-z0-9._-]{0,127}$"#
        var configurationKeys = Set<String>()
        for field in manifest.configuration {
            guard field.key.range(of: configurationKeyPattern, options: .regularExpression) != nil,
                  configurationKeys.insert(field.key).inserted
            else {
                throw PythiaPluginValidationError.invalidConfigurationKey(field.key)
            }
            guard ["text", "secret", "select"].contains(field.type) else {
                throw PythiaPluginValidationError.invalidConfigurationType(field.type)
            }
            if field.type == "secret", let defaultValue = field.defaultValue, !defaultValue.isEmpty {
                throw PythiaPluginValidationError.secretDefaultValue(field.key)
            }
        }
        guard manifest.capabilities.contains("translate") else {
            throw PythiaPluginValidationError.missingCapability("translate")
        }
    }

    public static func displayName(
        alias: String?,
        declaredDisplay: String?,
        declaredName: String?,
        fallback: String
    ) -> String {
        [alias, declaredDisplay, declaredName, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallback
    }
}
