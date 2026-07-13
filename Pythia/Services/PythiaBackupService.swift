import Foundation

struct PythiaConfigImportResult {
    let skippedSensitiveCount: Int
    let restoredHistoryCount: Int
}

struct PythiaWebDAVBackupResult {
    let httpCode: Int
    let errorMessage: String?

    var isSuccess: Bool {
        errorMessage == nil && (200..<300).contains(httpCode)
    }
}

struct PythiaWebDAVConnectionResult {
    let httpCode: Int
    let errorMessage: String?

    var isSuccess: Bool {
        errorMessage == nil && (200..<300).contains(httpCode)
    }
}

struct PythiaWebDAVHistorySyncResult {
    let downloadedCount: Int
    let uploadedCount: Int
    let visibleCount: Int
    let conflictCount: Int
    let httpCode: Int
    let backupURL: URL?
    let errorMessage: String?

    var isSuccess: Bool {
        errorMessage == nil && (200..<300).contains(httpCode)
    }

    var statusSummary: String {
        if let errorMessage { return "失败：\(errorMessage)" }
        if isSuccess {
            let conflictText = conflictCount > 0 ? "，冲突 \(conflictCount) 条" : ""
            return "成功：远程 \(downloadedCount) 条，本机 \(visibleCount) 条，上传 \(uploadedCount) 条\(conflictText)"
        }
        return "失败：HTTP \(httpCode)\(PythiaBackupService.webDAVErrorHint(code: httpCode))"
    }
}

enum PythiaBackupService {
    private static let sensitiveKeys: Set<String> = [
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
    ]

    static func configSnapshotData() -> Data? {
        try? PythiaPortableBackupCodec.encode(portableSnapshot())
    }

