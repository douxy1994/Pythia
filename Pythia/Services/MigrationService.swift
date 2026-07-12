import Foundation

final class MigrationService {
    static let shared = MigrationService()

    func migrateFromTauriPot() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/com.pot-app.desktop"),
            home.appendingPathComponent("Library/Application Support/pot"),
            home.appendingPathComponent("Library/Application Support/Pot"),
        ]
        var imported = 0
        for directory in candidates where FileManager.default.fileExists(atPath: directory.path) {
            imported += migrateJSONFiles(in: directory)
        }
        return imported == 0 ? "没有找到可迁移的旧 Pot 配置。" : "已迁移 \(imported) 项配置。"
    }

    private func migrateJSONFiles(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        var imported = 0
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let object = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            imported += migrateObject(object)
        }
        return imported
    }

    private func migrateObject(_ object: Any) -> Int {
        var imported = 0
        if let dict = object as? [String: Any] {
            imported += migrateDictionary(dict)
            for value in dict.values {
                imported += migrateObject(value)
            }
        } else if let array = object as? [Any] {
            for value in array {
                imported += migrateObject(value)
            }
        }
        return imported
    }

    private func migrateDictionary(_ dict: [String: Any]) -> Int {
        let preferences = Preferences.shared
        var imported = 0
        for (key, value) in dict {
            let lower = key.lowercased()
            if let bool = value as? Bool {
                switch lower {
                case "clipboard_monitor":
                    preferences.clipboardMonitoring = bool; imported += 1
                case "proxy_enable":
                    preferences.proxyEnabled = bool; imported += 1
                case "translate_close_on_blur":
                    preferences.translateCloseOnBlur = bool; imported += 1
                case "translate_always_on_top":
                    preferences.translateAlwaysOnTop = bool; imported += 1
                case "translate_remember_window_size":
                    preferences.translateRememberWindowSize = bool; imported += 1
                case "recognize_auto_copy":
                    preferences.recognizeAutoCopy = bool; imported += 1
                case "recognize_delete_newline":
                    preferences.recognizeDeleteNewline = bool; imported += 1
                case "translate_delete_newline":
                    preferences.translateDeleteNewline = bool; imported += 1
                case "hide_source":
                    preferences.hideSource = bool; imported += 1
                case "hide_language":
                    preferences.hideLanguage = bool; imported += 1
                case "dynamic_translate":
                    preferences.dynamicTranslate = bool; imported += 1
                case "incremental_translate":
                    preferences.incrementalTranslate = bool; imported += 1
                case "transparent":
                    preferences.transparent = bool; imported += 1
                case "check_update":
                    preferences.checkUpdate = bool; imported += 1
                case "history_disable":
                    preferences.historyDisable = bool; imported += 1
                case "dev_mode":
                    break
                case "recognize_hide_window":
                    preferences.recognizeHideWindow = bool; imported += 1
                case "recognize_close_on_blur":
                    preferences.recognizeCloseOnBlur = bool; imported += 1
                default:
                    break
                }
                continue
            }
            if let array = value as? [String], !array.isEmpty {
                switch lower {
                case "translate_service_list":
                    preferences.translateServiceList = array
                    preferences.translateServiceOrder = array
                    imported += 1
                case "recognize_service_list":
                    preferences.recognizeServiceList = array; imported += 1
                case "tts_service_list":
                    preferences.ttsServiceList = array; imported += 1
                case "collection_service_list":
                    preferences.collectionServiceList = array; imported += 1
                default:
                    break
                }
                continue
            }
            guard let string = value as? String, !string.isEmpty else { continue }
            if lower.contains("openai"), lower.contains("key") {
                preferences.openAIKey = string
                imported += 1
            } else if lower.contains("deepl"), lower.contains("key") {
                preferences.deepLKey = string
                imported += 1
            } else if lower.contains("baidu"), lower.contains("appid") {
                preferences.baiduAppID = string
                imported += 1
            } else if lower.contains("baidu"), lower.contains("secret") {
                preferences.baiduSecret = string
                imported += 1
            } else if lower.contains("youdao"), lower.contains("appkey") {
                preferences.youdaoAppKey = string
                imported += 1
            } else if lower.contains("youdao"), lower.contains("secret") {
                preferences.youdaoSecret = string
                imported += 1
            } else if lower == "app_theme" {
                preferences.theme = normalizeTheme(string)
                imported += 1
            } else if lower == "proxy_host" {
                preferences.proxyHost = string
                imported += 1
            } else if lower == "proxy_port" {
                preferences.proxyPort = string
                imported += 1
            } else if lower == "translate_window_position" {
                preferences.translateWindowPosition = normalizeWindowPosition(string)
                imported += 1
            } else if lower == "translate_auto_copy" {
                preferences.translateAutoCopy = string
                imported += 1
            } else if lower == "recognize_language" {
                preferences.recognizeLanguage = normalizeLanguage(string)
                imported += 1
            } else if lower == "hotkey_selection_translate" {
                preferences.hotkeySelectionTranslate = normalizeHotkey(string, fallback: "⇧⌘E")
                imported += 1
            } else if lower == "hotkey_input_translate" {
                preferences.hotkeyInputTranslate = normalizeHotkey(string, fallback: "⇧⌘D")
                imported += 1
            } else if lower == "hotkey_ocr_translate" {
                preferences.hotkeyOCRTranslate = normalizeHotkey(string, fallback: "⇧⌘O")
                imported += 1
            } else if lower == "hotkey_ocr_recognize" {
                preferences.hotkeyOCRRecognize = normalizeHotkey(string, fallback: "⇧⌘R")
                imported += 1
            } else if lower == "translate_target_language" || lower == "targetlanguage" || lower == "target_lang" || lower == "target" {
                preferences.targetLanguage = normalizeLanguage(string)
                imported += 1
            } else if lower == "translate_source_language" || lower == "sourcelanguage" || lower == "source_lang" || lower == "source" {
                preferences.sourceLanguage = normalizeLanguage(string)
                imported += 1
            } else if lower == "translate_second_language" {
                preferences.translateSecondLanguage = normalizeLanguage(string); imported += 1
            } else if lower == "translate_detect_engine" {
                preferences.translateDetectEngine = string; imported += 1
            } else if lower == "app_font" {
                preferences.appFont = string; imported += 1
            } else if lower == "app_fallback_font" {
                preferences.appFallbackFont = string; imported += 1
            } else if lower == "tray_click_event" {
                preferences.trayClickEvent = string; imported += 1
            } else if lower == "app_language" {
                preferences.appLanguage = string; imported += 1
            } else if lower == "proxy_username" {
                preferences.proxyUsername = string; imported += 1
            } else if lower == "proxy_password" {
                preferences.proxyPassword = string; imported += 1
            } else if lower == "no_proxy" {
                preferences.noProxy = string; imported += 1
            } else if lower == "backup_type" {
                preferences.backupType = string; imported += 1
            } else if lower == "webdav_url" {
                preferences.webdavURL = string; imported += 1
            } else if lower == "webdav_username" {
                preferences.webdavUsername = string; imported += 1
            } else if lower == "webdav_password" {
                preferences.webdavPassword = string; imported += 1
            }
        }
        if let int = dict["app_font_size"] as? Int { preferences.appFontSize = int; imported += 1 }
        if let int = dict["server_port"] as? Int { preferences.serverPort = int; imported += 1 }
        return imported
    }

    private func normalizeLanguage(_ value: String) -> String {
        switch value.lowercased() {
        case "zh_cn", "zh-cn", "zh_hans":
            return "zh-CN"
        case "zh_tw", "zh-tw", "zh_hant":
            return "zh-TW"
        default:
            return value
        }
    }

    private func normalizeTheme(_ value: String) -> String {
        switch value.lowercased() {
        case "light": return "light"
        case "dark": return "dark"
        default: return "system"
        }
    }

    private func normalizeWindowPosition(_ value: String) -> String {
        switch value.lowercased() {
        case "mouse": return "mouse"
        case "remember", "fixed": return "remember"
        default: return "center"
        }
    }

    private func normalizeHotkey(_ value: String, fallback: String) -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        return value
            .replacingOccurrences(of: "Command", with: "⌘")
            .replacingOccurrences(of: "Cmd", with: "⌘")
            .replacingOccurrences(of: "Shift", with: "⇧")
            .replacingOccurrences(of: "Option", with: "⌥")
            .replacingOccurrences(of: "Alt", with: "⌥")
            .replacingOccurrences(of: "Control", with: "⌃")
            .replacingOccurrences(of: "Ctrl", with: "⌃")
            .replacingOccurrences(of: "+", with: "")
    }
}
