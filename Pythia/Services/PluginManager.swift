import Foundation
import LocalAuthentication
import Security

private struct PluginSecretStore {
    private let service = "com.douxy.pythia.plugin-configuration"

    func read(pluginID: String, key: String) -> String? {
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(pluginID: pluginID, key: key),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Never trigger an authentication dialog. Pythia-created items do not
            // require user presence, and inaccessible legacy items are ignored.
            kSecUseAuthenticationContext as String: authenticationContext,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, pluginID: String, key: String) throws {
        let account = account(pluginID: pluginID, key: key)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func delete(pluginID: String, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(pluginID: pluginID, key: key),
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func account(pluginID: String, key: String) -> String {
        "\(pluginID):\(key)"
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "无法保存插件密钥。"]
            )
        }
    }
}

final class PluginManager {
    static let shared = PluginManager()
    let pluginsDirectory: URL
    let legacyPluginsDirectory: URL
    private let pluginSecretStore = PluginSecretStore()

    private init() {
        pluginsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pythia", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
        legacyPluginsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.douxy.pot", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: legacyPluginsDirectory, withIntermediateDirectories: true)
        migrateLegacyPluginConfigs()
        convertInstalledPotextPluginsIfNeeded()
        migratePluginSecretsToSecureStorage()
        restoreLegacyFalsePositiveSecrets()
    }

    // MARK: - Plugin configuration storage

    private var pluginConfigsURL: URL {
        pluginsDirectory.appendingPathComponent("plugin-configs.json")
    }

    private var pluginAliasesURL: URL {
        pluginsDirectory.appendingPathComponent("plugin-aliases.json")
    }

    private var legacyBackupsDirectory: URL {
        pluginsDirectory.appendingPathComponent("Legacy Backups", isDirectory: true)
    }

    /// Returns the stored configuration dictionary for a legacy plugin identified
    /// by its directory name (e.g. "plugin.com.xiaomi.mimo").
    func pluginConfig(forPluginName name: String) -> [String: String] {
        var config = loadPluginConfigs()[name] ?? [:]
        for key in secretConfigurationKeys(forPluginName: name) {
            if let value = pluginSecretStore.read(pluginID: name, key: key) {
                config[key] = value
            }
        }
        return config
    }

    func setPluginConfig(_ config: [String: String], forPluginName name: String) throws {
        let secretKeys = secretConfigurationKeys(forPluginName: name)
        var publicConfig = config
        for key in secretKeys {
            publicConfig.removeValue(forKey: key)
            let value = config[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                pluginSecretStore.delete(pluginID: name, key: key)
            } else {
                try pluginSecretStore.write(config[key] ?? value, pluginID: name, key: key)
            }
        }
        var all = loadPluginConfigs()
        all[name] = publicConfig
        savePluginConfigs(all)
    }

    private func secretConfigurationKeys(forPluginName name: String) -> Set<String> {
        Set(pluginNeeds(forPluginName: name).compactMap { need in
            guard let key = need["key"] as? String else { return nil }
            if need["secret"] as? Bool == true { return key }
            let type = (need["type"] as? String)?.lowercased() ?? ""
            if type == "secret" { return key }
            return PythiaPluginSecretPolicy.isLikelySecretKey(key) ? key : nil
        })
    }

    private func migratePluginSecretsToSecureStorage() {
        var all = loadPluginConfigs()
        var changed = false
        for pluginID in Array(all.keys) {
            var config = all[pluginID] ?? [:]
            for key in secretConfigurationKeys(forPluginName: pluginID) {
                guard let value = config[key], !value.isEmpty else { continue }
                do {
                    try pluginSecretStore.write(value, pluginID: pluginID, key: key)
                    config.removeValue(forKey: key)
                    changed = true
                } catch {
                    NSLog("Pythia plugin secret migration failed for %@/%@: %@", pluginID, key, error.localizedDescription)
                }
            }
            all[pluginID] = config
        }
        if changed { savePluginConfigs(all) }
    }

    private func restoreLegacyFalsePositiveSecrets() {
        var all = loadPluginConfigs()
        var changed = false
        for pluginID in plugins().map(\.name) {
            let secureKeys = secretConfigurationKeys(forPluginName: pluginID)
            for need in pluginNeeds(forPluginName: pluginID) {
                guard let key = need["key"] as? String,
                      !secureKeys.contains(key),
                      key.range(of: "key|secret|token|password", options: [.regularExpression, .caseInsensitive]) != nil,
                      let value = pluginSecretStore.read(pluginID: pluginID, key: key),
                      !value.isEmpty
                else { continue }
                all[pluginID, default: [:]][key] = value
                pluginSecretStore.delete(pluginID: pluginID, key: key)
                changed = true
            }
        }
        if changed { savePluginConfigs(all) }
    }

    private func loadPluginConfigs() -> [String: [String: String]] {
        guard let data = try? Data(contentsOf: pluginConfigsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        var configs: [String: [String: String]] = [:]
        for (name, value) in object {
            if let keys = value as? [String] {
                configs[name] = Dictionary(uniqueConfigKeys(keys).map { ($0, "") }, uniquingKeysWith: { a, _ in a })
            } else if let keys = value as? [Any] {
                configs[name] = Dictionary(uniqueConfigKeys(keys.compactMap { $0 as? String }).map { ($0, "") }, uniquingKeysWith: { a, _ in a })
            } else if let config = value as? [String: Any] {
                var normalized: [String: String] = [:]
                for (key, rawValue) in config {
                    let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedKey.isEmpty else { continue }
                    if let string = rawValue as? String, !string.isEmpty {
                        normalized[trimmedKey] = string
                    } else if let number = rawValue as? NSNumber {
                        normalized[trimmedKey] = number.stringValue
                    }
                }
                if !normalized.isEmpty {
                    configs[name] = normalized
                }
            }
        }
        return configs
    }

    private func savePluginConfigs(_ configs: [String: [String: String]]) {
        let normalized = configs.reduce(into: [String: [String: String]]()) { result, pair in
            let values = pair.value.reduce(into: [String: String]()) { partial, entry in
                let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return }
                partial[key] = entry.value
            }
            if !values.isEmpty {
                result[pair.key] = values
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: pluginConfigsURL, options: [.atomic])
    }

    private func uniqueConfigKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.compactMap { raw in
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return key
        }
    }

    private func loadPluginAliases() -> [String: String] {
        guard let data = try? Data(contentsOf: pluginAliasesURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return [:]
        }
        return object
    }