    static func importBackupData(_ data: Data) throws -> PythiaConfigImportResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidResponse
        }
        if object["product"] != nil || object["schemaVersion"] != nil {
            return try importPortableBackupData(data)
        }
        return importConfigDictionary(object)
    }

    static func importPortableBackupData(_ data: Data) throws -> PythiaConfigImportResult {
        let backup = try PythiaPortableBackupCodec.decode(data)
        applyPortableSettings(backup.settings)
        _ = try HistoryStore.shared.backupBeforeSync()
        let merged = PythiaHistoryMerger.merge(
            local: HistoryStore.shared.allRecordsForSync(),
            remote: backup.history
        )
        let pending = merged.merged.map { record -> PythiaHistoryRecord in
            var copy = record
            if copy.syncStatus != .conflict {
                copy.syncStatus = copy.deletedAt == nil ? .pendingUpload : .pendingDelete
            }
            return copy
        }
        HistoryStore.shared.restore(pending)
        return PythiaConfigImportResult(
            skippedSensitiveCount: 0,
            restoredHistoryCount: backup.history.count
        )
    }

    private static func portableSnapshot() -> PythiaPortableBackup {
        let preferences = Preferences.shared
        let services = preferences.translateServiceList.map(canonicalServiceID)
        let order = preferences.translateServiceOrder.map(canonicalServiceID)
        return PythiaPortableBackup(
            settings: PythiaPortableSettings(
                sourceLanguage: preferences.sourceLanguage,
                targetLanguage: preferences.targetLanguage,
                enabledTranslateServices: services,
                translateServiceOrder: order,
                openAICompatibleEnabled: services.contains("openai-compatible"),
                openAICompatibleName: "OpenAI",
                openAICompatibleBaseUrl: "https://api.openai.com/v1",
                openAICompatibleModel: preferences.openAIModel,
                deepLEnabled: services.contains("deepl"),
                deepLBaseUrl: "https://api-free.deepl.com/v2",
                libreTranslateEnabled: services.contains("libretranslate"),
                libreTranslateBaseUrl: preferences.libreTranslateURL,
                saveHistory: !preferences.historyDisable,
                themeMode: preferences.theme
            ),
            history: HistoryStore.shared.allRecordsForSync()
        )
    }

    private static func applyPortableSettings(_ settings: PythiaPortableSettings) {
        let preferences = Preferences.shared
        if let value = settings.sourceLanguage { preferences.sourceLanguage = value }
        if let value = settings.targetLanguage { preferences.targetLanguage = value }
        if let value = settings.enabledTranslateServices {
            preferences.translateServiceList = value.map(macOSServiceID)
        }
        if let value = settings.translateServiceOrder {
            preferences.translateServiceOrder = value.map(macOSServiceID)
        }
        if let value = settings.openAICompatibleModel { preferences.openAIModel = value }
        if let value = settings.libreTranslateBaseUrl { preferences.libreTranslateURL = value }
        if let value = settings.saveHistory { preferences.historyDisable = !value }
        if let value = settings.themeMode, ["system", "light", "dark"].contains(value) {
            preferences.theme = value
        }
    }

    private static func canonicalServiceID(_ value: String) -> String {
        switch value {
        case PythiaProvider.local.rawValue: return "local"
        case PythiaProvider.google.rawValue: return "google"
        case PythiaProvider.openAI.rawValue: return "openai-compatible"
        case PythiaProvider.deepL.rawValue: return "deepl"
        case PythiaProvider.baidu.rawValue: return "baidu"
        case PythiaProvider.youdao.rawValue: return "youdao"
        case PythiaProvider.libreTranslate.rawValue: return "libretranslate"
        default: return value
        }
    }

    private static func macOSServiceID(_ value: String) -> String {
        switch value {
        case "local": return PythiaProvider.local.rawValue
        case "google": return PythiaProvider.google.rawValue
        case "openai-compatible": return PythiaProvider.openAI.rawValue
        case "deepl": return PythiaProvider.deepL.rawValue
        case "baidu": return PythiaProvider.baidu.rawValue
        case "youdao": return PythiaProvider.youdao.rawValue
        case "libretranslate": return PythiaProvider.libreTranslate.rawValue
        default: return value
        }
    }

    @discardableResult
    static func importConfigDictionary(_ dict: [String: Any], importSensitiveFields: Bool = false) -> PythiaConfigImportResult {
        let skippedSensitiveCount = importSensitiveFields ? 0 : dict.keys.filter { sensitiveKeys.contains($0) }.count
        func stringValue(_ key: String) -> String? {
            guard importSensitiveFields || !sensitiveKeys.contains(key) else { return nil }
            return dict[key] as? String
        }

        let preferences = Preferences.shared
        if let value = stringValue("provider") { preferences.provider = PythiaProvider(rawValue: value) ?? preferences.provider }
        if let value = stringValue("sourceLanguage") { preferences.sourceLanguage = value }
        if let value = stringValue("targetLanguage") { preferences.targetLanguage = value }
        if let value = stringValue("openAIModel") { preferences.openAIModel = value }
        if let value = stringValue("libreTranslateURL") { preferences.libreTranslateURL = value }
        if let value = stringValue("openAIKey") { preferences.openAIKey = value }
        if let value = stringValue("deepLKey") { preferences.deepLKey = value }
        if let value = stringValue("baiduAppID") { preferences.baiduAppID = value }
        if let value = stringValue("baiduSecret") { preferences.baiduSecret = value }
        if let value = stringValue("youdaoAppKey") { preferences.youdaoAppKey = value }
        if let value = stringValue("youdaoSecret") { preferences.youdaoSecret = value }
        if let value = stringValue("libreTranslateKey") { preferences.libreTranslateKey = value }
        if let value = stringValue("pluginName") { preferences.pluginName = value }
        if let value = dict["clipboardMonitoring"] as? Bool { preferences.clipboardMonitoring = value }
        if let value = stringValue("theme") { preferences.theme = value }
        if let value = stringValue("themeColorHex") { preferences.themeColorHex = value }
        if let value = dict["proxyEnabled"] as? Bool { preferences.proxyEnabled = value }
        if let value = stringValue("proxyHost") { preferences.proxyHost = value }
        if let value = stringValue("proxyPort") { preferences.proxyPort = value }
        if let value = stringValue("proxyUsername") { preferences.proxyUsername = value }
        if let value = stringValue("proxyPassword") { preferences.proxyPassword = value }
        if let value = stringValue("noProxy") { preferences.noProxy = value }
        if let value = dict["translateCloseOnBlur"] as? Bool { preferences.translateCloseOnBlur = value }
        if let value = dict["translateAlwaysOnTop"] as? Bool { preferences.translateAlwaysOnTop = value }
        if let value = dict["translateRememberWindowSize"] as? Bool { preferences.translateRememberWindowSize = value }
        if let value = stringValue("translateWindowPosition") { preferences.translateWindowPosition = value }
        if let value = stringValue("translateAutoCopy") { preferences.translateAutoCopy = value }
        if let value = dict["translateDeleteNewline"] as? Bool { preferences.translateDeleteNewline = value }
        if let value = dict["smartTargetLanguage"] as? Bool { preferences.smartTargetLanguage = value }
        if let value = dict["hideSource"] as? Bool { preferences.hideSource = value }
        if let value = dict["hideLanguage"] as? Bool { preferences.hideLanguage = value }
        if let value = dict["dynamicTranslate"] as? Bool { preferences.dynamicTranslate = value }
        if let value = dict["incrementalTranslate"] as? Bool { preferences.incrementalTranslate = value }
        if let value = stringValue("translateSecondLanguage") { preferences.translateSecondLanguage = value }
        if let value = stringValue("translateDetectEngine") { preferences.translateDetectEngine = value }
        if let value = dict["transparent"] as? Bool { preferences.transparent = value }
        if let value = stringValue("appFont") { preferences.appFont = value }
        if let value = dict["appFontSize"] as? Int { preferences.appFontSize = value }
        if let value = stringValue("appFallbackFont") { preferences.appFallbackFont = value }
        if let value = stringValue("trayClickEvent") { preferences.trayClickEvent = value }
        if let value = dict["launchAtLogin"] as? Bool { preferences.launchAtLogin = value }
        if let value = dict["checkUpdate"] as? Bool { preferences.checkUpdate = value }
        if let value = dict["historyDisable"] as? Bool { preferences.historyDisable = value }
        if let value = dict["serverPort"] as? Int { preferences.serverPort = value }
        if let value = stringValue("appLanguage") { preferences.appLanguage = value }
        if let value = stringValue("recognizeLanguage") { preferences.recognizeLanguage = value }
        if let value = dict["recognizeAutoCopy"] as? Bool { preferences.recognizeAutoCopy = value }
        if let value = dict["recognizeDeleteNewline"] as? Bool { preferences.recognizeDeleteNewline = value }
        if let value = dict["recognizeHideWindow"] as? Bool { preferences.recognizeHideWindow = value }
        if let value = dict["recognizeCloseOnBlur"] as? Bool { preferences.recognizeCloseOnBlur = value }
        if let value = stringValue("hotkeySelectionTranslate") { preferences.hotkeySelectionTranslate = value }
        if let value = stringValue("hotkeyInputTranslate") { preferences.hotkeyInputTranslate = value }
        if let value = stringValue("hotkeyOCRTranslate") { preferences.hotkeyOCRTranslate = value }
        if let value = stringValue("hotkeyOCRRecognize") { preferences.hotkeyOCRRecognize = value }
        if let value = dict["translateServiceList"] as? [String] { preferences.translateServiceList = value }
        if let value = dict["translateServiceOrder"] as? [String] {
            preferences.translateServiceOrder = value
        } else if let value = dict["translateServiceList"] as? [String] {
            preferences.translateServiceOrder = value
        }
        if let value = dict["recognizeServiceList"] as? [String] { preferences.recognizeServiceList = value }
        if let value = dict["ttsServiceList"] as? [String] { preferences.ttsServiceList = value }
        if let value = dict["collectionServiceList"] as? [String] { preferences.collectionServiceList = value }
        if let value = stringValue("backupType") { preferences.backupType = value }
        if let value = stringValue("webdavURL") { preferences.webdavURL = value }
        if let value = stringValue("webdavUsername") { preferences.webdavUsername = value }
        if let value = stringValue("webdavPassword") { preferences.webdavPassword = value }
        if let value = dict["webdavHistoryAutoSync"] as? Bool { preferences.webdavHistoryAutoSync = value }
        if let value = dict["webdavHistorySyncIntervalValue"] as? Int,
           let unit = stringValue("webdavHistorySyncIntervalUnit") {
            preferences.webdavHistorySyncIntervalUnit = unit
            preferences.webdavHistorySyncIntervalValue = value
        } else if let value = dict["webdavHistorySyncIntervalMinutes"] as? Int {
            preferences.webdavHistorySyncIntervalMinutes = value
        }

        var restoredHistoryCount = 0
        if let historyArray = dict["historyRecords"] as? [[String: Any]], !historyArray.isEmpty {
            let records = HistoryStore.shared.records(fromJSONArray: historyArray)
            if !records.isEmpty {
                HistoryStore.shared.restore(records)
                restoredHistoryCount = records.count
            }
        }

        return PythiaConfigImportResult(
            skippedSensitiveCount: skippedSensitiveCount,
            restoredHistoryCount: restoredHistoryCount
        )
    }

    static func fetchFirstWebDAVBackup(urls: [URL], auth: String?, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        guard let url = urls.first else {
            completion(nil, nil, TranslationError.requestFailed("没有找到 WebDAV 备份文件。"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        PythiaNetworkSession.dataTask(with: request) { data, response, error in
            if error == nil,
               let http = response as? HTTPURLResponse,
               http.statusCode == 404,
               urls.count > 1 {
                fetchFirstWebDAVBackup(urls: Array(urls.dropFirst()), auth: auth, completion: completion)
                return
            }
            completion(data, response, error)
        }.resume()
    }

    static func backupToWebDAV(base: String, user: String, password: String, data: Data, completion: @escaping (PythiaWebDAVBackupResult) -> Void) {
        let auth = webDAVAuthHeader(user: user, password: password)
        let rootURL = webDAVSyncRootURL(base: base)
        let folderURL = webDAVBackupFolderURL(base: base)
        let fileURL = webDAVBackupFileURL(base: base)
        let temporaryURL = folderURL.appendingPathComponent("portable-backup.tmp.json")
        DispatchQueue.global(qos: .userInitiated).async {
            let root = ensureWebDAVFolder(url: rootURL, auth: auth)
            guard root.error == nil, isSuccessfulOrExistingWebDAVFolder(code: root.code) else {
                completion(PythiaWebDAVBackupResult(httpCode: root.code, errorMessage: root.error))
                return
            }
            let folder = ensureWebDAVFolder(url: folderURL, auth: auth)
            guard folder.error == nil, isSuccessfulOrExistingWebDAVFolder(code: folder.code) else {
                completion(PythiaWebDAVBackupResult(httpCode: folder.code, errorMessage: folder.error))
                return
            }
            let temporary = synchronousWebDAVRequest(
                url: temporaryURL,
                method: "PUT",
                auth: auth,
                body: data,
                contentType: "application/json"
            )
            guard temporary.error == nil, (200..<300).contains(temporary.code) else {
                completion(PythiaWebDAVBackupResult(httpCode: temporary.code, errorMessage: temporary.error))
                return
            }
            let move = synchronousWebDAVRequest(
                url: temporaryURL,
                method: "MOVE",
                auth: auth,
                headers: ["Destination": fileURL.absoluteString, "Overwrite": "T"]
            )
            if move.error == nil, (200..<300).contains(move.code) {
                completion(PythiaWebDAVBackupResult(httpCode: move.code, errorMessage: nil))
                return
            }
            let final = synchronousWebDAVRequest(
                url: fileURL,
                method: "PUT",
                auth: auth,
                body: data,
                contentType: "application/json"
            )
            if final.error == nil, (200..<300).contains(final.code) {
                _ = synchronousWebDAVRequest(url: temporaryURL, method: "DELETE", auth: auth)
            }
            completion(PythiaWebDAVBackupResult(httpCode: final.code, errorMessage: final.error))
        }
    }

    static func syncHistoryToWebDAV(base: String, user: String, password: String, completion: @escaping (PythiaWebDAVHistorySyncResult) -> Void) {
        let auth = webDAVAuthHeader(user: user, password: password)
        let rootURL = webDAVSyncRootURL(base: base)
        let historyFolderURL = rootURL.appendingPathComponent("history", isDirectory: true)
        let historyFileURL = historyFolderURL.appendingPathComponent("history.json")
        func finish(_ result: PythiaWebDAVHistorySyncResult) {
            recordHistorySyncResult(result)
            completion(result)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let rootResult = ensureWebDAVFolder(url: rootURL, auth: auth)
            if let error = rootResult.error {
                finish(PythiaWebDAVHistorySyncResult(downloadedCount: 0, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: rootResult.code, backupURL: nil, errorMessage: error))
                return
            }
            if !isSuccessfulOrExistingWebDAVFolder(code: rootResult.code) {
                finish(PythiaWebDAVHistorySyncResult(downloadedCount: 0, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: rootResult.code, backupURL: nil, errorMessage: nil))
                return
            }
            let historyFolderResult = ensureWebDAVFolder(url: historyFolderURL, auth: auth)
            if let error = historyFolderResult.error {
                finish(PythiaWebDAVHistorySyncResult(downloadedCount: 0, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: historyFolderResult.code, backupURL: nil, errorMessage: error))
                return
            }
            if !isSuccessfulOrExistingWebDAVFolder(code: historyFolderResult.code) {
                finish(PythiaWebDAVHistorySyncResult(downloadedCount: 0, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: historyFolderResult.code, backupURL: nil, errorMessage: nil))
                return
            }

            let remoteFetch = synchronousWebDAVRequest(url: historyFileURL, method: "GET", auth: auth)
            let remoteRecords: [PythiaHistoryRecord]
            if let error = remoteFetch.error {
                finish(PythiaWebDAVHistorySyncResult(downloadedCount: 0, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: remoteFetch.code, backupURL: nil, errorMessage: error))
                return
            } else if remoteFetch.code == 404 {
                remoteRecords = []
            } else if !(200..<300).contains(remoteFetch.code) {
                finish(PythiaWebDAVHistorySyncResult(downloadedCount: 0, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: remoteFetch.code, backupURL: nil, errorMessage: nil))
                return
            } else if let data = remoteFetch.data, !data.isEmpty {
                do {
                    remoteRecords = try decodeHistoryCollection(data).records
                } catch {
                    finish(PythiaWebDAVHistorySyncResult(downloadedCount: 0, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: remoteFetch.code, backupURL: nil, errorMessage: "远程历史文件损坏，已停止同步以保护本地数据：\(error.localizedDescription)"))
                    return
                }
            } else {
                remoteRecords = []
            }

            do {
                let backupURL = try HistoryStore.shared.backupBeforeSync()
                let localRecords = HistoryStore.shared.allRecordsForSync()
                let merged = PythiaHistoryMerger.merge(local: localRecords, remote: remoteRecords)
                HistoryStore.shared.restore(merged.merged)
                let collection = PythiaHistoryCollection(
                    deviceId: HistoryStore.shared.deviceIdentifierForSync(),
                    records: HistoryStore.shared.allRecordsForSync()
                )
                let uploadData = try historyEncoder().encode(collection)
                let upload = synchronousWebDAVRequest(
                    url: historyFileURL,
                    method: "PUT",
                    auth: auth,
                    body: uploadData,
                    contentType: "application/json"
                )
                if let error = upload.error {
                    finish(PythiaWebDAVHistorySyncResult(downloadedCount: remoteRecords.count, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: merged.conflicts.count, httpCode: upload.code, backupURL: backupURL, errorMessage: error))
                } else if (200..<300).contains(upload.code) {
                    finish(PythiaWebDAVHistorySyncResult(downloadedCount: remoteRecords.count, uploadedCount: collection.records.count, visibleCount: HistoryStore.shared.records.count, conflictCount: merged.conflicts.count, httpCode: upload.code, backupURL: backupURL, errorMessage: nil))
                } else {
                    finish(PythiaWebDAVHistorySyncResult(downloadedCount: remoteRecords.count, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: merged.conflicts.count, httpCode: upload.code, backupURL: backupURL, errorMessage: nil))
                }
            } catch {
                finish(PythiaWebDAVHistorySyncResult(downloadedCount: remoteRecords.count, uploadedCount: 0, visibleCount: HistoryStore.shared.records.count, conflictCount: 0, httpCode: -1, backupURL: nil, errorMessage: error.localizedDescription))
            }
        }
    }

    static func testWebDAVConnection(base: String, user: String, password: String, completion: @escaping (PythiaWebDAVConnectionResult) -> Void) {
        let auth = webDAVAuthHeader(user: user, password: password)
        let url = webDAVBackupFolderURL(base: base)
        DispatchQueue.global(qos: .userInitiated).async {
            let mkdirResult = ensureWebDAVFolder(url: url, auth: auth)
            if let error = mkdirResult.error {
                completion(PythiaWebDAVConnectionResult(httpCode: mkdirResult.code, errorMessage: error))
                return
            }
            if !isSuccessfulOrExistingWebDAVFolder(code: mkdirResult.code) {
                completion(PythiaWebDAVConnectionResult(httpCode: mkdirResult.code, errorMessage: nil))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PROPFIND"
            request.setValue("0", forHTTPHeaderField: "Depth")
            if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
            PythiaNetworkSession.dataTask(with: request) { _, response, error in
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(PythiaWebDAVConnectionResult(httpCode: code, errorMessage: error?.localizedDescription))
            }.resume()
        }
    }

    @discardableResult
    static func ensureWebDAVFolder(url: URL, auth: String?) -> (code: Int, error: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        let sem = DispatchSemaphore(value: 0)
        var statusCode = -1
        var message: String?
        let task = PythiaNetworkSession.dataTask(with: request) { _, response, error in
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            message = error?.localizedDescription
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 15) == .timedOut {
            task.cancel()
            return (-1, "WebDAV 请求超时")
        }
        return (statusCode, message)
    }

    static func canAutoSyncHistory() -> Bool {
        let preferences = Preferences.shared
        return preferences.backupType == "webdav"
            && preferences.webdavHistoryAutoSync
            && !preferences.webdavURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func recordHistorySyncResult(_ result: PythiaWebDAVHistorySyncResult) {
        let preferences = Preferences.shared
        preferences.webdavLastHistorySyncAt = ISO8601DateFormatter().string(from: Date())
        preferences.webdavLastHistorySyncStatus = result.statusSummary
        preferences.webdavLastHistorySyncError = result.isSuccess ? "" : result.statusSummary
    }

    private static func isSuccessfulOrExistingWebDAVFolder(code: Int) -> Bool {
        (200..<300).contains(code) || code == 405 || code == 409
    }

    static func webDAVAuthHeader(user: String, password: String) -> String? {
        guard !user.isEmpty else { return nil }
        let token = Data("\(user):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    static func webDAVErrorHint(code: Int) -> String {
        switch code {
        case 401: return "（账号或密码错误；坚果云需用应用专属密码）"
        case 403: return "（无权限，检查账号或目录权限）"
        case 404: return "（地址不存在；请确认地址含文件夹名，如 /dav/pot）"
        case 405: return "（方法不允许，服务器可能不支持该 WebDAV 操作）"
        case 409: return "（父目录不存在）"
        default: return ""
        }
    }

    static func webDAVBackupFolderURL(base: String) -> URL {
        webDAVSyncRootURL(base: base).appendingPathComponent("settings", isDirectory: true)
    }

    static func webDAVSyncRootURL(base: String) -> URL {
        normalizedWebDAVBaseURL(base: base, finalDirectoryName: "Pythia")
    }

    static func webDAVBackupFileURL(base: String) -> URL {
        webDAVBackupFolderURL(base: base).appendingPathComponent("portable-backup.json")
    }

    static func legacyWebDAVBackupFileURL(base: String) -> URL {
        legacyWebDAVBackupFolderURL(base: base).appendingPathComponent("pythia-config-backup.json")
    }

    static func oldestWebDAVBackupFileURL(base: String) -> URL {
        legacyWebDAVBackupFolderURL(base: base).appendingPathComponent("pot-config-backup.json")
    }

    private static func legacyWebDAVBackupFolderURL(base: String) -> URL {
        normalizedWebDAVBaseURL(base: base, finalDirectoryName: "pot")
    }

    private static func historyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func historyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func decodeHistoryCollection(_ data: Data) throws -> PythiaHistoryCollection {
        if let collection = try? historyDecoder().decode(PythiaHistoryCollection.self, from: data) {
            return collection
        }
        let records = try historyDecoder().decode([PythiaHistoryRecord].self, from: data)
        return PythiaHistoryCollection(deviceId: "legacy-remote", records: records)
    }

    private static func normalizedWebDAVBaseURL(base: String, finalDirectoryName: String) -> URL {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("//") { trimmed.removeLast() }
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        let lastSegment = (trimmed as NSString).lastPathComponent.lowercased()
        if lastSegment != finalDirectoryName.lowercased() {
            trimmed += "/\(finalDirectoryName)"
        }
        return URL(string: trimmed + "/") ?? URL(fileURLWithPath: "/dev/null")
    }

    private static func synchronousWebDAVRequest(
        url: URL,
        method: String,
        auth: String?,
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:]
    ) -> (data: Data?, code: Int, error: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var statusCode = -1
        var message: String?
        let task = PythiaNetworkSession.dataTask(with: request) { data, response, error in
            responseData = data
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            message = error?.localizedDescription
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 45) == .timedOut {
            task.cancel()
            return (responseData, -1, "WebDAV 请求超时")
        }
        return (responseData, statusCode, message)
    }
}
