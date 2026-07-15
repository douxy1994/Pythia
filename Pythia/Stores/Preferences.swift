import Foundation

final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    private let credentialStore = SecureCredentialStore(service: "com.douxy.pythia.credentials")
    private var volatileCredentials: [String: String] = [:]
    private var credentialStorageError: String?
    private let credentialLock = NSLock()

    private init() {
        migrateLegacyCredentials()
    }

    private func localString(forKey key: String) -> String {
        defaults.string(forKey: key) ?? ""
    }

    private func setLocalString(_ value: String, forKey key: String) {
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }

    private static let secureCredentialKeys = [
        "openAIKey",
        "deepLKey",
        "baiduAppID",
        "baiduSecret",
        "youdaoAppKey",
        "youdaoSecret",
        "libreTranslateKey",
        "proxyPassword",
        "webdavPassword",
    ]

    private func secureString(forKey key: String) -> String {
        if let value = credentialStore.read(key: key) { return value }
        credentialLock.lock()
        let volatile = volatileCredentials[key]
        credentialLock.unlock()
        if let volatile { return volatile }
        guard let legacy = defaults.string(forKey: key), !legacy.isEmpty else { return "" }
        do {
            try credentialStore.write(legacy, key: key)
            defaults.removeObject(forKey: key)
        } catch {
            recordCredentialStorageError(error)
        }
        return legacy
    }

    private func setSecureString(_ value: String, forKey key: String) {
        if value.isEmpty {
            credentialStore.delete(key: key)
            defaults.removeObject(forKey: key)
            credentialLock.lock()
            volatileCredentials.removeValue(forKey: key)
            credentialLock.unlock()
            return
        }
        do {
            try credentialStore.write(value, key: key)
            defaults.removeObject(forKey: key)
            credentialLock.lock()
            volatileCredentials.removeValue(forKey: key)
            credentialLock.unlock()
        } catch {
            credentialLock.lock()
            volatileCredentials[key] = value
            credentialLock.unlock()
            recordCredentialStorageError(error)
        }
    }

    private func migrateLegacyCredentials() {
        for key in Self.secureCredentialKeys {
            guard let value = defaults.string(forKey: key), !value.isEmpty else { continue }
            do {
                try credentialStore.write(value, key: key)
                defaults.removeObject(forKey: key)
            } catch {
                recordCredentialStorageError(error)
            }
        }
    }

    private func recordCredentialStorageError(_ error: Error) {
        credentialLock.lock()
        credentialStorageError = error.localizedDescription
        credentialLock.unlock()
        NSLog("Pythia secure credential storage failed: %@", error.localizedDescription)
    }

    func consumeCredentialStorageError() -> String? {
        credentialLock.lock()
        defer { credentialLock.unlock() }
        let error = credentialStorageError
        credentialStorageError = nil
        return error
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { return nil }
            seen.insert(value)
            return value
        }
    }

    private func enumString(forKey key: String, defaultValue: String, validValues: Set<String>, legacyValues: [String: String] = [:]) -> String {
        let raw = defaults.string(forKey: key) ?? defaultValue
        let normalized: String
        if validValues.contains(raw) {
            normalized = raw
        } else if let legacy = legacyValues[raw], validValues.contains(legacy) {
            normalized = legacy
        } else {
            normalized = defaultValue
        }
        if normalized != raw {
            defaults.set(normalized, forKey: key)
        }
        return normalized
    }

    private func setEnumString(_ value: String, forKey key: String, defaultValue: String, validValues: Set<String>, legacyValues: [String: String] = [:]) {
        let normalized: String
        if validValues.contains(value) {
            normalized = value
        } else if let legacy = legacyValues[value], validValues.contains(legacy) {
            normalized = legacy
        } else {
            normalized = defaultValue
        }
        defaults.set(normalized, forKey: key)
    }

    var provider: PythiaProvider {
        get { PythiaProvider(rawValue: defaults.string(forKey: "provider") ?? PythiaProvider.google.rawValue) ?? .google }
        set { defaults.set(newValue.rawValue, forKey: "provider") }
    }

    var sourceLanguage: String {
        get { defaults.string(forKey: "sourceLanguage") ?? "auto" }
        set { defaults.set(newValue, forKey: "sourceLanguage") }
    }

    var targetLanguage: String {
        get { defaults.string(forKey: "targetLanguage") ?? "zh-CN" }
        set { defaults.set(newValue, forKey: "targetLanguage") }
    }

    /// When source language is 自动检测, pick the target automatically for pure
    /// Chinese or pure non-Chinese input. Mixed Chinese/English input keeps the
    /// user's selected target language. Default on.
    var smartTargetLanguage: Bool {
        get { defaults.object(forKey: "smartTargetLanguage") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "smartTargetLanguage") }
    }

    var openAIKey: String {
        get { secureString(forKey: "openAIKey") }
        set { setSecureString(newValue, forKey: "openAIKey") }
    }

    var openAIModel: String {
        get { defaults.string(forKey: "openAIModel") ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: "openAIModel") }
    }

    var deepLKey: String {
        get { secureString(forKey: "deepLKey") }
        set { setSecureString(newValue, forKey: "deepLKey") }
    }

    var baiduAppID: String {
        get { secureString(forKey: "baiduAppID") }
        set { setSecureString(newValue, forKey: "baiduAppID") }
    }

    var baiduSecret: String {
        get { secureString(forKey: "baiduSecret") }
        set { setSecureString(newValue, forKey: "baiduSecret") }
    }

    var youdaoAppKey: String {
        get { secureString(forKey: "youdaoAppKey") }
        set { setSecureString(newValue, forKey: "youdaoAppKey") }
    }

    var youdaoSecret: String {
        get { secureString(forKey: "youdaoSecret") }
        set { setSecureString(newValue, forKey: "youdaoSecret") }
    }

    var libreTranslateURL: String {
        get { defaults.string(forKey: "libreTranslateURL") ?? "https://libretranslate.com" }
        set { defaults.set(newValue, forKey: "libreTranslateURL") }
    }

    var libreTranslateKey: String {
        get { secureString(forKey: "libreTranslateKey") }
        set { setSecureString(newValue, forKey: "libreTranslateKey") }
    }

    var pluginName: String {
        get { defaults.string(forKey: "pluginName") ?? "" }
        set { defaults.set(newValue, forKey: "pluginName") }
    }

    var clipboardMonitoring: Bool {
        get { defaults.bool(forKey: "clipboardMonitoring") }
        set { defaults.set(newValue, forKey: "clipboardMonitoring") }
    }

    var theme: String {
        get { defaults.string(forKey: "theme") ?? "system" }
        set { defaults.set(newValue, forKey: "theme") }
    }

    var themeColorHex: String {
        get { defaults.string(forKey: "themeColorHex") ?? "#80B847" }
        set { defaults.set(newValue, forKey: "themeColorHex") }
    }

    var proxyEnabled: Bool {
        get { defaults.bool(forKey: "proxyEnabled") }
        set { defaults.set(newValue, forKey: "proxyEnabled") }
    }

    var proxyHost: String {
        get { defaults.string(forKey: "proxyHost") ?? "" }
        set { defaults.set(newValue, forKey: "proxyHost") }
    }

    var proxyPort: String {
        get { defaults.string(forKey: "proxyPort") ?? "" }
        set { defaults.set(newValue, forKey: "proxyPort") }
    }

    var translateCloseOnBlur: Bool {
        get { defaults.object(forKey: "translateCloseOnBlur") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "translateCloseOnBlur") }
    }

    var translateAlwaysOnTop: Bool {
        get { defaults.bool(forKey: "translateAlwaysOnTop") }
        set { defaults.set(newValue, forKey: "translateAlwaysOnTop") }
    }

    var translateRememberWindowSize: Bool {
        get { defaults.bool(forKey: "translateRememberWindowSize") }
        set { defaults.set(newValue, forKey: "translateRememberWindowSize") }
    }

    var translateWindowPosition: String {
        get { defaults.string(forKey: "translateWindowPosition") ?? "center" }
        set { defaults.set(newValue, forKey: "translateWindowPosition") }
    }

    var translateWindowFrame: String {
        get { defaults.string(forKey: "translateWindowFrame") ?? "" }
        set { defaults.set(newValue, forKey: "translateWindowFrame") }
    }

    var translateAutoCopy: String {
        get { defaults.string(forKey: "translateAutoCopy") ?? "disable" }
        set { defaults.set(newValue, forKey: "translateAutoCopy") }
    }

    var recognizeLanguage: String {
        get { defaults.string(forKey: "recognizeLanguage") ?? "auto" }
        set { defaults.set(newValue, forKey: "recognizeLanguage") }
    }

    var recognizeAutoCopy: Bool {
        get { defaults.bool(forKey: "recognizeAutoCopy") }
        set { defaults.set(newValue, forKey: "recognizeAutoCopy") }
    }

    var recognizeDeleteNewline: Bool {
        get { defaults.bool(forKey: "recognizeDeleteNewline") }
        set { defaults.set(newValue, forKey: "recognizeDeleteNewline") }
    }

    var hotkeySelectionTranslate: String {
        get { defaults.string(forKey: "hotkeySelectionTranslate") ?? "⇧⌘E" }
        set { defaults.set(newValue, forKey: "hotkeySelectionTranslate") }
    }

    var hotkeyInputTranslate: String {
        get { defaults.string(forKey: "hotkeyInputTranslate") ?? "⇧⌘D" }
        set { defaults.set(newValue, forKey: "hotkeyInputTranslate") }
    }

    var hotkeyOCRTranslate: String {
        get { defaults.string(forKey: "hotkeyOCRTranslate") ?? "⇧⌘O" }
        set { defaults.set(newValue, forKey: "hotkeyOCRTranslate") }
    }

    var hotkeyOCRRecognize: String {
        get { defaults.string(forKey: "hotkeyOCRRecognize") ?? "⇧⌘R" }
        set { defaults.set(newValue, forKey: "hotkeyOCRRecognize") }
    }

    var translateServiceList: [String] {
        get { defaults.stringArray(forKey: "translateServiceList") ?? [PythiaProvider.google.rawValue] }
        set { defaults.set(newValue, forKey: "translateServiceList") }
    }

    var translateServiceOrder: [String] {
        get { defaults.stringArray(forKey: "translateServiceOrder") ?? translateServiceList }
        set { defaults.set(uniqueStrings(newValue), forKey: "translateServiceOrder") }
    }

    var recognizeServiceList: [String] {
        get { defaults.stringArray(forKey: "recognizeServiceList") ?? ["System OCR"] }
        set { defaults.set(newValue, forKey: "recognizeServiceList") }
    }

    var ttsServiceList: [String] {
        get { defaults.stringArray(forKey: "ttsServiceList") ?? ["macOS Speech"] }
        set { defaults.set(newValue, forKey: "ttsServiceList") }
    }

    var collectionServiceList: [String] {
        get { defaults.stringArray(forKey: "collectionServiceList") ?? [] }
        set { defaults.set(newValue, forKey: "collectionServiceList") }
    }

    // Settings aligned with original Pot (translate behavior / appearance /
    // general / OCR / proxy / backup).

    var translateDeleteNewline: Bool {
        get { defaults.bool(forKey: "translateDeleteNewline") }
        set { defaults.set(newValue, forKey: "translateDeleteNewline") }
    }

    var hideSource: Bool {
        get { defaults.bool(forKey: "hideSource") }
        set { defaults.set(newValue, forKey: "hideSource") }
    }

    var hideLanguage: Bool {
        get { defaults.bool(forKey: "hideLanguage") }
        set { defaults.set(newValue, forKey: "hideLanguage") }
    }

    var dynamicTranslate: Bool {
        get { defaults.bool(forKey: "dynamicTranslate") }
        set { defaults.set(newValue, forKey: "dynamicTranslate") }
    }

    var incrementalTranslate: Bool {
        get { defaults.bool(forKey: "incrementalTranslate") }
        set { defaults.set(newValue, forKey: "incrementalTranslate") }
    }

    var translateSecondLanguage: String {
        get { defaults.string(forKey: "translateSecondLanguage") ?? "en" }
        set { defaults.set(newValue, forKey: "translateSecondLanguage") }
    }

    var translateDetectEngine: String {
        get {
            enumString(
                forKey: "translateDetectEngine",
                defaultValue: "google",
                validValues: ["google", "bing"],
                legacyValues: ["Google": "google", "Bing": "bing"]
            )
        }
        set {
            setEnumString(
                newValue,
                forKey: "translateDetectEngine",
                defaultValue: "google",
                validValues: ["google", "bing"],
                legacyValues: ["Google": "google", "Bing": "bing"]
            )
        }
    }

    var transparent: Bool {
        get { defaults.object(forKey: "transparent") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "transparent") }
    }

    var appFont: String {
        get { defaults.string(forKey: "appFont") ?? "default" }
        set { defaults.set(newValue, forKey: "appFont") }
    }

    var appFontSize: Int {
        get { defaults.object(forKey: "appFontSize") as? Int ?? 16 }
        set { defaults.set(newValue, forKey: "appFontSize") }
    }

    var appFallbackFont: String {
        get { defaults.string(forKey: "appFallbackFont") ?? "default" }
        set { defaults.set(newValue, forKey: "appFallbackFont") }
    }

    var trayClickEvent: String {
        get {
            let raw = defaults.string(forKey: "trayClickEvent") ?? "config"
            let normalized: String
            switch raw {
            case "config", "settings", "显示设置", "设置":
                normalized = "config"
            case "translate", "translator", "显示翻译窗口", "翻译":
                normalized = "translate"
            case "history", "显示历史记录", "历史记录":
                normalized = "history"
            default:
                normalized = "translate"
            }
            if normalized != raw {
                defaults.set(normalized, forKey: "trayClickEvent")
            }
            return normalized
        }
        set {
            switch newValue {
            case "config", "settings", "显示设置", "设置":
                defaults.set("config", forKey: "trayClickEvent")
            case "history", "显示历史记录", "历史记录":
                defaults.set("history", forKey: "trayClickEvent")
            default:
                defaults.set("translate", forKey: "trayClickEvent")
            }
        }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var checkUpdate: Bool {
        get { defaults.object(forKey: "checkUpdate") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "checkUpdate") }
    }

    var lastNotifiedUpdateVersion: String {
        get { defaults.string(forKey: "lastNotifiedUpdateVersion") ?? "" }
        set { defaults.set(newValue, forKey: "lastNotifiedUpdateVersion") }
    }

    var historyDisable: Bool {
        get { defaults.bool(forKey: "historyDisable") }
        set { defaults.set(newValue, forKey: "historyDisable") }
    }

    var serverPort: Int {
        get { defaults.object(forKey: "serverPort") as? Int ?? 60828 }
        set { defaults.set(newValue, forKey: "serverPort") }
    }

    var appLanguage: String {
        get {
            enumString(
                forKey: "appLanguage",
                defaultValue: "zh_cn",
                validValues: ["zh_cn", "en"],
                legacyValues: ["简体中文": "zh_cn", "English": "en", "zh_CN": "zh_cn", "zh-CN": "zh_cn"]
            )
        }
        set {
            setEnumString(
                newValue,
                forKey: "appLanguage",
                defaultValue: "zh_cn",
                validValues: ["zh_cn", "en"],
                legacyValues: ["简体中文": "zh_cn", "English": "en", "zh_CN": "zh_cn", "zh-CN": "zh_cn"]
            )
        }
    }

    var recognizeHideWindow: Bool {
        get { defaults.bool(forKey: "recognizeHideWindow") }
        set { defaults.set(newValue, forKey: "recognizeHideWindow") }
    }

    var recognizeCloseOnBlur: Bool {
        get { defaults.bool(forKey: "recognizeCloseOnBlur") }
        set { defaults.set(newValue, forKey: "recognizeCloseOnBlur") }
    }

    var proxyUsername: String {
        get { defaults.string(forKey: "proxyUsername") ?? "" }
        set { defaults.set(newValue, forKey: "proxyUsername") }
    }

    var proxyPassword: String {
        get { secureString(forKey: "proxyPassword") }
        set { setSecureString(newValue, forKey: "proxyPassword") }
    }

    var noProxy: String {
        get { defaults.string(forKey: "noProxy") ?? "localhost,127.0.0.1" }
        set { defaults.set(newValue, forKey: "noProxy") }
    }

    var backupType: String {
        get {
            enumString(
                forKey: "backupType",
                defaultValue: "local",
                validValues: ["local", "webdav"],
                legacyValues: ["本地": "local", "WebDAV": "webdav"]
            )
        }
        set {
            setEnumString(
                newValue,
                forKey: "backupType",
                defaultValue: "local",
                validValues: ["local", "webdav"],
                legacyValues: ["本地": "local", "WebDAV": "webdav"]
            )
        }
    }

    var webdavURL: String {
        get { defaults.string(forKey: "webdavURL") ?? "" }
        set { defaults.set(newValue, forKey: "webdavURL") }
    }

    var webdavUsername: String {
        get { defaults.string(forKey: "webdavUsername") ?? "" }
        set { defaults.set(newValue, forKey: "webdavUsername") }
    }

    var webdavPassword: String {
        get { secureString(forKey: "webdavPassword") }
        set { setSecureString(newValue, forKey: "webdavPassword") }
    }

    var webdavHistoryAutoSync: Bool {
        get { defaults.bool(forKey: "webdavHistoryAutoSync") }
        set { defaults.set(newValue, forKey: "webdavHistoryAutoSync") }
    }

    var webdavHistorySyncIntervalValue: Int {
        get { migratedWebDAVSyncSchedule().value }
        set {
            let unit = PythiaWebDAVSyncUnit(rawValue: webdavHistorySyncIntervalUnit) ?? .hour
            let maximum = max(1, PythiaWebDAVSyncSchedule.maximumSeconds / unit.seconds)
            defaults.set(max(1, min(maximum, newValue)), forKey: "webdavHistorySyncIntervalValue")
        }
    }

    var webdavHistorySyncIntervalUnit: String {
        get { migratedWebDAVSyncSchedule().unit.rawValue }
        set {
            let normalized = PythiaWebDAVSyncUnit(rawValue: newValue) ?? .hour
            defaults.set(normalized.rawValue, forKey: "webdavHistorySyncIntervalUnit")
            let currentValue = defaults.object(forKey: "webdavHistorySyncIntervalValue") as? Int ?? 1
            webdavHistorySyncIntervalValue = currentValue
        }
    }

    var webdavHistorySyncIntervalSeconds: Int {
        migratedWebDAVSyncSchedule().seconds
    }

    var webdavHistorySyncIntervalMinutes: Int {
        get {
            webdavHistorySyncIntervalSeconds / 60
        }
        set {
            let schedule = PythiaWebDAVSyncSchedule.fromLegacyMinutes(newValue)
            defaults.set(schedule.unit.rawValue, forKey: "webdavHistorySyncIntervalUnit")
            defaults.set(schedule.value, forKey: "webdavHistorySyncIntervalValue")
            defaults.set(max(1, newValue), forKey: "webdavHistorySyncIntervalMinutes")
        }
    }

    private func migratedWebDAVSyncSchedule() -> PythiaWebDAVSyncSchedule {
        if let value = defaults.object(forKey: "webdavHistorySyncIntervalValue") as? Int,
           let rawUnit = defaults.string(forKey: "webdavHistorySyncIntervalUnit"),
           let unit = PythiaWebDAVSyncUnit(rawValue: rawUnit),
           let schedule = PythiaWebDAVSyncSchedule(value: value, unit: unit) {
            return schedule
        }
        let legacyMinutes = defaults.object(forKey: "webdavHistorySyncIntervalMinutes") as? Int ?? 60
        let schedule = PythiaWebDAVSyncSchedule.fromLegacyMinutes(legacyMinutes)
        defaults.set(schedule.value, forKey: "webdavHistorySyncIntervalValue")
        defaults.set(schedule.unit.rawValue, forKey: "webdavHistorySyncIntervalUnit")
        return schedule
    }

    var webdavLastHistorySyncAt: String {
        get { defaults.string(forKey: "webdavLastHistorySyncAt") ?? "" }
        set { setLocalString(newValue, forKey: "webdavLastHistorySyncAt") }
    }

    var webdavLastHistorySyncStatus: String {
        get { defaults.string(forKey: "webdavLastHistorySyncStatus") ?? "" }
        set { setLocalString(newValue, forKey: "webdavLastHistorySyncStatus") }
    }

    var webdavLastHistorySyncError: String {
        get { defaults.string(forKey: "webdavLastHistorySyncError") ?? "" }
        set { setLocalString(newValue, forKey: "webdavLastHistorySyncError") }
    }

    func exportSnapshot() -> [String: Any] {
        [
            "provider": provider.rawValue,
            "sourceLanguage": sourceLanguage,
            "targetLanguage": targetLanguage,
            "openAIModel": openAIModel,
            "libreTranslateURL": libreTranslateURL,
            "pluginName": pluginName,
            "clipboardMonitoring": clipboardMonitoring,
            "theme": theme,
            "themeColorHex": themeColorHex,
            "proxyEnabled": proxyEnabled,
            "proxyHost": proxyHost,
            "proxyPort": proxyPort,
            "translateCloseOnBlur": translateCloseOnBlur,
            "translateAlwaysOnTop": translateAlwaysOnTop,
            "translateRememberWindowSize": translateRememberWindowSize,
            "translateWindowPosition": translateWindowPosition,
            "translateAutoCopy": translateAutoCopy,
            "smartTargetLanguage": smartTargetLanguage,
            "recognizeLanguage": recognizeLanguage,
            "recognizeAutoCopy": recognizeAutoCopy,
            "recognizeDeleteNewline": recognizeDeleteNewline,
            "hotkeySelectionTranslate": hotkeySelectionTranslate,
            "hotkeyInputTranslate": hotkeyInputTranslate,
            "hotkeyOCRTranslate": hotkeyOCRTranslate,
            "hotkeyOCRRecognize": hotkeyOCRRecognize,
            "translateServiceList": translateServiceList,
            "translateServiceOrder": translateServiceOrder,
            "recognizeServiceList": recognizeServiceList,
            "ttsServiceList": ttsServiceList,
            "collectionServiceList": collectionServiceList,
            "translateDeleteNewline": translateDeleteNewline,
            "hideSource": hideSource,
            "hideLanguage": hideLanguage,
            "dynamicTranslate": dynamicTranslate,
            "incrementalTranslate": incrementalTranslate,
            "translateSecondLanguage": translateSecondLanguage,
            "translateDetectEngine": translateDetectEngine,
            "transparent": transparent,
            "appFont": appFont,
            "appFontSize": appFontSize,
            "appFallbackFont": appFallbackFont,
            "trayClickEvent": trayClickEvent,
            "launchAtLogin": launchAtLogin,
            "checkUpdate": checkUpdate,
            "historyDisable": historyDisable,
            "serverPort": serverPort,
            "appLanguage": appLanguage,
            "recognizeHideWindow": recognizeHideWindow,
            "recognizeCloseOnBlur": recognizeCloseOnBlur,
            "proxyUsername": proxyUsername,
            "noProxy": noProxy,
            "backupType": backupType,
            "webdavURL": webdavURL,
            "webdavUsername": webdavUsername,
            "webdavHistoryAutoSync": webdavHistoryAutoSync,
            "webdavHistorySyncIntervalValue": webdavHistorySyncIntervalValue,
            "webdavHistorySyncIntervalUnit": webdavHistorySyncIntervalUnit,
            "webdavHistorySyncIntervalMinutes": webdavHistorySyncIntervalMinutes,
            "webdavLastHistorySyncAt": webdavLastHistorySyncAt,
            "webdavLastHistorySyncStatus": webdavLastHistorySyncStatus,
            "webdavLastHistorySyncError": webdavLastHistorySyncError,
            "sensitiveFieldsOmitted": [
                "openAIKey",
                "deepLKey",
                "baiduAppID",
                "baiduSecret",
                "youdaoAppKey",
                "youdaoSecret",
                "libreTranslateKey",
                "proxyPassword",
                "webdavPassword",
                "pluginConfigs",
            ],
        ]
    }
}