    private func savePluginAliases(_ aliases: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: aliases, options: [.prettyPrinted]) else { return }
        try? data.write(to: pluginAliasesURL, options: [.atomic])
    }

    func renamePluginDisplay(name: String, displayName: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedDisplay.isEmpty else { return }
        var aliases = loadPluginAliases()
        aliases[trimmedName] = trimmedDisplay
        savePluginAliases(aliases)
    }

    /// Reads config items declared in a legacy plugin's info.json (`needs`).
    func pluginNeeds(forPluginName name: String) -> [[String: Any]] {
        if let manifest = pythiaManifest(forPluginID: name) {
            return manifest.configuration.map { field in
                var need: [String: Any] = [
                    "key": field.key,
                    "display": field.label,
                    "type": field.type == "secret" ? "input" : field.type,
                ]
                if let defaultValue = field.defaultValue { need["default"] = defaultValue }
                if let options = field.options { need["options"] = options }
                if field.type == "secret" { need["secret"] = true }
                return need
            }
        }
        guard let directory = legacyPluginDirectory(named: name) else { return [] }
        guard let infoData = try? Data(contentsOf: directory.appendingPathComponent("info.json")),
              let info = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
              let needs = info["needs"] as? [[String: Any]]
        else {
            return []
        }
        return needs
    }

    func legacyPluginDirectory(named name: String) -> URL? {
        let nativeDirectory = pluginsDirectory.appendingPathComponent("\(name).pythia", isDirectory: true)
        if FileManager.default.fileExists(atPath: nativeDirectory.appendingPathComponent("manifest.json").path) {
            return nativeDirectory
        }
        for type in ["translate", "recognize", "tts", "collection"] {
            let directory = legacyPluginsDirectory.appendingPathComponent(type).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("info.json").path) {
                return directory
            }
        }
        return nil
    }

    /// Imports plugin configs from the original Pot config.json. Original Pot
    /// stores them keyed by instance id "plugin.xxx@yyy"; we collapse them onto
    /// the plugin directory name. Only run once.
    private func migrateLegacyPluginConfigs() {
        let marker = pluginsDirectory.appendingPathComponent(".configs-migrated")
        if FileManager.default.fileExists(atPath: marker.path) { return }
        defer { try? "".write(to: marker, atomically: true, encoding: .utf8) }

        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.pot-app.desktop/config.json"),
        ]
        var collected: [String: [String: String]] = [:]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            for (key, value) in object {
                // Match "plugin.<name>@<instance>"
                guard key.hasPrefix("plugin."), key.contains("@"),
                      let dict = value as? [String: Any]
                else { continue }
                let pluginName = String(key.split(separator: "@").first ?? "")
                guard !pluginName.isEmpty else { continue }
                // Flatten values to strings; skip empty entries.
                var flat: [String: String] = [:]
                for (k, v) in dict {
                    let s: String
                    if let b = v as? Bool { s = b ? "true" : "false" }
                    else if let n = v as? NSNumber { s = n.stringValue }
                    else if let str = v as? String { s = str }
                    else { continue }
                    if !s.isEmpty { flat[k] = s }
                }
                // Prefer the instance that actually has values.
                if flat.count > (collected[pluginName]?.count ?? 0) {
                    collected[pluginName] = flat
                }
            }
        }
        if !collected.isEmpty {
            var existing = loadPluginConfigs()
            for (name, cfg) in collected where existing[name] == nil {
                existing[name] = cfg
            }
            savePluginConfigs(existing)
        }
    }

    func plugins() -> [CommandPlugin] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil) else {
            return legacyPlugins()
        }
        let aliases = loadPluginAliases()
        let commandPlugins: [CommandPlugin] = files
            .filter { $0.pathExtension == "json" || $0.pathExtension == "potplugin" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                guard let plugin = try? JSONDecoder().decode(CommandPlugin.self, from: data) else { return nil }
                return CommandPlugin(
                    name: plugin.name,
                    command: plugin.command,
                    arguments: plugin.arguments,
                    environment: plugin.environment,
                    legacyDirectory: plugin.legacyDirectory,
                    legacyType: plugin.legacyType,
                    displayName: aliases[plugin.name] ?? plugin.displayName,
                    packageFormat: plugin.packageFormat,
                    packageVersion: plugin.packageVersion,
                    packageAuthor: plugin.packageAuthor,
                    entry: plugin.entry
                )
            }
        let nativePlugins = pythiaPlugins(aliases: aliases)
        let nativeIDs = Set(nativePlugins.map(\.name))
        let compatiblePlugins = legacyPlugins().filter { !nativeIDs.contains($0.name) }
        let compatibleCommands = commandPlugins.filter { !nativeIDs.contains($0.name) }
        return (nativePlugins + compatibleCommands + compatiblePlugins)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func pythiaPlugins(aliases: [String: String]) -> [CommandPlugin] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap { directory in
            guard directory.pathExtension.lowercased() == PluginPackageFormat.pythia.rawValue,
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let manifest = try? loadPythiaManifest(at: directory),
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifest.entry).path)
            else { return nil }
            return CommandPlugin(
                name: manifest.id,
                command: "",
                legacyDirectory: directory.path,
                legacyType: "translate",
                displayName: aliases[manifest.id] ?? manifest.name,
                packageFormat: PluginPackageFormat.pythia.rawValue,
                packageVersion: manifest.version,
                packageAuthor: manifest.author,
                entry: manifest.entry
            )
        }
    }

    private func pythiaManifest(forPluginID id: String) -> PythiaPluginManifest? {
        let directory = pluginsDirectory.appendingPathComponent("\(id).pythia", isDirectory: true)
        return try? loadPythiaManifest(at: directory)
    }

    func pluginDetails(forPluginName name: String) -> String {
        guard let plugin = plugins().first(where: { $0.name == name }) else { return "" }
        var details = ["格式：.\(plugin.packageFormat ?? "potext")"]
        if let version = plugin.packageVersion, !version.isEmpty {
            details.append("版本：\(version)")
        }
        if let author = plugin.packageAuthor, !author.isEmpty {
            details.append("作者：\(author)")
        }
        if let manifest = pythiaManifest(forPluginID: name) {
            let permissions = manifest.permissions.isEmpty ? "无" : manifest.permissions.joined(separator: "、")
            details.append("权限：\(permissions)")
        }

        let directory = pluginsDirectory.appendingPathComponent("\(name).pythia", isDirectory: true)
        let reportURL = directory.appendingPathComponent("conversion.json")
        if let data = try? Data(contentsOf: reportURL),
           let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let status = (report["status"] as? String) ?? "converted"
            details.append("转换：\(status)")
            if let warnings = report["warnings"] as? [String], !warnings.isEmpty {
                details.append("警告：\(warnings.joined(separator: "；"))")
            }
        } else if plugin.packageFormat == PluginPackageFormat.pythia.rawValue {
            details.append("转换：原生 .pythia")
        } else {
            details.append("转换：兼容模式")
        }
        return details.joined(separator: "  ·  ")
    }

    private func loadPythiaManifest(at directory: URL) throws -> PythiaPluginManifest {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        return try PluginPackagePolicy.decodeAndValidateManifest(data, platform: "macos")
    }

    func translatePlugins() -> [CommandPlugin] {
        plugins().filter { plugin in
            if let type = plugin.legacyType {
                return type == "translate"
            }
            return true
        }
    }

    func plugins(type: String) -> [CommandPlugin] {
        plugins().filter { $0.legacyType == type }
    }

    func serviceOptions(for type: String) -> [(id: String, title: String)] {
        let builtIns: [(id: String, title: String)]
        switch type {
        case "translate":
            builtIns = PythiaProvider.allCases
                .filter { $0 != .plugin }
                .map { (id: $0.rawValue, title: $0.rawValue) }
        case "recognize":
            builtIns = [(id: "System OCR", title: "系统 OCR")]
        case "tts":
            builtIns = [(id: "macOS Speech", title: "macOS Speech")]
        case "collection":
            builtIns = []
        default:
            builtIns = []
        }
        let pluginSource = type == "translate" ? translatePlugins() : plugins(type: type)
        var seen = Set<String>()
        return (builtIns + pluginSource.map { (id: $0.serviceIdentifier, title: $0.title) }).filter { option in
            if seen.contains(option.id) { return false }
            seen.insert(option.id)
            return true
        }
    }

    func translationServiceOptions() -> [(id: String, title: String)] {
        serviceOptions(for: "translate")
    }

    func translationServiceOptions(orderedBy savedOrder: [String]) -> [(id: String, title: String)] {
        let all = translationServiceOptions()
        let optionMap = Dictionary(all.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var ordered: [(id: String, title: String)] = []
        for raw in savedOrder {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            ordered.append((id: id, title: optionMap[id] ?? id))
        }
        for option in all where !seen.contains(option.id) {
            seen.insert(option.id)
            ordered.append(option)
        }
        return ordered
    }

    func displayName(forServiceIdentifier identifier: String) -> String {
        let trimmed = TranslationService.canonicalServiceIdentifier(identifier)
        if let provider = PythiaProvider.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }), provider != .plugin {
            return provider.rawValue
        }
        if let plugin = plugin(forServiceIdentifier: trimmed) {
            return plugin.title
        }
        if trimmed == PythiaProvider.plugin.rawValue {
            return selectedPlugin()?.title ?? "Plugin"
        }
        return trimmed
    }

    func plugin(forServiceIdentifier identifier: String) -> CommandPlugin? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.lowercased().hasPrefix("plugin:") ? String(trimmed.dropFirst("plugin:".count)) : trimmed
        return plugins().first { plugin in
            plugin.name == name || plugin.title == name || plugin.serviceIdentifier == trimmed
        }
    }

    func legacyPlugins(type: String? = nil) -> [CommandPlugin] {
        let types = type.map { [$0] } ?? ["translate", "recognize", "tts", "collection"]
        let aliases = loadPluginAliases()
        return types.flatMap { pluginType -> [CommandPlugin] in
            let directory = legacyPluginsDirectory.appendingPathComponent(pluginType, isDirectory: true)
            guard let pluginDirs = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
                return []
            }
            return pluginDirs.compactMap { pluginDirectory in
                guard
                    (try? pluginDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                    let info = legacyInfo(in: pluginDirectory),
                    FileManager.default.fileExists(atPath: pluginDirectory.appendingPathComponent("main.js").path)
                else { return nil }
                let pluginName = pluginDirectory.lastPathComponent
                let display = PluginPackagePolicy.displayName(
                    alias: aliases[pluginName],
                    declaredDisplay: info["display"] as? String,
                    declaredName: info["name"] as? String,
                    fallback: pluginName
                )
                return CommandPlugin(
                    name: pluginName,
                    command: "",
                    legacyDirectory: pluginDirectory.path,
                    legacyType: pluginType,
                    displayName: display,
                    packageFormat: PluginPackageFormat.potext.rawValue
                )
            }
        }
    }

    private func legacyInfo(in directory: URL) -> [String: Any]? {
        let infoURL = directory.appendingPathComponent("info.json")
        guard
            let data = try? Data(contentsOf: infoURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    func selectedPlugin() -> CommandPlugin? {
        let preferred = Preferences.shared.pluginName
        let all = plugins()
        if !preferred.isEmpty, let plugin = all.first(where: { $0.name == preferred || $0.title == preferred }) {
            return plugin
        }
        return all.first
    }

    /// Deletes an installed plugin and removes every service-list reference to it.
    func deletePlugin(name: String) throws {
        let secretKeys = secretConfigurationKeys(forPluginName: name)
        var removedFile = false
        for type in ["translate", "recognize", "tts", "collection"] {
            let dir = legacyPluginsDirectory.appendingPathComponent(type).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
                removedFile = true
            }
        }
        let nativeDirectory = pluginsDirectory.appendingPathComponent("\(name).pythia", isDirectory: true)
        if FileManager.default.fileExists(atPath: nativeDirectory.path) {
            try FileManager.default.removeItem(at: nativeDirectory)
            removedFile = true
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil) {
            for file in files where ["json", "potplugin"].contains(file.pathExtension.lowercased()) {
                guard
                    let data = try? Data(contentsOf: file),
                    let plugin = try? JSONDecoder().decode(CommandPlugin.self, from: data),
                    plugin.name == name
                else { continue }
                try FileManager.default.removeItem(at: file)
                removedFile = true
            }
        }
        guard removedFile else {
            throw TranslationError.requestFailed("找不到要删除的插件文件。")
        }
        var configs = loadPluginConfigs()
        configs.removeValue(forKey: name)
        savePluginConfigs(configs)
        for key in secretKeys {
            pluginSecretStore.delete(pluginID: name, key: key)
        }
        var aliases = loadPluginAliases()
        aliases.removeValue(forKey: name)
        savePluginAliases(aliases)

        let serviceID = "plugin:\(name)"
        let preferences = Preferences.shared
        preferences.translateServiceList.removeAll { $0 == serviceID }
        preferences.translateServiceOrder.removeAll { $0 == serviceID }
        preferences.recognizeServiceList.removeAll { $0 == serviceID }
        preferences.ttsServiceList.removeAll { $0 == serviceID }
        preferences.collectionServiceList.removeAll { $0 == serviceID }
    }

    func installPlugin(from url: URL) throws -> String {
        guard let format = PluginPackagePolicy.format(fileName: url.lastPathComponent) else {
            throw TranslationError.requestFailed("请选择 .pythia 或 .potext 插件。")
        }
        switch format {
        case .pythia:
            return try installPythia(from: url)
        case .potext:
            return try installPotext(from: url)
        }
    }

    func installPythia(from url: URL) throws -> String {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("pythia-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw TranslationError.requestFailed("找不到所选插件。")
        }
        if isDirectory.boolValue {
            let copied = temp.appendingPathComponent(url.lastPathComponent, isDirectory: true)
            try FileManager.default.copyItem(at: url, to: copied)
        } else {
            try extractPluginArchive(url, to: temp)
        }

        let packageRoot = try locatePackageRoot(in: temp, manifestName: "manifest.json")
        let manifest = try loadPythiaManifest(at: packageRoot)
        let entryURL = packageRoot.appendingPathComponent(manifest.entry).standardizedFileURL
        guard entryURL.path.hasPrefix(packageRoot.standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: entryURL.path)
        else {
            throw TranslationError.requestFailed("插件入口不存在：\(manifest.entry)。")
        }

        let target = pluginsDirectory.appendingPathComponent("\(manifest.id).pythia", isDirectory: true)
        let staging = pluginsDirectory.appendingPathComponent(".install-\(UUID().uuidString).pythia", isDirectory: true)
        try FileManager.default.copyItem(at: packageRoot, to: staging)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: target)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        registerLegacyPluginInstance(name: manifest.id, type: "translate")
        return "已安装 \(manifest.name)（.pythia \(manifest.version)）。可在翻译服务中启用。"
    }

    func installPotext(from url: URL) throws -> String {
        guard PluginPackagePolicy.format(fileName: url.lastPathComponent) == .potext else {
            throw TranslationError.requestFailed("请选择 .potext 兼容插件文件。")
        }
        let pluginName = url.deletingPathExtension().lastPathComponent
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("potext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try extractPluginArchive(url, to: temp)
        let packageRoot = try locatePackageRoot(in: temp, manifestName: "info.json")
        let infoURL = packageRoot.appendingPathComponent("info.json")
        let mainURL = packageRoot.appendingPathComponent("main.js")
        guard FileManager.default.fileExists(atPath: infoURL.path) else {
            throw TranslationError.requestFailed("插件缺少 info.json。")
        }
        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            throw TranslationError.requestFailed("插件缺少 main.js。")
        }
        guard
            let data = try? Data(contentsOf: infoURL),
            let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = info["plugin_type"] as? String
        else {
            throw TranslationError.requestFailed("info.json 缺少 plugin_type。")
        }
        let targetParent = legacyPluginsDirectory.appendingPathComponent(type, isDirectory: true)
        let target = targetParent.appendingPathComponent(pluginName, isDirectory: true)
        try FileManager.default.createDirectory(at: targetParent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: packageRoot, to: target)
        registerLegacyPluginInstance(name: pluginName, type: type)
        let display = (info["display"] as? String) ?? pluginName
        do {
            let converted = try convertLegacyPluginDirectory(target, replaceExisting: true)
            return "已安装并转换 \(display)：\(converted.lastPathComponent)。原 .potext 已保留为备份，默认使用 .pythia 版本。"
        } catch {
            let fallbackMessage = "自动转换失败，已保留并启用 .potext 兼容版本。原因：\(error.localizedDescription)"
            if type == "translate" {
                return "已安装 \(display)（translate）。\(fallbackMessage)"
            }
            return "已安装 \(display)（\(type)）。\(fallbackMessage)"
        }
    }

    @discardableResult
    func convertAllInstalledPotextPlugins(replaceExisting: Bool = false) -> [String] {
        var messages: [String] = []
        for type in ["translate", "recognize", "tts", "collection"] {
            let parent = legacyPluginsDirectory.appendingPathComponent(type, isDirectory: true)
            guard let directories = try? FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for directory in directories where (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                do {
                    let target = try convertLegacyPluginDirectory(directory, replaceExisting: replaceExisting)
                    messages.append("\(directory.lastPathComponent)：已转换为 \(target.lastPathComponent)")
                } catch {
                    messages.append("\(directory.lastPathComponent)：转换失败，继续使用 .potext 兼容层（\(error.localizedDescription)）")
                }
            }
        }
        return messages
    }

    @discardableResult
    func convertLegacyPlugin(name: String, replaceExisting: Bool = true) throws -> URL {
        let directory = ["translate", "recognize", "tts", "collection"]
            .map { legacyPluginsDirectory.appendingPathComponent($0, isDirectory: true).appendingPathComponent(name, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("info.json").path) }
        guard let directory else {
            throw TranslationError.requestFailed("找不到可转换的 .potext 插件：\(name)。")
        }
        return try convertLegacyPluginDirectory(directory, replaceExisting: replaceExisting)
    }

    private func convertInstalledPotextPluginsIfNeeded() {
        let marker = pluginsDirectory.appendingPathComponent(".potext-conversion-v1")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let messages = convertAllInstalledPotextPlugins(replaceExisting: false)
        let report = messages.joined(separator: "\n")
        try? report.write(to: marker, atomically: true, encoding: .utf8)
    }

    private func convertLegacyPluginDirectory(_ source: URL, replaceExisting: Bool) throws -> URL {
        let infoURL = source.appendingPathComponent("info.json")
        let mainURL = source.appendingPathComponent("main.js")
        let infoData = try Data(contentsOf: infoURL)
        let legacyMain = try String(contentsOf: mainURL, encoding: .utf8)
        let conversion = try PotextPluginConverter.convert(
            infoData: infoData,
            mainJavaScript: legacyMain,
            fallbackIdentifier: source.lastPathComponent
        )
        let target = pluginsDirectory.appendingPathComponent("\(conversion.manifest.id).pythia", isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path), !replaceExisting {
            return target
        }

        try FileManager.default.createDirectory(at: legacyBackupsDirectory, withIntermediateDirectories: true)
        let backup = legacyBackupsDirectory.appendingPathComponent("\(source.lastPathComponent).potext")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try createPotextBackup(from: source, at: backup)
        }

        let staging = pluginsDirectory.appendingPathComponent(".convert-\(UUID().uuidString).pythia", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: staging)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let manifestData = try encoder.encode(conversion.manifest)
            try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: [.atomic])
            try legacyMain.write(to: staging.appendingPathComponent("legacy-main.js"), atomically: true, encoding: .utf8)
            try conversion.mainJavaScript.write(to: staging.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
            let report: [String: Any] = [
                "schemaVersion": 1,
                "sourceFormat": "potext",
                "sourcePlugin": source.lastPathComponent,
                "convertedAt": ISO8601DateFormatter().string(from: Date()),
                "status": "converted",
                "warnings": conversion.warnings,
                "originalBackup": backup.lastPathComponent,
            ]
            let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try reportData.write(to: staging.appendingPathComponent("conversion.json"), options: [.atomic])

            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: target)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        registerLegacyPluginInstance(name: conversion.manifest.id, type: "translate")
        return target
    }

    private func createPotextBackup(from directory: URL, at target: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", directory.path, target.path]
        let errorOutput = Pipe()
        process.standardError = errorOutput
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TranslationError.requestFailed(message.isEmpty ? "无法创建原始 .potext 备份。" : message)
        }
    }

    private func extractPluginArchive(_ archive: URL, to destination: URL) throws {
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listProcess.arguments = ["-Z1", archive.path]
        let listOutput = Pipe()
        let listError = Pipe()
        listProcess.standardOutput = listOutput
        listProcess.standardError = listError
        try listProcess.run()
        listProcess.waitUntilExit()
        let listData = listOutput.fileHandleForReading.readDataToEndOfFile()
        guard listProcess.terminationStatus == 0,
              let listing = String(data: listData, encoding: .utf8)
        else {
            let message = String(data: listError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TranslationError.requestFailed(message.isEmpty ? "无法读取插件压缩包。" : message)
        }
        let unsafePath = listing.split(whereSeparator: \.isNewline).first { rawPath in
            let path = String(rawPath).replacingOccurrences(of: "\\", with: "/")
            return path.hasPrefix("/") || path.split(separator: "/").contains("..")
        }
        guard unsafePath == nil else {
            throw TranslationError.requestFailed("插件压缩包包含不安全路径：\(unsafePath!)。")
        }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", archive.path, "-d", destination.path]
        let errorOutput = Pipe()
        unzip.standardError = errorOutput
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            let message = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TranslationError.requestFailed(message.isEmpty ? "无法解压插件。" : message)
        }
    }

    private func locatePackageRoot(in directory: URL, manifestName: String) throws -> URL {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifestName).path) {
            return directory
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw TranslationError.requestFailed("插件包内容无效。")
        }
        let candidates = children.filter { child in
            (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && FileManager.default.fileExists(atPath: child.appendingPathComponent(manifestName).path)
        }
        guard candidates.count == 1, let root = candidates.first else {
            throw TranslationError.requestFailed("插件包必须在根目录或唯一顶层目录中包含 \(manifestName)。")
        }
        return root
    }

    func importLegacyPluginsFromOldPot() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Application Support/com.pot-app.desktop/plugins", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/pot/plugins", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Pot/plugins", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/com.douxy.pot/plugins", isDirectory: true),
        ]
        let types = ["translate", "recognize", "tts", "collection"]
        var imported = 0
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            for type in types {
                let sourceParent = root.appendingPathComponent(type, isDirectory: true)
                guard let pluginDirs = try? FileManager.default.contentsOfDirectory(at: sourceParent, includingPropertiesForKeys: [.isDirectoryKey]) else {
                    continue
                }
                let targetParent = legacyPluginsDirectory.appendingPathComponent(type, isDirectory: true)
                try? FileManager.default.createDirectory(at: targetParent, withIntermediateDirectories: true)
                for pluginDir in pluginDirs {
                    guard
                        (try? pluginDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                        FileManager.default.fileExists(atPath: pluginDir.appendingPathComponent("info.json").path),
                        FileManager.default.fileExists(atPath: pluginDir.appendingPathComponent("main.js").path)
                    else { continue }
                    let target = targetParent.appendingPathComponent(pluginDir.lastPathComponent, isDirectory: true)
                    if pluginDir.standardizedFileURL == target.standardizedFileURL {
                        registerLegacyPluginInstance(name: pluginDir.lastPathComponent, type: type)
                        imported += 1
                        continue
                    }
                    do {
                        if FileManager.default.fileExists(atPath: target.path) {
                            try FileManager.default.removeItem(at: target)
                        }
                        try FileManager.default.copyItem(at: pluginDir, to: target)
                        registerLegacyPluginInstance(name: pluginDir.lastPathComponent, type: type)
                        imported += 1
                    } catch {
                        NSLog("Pythia legacy plugin import failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        return imported == 0 ? "没有找到可导入的旧版插件。" : "已导入 \(imported) 个旧版插件。"
    }

    private func registerLegacyPluginInstance(name: String, type: String) {
        let preferences = Preferences.shared
        let instance = "plugin:\(name)"
        switch type {
        case "translate":
            var list = preferences.translateServiceList
            if !list.contains(instance) { list.insert(instance, at: 0) }
            preferences.translateServiceList = list
            var order = preferences.translateServiceOrder.filter { $0 != instance }
            order.insert(instance, at: 0)
            preferences.translateServiceOrder = order
        case "recognize":
            var list = preferences.recognizeServiceList
            if !list.contains(instance) { list.append(instance) }
            preferences.recognizeServiceList = list
        case "tts":
            var list = preferences.ttsServiceList
            if !list.contains(instance) { list.append(instance) }
            preferences.ttsServiceList = list
        case "collection":
            var list = preferences.collectionServiceList
            if !list.contains(instance) { list.append(instance) }
            preferences.collectionServiceList = list
        default:
            break
        }
    }

    func translate(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        translate(
            text: text,
            sourceLanguage: Preferences.shared.sourceLanguage,
            targetLanguage: Preferences.shared.targetLanguage,
            completion: completion
        )
    }

    func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let plugin = selectedPlugin() else {
            completion(.failure(TranslationError.requestFailed("没有可用插件。请在设置里安装或选择插件。")))
            return
        }
        translate(plugin: plugin, text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, completion: completion)
    }

    func translate(serviceIdentifier: String, text: String, completion: @escaping (Result<String, Error>) -> Void) {
        translate(
            serviceIdentifier: serviceIdentifier,
            text: text,
            sourceLanguage: Preferences.shared.sourceLanguage,
            targetLanguage: Preferences.shared.targetLanguage,
            completion: completion
        )
    }

    func translate(
        serviceIdentifier: String,
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let plugin = plugin(forServiceIdentifier: serviceIdentifier) else {
            completion(.failure(TranslationError.requestFailed("找不到插件服务：\(serviceIdentifier)。")))
            return
        }
        translate(plugin: plugin, text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, completion: completion)
    }

    func runLegacyService(
        serviceIdentifier: String,
        expectedType: String,
        input: String,
        sourceLanguage: String,
        targetLanguage: String,
        targetPayload: Any? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let plugin = plugin(forServiceIdentifier: serviceIdentifier) else {
            completion(.failure(TranslationError.requestFailed("找不到插件服务：\(serviceIdentifier)。")))
            return
        }
        guard plugin.legacyType == expectedType else {
            completion(.failure(TranslationError.requestFailed("插件类型不匹配：需要 \(expectedType)，实际是 \(plugin.legacyType ?? "command")。")))
            return
        }
        runLegacyPlugin(plugin, input: input, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, targetPayload: targetPayload, completion: completion)
    }

    private func translate(
        plugin: CommandPlugin,
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if plugin.packageFormat == PluginPackageFormat.pythia.rawValue {
            runPythiaPlugin(
                plugin,
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                completion: completion
            )
            return
        }
        if plugin.legacyDirectory != nil {
            translateWithLegacyPlugin(plugin, text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, completion: completion)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: plugin.command)
            process.arguments = (plugin.arguments ?? []).map {
                $0.replacingOccurrences(of: "{text}", with: text)
                    .replacingOccurrences(of: "{source}", with: sourceLanguage)
                    .replacingOccurrences(of: "{target}", with: targetLanguage)
            }
            var environment = ProcessInfo.processInfo.environment
            plugin.environment?.forEach {
                environment[$0.key] = $0.value.replacingOccurrences(of: "{text}", with: text)
                    .replacingOccurrences(of: "{source}", with: sourceLanguage)
                    .replacingOccurrences(of: "{target}", with: targetLanguage)
            }
            environment["POT_TEXT"] = text
            environment["POT_SOURCE_LANGUAGE"] = sourceLanguage
            environment["POT_TARGET_LANGUAGE"] = targetLanguage
            process.environment = environment

            let input = Pipe()
            let output = Pipe()
            let errorOutput = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errorOutput
            do {
                try process.run()
                input.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
                input.fileHandleForWriting.closeFile()
                process.waitUntilExit()
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    completion(.success(stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    completion(.failure(TranslationError.requestFailed(stderr.isEmpty ? "插件执行失败。" : stderr)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func runPythiaPlugin(
        _ plugin: CommandPlugin,
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let directory = plugin.legacyDirectory, let entry = plugin.entry else {
            completion(.failure(TranslationError.requestFailed(".pythia 插件缺少目录或入口信息。")))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let runner = Bundle.main.url(forResource: "pythia-plugin-runner", withExtension: "cjs") else {
                    throw TranslationError.requestFailed("Pythia 插件运行时资源缺失。")
                }
                let bundledRuntime = Bundle.main.resourceURL?
                    .appendingPathComponent("runtime", isDirectory: true)
                    .appendingPathComponent("node")
                guard let nodeRuntime = NodeRuntimeResolver.resolve(
                    preferredCandidates: bundledRuntime.map { [$0] } ?? []
                ) else {
                    throw TranslationError.requestFailed("未找到 Node.js 运行环境，无法执行 .pythia JavaScript 插件。")
                }
                let requestID = UUID().uuidString
                let request: [String: Any] = [
                    "schemaVersion": "1.0",
                    "requestId": requestID,
                    "type": "translate",
                    "input": [
                        "text": text,
                        "sourceLanguage": sourceLanguage,
                        "targetLanguage": targetLanguage,
                        "detectedLanguage": sourceLanguage,
                    ],
                    "context": [
                        "platform": "macos",
                        "pythiaVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
                    ],
                ]
                let requestData = try JSONSerialization.data(withJSONObject: request)
                guard let requestJSON = String(data: requestData, encoding: .utf8) else {
                    throw TranslationError.requestFailed("无法编码插件请求。")
                }
                var config = self.pluginConfig(forPluginName: plugin.name)
                if config["enable"] == nil { config["enable"] = "true" }
                let configData = try JSONSerialization.data(withJSONObject: config)
                guard let configJSON = String(data: configData, encoding: .utf8) else {
                    throw TranslationError.requestFailed("无法编码插件配置。")
                }

                let process = Process()
                process.executableURL = nodeRuntime
                process.arguments = [runner.path, directory, entry]
                var environment = ProcessInfo.processInfo.environment
                let nodeDirectory = nodeRuntime.deletingLastPathComponent().path
                let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                environment["PATH"] = "\(nodeDirectory):\(inheritedPath)"
                environment["PYTHIA_PLUGIN_REQUEST"] = requestJSON
                environment["PYTHIA_PLUGIN_CONFIG"] = configJSON
                let timeoutMilliseconds = Self.legacyPluginTimeoutMilliseconds(for: text)
                environment["PYTHIA_PLUGIN_TIMEOUT_MS"] = String(timeoutMilliseconds)
                process.environment = environment

                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("pythia-plugin-\(UUID().uuidString).out")
                let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("pythia-plugin-\(UUID().uuidString).err")
                FileManager.default.createFile(atPath: outputURL.path, contents: nil)
                FileManager.default.createFile(atPath: errorURL.path, contents: nil)
                defer {
                    try? FileManager.default.removeItem(at: outputURL)
                    try? FileManager.default.removeItem(at: errorURL)
                }
                let outputHandle = try FileHandle(forWritingTo: outputURL)
                let errorHandle = try FileHandle(forWritingTo: errorURL)
                process.standardOutput = outputHandle
                process.standardError = errorHandle
                try process.run()

                let stateLock = NSLock()
                var timedOut = false
                let timeoutTask = DispatchWorkItem {
                    stateLock.lock()
                    defer { stateLock.unlock() }
                    guard process.isRunning else { return }
                    timedOut = true
                    process.terminate()
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + .milliseconds(timeoutMilliseconds + 2_000),
                    execute: timeoutTask
                )
                process.waitUntilExit()
                timeoutTask.cancel()
                try outputHandle.close()
                try errorHandle.close()
                stateLock.lock()
                let didTimeOut = timedOut
                stateLock.unlock()
                if didTimeOut {
                    throw TranslationError.requestFailed("插件执行超时，已终止该插件进程。")
                }

                let outputData = try Data(contentsOf: outputURL)
                let errorData = try Data(contentsOf: errorURL)
                guard outputData.count <= 8 * 1024 * 1024 else {
                    throw TranslationError.requestFailed("插件响应超过 8 MiB 限制。")
                }
                let stderr = String(data: errorData, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    let message = Self.redactedPluginMessage(stderr.isEmpty ? "插件执行失败。" : stderr, config: config)
                    throw TranslationError.requestFailed(message)
                }
                guard let response = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
                      response["requestId"] as? String == requestID,
                      let succeeded = response["success"] as? Bool
                else {
                    throw TranslationError.requestFailed("插件返回了无效或空的统一响应。")
                }
                if !succeeded {
                    let pluginError = response["error"] as? [String: Any]
                    let code = pluginError?["code"] as? String ?? "RUNTIME_ERROR"
                    let message = pluginError?["message"] as? String ?? "插件报告执行失败。"
                    throw TranslationError.requestFailed("\(code)：\(Self.redactedPluginMessage(message, config: config))")
                }
                guard let data = response["data"] as? [String: Any],
                      let translatedText = data["text"] as? String,
                      !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw TranslationError.requestFailed("插件成功响应缺少非空 data.text。")
                }
                completion(.success(translatedText))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func redactedPluginMessage(_ message: String, config: [String: String]) -> String {
        config.reduce(message) { result, pair in
            let isSecret = pair.key.range(of: "key|secret|token|password", options: [.regularExpression, .caseInsensitive]) != nil
            guard isSecret, pair.value.count >= 4 else { return result }
            return result.replacingOccurrences(of: pair.value, with: "[REDACTED]")
        }
    }

    private func translateWithLegacyPlugin(
        _ plugin: CommandPlugin,
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard plugin.legacyType == "translate", plugin.legacyDirectory != nil else {
            completion(.failure(TranslationError.requestFailed("当前原版插件不是翻译插件。")))
            return
        }
        runLegacyPlugin(plugin, input: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, completion: completion)
    }

    private func runLegacyPlugin(
        _ plugin: CommandPlugin,
        input: String,
        sourceLanguage: String,
        targetLanguage: String,
        targetPayload: Any? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let directory = plugin.legacyDirectory else {
            completion(.failure(TranslationError.requestFailed("当前插件不是原版 Pot 插件。")))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let runner = try self.ensureLegacyRunner()
                guard let nodeRuntime = NodeRuntimeResolver.resolve() else {
                    throw TranslationError.requestFailed(
                        "未找到 Node.js 运行环境。请安装 Node.js，或通过 Homebrew、NVM、Volta 提供可执行的 node。"
                    )
                }
                let process = Process()
                process.executableURL = nodeRuntime
                process.arguments = [
                    runner.path,
                    directory,
                    sourceLanguage,
                    targetLanguage,
                ]
                var environment = ProcessInfo.processInfo.environment
                let nodeDirectory = nodeRuntime.deletingLastPathComponent().path
                let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                environment["PATH"] = "\(nodeDirectory):\(inheritedPath)"
                environment["POT_TEXT"] = input
                environment["POT_TIMEOUT_MS"] = String(Self.legacyPluginTimeoutMilliseconds(for: input))
                if let targetPayload,
                   JSONSerialization.isValidJSONObject(targetPayload),
                   let data = try? JSONSerialization.data(withJSONObject: targetPayload),
                   let json = String(data: data, encoding: .utf8) {
                    environment["POT_TARGET"] = json
                } else if let targetString = targetPayload as? String {
                    environment["POT_TARGET"] = Self.jsonStringPayload(targetString)
                }
                // Pass the plugin's stored config (apiKey/model/...) so legacy
                // plugins can read credentials. Defaults to { enable: true }.
                let pluginName = (directory as NSString).lastPathComponent
                var config = PluginManager.shared.pluginConfig(forPluginName: pluginName)
                if config["enable"] == nil { config["enable"] = "true" }
                if let configData = try? JSONSerialization.data(withJSONObject: config),
                   let configJSON = String(data: configData, encoding: .utf8) {
                    environment["POT_PLUGIN_CONFIG"] = configJSON
                }
                process.environment = environment
                let output = Pipe()
                let errorOutput = Pipe()
                process.standardOutput = output
                process.standardError = errorOutput
                try process.run()
                process.waitUntilExit()
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    completion(.success(stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    completion(.failure(TranslationError.requestFailed(stderr.isEmpty ? "原版插件执行失败。" : stderr)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func jsonStringPayload(_ value: String) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "\"\""
    }

    private static func legacyPluginTimeoutMilliseconds(for input: String) -> Int {
        let seconds = min(1_200, max(180, 180 + Double(input.count) / 20.0))
        return Int(seconds * 1_000)
    }

    private func ensureLegacyRunner() throws -> URL {
        let support = pluginsDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let runner = support.appendingPathComponent("legacy-plugin-runner.cjs")
        let script = """
        const fs = require('fs');
        const path = require('path');
        const nodeHttp = require('http');
        const nodeHttps = require('https');
        const childProcess = require('child_process');
        const os = require('os');
        const pluginDir = process.argv[2];
        const from = process.argv[3] || 'auto';
        const to = process.argv[4] || 'zh-CN';
        const text = process.env.POT_TEXT || '';
        const hostTimeoutMs = Math.max(30000, Number(process.env.POT_TIMEOUT_MS || 600000) || 600000);
        const script = fs.readFileSync(path.join(pluginDir, 'main.js'), 'utf8');
        const info = JSON.parse(fs.readFileSync(path.join(pluginDir, 'info.json'), 'utf8'));
        global.ResponseType = { Text: 'Text', Json: 'Json', JSON: 'Json' };
        const Body = {
          json: (payload) => ({ type: 'Json', payload }),
          form: (payload) => ({ type: 'Form', payload }),
          text: (payload) => ({ type: 'Text', payload }),
        };
        global.Body = Body;
        // Original Pot plugins use the Tauri-style fetch API: they pass a body
        // shaped like { type: "Json"|"Text"|"Form", payload } and expect a
        // response shaped like { ok, status, data } where `data` is the parsed
        // JSON. Node's undici-backed global.fetch can occasionally fail before
        // the TLS handshake on macOS, so this shim normalizes Tauri options and
        // performs bounded retries through Node's http/https client.
        const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
        const headersObject = (headers = {}) => {
          if (headers && typeof headers.entries === 'function') {
            return Object.fromEntries(headers.entries());
          }
          if (Array.isArray(headers)) {
            return Object.fromEntries(headers);
          }
          return { ...headers };
        };
        const headerValue = (headers, name) => {
          const target = name.toLowerCase();
          const key = Object.keys(headers).find((candidate) => candidate.toLowerCase() === target);
          return key ? headers[key] : undefined;
        };
        const setHeaderIfMissing = (headers, name, value) => {
          if (headerValue(headers, name) === undefined) headers[name] = value;
        };
        const serializeBody = (options, headers) => {
          const body = options.body;
          if (body === undefined || body === null) return undefined;
          if (Buffer.isBuffer(body) || typeof body === 'string') return body;
          if (body && typeof body === 'object' && (body.type === 'Json' || body.type === 'Text' || body.type === 'Raw')) {
            if (body.type === 'Json') {
              setHeaderIfMissing(headers, 'Content-Type', 'application/json');
              return JSON.stringify(body.payload);
            }
            return String(body.payload ?? '');
          }
          if (body && typeof body === 'object' && body.type === 'Form') {
            setHeaderIfMissing(headers, 'Content-Type', 'application/x-www-form-urlencoded');
            return new URLSearchParams(body.payload || {}).toString();
          }
          setHeaderIfMissing(headers, 'Content-Type', 'application/json');
          return JSON.stringify(body);
        };
        const parseData = (rawText, responseType) => {
          if (responseType === 'Text' || responseType === 'text') return rawText;
          try { return rawText.length ? JSON.parse(rawText) : null; } catch (e) { return rawText; }
        };
        const requestOnce = (url, options) => new Promise((resolve, reject) => {
          const target = url instanceof URL ? url : new URL(String(url));
          const client = target.protocol === 'http:' ? nodeHttp : nodeHttps;
          const body = options.bodyBuffer;
          const headers = { ...options.headers };
          if (body !== undefined) {
            setHeaderIfMissing(headers, 'Content-Length', String(Buffer.byteLength(body)));
          }
          setHeaderIfMissing(headers, 'Connection', 'close');
          const req = client.request({
            protocol: target.protocol,
            hostname: target.hostname,
            port: target.port || undefined,
            path: `${target.pathname}${target.search}`,
            method: options.method || 'GET',
            headers,
            timeout: hostTimeoutMs,
          }, (res) => {
            const chunks = [];
            res.on('data', (chunk) => chunks.push(chunk));
            res.on('end', () => {
              const rawText = Buffer.concat(chunks).toString('utf8');
              resolve({
                ok: res.statusCode >= 200 && res.statusCode < 300,
                status: res.statusCode || 0,
                url: target.toString(),
                data: parseData(rawText, options.responseType),
                headers: res.headers || {},
              });
            });
          });
          req.on('timeout', () => req.destroy(new Error(`Plugin request timed out after ${Math.round(hostTimeoutMs / 1000)}s`)));
          req.on('error', reject);
          if (body !== undefined) req.write(body);
          req.end();
        });
        const curlQuote = (value) => `"${String(value).replace(/\\\\/g, '\\\\\\\\').replace(/"/g, '\\\\"').replace(/\\r?\\n/g, ' ')}"`;
        const requestWithCurl = (url, options) => {
          const target = url instanceof URL ? url : new URL(String(url));
          const timeoutSeconds = Math.max(30, Math.ceil(hostTimeoutMs / 1000));
          const configLines = [
            `url = ${curlQuote(target.toString())}`,
            `request = ${curlQuote(options.method || 'GET')}`,
            'silent',
            'show-error',
            'location',
            'http1.1',
            `connect-timeout = ${Math.min(30, timeoutSeconds)}`,
            `max-time = ${timeoutSeconds}`,
            `write-out = ${curlQuote('\\nPYTHIA_HTTP_STATUS:%{http_code}')}`,
          ];
          for (const [key, value] of Object.entries(options.headers || {})) {
            if (value === undefined || value === null) continue;
            configLines.push(`header = ${curlQuote(`${key}: ${value}`)}`);
          }
          const configPath = path.join(os.tmpdir(), `pythia-curl-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.conf`);
          fs.writeFileSync(configPath, `${configLines.join('\\n')}\\n`, { mode: 0o600 });
          try {
            const args = ['--config', configPath];
            if (options.bodyBuffer !== undefined) args.push('--data-binary', '@-');
            const result = childProcess.spawnSync('/usr/bin/curl', args, {
              input: options.bodyBuffer,
              encoding: 'utf8',
              timeout: hostTimeoutMs + 5000,
              maxBuffer: 64 * 1024 * 1024,
            });
            if (result.error) throw result.error;
            const stdout = result.stdout || '';
            const marker = '\\nPYTHIA_HTTP_STATUS:';
            const markerIndex = stdout.lastIndexOf(marker);
            const rawText = markerIndex >= 0 ? stdout.slice(0, markerIndex) : stdout;
            const status = markerIndex >= 0 ? Number(stdout.slice(markerIndex + marker.length).trim()) : 0;
            if (result.status !== 0 && status === 0) {
              throw new Error((result.stderr || `curl exited with status ${result.status}`).trim());
            }
            return {
              ok: status >= 200 && status < 300,
              status,
              url: target.toString(),
              data: parseData(rawText, options.responseType),
              headers: {},
            };
          } finally {
            try { fs.unlinkSync(configPath); } catch (e) {}
          }
        };
        const isRetryable = (error) => {
          const code = error && (error.code || (error.cause && error.cause.code));
          return ['ECONNRESET', 'ETIMEDOUT', 'EAI_AGAIN', 'ENOTFOUND', 'ECONNREFUSED', 'EPIPE'].includes(code)
            || /fetch failed|socket disconnected|network/i.test(String(error && error.message));
        };
        const tauriFetch = async (url, options = {}) => {
          const headers = headersObject(options.headers || {});
          const bodyBuffer = serializeBody(options, headers);
          const requestOptions = {
            method: options.method || 'GET',
            headers,
            bodyBuffer,
            responseType: options.responseType,
          };
          let lastError;
          for (let attempt = 0; attempt < 4; attempt += 1) {
            try {
              return await requestOnce(url, requestOptions);
            } catch (error) {
              lastError = error;
              if (!isRetryable(error) || attempt === 3) break;
              await sleep([250, 800, 1600][attempt]);
            }
          }
          try {
            return requestWithCurl(url, requestOptions);
          } catch (curlError) {
            lastError = curlError || lastError;
          }
          const target = typeof url === 'string' ? url : (url && url.url ? url.url : String(url));
          const detail = lastError && lastError.cause ? lastError.cause.message : (lastError && lastError.message ? lastError.message : String(lastError));
          throw new Error(`Plugin HTTP request failed: ${target}: ${detail}`);
        };
        const utils = {
          pluginDir,
          cacheDir: path.join(pluginDir, '.cache'),
          osType: 'Darwin',
          readTextFile: async (p) => fs.readFileSync(path.isAbsolute(p) ? p : path.join(pluginDir, p), 'utf8'),
          readBinaryFile: async (p) => fs.readFileSync(path.isAbsolute(p) ? p : path.join(pluginDir, p)),
          tauriFetch,
          http: { fetch: tauriFetch },
          run: async () => { throw new Error('此原版插件调用了 Tauri run_binary，本原生版暂未支持该私有接口。'); },
          Database: null,
          CryptoJS: null
        };
        (async () => {
          const fn = eval(`${script}\\n${info.plugin_type}`);
          const language = info.language || {};
          const mappedFrom = language[from] || from;
          const mappedTo = language[to] || to;
          // Config (apiKey/model/...) is passed from the host via env var.
          let config = { enable: 'true' };
          try {
            const raw = process.env.POT_PLUGIN_CONFIG;
            if (raw) config = Object.assign({ enable: 'true' }, JSON.parse(raw));
          } catch (e) {
            process.stderr.write('Failed to parse POT_PLUGIN_CONFIG: ' + String(e) + '\\n');
          }
          let directResult;
          const context = {
            config,
            detect: from,
            utils,
            setResult: (v) => { directResult = v; }
          };
          let result;
          switch (info.plugin_type) {
            case 'translate':
              result = await fn(text.trim(), mappedFrom, mappedTo, context);
              break;
            case 'recognize':
              result = await fn(text.trim(), mappedFrom, context);
              break;
            case 'tts':
              result = await fn(text.trim(), mappedTo, context);
              break;
            case 'collection': {
              let target = process.env.POT_TARGET || '';
              try { target = target ? JSON.parse(target) : ''; } catch (e) {}
              result = await fn(text.trim(), target, context);
              break;
            }
            default:
              throw new Error(`Unsupported plugin type: ${info.plugin_type}`);
          }
          const value = directResult !== undefined ? directResult : result;
          if (value === undefined || value === null) return;
          if (typeof value === 'string') process.stdout.write(value);
          else process.stdout.write(JSON.stringify(value));
        })().catch((error) => {
          process.stderr.write(error && error.stack ? error.stack : String(error));
          process.exit(1);
        });
        """
        try script.write(to: runner, atomically: true, encoding: .utf8)
        return runner
    }
}
