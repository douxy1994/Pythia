import AppKit
import ServiceManagement

final class PythiaAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    static weak var shared: PythiaAppDelegate?
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let translator = TranslatorWindowController()
    private var settings: SettingsWindowController?
    private var history: HistoryWindowController?
    private let hotKeys = HotKeyMonitor()
    private let httpServer = PythiaHTTPServer()
    private var lastExternalApplication: NSRunningApplication?
    private var webDAVHistorySyncTimer: Timer?
    private var webDAVHistorySyncDebounce: DispatchWorkItem?
    private var isWebDAVHistorySyncRunning = false
    var statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        PythiaAppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        _ = Preferences.shared.trayClickEvent
        configureFrontmostApplicationTracking()
        installMainMenu()
        buildMenuBar()
        configureHotKeys()
        configureHTTPServer()
        applyClipboardPreference()
        applyRuntimePreferences()
        translator.showAndFocus()
        observeHistoryChangesForSync()
        scheduleStartupUpdateCheck()
        scheduleStartupHistorySync()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        webDAVHistorySyncDebounce?.cancel()
        webDAVHistorySyncDebounce = nil
        webDAVHistorySyncTimer?.invalidate()
        webDAVHistorySyncTimer = nil
        runWebDAVHistorySync(reason: "退出前同步", waitUntilFinished: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        translator.showAndFocus()
        return true
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let shouldCenter = settings == nil || settings?.window == nil
        if settings == nil || settings?.window == nil {
            settings = SettingsWindowController()
        }
        settings?.showWindow(nil)
        if shouldCenter {
            settings?.window?.center()
        }
        settings?.window?.makeKeyAndOrderFront(NSApp)
        settings?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func setStatus(_ text: String) {
        translator.setStatus(text)
    }

    func showHistory() {
        NSApp.activate(ignoringOtherApps: true)
        if history == nil || history?.window == nil {
            history = HistoryWindowController()
            history?.onLoadRecord = { [weak self] record in
                self?.translator.loadRecord(record)
            }
        }
        history?.showAndFocus()
    }

    func applyClipboardPreference() {
        ClipboardMonitor.shared.onText = { [weak self] text in
            self?.translator.showAndFocus(with: text)
            self?.translator.translate(text)
        }
        Preferences.shared.clipboardMonitoring ? ClipboardMonitor.shared.start() : ClipboardMonitor.shared.stop()
        buildMenuBar()
    }

    func translateSelection() {
        let targetApplication = selectionTargetApplication()
        let targetName = targetApplication?.localizedName ?? "当前应用"
        translator.setStatus("正在读取选中文本...")
        // Read the selection BEFORE focusing the Pot window: once Pot comes to
        // the front, the previously focused app loses focus and its selected
        // text is no longer readable via Accessibility.
        SelectionReader.shared.selectedText(targetApplication: targetApplication) { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.translator.showAndFocus()
                    let message = SelectionReader.shared.accessibilityTrusted(prompt: false)
                        ? "没有从「\(targetName)」读取到选中的文字。请先在目标应用中选中文字；如果仍失败，可能是目标应用没有向 macOS 辅助功能接口暴露选区。"
                        : "Pythia 当前没有辅助功能权限。请在系统设置的「隐私与安全性」-「辅助功能」中允许 Pythia；使用稳定签名版本后，后续更新不需要重复授权。"
                    self.translator.showMessage(
                        title: "划词",
                        text: message,
                        status: "未读取到选中文本"
                    )
                    return
                }
                self.translator.showAndFocus(with: trimmed)
                self.translator.translate(trimmed)
            }
        }
    }

    private func configureFrontmostApplicationTracking() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        rememberExternalApplication(app)
    }

    private func selectionTargetApplication() -> NSRunningApplication? {
        if let app = NSWorkspace.shared.frontmostApplication,
           isExternalApplication(app) {
            rememberExternalApplication(app)
            return app
        }
        if let app = lastExternalApplication,
           isExternalApplication(app) {
            return app
        }
        return nil
    }

    private func rememberExternalApplication(_ app: NSRunningApplication?) {
        guard let app, isExternalApplication(app) else { return }
        lastExternalApplication = app
    }

    private func isExternalApplication(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated,
              app.processIdentifier != pid_t(ProcessInfo.processInfo.processIdentifier) else {
            return false
        }
        if let bundleIdentifier = app.bundleIdentifier,
           bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }
        return true
    }

    @discardableResult
    func applyRuntimePreferences() -> String? {
        applyTheme()
        applyProxy()
        applyWindowPreferences()
        translator.applyVisualPreferences()
        let hotKeyWarning = hotKeys.start()
        let serverWarning = applyHTTPServerPreference()
        configureWebDAVHistoryAutoSync()
        buildMenuBar()
        let loginWarning = applyLaunchAtLoginPreference()
        let warning = [hotKeyWarning, serverWarning, loginWarning]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "；")
        return warning.isEmpty ? nil : warning
    }

    @discardableResult
    private func applyLaunchAtLoginPreference() -> String? {
        let shouldLaunch = Preferences.shared.launchAtLogin
        let service = SMAppService.mainApp
        do {
            if shouldLaunch {
                switch service.status {
                case .enabled:
                    return nil
                case .requiresApproval:
                    return "开机启动需要在系统设置登录项中批准"
                default:
                    try service.register()
                    return service.status == .requiresApproval ? "开机启动需要在系统设置登录项中批准" : nil
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return nil
        } catch {
            return "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    private func scheduleStartupUpdateCheck() {
        guard Preferences.shared.checkUpdate else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.checkForUpdatesOnStartup()
        }
    }

    private func scheduleStartupHistorySync() {
        guard PythiaBackupService.canAutoSyncHistory() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.runWebDAVHistorySync(reason: "启动同步")
        }
    }

    private func configureWebDAVHistoryAutoSync() {
        webDAVHistorySyncTimer?.invalidate()
        webDAVHistorySyncTimer = nil
        webDAVHistorySyncDebounce?.cancel()
        webDAVHistorySyncDebounce = nil
        guard PythiaBackupService.canAutoSyncHistory() else { return }
        let interval = TimeInterval(Preferences.shared.webdavHistorySyncIntervalSeconds)
        webDAVHistorySyncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runWebDAVHistorySync(reason: "自动同步")
        }
        if let timer = webDAVHistorySyncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func observeHistoryChangesForSync() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyChangedForSync(_:)),
            name: .historyChanged,
            object: nil
        )
    }

    @objc private func historyChangedForSync(_ notification: Notification) {
        scheduleDebouncedHistorySync()
    }

    private func scheduleDebouncedHistorySync() {
        guard PythiaBackupService.canAutoSyncHistory(), !isWebDAVHistorySyncRunning else { return }
        webDAVHistorySyncDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runWebDAVHistorySync(reason: "历史变更同步")
        }
        webDAVHistorySyncDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }

    private func runWebDAVHistorySync(reason: String, waitUntilFinished: Bool = false) {
        let preferences = Preferences.shared
        guard PythiaBackupService.canAutoSyncHistory() else { return }
        guard !isWebDAVHistorySyncRunning else { return }
        let url = preferences.webdavURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        isWebDAVHistorySyncRunning = true
        translator.setStatus("\(reason)中...")
        let semaphore = DispatchSemaphore(value: 0)
        PythiaBackupService.syncHistoryToWebDAV(
            base: url,
            user: preferences.webdavUsername,
            password: preferences.webdavPassword
        ) { [weak self] result in
            let updateUI = {
                guard let self else { return }
                self.isWebDAVHistorySyncRunning = false
                self.translator.setStatus(result.isSuccess ? "\(reason)完成" : "\(reason)失败")
            }
            if waitUntilFinished {
                semaphore.signal()
                DispatchQueue.main.async(execute: updateUI)
            } else {
                DispatchQueue.main.async {
                    updateUI()
                    semaphore.signal()
                }
            }
        }
        if waitUntilFinished {
            _ = semaphore.wait(timeout: .now() + 20)
        }
    }

    private func checkForUpdatesOnStartup() {
        PythiaUpdateChecker.shared.check { result in
            DispatchQueue.main.async {
                guard case .success(let info) = result, info.isNewer else { return }
                guard Preferences.shared.lastNotifiedUpdateVersion != info.latestVersion else {
                    self.translator.setStatus("发现新版本 \(info.latestVersion)")
                    return
                }
                Preferences.shared.lastNotifiedUpdateVersion = info.latestVersion
                let alert = NSAlert()
                alert.messageText = "Pythia 有新版本 \(info.latestVersion)"
                alert.informativeText = "当前版本：\(info.currentVersion)\n发布版本：\(info.releaseName)"
                alert.addButton(withTitle: "打开发布页")
                alert.addButton(withTitle: "稍后")
                if alert.runModal() == .alertFirstButtonReturn, let url = info.releaseURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func applyTheme() {
        switch Preferences.shared.theme {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
        NSApp.windows.forEach { window in
            window.contentView?.needsDisplay = true
            window.contentView?.subviews.forEach { $0.needsDisplay = true }
        }
    }

    private func applyProxy() {
        let preferences = Preferences.shared
        guard preferences.proxyEnabled, !preferences.proxyHost.isEmpty, !preferences.proxyPort.isEmpty else {
            unsetenv("http_proxy")
            unsetenv("https_proxy")
            unsetenv("all_proxy")
            unsetenv("no_proxy")
            unsetenv("NO_PROXY")
            return
        }
        let proxy = "http://\(preferences.proxyHost):\(preferences.proxyPort)"
        setenv("http_proxy", proxy, 1)
        setenv("https_proxy", proxy, 1)
        setenv("all_proxy", proxy, 1)
        let noProxy = preferences.noProxy.trimmingCharacters(in: .whitespacesAndNewlines)
        if noProxy.isEmpty {
            unsetenv("no_proxy")
            unsetenv("NO_PROXY")
        } else {
            setenv("no_proxy", noProxy, 1)
            setenv("NO_PROXY", noProxy, 1)
        }
    }

    private func applyWindowPreferences() {
        translator.window?.level = Preferences.shared.translateAlwaysOnTop ? .floating : .normal
    }

    private func configureHotKeys() {
        hotKeys.onTranslateSelection = { [weak self] in self?.translateSelection() }
        hotKeys.onInputTranslate = { [weak self] in self?.showInputTranslator() }
        hotKeys.onOCR = { [weak self] in
            self?.translator.showAndFocus()
            self?.translator.recognizeScreen(translateAfterRecognition: true)
        }
        hotKeys.onOCRRecognize = { [weak self] in
            self?.translator.showAndFocus()
            self?.translator.recognizeScreen(translateAfterRecognition: false)
        }
        hotKeys.start()
    }

    private func configureHTTPServer() {
        httpServer.onTranslateRequest = { [weak self] text, completion in
            guard let self else { completion(.failure(TranslationError.requestFailed("app unavailable"))); return }
            self.translator.showAndFocus(with: text)
            self.translator.translate(text, completion: completion)
        }
        httpServer.onSelectionTranslate = { [weak self] in self?.translateSelection() }
        httpServer.onInputTranslate = { [weak self] in self?.showInputTranslator() }
        httpServer.onOCRRecognize = { [weak self] in
            self?.translator.showAndFocus()
            self?.translator.recognizeScreen(translateAfterRecognition: false)
        }
        httpServer.onOCRTranslate = { [weak self] in
            self?.translator.showAndFocus()
            self?.translator.recognizeScreen(translateAfterRecognition: true)
        }
        httpServer.onConfig = { [weak self] in self?.showSettings() }
        applyHTTPServerPreference()
    }

    @discardableResult
    private func applyHTTPServerPreference() -> String? {
        let rawPort = Preferences.shared.serverPort
        guard (1...65_535).contains(rawPort), let port = UInt16(exactly: rawPort) else {
            Preferences.shared.serverPort = 60828
            let startWarning = httpServer.start(port: 60828)
            return startWarning.map { "外部服务端口无效，已恢复为 60828；\($0)" } ?? "外部服务端口无效，已恢复为 60828"
        }
        return httpServer.start(port: port)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        statusItem.menu = nil
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }

    @objc func showTranslator() {
        translator.showAndFocus()
    }

    @objc func inputTranslateMenu() {
        showInputTranslator()
    }

    func showInputTranslator() {
        translator.showForInputTranslation()
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            openStatusMenu(from: sender)
            return
        }
        switch Preferences.shared.trayClickEvent {
        case "config":
            showSettings()
        case "history":
            showHistory()
        default:
            translator.showAndFocus()
        }
    }

    func openStatusMenu(from sender: NSStatusBarButton) {
        statusItem.menu = statusMenu
        sender.performClick(nil)
    }

    @objc func selectionMenu() {
        translateSelection()
    }

    @objc func ocrMenu() {
        translator.showAndFocus()
        translator.recognizeScreen(translateAfterRecognition: true)
    }

    @objc func ocrRecognizeMenu() {
        translator.showAndFocus()
        translator.recognizeScreen(translateAfterRecognition: false)
    }

    @objc func speakResult() {
        translator.speakResult()
    }

    @objc func collectionMenu() {
        translator.addCurrentResultToCollection()
    }

    @objc func historyMenu() {
        NSApp.activate(ignoringOtherApps: true)
        showHistory()
    }

    @objc func toggleClipboard() {
        Preferences.shared.clipboardMonitoring.toggle()
        applyClipboardPreference()
    }

    @objc func settingsMenu() {
        NSApp.activate(ignoringOtherApps: true)
        showSettings()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

@main
enum PythiaMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = PythiaAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
