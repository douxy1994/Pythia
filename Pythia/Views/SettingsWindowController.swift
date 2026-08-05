import AppKit
import Foundation
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let tabTitles = ["通用", "翻译", "服务", "OCR", "TTS", "生词本", "插件", "快捷键", "历史", "代理", "备份", "迁移", "关于"]
    private let tabSymbols = [
        "slider.horizontal.3", "character.book.closed", "server.rack", "viewfinder",
        "speaker.wave.2", "book.closed", "puzzlepiece.extension", "keyboard",
        "clock.arrow.circlepath", "network", "externaldrive", "arrow.triangle.2.circlepath",
        "info.circle",
    ]
    private let tabSubtitles = [
        "语言、外观与日常使用体验。",
        "翻译行为、窗口与服务管理。",
        "API 密钥、模型与服务连通性。",
        "截图识别服务与 OCR 行为。",
        "文字转语音与语音服务。",
        "管理生词本与收藏服务。",
        "安装、配置和维护 Pythia 插件。",
        "设置系统级快捷键。",
        "历史记录开关与存储行为。",
        "配置网络代理与免代理地址。",
        "本地导出和 WebDAV 同步。",
        "从旧版本导入配置与插件。",
        "版本信息、更新与项目链接。",
    ]
    private let sidebarStack = FlippedStackView()
    private var sidebarItems: [SettingsSidebarItemView] = []
    private var selectedSettingsIndex = 0
    // The settings workspace is a flat content plane. Only the About page
    // creates explicit content cards; navigation gets the system glass layer.
    private let tabCard = NSView()
    private var activeTabView: NSView?
    private var activeTabConstraints: [NSLayoutConstraint] = []
    private var isLoadingSettings = false
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let secondTargetLanguagePopup = NSPopUpButton()
    private let openAIKeyField = NSSecureTextField()
    private let openAINameField = NSTextField()
    private let openAIBaseURLField = NSTextField()
    private let openAICompatibleAPIPopup = NSPopUpButton()
    private let openAIModelField = NSTextField()
    private let deepLKeyField = NSSecureTextField()
    private let baiduAppIDField = NSTextField()
    private let baiduSecretField = NSSecureTextField()
    private let youdaoAppKeyField = NSTextField()
    private let youdaoSecretField = NSSecureTextField()
    private let libreURLField = NSTextField()
    private let libreKeyField = NSSecureTextField()
    private let pluginPopup = NSPopUpButton()
    private let pluginPathLabel = NSTextField(labelWithString: PluginManager.shared.pluginsDirectory.path)
    private let pluginMetadataLabel = NSTextField(wrappingLabelWithString: "")
    private let pluginConfigStack = FullWidthStackView()
    private let pluginTestResultLabel = NSTextField(labelWithString: "")
    private let pluginListStack = FullWidthStackView()
    private var pluginListFields: [String: [NSControl]] = [:]
    private var pluginListStatusLabels: [String: NSTextField] = [:]
    private var pluginListDetails: [String: NSView] = [:]
    private var pluginListDisclosureButtons: [String: NSButton] = [:]
    private var expandedPluginNames = Set<String>()
    private let serviceTestResultLabel = NSTextField(labelWithString: "")
    private let clipboardCheckbox = NSButton(checkboxWithTitle: "监听剪贴板", target: nil, action: nil)
    private let compactTranslationWindowCheckbox = NSButton(checkboxWithTitle: "划词翻译或截图 OCR 翻译时默认打开简约窗口", target: nil, action: nil)
    private let floatingSelectionButtonCheckbox = NSButton(checkboxWithTitle: "实验性悬浮划词按钮（默认关闭）", target: nil, action: nil)
    private let recognizeLanguagePopup = NSPopUpButton()
    private let recognizeAutoCopyCheckbox = NSButton(checkboxWithTitle: "OCR 后自动复制", target: nil, action: nil)
    private let recognizeDeleteNewlineCheckbox = NSButton(checkboxWithTitle: "识别结果删除换行", target: nil, action: nil)
    private let hotkeySelectionField = HotkeyRecorderField()
    private let hotkeyInputField = HotkeyRecorderField()
    private let hotkeyOCRTranslateField = HotkeyRecorderField()
    private let hotkeyOCRRecognizeField = HotkeyRecorderField()
    private let proxyEnabledCheckbox = NSButton(checkboxWithTitle: "启用代理", target: nil, action: nil)
    private let proxyHostField = NSTextField()
    private let proxyPortField = NSTextField()
    private let themePopup = NSPopUpButton()
    private let themeColorWell = NSColorWell()
    private let serviceOrderList = ServiceOrderListView()
    private let recognizeServiceList = ServiceOrderListView()
    private let ttsServiceList = ServiceOrderListView()
    private let collectionServiceList = ServiceOrderListView()
    private let autoCopyPopup = NSPopUpButton()
    private let windowPositionPopup = NSPopUpButton()
    private let closeOnBlurCheckbox = NSButton(checkboxWithTitle: "翻译窗口失焦后关闭", target: nil, action: nil)
    private let alwaysOnTopCheckbox = NSButton(checkboxWithTitle: "翻译窗口总在最前", target: nil, action: nil)
    private let rememberWindowSizeCheckbox = NSButton(checkboxWithTitle: "记住翻译窗口尺寸", target: nil, action: nil)
    private var autosaveWorkItem: DispatchWorkItem?
    private var aboutCheckButton: NSButton?
    private let updateBanner = PythiaTopInfoBannerView()
    private var updateBannerDismissWorkItem: DispatchWorkItem?
    private var updateBannerGeneration = 0
    // Translate behavior (aligned with original Pot)
    private let translateDeleteNewlineCheckbox = NSButton(checkboxWithTitle: "翻译结果删除换行", target: nil, action: nil)
    private let smartTargetCheckbox = NSButton(checkboxWithTitle: "自动检测时智能选择目标语言", target: nil, action: nil)
    private let hideSourceCheckbox = NSButton(checkboxWithTitle: "隐藏原文输入框", target: nil, action: nil)
    private let hideLanguageCheckbox = NSButton(checkboxWithTitle: "隐藏语言栏", target: nil, action: nil)
    private let dynamicTranslateCheckbox = NSButton(checkboxWithTitle: "动态翻译（输入时自动翻译）", target: nil, action: nil)
    private let incrementalTranslateCheckbox = NSButton(checkboxWithTitle: "增量翻译", target: nil, action: nil)
    // Appearance / general
    private let appFontField = NSTextField()
    private let appFontSizeField = NSTextField()
    private let appFallbackFontField = NSTextField()
    private let trayClickPopup = NSPopUpButton()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "开机时启动 Pythia", target: nil, action: nil)
    private let checkUpdateCheckbox = NSButton(checkboxWithTitle: "启动时检查更新", target: nil, action: nil)
    private let serverPortField = NSTextField()
    // History
    private let historyDisableCheckbox = NSButton(checkboxWithTitle: "关闭历史记录", target: nil, action: nil)
    // OCR extra
    private let recognizeHideWindowCheckbox = NSButton(checkboxWithTitle: "识别后隐藏窗口", target: nil, action: nil)
    private let recognizeCloseOnBlurCheckbox = NSButton(checkboxWithTitle: "OCR 结果窗口失焦后关闭", target: nil, action: nil)
    // Proxy extra
    private let proxyUsernameField = NSTextField()
    private let proxyPasswordField = NSSecureTextField()
    private let noProxyField = NSTextField()
    // Backup extra
    private let backupTypePopup = NSPopUpButton()
    private let webdavURLField = NSTextField()
    private let webdavUsernameField = NSTextField()
    private let webdavPasswordField = NSSecureTextField()
    private let webdavHistoryAutoSyncCheckbox = NSButton(checkboxWithTitle: "自动同步历史记录", target: nil, action: nil)
    private let webdavHistorySyncIntervalField = NSTextField()
    private let webdavHistorySyncIntervalUnitPopup = NSPopUpButton()
    private let webdavHistorySyncStatusLabel = NSTextField(labelWithString: "")
    /// The WebDAV-specific rows (address/username/password/test result),
    /// shown only when 备份方式 = WebDAV.
    private var webdavRows: [NSView] = []
    /// The WebDAV action button row, shown only when 备份方式 = WebDAV.
    private var webdavActionButtons: NSView?
    /// The local backup/export button row, shown only when 备份方式 = 本地.
    private var localActionButtons: NSView?
    /// Note shown only in 本地 mode.
    private var localNoteRow: NSView?
    /// Note shown only in WebDAV mode.
    private var webdavNoteRow: NSView?
    /// Result label for the WebDAV connectivity test.
    private let webdavTestResultLabel = NSTextField(labelWithString: "")

    init() {
        let window = StableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pythia 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 660)
        window.setContentSize(NSSize(width: 1080, height: 720))
        super.init(window: window)
        window.stableMinWidth = 1080
        window.delegate = self
        recognizeServiceList.optionProvider = { PluginManager.shared.serviceOptions(for: "recognize") }
        ttsServiceList.optionProvider = { PluginManager.shared.serviceOptions(for: "tts") }
        collectionServiceList.optionProvider = { PluginManager.shared.serviceOptions(for: "collection") }
        for list in [serviceOrderList, recognizeServiceList, ttsServiceList, collectionServiceList] {
            list.onChange = { [weak self] _ in self?.scheduleAutosave() }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editableControlDidEndEditing(_:)),
            name: NSControl.textDidEndEditingNotification,
            object: nil
        )
        configureSettingsLanguagePopup(secondTargetLanguagePopup, includeAuto: false)
        buildUI()
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        // The content view must fill the window frame so its subviews stretch
        // when the user resizes. NSWindow otherwise shrinks the content view to
        // its subviews' fitting size. Pin the content view to the window's
        // contentLayoutGuide on all four edges so it always tracks the frame.
        content.translatesAutoresizingMaskIntoConstraints = false
        if let guide = window?.contentLayoutGuide as? NSLayoutGuide {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                content.topAnchor.constraint(equalTo: guide.topAnchor),
                content.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            ])
        }

        let background = LiquidGlassBackgroundView()
        background.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Match the macOS 27 / ChatGPT settings composition: one full-height
        // system sidebar layer, no inset card, no custom border or corner
        // treatment. AppKit adapts `.sidebar` to the current system appearance.
        let sidebarMaterial = NSVisualEffectView()
        sidebarMaterial.translatesAutoresizingMaskIntoConstraints = false
        sidebarMaterial.material = .sidebar
        sidebarMaterial.blendingMode = .withinWindow
        sidebarMaterial.state = .active
        content.addSubview(sidebarMaterial)

        let sidebarDivider = NSView()
        sidebarDivider.translatesAutoresizingMaskIntoConstraints = false
        sidebarDivider.wantsLayer = true
        sidebarDivider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        content.addSubview(sidebarDivider)

        let sidebarTitle = NSTextField(labelWithString: "设置")
        sidebarTitle.translatesAutoresizingMaskIntoConstraints = false
        sidebarTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        sidebarTitle.textColor = .labelColor
        sidebarMaterial.addSubview(sidebarTitle)

        let sidebarScroll = NSScrollView()
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.hasHorizontalScroller = false
        sidebarScroll.drawsBackground = false
        sidebarScroll.borderType = .noBorder
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .width
        sidebarStack.spacing = 4
        sidebarStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.documentView = sidebarStack
        sidebarMaterial.addSubview(sidebarScroll)
        buildSidebarItems()

        // Keep the workspace surface flat. About is the only page that creates
        // explicit content cards; regular settings pages stay on this plane.
        tabCard.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabCard)
        showTab(index: 0)

        updateBanner.translatesAutoresizingMaskIntoConstraints = false
        updateBanner.isHidden = true
        updateBanner.onDismiss = { [weak self] in
            self?.dismissUpdateBanner()
        }
        content.addSubview(updateBanner)

        NSLayoutConstraint.activate([
            sidebarMaterial.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebarMaterial.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarMaterial.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            // Keep the navigation column compact like ChatGPT's settings
            // sidebar; the content grid gets the reclaimed width.
            sidebarMaterial.widthAnchor.constraint(equalToConstant: 248),

            sidebarDivider.leadingAnchor.constraint(equalTo: sidebarMaterial.trailingAnchor),
            sidebarDivider.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarDivider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarDivider.widthAnchor.constraint(equalToConstant: 1),

            sidebarTitle.leadingAnchor.constraint(equalTo: sidebarMaterial.leadingAnchor, constant: 18),
            sidebarTitle.trailingAnchor.constraint(equalTo: sidebarMaterial.trailingAnchor, constant: -18),
            sidebarTitle.topAnchor.constraint(equalTo: sidebarMaterial.topAnchor, constant: 18),

            sidebarScroll.leadingAnchor.constraint(equalTo: sidebarMaterial.leadingAnchor, constant: 8),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebarMaterial.trailingAnchor, constant: -8),
            sidebarScroll.topAnchor.constraint(equalTo: sidebarTitle.bottomAnchor, constant: 16),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebarMaterial.bottomAnchor, constant: -10),
            sidebarStack.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor),
            sidebarStack.heightAnchor.constraint(greaterThanOrEqualTo: sidebarScroll.contentView.heightAnchor),

            tabCard.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
            tabCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            tabCard.topAnchor.constraint(equalTo: sidebarMaterial.topAnchor),
            tabCard.bottomAnchor.constraint(equalTo: sidebarMaterial.bottomAnchor),

            updateBanner.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            updateBanner.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            updateBanner.widthAnchor.constraint(equalToConstant: 680),
            updateBanner.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            updateBanner.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            updateBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    private func buildSidebarItems() {
        sidebarStack.arrangedSubviews.forEach { item in
            sidebarStack.removeArrangedSubview(item)
            item.removeFromSuperview()
        }
        sidebarItems = tabTitles.enumerated().map { index, title in
            SettingsSidebarItemView(
                title: title,
                symbolName: tabSymbols[index],
                index: index,
                target: self,
                action: #selector(sidebarItemClicked(_:))
            )
        }
        sidebarItems.forEach { item in
            sidebarStack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        }
        updateSidebarSelection()
    }

    private func updateSidebarSelection() {
        sidebarItems.forEach { item in
            item.isActive = item.index == selectedSettingsIndex
        }
    }

    @objc private func sidebarItemClicked(_ sender: SettingsSidebarItemView) {
        autosaveWorkItem?.cancel()
        persistSettings()
        showTab(index: sender.index)
    }

    private func generalTab() -> NSView {
        let stack = formStack()
        configureSettingsLanguagePopup(sourceLanguagePopup, includeAuto: true)
        configureSettingsLanguagePopup(targetLanguagePopup, includeAuto: false)
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: ["跟随系统", "浅色", "深色"])
        if #available(macOS 14.0, *) {
            themeColorWell.supportsAlpha = false
        }
        themeColorWell.target = self
        themeColorWell.action = #selector(themeColorChanged)
        trayClickPopup.removeAllItems()
        trayClickPopup.addItems(withTitles: ["显示设置", "显示翻译窗口", "显示历史记录"])
        trayClickPopup.target = self
        trayClickPopup.action = #selector(trayClickEventChanged)
        autoCopyPopup.removeAllItems()
        autoCopyPopup.addItems(withTitles: ["不自动复制", "复制原文", "复制译文", "复制原文和译文"])

        stack.addArrangedSubview(settingsSection(
            "翻译服务",
            icon: "square.stack.3d.up",
            detail: "主界面翻译会同时请求勾选的服务，并按此处顺序在译文区分组显示。",
            views: [row("已启用服务", serviceOrderList)]
        ))
        stack.addArrangedSubview(settingsSection(
            "外观与语言",
            icon: "paintbrush",
            views: [
                row("外观", themePopup),
                row("主题色", themeColorWell),
                row("界面字体", appFontField),
                row("界面字号", appFontSizeField),
                row("回退字体", appFallbackFontField),
                row("源语言", sourceLanguagePopup),
                row("目标语言", targetLanguagePopup),
            ]
        ))
        stack.addArrangedSubview(settingsSection(
            "日常使用",
            icon: "hand.tap",
            views: [
                row("自动复制", autoCopyPopup),
                indented(clipboardCheckbox),
                indented(compactTranslationWindowCheckbox),
                indented(floatingSelectionButtonCheckbox),
                note("启用后，在 Word、PDF、网页和聊天软件中拖选文字会显示小型 Pythia 图标；图标不抢占焦点，点击后读取选区并打开简约翻译窗口，5 秒后自动隐藏。"),
                row("托盘点击", trayClickPopup),
            ]
        ))

        // System permissions (辅助功能 / 屏幕录制) only need to be requested once;
        // keep the action here in 通用 instead of in the always-visible footer.
        let permButtons = NSStackView()
        permButtons.orientation = .horizontal
        permButtons.spacing = 10
        permButtons.addArrangedSubview(PillButton("请求辅助功能与屏幕录制权限", target: self, action: #selector(requestPermissions)))
        stack.addArrangedSubview(settingsSection(
            "启动与系统集成",
            icon: "power",
            detail: "开机启动使用 macOS 登录项注册；外部服务端口用于本地 API 调用。",
            views: [
                indented(launchAtLoginCheckbox),
                indented(checkUpdateCheckbox),
                row("外部服务端口", serverPortField),
                leadingFullWidth(permButtons, minHeight: 0),
                note("点击后请在系统设置中允许「辅助功能」（划词翻译需要）；截图 OCR 还需要「屏幕录制」权限。"),
            ]
        ))
        return stack
    }

    private func translateTab() -> NSView {
        let stack = formStack()
        configureSettingsLanguagePopup(secondTargetLanguagePopup, includeAuto: false)
        windowPositionPopup.removeAllItems()
        windowPositionPopup.addItems(withTitles: ["居中", "鼠标附近", "记住位置"])
        let svcButtons = NSStackView()
        svcButtons.orientation = .horizontal
        svcButtons.spacing = 10
        svcButtons.addArrangedSubview(PillButton("+ 添加自定义服务 ID", target: self, action: #selector(addCustomServiceID)))
        svcButtons.addArrangedSubview(PillButton("重置为内置服务", target: self, action: #selector(resetTranslateServices)))
        stack.addArrangedSubview(settingsSection(
            "服务管理",
            icon: "square.stack.3d.up",
            detail: "自定义服务只需填写一个稳定 ID；服务启用和排序请在「通用」页调整。",
            views: [
                leadingFullWidth(svcButtons, minHeight: 0),
                note("自定义 ID 示例：plugin:custom-name。"),
            ]
        ))
        stack.addArrangedSubview(settingsSection(
            "翻译行为",
            icon: "text.bubble",
            detail: "这些选项与原版 Pot 保持一致。",
            views: [
                indented(translateDeleteNewlineCheckbox),
                indented(smartTargetCheckbox),
                row("第二目标语言", secondTargetLanguagePopup),
                note("启用智能目标语言时，自动检测到中文会翻译到第二目标语言；检测到非中文会翻译到通用页的目标语言；中英文混合内容仍以当前目标语言为准。"),
                indented(hideSourceCheckbox),
                indented(hideLanguageCheckbox),
                indented(dynamicTranslateCheckbox),
                indented(incrementalTranslateCheckbox),
            ]
        ))
        stack.addArrangedSubview(settingsSection(
            "翻译窗口",
            icon: "macwindow",
            views: [
                row("翻译窗口位置", windowPositionPopup),
                indented(closeOnBlurCheckbox),
                indented(alwaysOnTopCheckbox),
                indented(rememberWindowSizeCheckbox),
            ]
        ))
        return stack
    }

    private func servicesTab() -> NSView {
        let stack = formStack()
        openAICompatibleAPIPopup.removeAllItems()
        openAICompatibleAPIPopup.addItems(withTitles: ["OpenAI", "Anthropic"])
        let verifyButtons = NSStackView()
        verifyButtons.orientation = .horizontal
        verifyButtons.spacing = 10
        for (title, identifier) in [
            ("验证 OpenAI", "OpenAI"),
            ("验证 DeepL", "DeepL"),
            ("验证 百度", "Baidu"),
            ("验证 有道", "Youdao"),
            ("验证 LibreTranslate", "LibreTranslate"),
        ] {
            let button = PillButton(title, target: self, action: #selector(verifyBuiltInService(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(identifier)
            verifyButtons.addArrangedSubview(button)
        }
        serviceTestResultLabel.lineBreakMode = .byTruncatingTail
        serviceTestResultLabel.maximumNumberOfLines = 1
        serviceTestResultLabel.font = .systemFont(ofSize: 12)
        let serviceResultCaption = NSTextField(labelWithString: "检测结果：")
        serviceResultCaption.font = .systemFont(ofSize: 12)
        serviceResultCaption.textColor = .secondaryLabelColor
        let serviceResultBox = NSStackView()
        serviceResultBox.orientation = .horizontal
        serviceResultBox.alignment = .firstBaseline
        serviceResultBox.spacing = 6
        serviceResultBox.addArrangedSubview(serviceResultCaption)
        serviceResultBox.addArrangedSubview(serviceTestResultLabel)
        stack.addArrangedSubview(settingsSection(
            "自定义大模型 API",
            icon: "key",
            detail: "大模型翻译服务可连接 OpenAI Chat Completions 或 Anthropic Messages 兼容接口；长文档自动安全分段，密钥只写入本地凭据文件。",
            views: [
                row("显示名称", openAINameField),
                row("接口类型", openAICompatibleAPIPopup),
                row("API 基础地址", openAIBaseURLField),
                row("模型", openAIModelField),
                row("API Key", openAIKeyField),
            ]
        ))
        stack.addArrangedSubview(settingsSection(
            "其它服务凭据",
            icon: "key.fill",
            detail: "密钥只写入 Pythia 的本地凭据文件，不进入普通设置 JSON。",
            views: [
                row("DeepL API key", deepLKeyField),
                row("百度 AppID", baiduAppIDField),
                row("百度密钥", baiduSecretField),
                row("有道 AppKey", youdaoAppKeyField),
                row("有道密钥", youdaoSecretField),
                row("LibreTranslate URL", libreURLField),
                row("LibreTranslate Key", libreKeyField),
            ]
        ))
        stack.addArrangedSubview(settingsSection(
            "验证服务",
            icon: "checkmark.shield",
            detail: "填写上方 Key 后点击按钮，会按当前输入保存并发起一次真实翻译测试。",
            views: [
                leadingFullWidth(verifyButtons, minHeight: 0),
                leadingFullWidth(serviceResultBox, minHeight: 0),
                note("自定义大模型 API / DeepL / 百度 / 有道 / LibreTranslate 均需自行配置 API Key；基础地址可填写服务根地址、/v1 地址或完整请求端点。Google 与「本地预览」无需 Key。"),
            ]
        ))
        return stack
    }

    private func ocrTab() -> NSView {
        let stack = formStack()
        configureSettingsLanguagePopup(recognizeLanguagePopup, includeAuto: true)
        stack.addArrangedSubview(settingsSection(
            "OCR 服务",
            icon: "viewfinder",
            detail: "内置系统 OCR 使用 macOS Vision；旧版 recognize 插件会在导入或安装后自动列在这里。",
            views: [row("已启用服务", recognizeServiceList)]
        ))
        stack.addArrangedSubview(settingsSection(
            "识别行为",
            icon: "text.viewfinder",
            views: [
                row("OCR 语言", recognizeLanguagePopup),
                indented(recognizeAutoCopyCheckbox),
                indented(recognizeDeleteNewlineCheckbox),
                indented(recognizeHideWindowCheckbox),
                indented(recognizeCloseOnBlurCheckbox),
                note("截图 OCR 会按上方启用顺序逐个尝试：系统 OCR 和旧版 recognize 插件都可参与；某个服务失败或返回空结果时会自动尝试下一个。"),
            ]
        ))
        return stack
    }

    private func ttsTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(settingsSection(
            "TTS 服务",
            icon: "speaker.wave.2",
            detail: "内置 macOS Speech 会按目标语言自动选择系统语音；旧版 TTS 插件会在导入或安装后自动列在这里。",
            showsHeader: false,
            views: [row("已启用服务", ttsServiceList)]
        ))
        return stack
    }

    private func collectionTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(settingsSection(
            "生词本服务",
            icon: "book.closed",
            detail: "旧版 collection 插件会在导入或安装后自动列在这里。服务启用和顺序会随配置备份/恢复。",
            showsHeader: false,
            views: [row("已启用服务", collectionServiceList)]
        ))
        return stack
    }

    private func pluginsTab() -> NSView {
        let stack = formStack()

        let installButtons = NSStackView()
        installButtons.orientation = .horizontal
        installButtons.spacing = 10
        installButtons.addArrangedSubview(PillButton("安装插件", target: self, action: #selector(installPlugin)))
        installButtons.addArrangedSubview(PillButton("打开插件目录", target: self, action: #selector(openPluginFolder)))
        installButtons.addArrangedSubview(PillButton("刷新列表", target: self, action: #selector(refreshPlugins)))
        installButtons.addArrangedSubview(PillButton("插件开发指南", target: self, action: #selector(openPluginDevelopmentGuide)))
        stack.addArrangedSubview(settingsSection(
            "安装插件",
            icon: "square.and.arrow.down",
            detail: "支持 .pythia 和 .potext 格式；安装后所有插件都会在下方列表中显示。",
            views: [leadingFullWidth(installButtons, minHeight: 0)]
        ))

        // Keep the popup/config fields alive for existing migration and load
        // paths, but make the list the only visible plugin management surface.
        rebuildPluginPopup()
        pluginListStack.orientation = .vertical
        pluginListStack.alignment = .width
        pluginListStack.spacing = 0
        pluginListStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        pluginListStack.translatesAutoresizingMaskIntoConstraints = false
        rebuildPluginList()

        stack.addArrangedSubview(settingsSection(
            "已安装插件",
            icon: "puzzlepiece.extension",
            detail: "全部已安装插件按列表展示；点击左侧箭头展开二级配置，右侧垃圾桶可直接删除。",
            alignBodyToHeaderText: false,
            // Give the nested list an explicit leading/trailing constraint
            // chain. A bare nested NSStackView has no intrinsic width, which
            // was the source of the right-shifted/zero-height plugin section.
            // Keep the list itself away from the scroll indicator. The outer
            // settings scroll view also reserves a small trailing inset for
            // every page; this extra inset keeps the expanded plugin fields
            // from visually running into the indicator as well.
            views: [leadingFullWidth(pluginListStack, trailingInset: 14, minHeight: 0)]
        ))
        return stack
    }

    private func rebuildPluginList() {
        pluginListStack.arrangedSubviews.forEach {
            pluginListStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        pluginListFields.removeAll()
        pluginListStatusLabels.removeAll()
        pluginListDetails.removeAll()
        pluginListDisclosureButtons.removeAll()

        let plugins = PluginManager.shared.plugins()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let currentNames = Set(plugins.map(\.name))
        expandedPluginNames.formIntersection(currentNames)

        guard !plugins.isEmpty else {
            pluginListStack.addArrangedSubview(note("尚未安装插件。点击上方「安装插件」选择 .pythia 或 .potext 文件。"))
            return
        }
        plugins.forEach { plugin in
            pluginListStack.addArrangedSubview(pluginListItem(for: plugin))
        }
    }

    private func pluginListItem(for plugin: CommandPlugin) -> NSView {
        // Plugin rows are a flat list, not nested cards. A separator keeps
        // rows readable without adding another rounded container.
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let isExpanded = expandedPluginNames.contains(plugin.name)
        let disclosure = GlassIconButton(
            systemName: isExpanded ? "chevron.down" : "chevron.right",
            accessibility: isExpanded ? "收起 \(plugin.title)" : "展开 \(plugin.title)",
            target: self,
            action: #selector(togglePluginDisclosure(_:)),
            width: 18
        )
        disclosure.identifier = NSUserInterfaceItemIdentifier(plugin.name)
        disclosure.toolTip = isExpanded ? "收起插件配置" : "展开插件配置"

        let titleLabel = NSTextField(labelWithString: plugin.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = PythiaDesign.themeColor()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let format = plugin.packageFormat ?? (plugin.legacyType == nil ? "command" : "potext")
        var summaryParts = [".\(format)"]
        if let version = plugin.packageVersion, !version.isEmpty {
            summaryParts.append("v\(version)")
        }
        if let author = plugin.packageAuthor, !author.isEmpty {
            summaryParts.append(author)
        }
        let needsCount = PluginManager.shared.pluginNeeds(forPluginName: plugin.name).count
        summaryParts.append(needsCount == 0 ? "无配置项" : "\(needsCount) 项配置")
        let summaryLabel = NSTextField(labelWithString: summaryParts.joined(separator: "  ·  "))
        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, summaryLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let deleteButton = GlassIconButton(
            systemName: "trash",
            accessibility: "删除 \(plugin.title)",
            target: self,
            action: #selector(deletePluginFromList(_:))
        )
        deleteButton.identifier = NSUserInterfaceItemIdentifier(plugin.name)
        deleteButton.contentTintColor = .systemRed
        deleteButton.toolTip = "删除插件"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [disclosure, textStack, spacer, deleteButton])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        // The disclosure control is the list's leading icon. Keep its visual
        // center on the same vertical grid as the section/page icons; the
        // title text then starts on the same column as the section title.
        header.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 10)
        header.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let detail = FullWidthStackView()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.orientation = .vertical
        detail.alignment = .width
        detail.spacing = 9
        // Detail text and action buttons share the title text column rather
        // than inheriting an extra, unrelated indentation from the arrow.
        // FullWidthStackView pins arranged views to its own width, so apply
        // this inset explicitly to each detail row instead of relying only
        // on NSStackView.edgeInsets.
        detail.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 14, right: 18)
        detail.isHidden = !isExpanded

        let detailText = PluginManager.shared.pluginDetails(forPluginName: plugin.name)
        if !detailText.isEmpty {
            detail.addArrangedSubview(pluginDetailAligned(note(detailText)))
        }
        let pluginPath = PluginManager.shared.legacyPluginDirectory(named: plugin.name)?.path
            ?? PluginManager.shared.pluginsDirectory.appendingPathComponent("\(plugin.name).pythia").path
        detail.addArrangedSubview(pluginDetailAligned(note("目录：\(pluginPath)")))

        let (configurationView, controls) = pluginConfigurationView(for: plugin.name)
        detail.addArrangedSubview(pluginDetailAligned(configurationView))

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        let testButton = PillButton("测试连通性", target: self, action: #selector(testPluginListConnection(_:)))
        testButton.identifier = NSUserInterfaceItemIdentifier(plugin.name)
        let renameButton = PillButton("重命名", target: self, action: #selector(renamePluginFromList(_:)))
        renameButton.identifier = NSUserInterfaceItemIdentifier(plugin.name)
        actions.addArrangedSubview(testButton)
        actions.addArrangedSubview(renameButton)

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actions.addArrangedSubview(statusLabel)
        detail.addArrangedSubview(pluginDetailAligned(actions))

        let content = FullWidthStackView(views: [header, detail])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 0
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            // FullWidthStackView's intrinsic-width alignment is intentionally
            // overridden here with required edge constraints. Without this,
            // an expanded plugin's detail stack can keep its fitting width and
            // drift to the right while the header still looks correct.
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detail.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        card.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])

        pluginListFields[plugin.name] = controls
        pluginListStatusLabels[plugin.name] = statusLabel
        pluginListDetails[plugin.name] = detail
        pluginListDisclosureButtons[plugin.name] = disclosure
        return card
    }

    private func pluginDetailAligned(_ control: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 26),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func pluginConfigurationView(for name: String) -> (NSView, [NSControl]) {
        let stack = FullWidthStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let needs = PluginManager.shared.pluginNeeds(forPluginName: name)
        guard !needs.isEmpty else {
            stack.addArrangedSubview(note("该插件没有配置项。"))
            return (stack, [])
        }

        let stored = PluginManager.shared.pluginConfig(forPluginName: name)
        var controls: [NSControl] = []
        for need in needs {
            guard let key = need["key"] as? String,
                  let display = need["display"] as? String
            else { continue }
            let type = (need["type"] as? String)?.lowercased() ?? "input"
            if type == "select", let options = need["options"] as? [String: String], !options.isEmpty {
                let popup = NSPopUpButton()
                let ordered = options.sorted { $0.key < $1.key }
                for (optionKey, label) in ordered {
                    let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                    item.representedObject = optionKey
                    popup.menu?.addItem(item)
                }
                let desired = stored[key] ?? (need["default"] as? String ?? "")
                if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == desired }) {
                    popup.select(item)
                } else if let first = popup.itemArray.first {
                    popup.select(first)
                }
                popup.identifier = NSUserInterfaceItemIdentifier(key)
                controls.append(popup)
                stack.addArrangedSubview(row(display, popup))
            } else {
                let field = ((need["secret"] as? Bool == true)
                    || PythiaPluginSecretPolicy.isLikelySecretKey(key))
                    ? NSSecureTextField() : NSTextField()
                field.stringValue = stored[key] ?? (need["default"] as? String ?? "")
                field.identifier = NSUserInterfaceItemIdentifier(key)
                field.placeholderString = display
                controls.append(field)
                stack.addArrangedSubview(row(display, field))
            }
        }
        return (stack, controls)
    }

    private func collectPluginConfig(for name: String) -> [String: String] {
        var config: [String: String] = [:]
        for control in pluginListFields[name] ?? [] {
            guard let key = control.identifier?.rawValue else { continue }
            if let popup = control as? NSPopUpButton {
                config[key] = (popup.selectedItem?.representedObject as? String) ?? ""
            } else if let field = control as? NSTextField {
                config[key] = field.stringValue
            }
        }
        return config
    }

    @objc private func togglePluginDisclosure(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue,
              let detail = pluginListDetails[name],
              let disclosure = pluginListDisclosureButtons[name],
              let plugin = PluginManager.shared.plugins().first(where: { $0.name == name })
        else { return }
        if expandedPluginNames.contains(name) {
            expandedPluginNames.remove(name)
            detail.isHidden = true
            disclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "展开 \(plugin.title)")
            disclosure.toolTip = "展开插件配置"
            disclosure.setAccessibilityLabel("展开 \(plugin.title)")
        } else {
            expandedPluginNames.insert(name)
            detail.isHidden = false
            disclosure.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "收起 \(plugin.title)")
            disclosure.toolTip = "收起插件配置"
            disclosure.setAccessibilityLabel("收起 \(plugin.title)")
        }
    }

    @objc private func testPluginListConnection(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue,
              let status = pluginListStatusLabels[name]
        else { return }
        var config = collectPluginConfig(for: name)
        if config["enable"] == nil { config["enable"] = "true" }
        do {
            try PluginManager.shared.setPluginConfig(config, forPluginName: name)
        } catch {
            status.stringValue = "保存失败：\(error.localizedDescription)"
            status.textColor = .systemRed
            return
        }
        status.stringValue = "检测中…"
        status.textColor = .secondaryLabelColor
        let serviceID = "plugin:\(name)"
        let type = PluginManager.shared.plugin(forServiceIdentifier: serviceID)?.legacyType ?? "translate"
        runPluginConnectionTest(serviceID: serviceID, type: type, resultLabel: status)
    }

    @objc private func deletePluginFromList(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue,
              let plugin = PluginManager.shared.plugins().first(where: { $0.name == name })
        else { return }
        deletePlugin(named: name, displayName: plugin.title)
    }

    @objc private func renamePluginFromList(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue,
              let plugin = PluginManager.shared.plugins().first(where: { $0.name == name })
        else { return }
        let alert = NSAlert()
        alert.messageText = "重命名插件"
        alert.informativeText = "只修改 Pythia 中显示的名称，不会改动插件目录、服务标识或已有配置。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = plugin.title
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            showAlert("插件名称不能为空。")
            return
        }
        PluginManager.shared.renamePluginDisplay(name: name, displayName: newName)
        expandedPluginNames.insert(name)
        refreshPlugins()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        pluginListStatusLabels[name]?.stringValue = "已重命名为 \(newName)"
        pluginListStatusLabels[name]?.textColor = PythiaDesign.themeColor()
    }

    @objc private func reconvertPluginFromList(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        do {
            let target = try PluginManager.shared.convertLegacyPlugin(name: name, replaceExisting: true)
            refreshPlugins()
            expandedPluginNames.insert(name)
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            showAlert("已重新转换为 \(target.lastPathComponent)。原 .potext 备份保持不变。")
        } catch {
            showAlert("重新转换失败，插件继续使用当前可用版本：\(error.localizedDescription)")
        }
    }

    /// The currently selected legacy plugin directory name (e.g. plugin.com.xiaomi.mimo).
    /// The plugin popup stores the directory name directly on each menu item's
    /// `representedObject` (see pluginsTab), so we read it straight from the
    /// selected item — no fragile title/index lookup involved.
    private var currentPluginName: String? {
        guard let item = pluginPopup.selectedItem,
              let dirName = item.representedObject as? String,
              !dirName.isEmpty
        else { return nil }
        return dirName
    }

    /// Rebuilds the plugin popup from current plugins, storing each
    /// plugin's stable id on the item's representedObject. Keeps the
    /// previously selected id if it still exists.
    private func rebuildPluginPopup() {
        let previouslySelectedDir = (pluginPopup.selectedItem?.representedObject as? String)
        pluginPopup.removeAllItems()
        let plugins = PluginManager.shared.plugins()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if plugins.isEmpty {
            pluginPopup.addItem(withTitle: "无")
            pluginPopup.selectedItem?.representedObject = nil
            return
        }
        for plugin in plugins {
            let format = plugin.packageFormat ?? (plugin.legacyType == nil ? "command" : "potext")
            let version = plugin.packageVersion.map { " \($0)" } ?? ""
            let item = NSMenuItem(
                title: "\(plugin.title) · \(format)\(version)",
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = plugin.name
            pluginPopup.menu?.addItem(item)
        }
        // Restore the previous selection by directory name (not title), else first.
        if let dir = previouslySelectedDir,
           let item = pluginPopup.itemArray.first(where: { ($0.representedObject as? String) == dir }) {
            pluginPopup.select(item)
        } else if let first = pluginPopup.itemArray.first {
            pluginPopup.select(first)
        }
    }

    @objc private func pluginSelectionChanged() {
        persistSettings()
        rebuildPluginConfigFields()
        pluginTestResultLabel.stringValue = ""
        updatePluginPathLabel()
    }

    /// Updates the "插件目录" label to the absolute path of the currently
    /// selected plugin's directory, so the user can see which plugin folder the
    /// shown config belongs to.
    private func updatePluginPathLabel() {
        if let name = currentPluginName {
            if let directory = PluginManager.shared.legacyPluginDirectory(named: name) {
                pluginPathLabel.stringValue = directory.path
            } else {
                pluginPathLabel.stringValue = PluginManager.shared.pluginsDirectory.appendingPathComponent(name).path
            }
            pluginMetadataLabel.stringValue = PluginManager.shared.pluginDetails(forPluginName: name)
        } else {
            pluginPathLabel.stringValue = ""
            pluginMetadataLabel.stringValue = ""
        }
    }

    private func rebuildPluginConfigFields() {
        pluginConfigStack.arrangedSubviews.forEach {
            pluginConfigStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let name = currentPluginName
        let needs = name.map { PluginManager.shared.pluginNeeds(forPluginName: $0) } ?? []
        guard let name else {
            pluginConfigStack.addArrangedSubview(note("没有可配置的插件。请先安装 .pythia 或兼容 .potext 插件。"))
            return
        }
        guard !needs.isEmpty else {
            pluginConfigStack.addArrangedSubview(note("该插件（\(name)）没有需要配置的项。"))
            return
        }
        pluginConfigStack.addArrangedSubview(note("配置项（\(name)）："))
        let stored = PluginManager.shared.pluginConfig(forPluginName: name)
        for need in needs {
            guard let key = need["key"] as? String,
                  let display = need["display"] as? String
            else { continue }
            let type = (need["type"] as? String) ?? "input"
            if type == "select", let options = need["options"] as? [String: String] {
                let popup = NSPopUpButton()
                // Keep options order stable; show display text, store the key on
                // each menu item's representedObject so we persist the KEY (not
                // the localized label) — matching original Pot.
                let ordered = options.sorted { $0.key < $1.key }
                for (optionKey, label) in ordered {
                    let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                    item.representedObject = optionKey
                    popup.menu?.addItem(item)
                }
                let desired = stored[key] ?? (need["default"] as? String ?? "")
                if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == desired }) {
                    popup.select(item)
                } else if let first = popup.itemArray.first {
                    popup.select(first)
                }
                popup.identifier = NSUserInterfaceItemIdentifier(key)
                pluginConfigStack.addArrangedSubview(row(display, popup))
            } else {
                let field = ((need["secret"] as? Bool == true)
                    || PythiaPluginSecretPolicy.isLikelySecretKey(key))
                    ? NSSecureTextField() : NSTextField()
                field.stringValue = stored[key] ?? ((need["default"] as? String) ?? "")
                field.identifier = NSUserInterfaceItemIdentifier(key)
                field.placeholderString = display
                pluginConfigStack.addArrangedSubview(row(display, field))
            }
        }
    }

    /// Collects the current values from the dynamic plugin config fields into a
    /// [key: value] dictionary (matching the plugin's `needs` keys). For select
    /// fields the stored value is the option KEY (via representedObject), not
    /// the localized label — matching original Pot behavior.
    private func collectPluginConfig() -> [String: String] {
        var config: [String: String] = [:]
        func record(_ control: NSControl) {
            guard let key = control.identifier?.rawValue else { return }
            if let popup = control as? NSPopUpButton {
                config[key] = (popup.selectedItem?.representedObject as? String) ?? ""
            } else if let field = control as? NSTextField {
                config[key] = field.stringValue
            }
        }
        for sub in pluginConfigStack.arrangedSubviews {
            for view in [sub] + sub.subviews {
                if let control = view as? NSControl { record(control) }
                for inner in view.subviews {
                    if let control = inner as? NSControl { record(control) }
                }
            }
        }
        return config
    }

    @objc private func savePluginConfig() {
        guard let name = currentPluginName else { return }
        let config = collectPluginConfig()
        do {
            try PluginManager.shared.setPluginConfig(config, forPluginName: name)
            PythiaAppDelegate.shared?.setStatus("已保存 \(name) 的插件配置")
            pluginTestResultLabel.stringValue = "配置已安全保存"
            pluginTestResultLabel.textColor = PythiaDesign.themeColor()
        } catch {
            pluginTestResultLabel.stringValue = "保存失败：\(error.localizedDescription)"
            pluginTestResultLabel.textColor = .systemRed
        }
    }

    /// Runs a real translation through the selected plugin to verify the saved
    /// configuration (API key, model, ...) actually works.
    @objc private func testPluginConnection() {
        guard let name = currentPluginName else {
            pluginTestResultLabel.stringValue = "请先选择一个插件"
            pluginTestResultLabel.textColor = .systemRed
            return
        }
        // Save the current field values first so the runner reads the latest config.
        let config = collectPluginConfig()
        var cfg = config
        if cfg["enable"] == nil { cfg["enable"] = "true" }
        do {
            try PluginManager.shared.setPluginConfig(cfg, forPluginName: name)
        } catch {
            pluginTestResultLabel.stringValue = "保存失败：\(error.localizedDescription)"
            pluginTestResultLabel.textColor = .systemRed
            return
        }
        let serviceID = "plugin:\(name)"
        if let plugin = PluginManager.shared.plugin(forServiceIdentifier: serviceID),
           let type = plugin.legacyType {
            runPluginConnectionTest(serviceID: serviceID, type: type)
        } else {
            runPluginConnectionTest(serviceID: serviceID, type: "translate")
        }
    }

    private func runPluginConnectionTest(
        serviceID: String,
        type: String,
        resultLabel: NSTextField? = nil
    ) {
        switch type {
        case "translate":
            testTranslatePluginConnection(serviceID: serviceID, resultLabel: resultLabel)
        case "recognize":
            testRecognizePluginConnection(serviceID: serviceID, resultLabel: resultLabel)
        case "tts":
            testTTSPluginConnection(serviceID: serviceID, resultLabel: resultLabel)
        case "collection":
            testCollectionPluginConnection(serviceID: serviceID, resultLabel: resultLabel)
        default:
            let outputLabel = resultLabel ?? pluginTestResultLabel
            outputLabel.stringValue = "✗ 不支持的插件类型：\(type)"
            outputLabel.textColor = .systemRed
        }
    }

    private func testTranslatePluginConnection(serviceID: String, resultLabel: NSTextField? = nil) {
        let outputLabel = resultLabel ?? pluginTestResultLabel
        outputLabel.stringValue = "检测中…"
        outputLabel.textColor = .secondaryLabelColor
        TranslationService.shared.translateService(
            identifier: serviceID,
            text: "hello",
            sourceLanguage: "auto",
            targetLanguage: Preferences.shared.targetLanguage.isEmpty ? "zh-CN" : Preferences.shared.targetLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self != nil else { return }
                switch result {
                case .success(let output):
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    outputLabel.stringValue = "✓ 连通正常：hello → \(trimmed)"
                    outputLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.2, alpha: 1)
                case .failure(let error):
                    outputLabel.stringValue = "✗ 失败：\(error.localizedDescription)"
                    outputLabel.textColor = .systemRed
                }
            }
        }
    }

    private func testRecognizePluginConnection(serviceID: String, resultLabel: NSTextField? = nil) {
        let outputLabel = resultLabel ?? pluginTestResultLabel
        outputLabel.stringValue = "检测中…"
        outputLabel.textColor = .secondaryLabelColor
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceID,
            expectedType: "recognize",
            input: Self.samplePNGBase64,
            sourceLanguage: Preferences.shared.recognizeLanguage,
            targetLanguage: Preferences.shared.targetLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self != nil else { return }
                switch result {
                case .success(let output):
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    outputLabel.stringValue = trimmed.isEmpty ? "✓ OCR 插件已执行，但未返回文本" : "✓ OCR 插件已执行：\(trimmed)"
                    outputLabel.textColor = PythiaDesign.themeColor()
                case .failure(let error):
                    outputLabel.stringValue = "✗ OCR 测试失败：\(error.localizedDescription)"
                    outputLabel.textColor = .systemRed
                }
            }
        }
    }

    private func testTTSPluginConnection(serviceID: String, resultLabel: NSTextField? = nil) {
        let outputLabel = resultLabel ?? pluginTestResultLabel
        outputLabel.stringValue = "检测中…"
        outputLabel.textColor = .secondaryLabelColor
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceID,
            expectedType: "tts",
            input: "hello",
            sourceLanguage: Preferences.shared.targetLanguage,
            targetLanguage: Preferences.shared.targetLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self != nil else { return }
                switch result {
                case .success(let output):
                    outputLabel.stringValue = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✓ TTS 插件已执行" : "✓ TTS 插件已返回音频/结果"
                    outputLabel.textColor = PythiaDesign.themeColor()
                case .failure(let error):
                    outputLabel.stringValue = "✗ TTS 测试失败：\(error.localizedDescription)"
                    outputLabel.textColor = .systemRed
                }
            }
        }
    }

    private func testCollectionPluginConnection(serviceID: String, resultLabel: NSTextField? = nil) {
        let outputLabel = resultLabel ?? pluginTestResultLabel
        outputLabel.stringValue = "检测中…"
        outputLabel.textColor = .secondaryLabelColor
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceID,
            expectedType: "collection",
            input: "hello",
            sourceLanguage: Preferences.shared.sourceLanguage,
            targetLanguage: Preferences.shared.targetLanguage,
            targetPayload: "你好"
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self != nil else { return }
                switch result {
                case .success:
                    outputLabel.stringValue = "✓ 生词本插件已执行：hello → 你好"
                    outputLabel.textColor = PythiaDesign.themeColor()
                case .failure(let error):
                    outputLabel.stringValue = "✗ 生词本测试失败：\(error.localizedDescription)"
                    outputLabel.textColor = .systemRed
                }
            }
        }
    }

    /// Saves only the 服务 tab fields so verification uses what the user just
    /// typed without waiting for the normal autosave debounce.
    private func persistServiceFields() {
        let preferences = Preferences.shared
        preferences.openAIKey = openAIKeyField.stringValue
        let displayName = openAINameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.openAICompatibleName = displayName.isEmpty ? "OpenAI" : displayName
        let baseURL = openAIBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.openAIBaseURL = baseURL.isEmpty ? "https://api.openai.com/v1" : baseURL
        preferences.openAICompatibleAPI = selectedPopupValue(
            openAICompatibleAPIPopup,
            mapping: ["openai": "OpenAI", "anthropic": "Anthropic"]
        )
        preferences.openAIModel = openAIModelField.stringValue.isEmpty ? "gpt-4o-mini" : openAIModelField.stringValue
        preferences.deepLKey = deepLKeyField.stringValue
        preferences.baiduAppID = baiduAppIDField.stringValue
        preferences.baiduSecret = baiduSecretField.stringValue
        preferences.youdaoAppKey = youdaoAppKeyField.stringValue
        preferences.youdaoSecret = youdaoSecretField.stringValue
        preferences.libreTranslateURL = libreURLField.stringValue.isEmpty ? "https://libretranslate.com" : libreURLField.stringValue
        preferences.libreTranslateKey = libreKeyField.stringValue
    }

    /// Verifies a built-in key-based translation service by saving the typed
    /// fields and running one real translation through TranslationService.
    @objc private func verifyBuiltInService(_ sender: NSButton) {
        guard
            let identifier = sender.identifier?.rawValue,
            let provider = PythiaProvider.allCases.first(where: { $0.rawValue == identifier })
        else { return }
        persistServiceFields()
        serviceTestResultLabel.stringValue = "检测中…"
        serviceTestResultLabel.textColor = .secondaryLabelColor
        TranslationService.shared.translate(
            text: "hello",
            provider: provider,
            sourceLanguage: "auto",
            targetLanguage: "zh-CN"
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let output):
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.serviceTestResultLabel.stringValue = "✓ \(provider.rawValue) 连通正常：hello → \(trimmed)"
                    self.serviceTestResultLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.2, alpha: 1)
                case .failure(let error):
                    self.serviceTestResultLabel.stringValue = "✗ \(provider.rawValue) 失败：\(error.localizedDescription)"
                    self.serviceTestResultLabel.textColor = .systemRed
                }
            }
        }
    }

    private func testRecognizePluginConnection(serviceID: String) {
        pluginTestResultLabel.stringValue = "检测中…"
        pluginTestResultLabel.textColor = .secondaryLabelColor
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceID,
            expectedType: "recognize",
            input: Self.samplePNGBase64,
            sourceLanguage: Preferences.shared.recognizeLanguage,
            targetLanguage: Preferences.shared.targetLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let output):
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.pluginTestResultLabel.stringValue = trimmed.isEmpty ? "✓ OCR 插件已执行，但未返回文本" : "✓ OCR 插件已执行：\(trimmed)"
                    self.pluginTestResultLabel.textColor = PythiaDesign.themeColor()
                case .failure(let error):
                    self.pluginTestResultLabel.stringValue = "✗ OCR 测试失败：\(error.localizedDescription)"
                    self.pluginTestResultLabel.textColor = .systemRed
                }
            }
        }
    }

    private func testTTSPluginConnection(serviceID: String) {
        pluginTestResultLabel.stringValue = "检测中…"
        pluginTestResultLabel.textColor = .secondaryLabelColor
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceID,
            expectedType: "tts",
            input: "hello",
            sourceLanguage: Preferences.shared.targetLanguage,
            targetLanguage: Preferences.shared.targetLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let output):
                    self.pluginTestResultLabel.stringValue = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✓ TTS 插件已执行" : "✓ TTS 插件已返回音频/结果"
                    self.pluginTestResultLabel.textColor = PythiaDesign.themeColor()
                case .failure(let error):
                    self.pluginTestResultLabel.stringValue = "✗ TTS 测试失败：\(error.localizedDescription)"
                    self.pluginTestResultLabel.textColor = .systemRed
                }
            }
        }
    }

    private func testCollectionPluginConnection(serviceID: String) {
        pluginTestResultLabel.stringValue = "检测中…"
        pluginTestResultLabel.textColor = .secondaryLabelColor
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceID,
            expectedType: "collection",
            input: "hello",
            sourceLanguage: Preferences.shared.sourceLanguage,
            targetLanguage: Preferences.shared.targetLanguage,
            targetPayload: "你好"
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.pluginTestResultLabel.stringValue = "✓ 生词本插件已执行：hello → 你好"
                    self.pluginTestResultLabel.textColor = PythiaDesign.themeColor()
                case .failure(let error):
                    self.pluginTestResultLabel.stringValue = "✗ 生词本测试失败：\(error.localizedDescription)"
                    self.pluginTestResultLabel.textColor = .systemRed
                }
            }
        }
    }

    private static let samplePNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lJ7z9wAAAABJRU5ErkJggg=="

    private func shortcutsTab() -> NSView {
        let stack = formStack()
        // Constrain each hotkey recorder to a fixed height. A bezeled, non-editable
        // NSTextField can report an inflated intrinsic height that makes its row
        // container ~5x too tall, leaving large gaps between rows. Pinning the
        // height to a standard control height fixes the spacing.
        for field in [hotkeySelectionField, hotkeyInputField, hotkeyOCRTranslateField, hotkeyOCRRecognizeField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.heightAnchor.constraint(equalToConstant: 24).isActive = true
            // Let the field stretch to fill the row's control column (same as
            // popups/text fields), so the row container fills the form width and
            // its label lands at the left edge. A max-width constraint here would
            // shrink the container and push the label right.
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        stack.addArrangedSubview(settingsSection(
            "系统级快捷键",
            icon: "keyboard",
            detail: "点击输入框后按下组合键即可录制；保存后会重新注册系统级快捷键。",
            showsHeader: false,
            views: [
                row("划词翻译", hotkeySelectionField),
                row("输入翻译", hotkeyInputField),
                row("截图翻译", hotkeyOCRTranslateField),
                row("截图 OCR", hotkeyOCRRecognizeField),
                note("格式示例：⇧⌘E、⌥⌘D、⌃⇧R。快捷键不能使用重复组合。"),
            ]
        ))
        return stack
    }

    private func backupTab() -> NSView {
        let stack = formStack()
        backupTypePopup.removeAllItems()
        backupTypePopup.addItems(withTitles: ["本地", "WebDAV"])
        backupTypePopup.target = self
        backupTypePopup.action = #selector(backupTypeChanged)
        stack.addArrangedSubview(sectionTextAligned(row("备份方式", backupTypePopup), minHeight: 0))

        // Add the WebDAV-specific rows directly to the main form (so they share
        // the exact same left edge as "备份方式"), but keep references so we can
        // show/hide them when 备份方式 changes.
        let urlRow = sectionTextAligned(row("WebDAV 地址", webdavURLField), minHeight: 0)
        let userRow = sectionTextAligned(row("WebDAV 用户名", webdavUsernameField), minHeight: 0)
        let passRow = sectionTextAligned(row("WebDAV 密码", webdavPasswordField), minHeight: 0)
        webdavHistorySyncIntervalField.placeholderString = "1"
        webdavHistorySyncIntervalUnitPopup.removeAllItems()
        webdavHistorySyncIntervalUnitPopup.addItems(withTitles: ["分钟", "小时", "天", "周"])
        webdavHistoryAutoSyncCheckbox.target = self
        webdavHistoryAutoSyncCheckbox.action = #selector(webDAVAutoSyncChanged)
        let autoSyncRow = sectionTextAligned(indented(webdavHistoryAutoSyncCheckbox), minHeight: 0)
        let intervalControls = NSStackView()
        intervalControls.orientation = .horizontal
        intervalControls.alignment = .centerY
        intervalControls.spacing = 8
        intervalControls.addArrangedSubview(webdavHistorySyncIntervalField)
        intervalControls.addArrangedSubview(webdavHistorySyncIntervalUnitPopup)
        webdavHistorySyncIntervalField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        webdavHistorySyncIntervalUnitPopup.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let intervalRow = sectionTextAligned(row("自动同步间隔", intervalControls), minHeight: 0)
        webdavHistorySyncStatusLabel.lineBreakMode = .byWordWrapping
        webdavHistorySyncStatusLabel.maximumNumberOfLines = 3
        webdavHistorySyncStatusLabel.font = .systemFont(ofSize: 12)
        webdavHistorySyncStatusLabel.textColor = .secondaryLabelColor
        let statusRow = sectionTextAligned(
            leadingFullWidth(webdavHistorySyncStatusLabel, minHeight: 0),
            minHeight: 0
        )
        webdavTestResultLabel.lineBreakMode = .byTruncatingTail
        webdavTestResultLabel.maximumNumberOfLines = 1
        webdavTestResultLabel.font = .systemFont(ofSize: 12)
        // Result row: a "检测结果：" caption and the colored result, both at the
        // form's left edge (relX 221), aligned on the first baseline so they sit
        // on exactly one horizontal line.
        let resultCaption = NSTextField(labelWithString: "连通检测结果：")
        resultCaption.font = .systemFont(ofSize: 12)
        resultCaption.textColor = .secondaryLabelColor
        let resultBox = NSStackView()
        resultBox.orientation = .horizontal
        resultBox.alignment = .firstBaseline
        resultBox.spacing = 6
        resultBox.addArrangedSubview(resultCaption)
        resultBox.addArrangedSubview(webdavTestResultLabel)
        let resultRow = sectionTextAligned(leadingFullWidth(resultBox, minHeight: 0), minHeight: 0)
        webdavRows = [urlRow, userRow, passRow, autoSyncRow, intervalRow, statusRow, resultRow]
        webdavRows.forEach { stack.addArrangedSubview($0) }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(PillButton("导出配置到本地", target: self, action: #selector(exportConfig)))
        buttons.addArrangedSubview(PillButton("从本地导入配置", target: self, action: #selector(importConfig)))
        buttons.addArrangedSubview(PillButton("导出历史到本地", target: self, action: #selector(exportHistoryFromSettings)))
        let localButtonsRow = sectionTextAligned(leadingFullWidth(buttons, minHeight: 0), minHeight: 0)
        stack.addArrangedSubview(localButtonsRow)
        localActionButtons = localButtonsRow

        let webdavButtons = NSStackView()
        webdavButtons.orientation = .horizontal
        webdavButtons.spacing = 10
        webdavButtons.addArrangedSubview(PillButton("测试 WebDAV 连通性", target: self, action: #selector(testWebDAVConnection)))
        webdavButtons.addArrangedSubview(PillButton("同步历史", target: self, action: #selector(syncHistoryWithWebDAV)))
        webdavButtons.addArrangedSubview(PillButton("备份到 WebDAV", target: self, action: #selector(backupToWebDAV)))
        webdavButtons.addArrangedSubview(PillButton("从 WebDAV 恢复", target: self, action: #selector(restoreFromWebDAV)))
        let webdavButtonsRow = sectionTextAligned(leadingFullWidth(webdavButtons, minHeight: 0), minHeight: 0)
        stack.addArrangedSubview(webdavButtonsRow)
        webdavActionButtons = webdavButtonsRow

        let localNote = sectionTextAligned(
            note("本地导出/导入即时生效，文件保存在你选择的位置。"),
            minHeight: 0
        )
        let webdavNote = sectionTextAligned(
            note("坚果云需用应用专属密码（非登录密码）。历史同步使用 /Pythia/history/history.json；配置备份仍兼容旧备份目录。"),
            minHeight: 0
        )
        localNoteRow = localNote
        webdavNoteRow = webdavNote
        stack.addArrangedSubview(localNote)
        stack.addArrangedSubview(webdavNote)
        // Apply current visibility based on the saved backup type.
        updateWebDAVFieldsVisibility()
        updateWebDAVAutoSyncControls()
        return stack
    }

    @objc private func webDAVAutoSyncChanged() {
        updateWebDAVAutoSyncControls()
        scheduleAutosave()
    }

    private func updateWebDAVAutoSyncControls() {
        let enabled = webdavHistoryAutoSyncCheckbox.state == .on
        webdavHistorySyncIntervalField.isEnabled = enabled
        webdavHistorySyncIntervalUnitPopup.isEnabled = enabled
    }

    /// Shows or hides the WebDAV fields depending on 备份方式.
    @objc private func backupTypeChanged() {
        updateWebDAVFieldsVisibility()
        scheduleAutosave()
    }

    private func updateWebDAVFieldsVisibility() {
        let isWebDAV = backupTypePopup.titleOfSelectedItem == "WebDAV"
        webdavRows.forEach { $0.isHidden = !isWebDAV }
        webdavActionButtons?.isHidden = !isWebDAV
        localActionButtons?.isHidden = isWebDAV
        localNoteRow?.isHidden = isWebDAV
        webdavNoteRow?.isHidden = !isWebDAV
    }

    private func refreshWebDAVHistorySyncStatus() {
        let preferences = Preferences.shared
        let lastAt = preferences.webdavLastHistorySyncAt
        let status = preferences.webdavLastHistorySyncStatus
        if lastAt.isEmpty && status.isEmpty {
            webdavHistorySyncStatusLabel.stringValue = "历史同步：尚未同步。"
        } else if lastAt.isEmpty {
            webdavHistorySyncStatusLabel.stringValue = "历史同步：\(status)"
        } else {
            webdavHistorySyncStatusLabel.stringValue = "上次历史同步：\(lastAt)\n\(status)"
        }
    }

    private func proxyTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(settingsSection(
            "网络代理",
            icon: "network",
            detail: "设置会应用到当前进程的 HTTP、HTTPS 与 ALL_PROXY 网络请求。",
            showsHeader: false,
            views: [
                indented(proxyEnabledCheckbox),
                row("代理主机", proxyHostField),
                row("代理端口", proxyPortField),
                row("代理用户名", proxyUsernameField),
                row("代理密码", proxyPasswordField),
                row("不代理地址", noProxyField),
                note("多个免代理地址可用逗号、分号或换行分隔。保存后会设置当前进程的 http_proxy/https_proxy/all_proxy 环境变量。"),
            ]
        ))
        return stack
    }

    private func historyTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(settingsSection(
            "历史记录",
            icon: "clock.arrow.circlepath",
            detail: "控制翻译结果是否写入本机历史记录。",
            showsHeader: false,
            views: [
                indented(historyDisableCheckbox),
                note("关闭后不会记录任何翻译历史。已有的历史可在历史窗口手动清除。"),
            ]
        ))
        return stack
    }

    private func migrationTab() -> NSView {
        let stack = formStack()
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(PillButton("导入旧版配置和插件", target: self, action: #selector(migrateConfig)))
        buttons.addArrangedSubview(PillButton("仅导入旧版插件", target: self, action: #selector(importLegacyPlugins)))
        stack.addArrangedSubview(settingsSection(
            "迁移旧版数据",
            icon: "arrow.triangle.2.circlepath",
            detail: "扫描本机旧 Pot/Tauri 配置目录，并将可识别内容导入 Pythia。",
            views: [
                note("旧 Pot 插件会直接转换为 .pythia；转换成功后，Pythia 不保留旧插件或 .potext 备份。密钥写入仅当前用户可读的 Pythia 本地凭据文件，不访问 macOS 钥匙串，也不会输出到日志。"),
                leadingFullWidth(buttons, minHeight: 0),
            ]
        ))
        stack.addArrangedSubview(settingsSection(
            "本地 API",
            icon: "network.badge.shield.half.filled",
            detail: "供外部工具调用的本地服务端点。",
            views: [note("外部调用 API：127.0.0.1:60828，支持 /translate、/selection_translate、/input_translate、/ocr_recognize、/ocr_translate、/config。")]
        ))
        return stack
    }

    private func aboutTab() -> NSView {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Self.sourceRevision

        let stack = FlippedStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 42, bottom: 28, right: 42)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Hero: icon, name, version pills, description.
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 22
        icon.layer?.masksToBounds = true
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96),
        ])

        let nameLabel = NSTextField(labelWithString: "Pythia")
        nameLabel.font = .systemFont(ofSize: 30, weight: .bold)
        nameLabel.textColor = PythiaDesign.themeColor()
        nameLabel.alignment = .center

        let pills = NSStackView(views: [
            aboutVersionPill("正式版本 \(version)"),
            aboutVersionPill("开发版本 \(build)"),
        ])
        pills.orientation = .horizontal
        pills.spacing = 8

        let descriptionLabel = AutoWrappingLabel(wrappingLabelWithString: "本地优先的多服务桌面翻译：划词、输入、截图即翻，多个翻译服务并排作答。")
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .center
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // This width constraint is activated only after the label has been
        // inserted into the stack. AppKit raises NSGenericException when a
        // constraint is activated before both items share a view hierarchy.
        let descriptionWidthConstraint = descriptionLabel.widthAnchor.constraint(
            lessThanOrEqualTo: stack.widthAnchor,
            constant: -24
        )

        // Action bar: GitHub + 检查更新（含忙碌状态）。
        let githubButton = PillButton("GitHub", target: self, action: #selector(openGitHubProject))
        if let mark = NSImage(named: "GitHubMark") {
            mark.isTemplate = true
            mark.size = NSSize(width: 15, height: 15)
            githubButton.image = mark
        } else {
            githubButton.image = NSImage(systemSymbolName: "link", accessibilityDescription: "GitHub")
        }
        githubButton.imagePosition = .imageLeading
        githubButton.imageHugsTitle = true
        githubButton.imageScaling = .scaleProportionallyDown
        githubButton.widthAnchor.constraint(equalToConstant: 94).isActive = true

        let checkButton = PillButton("检查更新", target: self, action: #selector(checkForUpdates))
        checkButton.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "检查更新")
        checkButton.imagePosition = .imageLeading
        checkButton.imageHugsTitle = true
        checkButton.imageScaling = .scaleProportionallyDown
        checkButton.widthAnchor.constraint(equalToConstant: 110).isActive = true
        aboutCheckButton = checkButton

        // Keep the centered group limited to the two visible actions.
        let actionStack = NSStackView(views: [githubButton, checkButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 10
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        let actionContainer = NSView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.addSubview(actionStack)
        NSLayoutConstraint.activate([
            actionStack.centerXAnchor.constraint(equalTo: actionContainer.centerXAnchor),
            actionStack.topAnchor.constraint(equalTo: actionContainer.topAnchor),
            actionStack.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor),
        ])

        // Cards.
        let releaseCard = aboutReleaseNotesCard(version: version)
        let aboutCard = aboutSoftwareCard()

        // Footer.
        let footerLine = NSTextField(labelWithString: "本地优先 · 原生 macOS · 多服务翻译")
        footerLine.font = .systemFont(ofSize: 11, weight: .medium)
        footerLine.textColor = .secondaryLabelColor
        let copyrightLabel = NSTextField(labelWithString: "Copyright © 2026 douxy1994")
        copyrightLabel.font = .systemFont(ofSize: 11, weight: .medium)
        copyrightLabel.textColor = .secondaryLabelColor
        let licenseLabel = NSTextField(labelWithString: "Licensed under GNU Affero General Public License v3.0")
        licenseLabel.font = .systemFont(ofSize: 10)
        licenseLabel.textColor = .tertiaryLabelColor
        let bundleLabel = NSTextField(labelWithString: "Bundle ID  com.douxy.pythia")
        bundleLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        bundleLabel.textColor = .tertiaryLabelColor
        let footer = NSStackView(views: [footerLine, copyrightLabel, licenseLabel, bundleLabel])
        footer.orientation = .vertical
        footer.alignment = .centerX
        footer.spacing = 5

        for view in [icon, nameLabel, pills, descriptionLabel, actionContainer, releaseCard, aboutCard, footer] {
            stack.addArrangedSubview(view)
        }
        // Natural width remains one line at the normal window size and wraps
        // to at most two lines only when the user narrows the window.
        descriptionWidthConstraint.isActive = true
        // Keep the hero compact so the title sits slightly higher and the
        // visible top/bottom breathing room stays balanced above the cards.
        stack.setCustomSpacing(8, after: icon)
        // Keep a deliberate breathing gap below the app name before the
        // version pills; the title should not visually touch the metadata.
        stack.setCustomSpacing(8, after: nameLabel)
        stack.setCustomSpacing(10, after: pills)
        stack.setCustomSpacing(10, after: actionContainer)
        stack.setCustomSpacing(16, after: aboutCard)

        for card in [releaseCard, aboutCard] {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -84).isActive = true
        }
        return stack
    }

    /// Mirrors AI Memory's About page: the development version is the short
    /// source revision recorded into the app bundle during the Xcode build,
    /// rather than the numeric marketing/build setting.
    private static var sourceRevision: String {
        let bundledRevision = Bundle.main.url(
            forResource: "PythiaSourceRevision",
            withExtension: "txt"
        ).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let plistRevision = Bundle.main.object(
            forInfoDictionaryKey: "PythiaSourceRevision"
        ) as? String
        let revision = (bundledRevision ?? plistRevision)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let revision, !revision.isEmpty, revision != "uncommitted" else {
            return "未提交构建"
        }
        return revision
    }

    private func aboutVersionPill(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        pill.layer?.cornerRadius = 10
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.widthAnchor.constraint(equalTo: label.widthAnchor, constant: 20),
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            pill.heightAnchor.constraint(equalToConstant: 20),
        ])
        return pill
    }

    private func aboutCardContainer() -> NSView {
        let view = NSVisualEffectView()
        view.material = .contentBackground
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        // Keep the cards visibly distinct from the About page surface, like
        // AI Memory's white content cards on a quiet neutral background.
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = 14
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        view.layer?.shadowColor = NSColor.black.withAlphaComponent(0.12).cgColor
        view.layer?.shadowOpacity = 1
        view.layer?.shadowRadius = 8
        view.layer?.shadowOffset = NSSize(width: 0, height: -2)
        return view
    }

    /// A card title row pinned to the leading edge; plain NSTextFields in a
    /// .width-aligned NSStackView don't reliably stretch, which centered them.
    private func aboutCardTitle(_ text: String) -> NSView {
        let container = NSView()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func aboutReleaseNotesCard(version: String) -> NSView {
        let card = aboutCardContainer()
        let titleLabel = NSTextField(labelWithString: "最近版本更新")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let versionTag = NSTextField(labelWithString: "v\(version)")
        versionTag.font = .systemFont(ofSize: 11, weight: .semibold)
        versionTag.textColor = PythiaDesign.themeColor()
        versionTag.translatesAutoresizingMaskIntoConstraints = false
        let header = NSView()
        header.addSubview(titleLabel)
        header.addSubview(versionTag)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            versionTag.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            versionTag.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        let updateItems = [
            aboutUpdateItem("大模型长文档翻译", "自定义 OpenAI 与 Anthropic 接口按约 1800 字符安全分段并顺序合并，不再被固定短超时中断。"),
            aboutUpdateItem("数字与格式保护", "分段不切断小数、日期、时间、版本号、科学计数法或扩展字形簇，并保留段落、列表和空白。"),
            aboutUpdateItem("有界重试", "临时网络错误、限流和服务端错误最多尝试三次，支持 Retry-After 秒数与 HTTP 日期。"),
            aboutUpdateItem("真正可取消", "取消会立即终止当前请求或退避等待、停止后续分段，并与请求超时显示不同结果。"),
        ]
        let rows = FullWidthStackView()
        updateItems.forEach { item in
            rows.addArrangedSubview(item)
            let width = item.widthAnchor.constraint(equalTo: rows.widthAnchor)
            width.priority = .required
            width.isActive = true
        }
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 12

        // Keep the header and update list on one explicit horizontal grid.
        // Intrinsic-width stack rows otherwise remain centered in AppKit.
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)
        content.addSubview(rows)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            rows.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            rows.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            rows.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])
        return card
    }

    private func aboutSoftwareCard() -> NSView {
        let card = aboutCardContainer()
        let titleLabel = NSTextField(labelWithString: "关于本软件")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .left

        let bodyLabel = AutoWrappingLabel(wrappingLabelWithString: "Pythia 是一款本地优先的桌面翻译工具。一个快捷键即可从划词、输入或截图中取词，在简约或完整窗口中让多个翻译服务并排作答；内置服务、自定义大模型 API 与 .pythia 插件可共同使用，历史记录可通过 WebDAV 在 macOS 与 Windows 之间同步，API Key 只保存在本机私有凭据文件中。")
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.alignment = .left
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.cell?.wraps = true
        bodyLabel.cell?.truncatesLastVisibleLine = false
        bodyLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = NSView()
        let bodyContainer = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        content.addSubview(titleLabel)
        content.addSubview(bodyContainer)
        bodyContainer.addSubview(bodyLabel)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            bodyContainer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            bodyContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            bodyLabel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])
        return card
    }

    private func aboutUpdateItem(_ title: String, _ detail: String) -> NSView {
        let container = NSView()
        let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        let check = NSImageView(image: symbol ?? NSImage())
        check.contentTintColor = PythiaDesign.themeColor()
        check.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .left
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(check)
        container.addSubview(titleLabel)
        container.addSubview(detailLabel)
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            check.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            check.widthAnchor.constraint(equalToConstant: 14),
            check.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func scrollTab(_ document: NSView) -> NSView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        // Prevent the scroll view (and thus the window) from shrinking to the
        // document's fitting size. Without this, a short tab (e.g. 快捷键) makes
        // the document's intrinsic width small, the clip view hugs it, and the
        // whole window collapses narrower when switching tabs.
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.contentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        document.translatesAutoresizingMaskIntoConstraints = false
        document.setContentHuggingPriority(.defaultLow, for: .horizontal)
        document.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.documentView = document

        // Pin the document width to the clip view so it wraps to the window
        // width. Do NOT force the document height to the clip-view height:
        // that stretches the (vertical NSStackView) form and its default gravity
        // distribution spreads/centers the rows, leaving large unexplained gaps.
        // Instead let the document size to its content; the scroll view scrolls
        // when content is taller than the visible area.
        NSLayoutConstraint.activate([
            // Reserve an explicit breathing space before the vertical scroll
            // indicator on every settings page. Pinning the document to the
            // clip view's full width made rows and plugin fields look attached
            // to the indicator at the right edge.
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor, constant: -18),
        ])
        return scroll
    }

    /// Keeps the selected category's title and explanation fixed above the
    /// scrollable form, matching the compact two-column settings pattern used
    /// by AI Memory. The form itself remains an AppKit view so every existing
    /// setting control and action keeps its current responder behavior.
    private func settingsPage(_ document: NSView, index: Int, showsHeader: Bool = true) -> NSView {
        let page = NSView()
        page.translatesAutoresizingMaskIntoConstraints = false
        page.setContentHuggingPriority(.defaultLow, for: .horizontal)
        page.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        guard showsHeader else {
            page.addSubview(document)
            NSLayoutConstraint.activate([
                document.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                document.trailingAnchor.constraint(equalTo: page.trailingAnchor),
                document.topAnchor.constraint(equalTo: page.topAnchor),
                document.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            ])
            return page
        }

        let header = settingsPageHeader(
            title: tabTitles[index],
            subtitle: tabSubtitles[index],
            symbolName: tabSymbols[index]
        )
        page.addSubview(header)
        page.addSubview(document)
        NSLayoutConstraint.activate([
            // The page title uses the same horizontal grid as the document;
            // the icon and title therefore line up with section icons and
            // labels below instead of starting one inset farther right.
            header.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -10),
            // The page header shares the sidebar title's top baseline: the
            // active tab content starts 16pt below the tab card, so 2pt here
            // matches the sidebar's 18pt title inset.
            header.topAnchor.constraint(equalTo: page.topAnchor, constant: 2),
            document.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 10),
            document.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -10),
            document.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            document.bottomAnchor.constraint(equalTo: page.bottomAnchor),
        ])
        return page
    }

    private func settingsPageHeader(title: String, subtitle: String, symbolName: String) -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let symbol = NSImageView(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage()
        )
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.setAccessibilityElement(false)
        symbol.imageScaling = .scaleProportionallyDown
        symbol.contentTintColor = PythiaDesign.themeColor()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        titleLabel.textColor = PythiaDesign.themeColor()

        let subtitleLabel = AutoWrappingLabel(wrappingLabelWithString: subtitle)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let copy = NSStackView(views: [titleLabel, subtitleLabel])
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 5

        header.addSubview(symbol)
        header.addSubview(copy)
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            symbol.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            symbol.heightAnchor.constraint(equalToConstant: 18),
            copy.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 10),
            copy.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            copy.topAnchor.constraint(equalTo: header.topAnchor),
            copy.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        return header
    }

    /// The window width the user has chosen (set by real user resizing). Restored
    /// after every tab switch so the window does not shrink to a tab's fitting size.
    private var settingsUserWidth: CGFloat = 1080

    // MARK: - NSWindowDelegate

    /// Capture the width when the user actively resizes wider than the current
    /// record, and enforce it as the window's stable minimum so a short tab
    /// cannot shrink the window (NSWindow otherwise auto-resizes to its content's
    /// fitting size).
    func windowDidResize(_ notification: Notification) {
        guard let win = window as? StableWindow else { return }
        let w = win.frame.width
        if w > settingsUserWidth + 0.5 {
            settingsUserWidth = w
            win.stableMinWidth = settingsUserWidth
        }
    }

    func windowWillClose(_ notification: Notification) {
        flushPendingAutosave()
    }

    /// Commits the current editor value even when the app quits inside the
    /// debounce window, so automatic saving never depends on a Save button or
    /// on a delayed work item getting another main-run-loop turn.
    func flushPendingAutosave() {
        window?.makeFirstResponder(nil)
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
        persistSettings()
    }

    /// Selects the 关于 tab; used by the app menu's 关于 Pythia item so the
    /// custom about page (version pills, update check) shows instead of the
    /// standard macOS about panel.
    func selectAboutTab() {
        showTab(index: tabTitles.firstIndex(of: "关于") ?? (tabTitles.count - 1))
    }

    private func showTab(index: Int) {
        selectedSettingsIndex = max(0, min(index, tabTitles.count - 1))
        updateSidebarSelection()
        NSLayoutConstraint.deactivate(activeTabConstraints)
        activeTabConstraints.removeAll()
        activeTabView?.removeFromSuperview()
        let document: NSView
        switch selectedSettingsIndex {
        case 1: document = scrollTab(translateTab())
        case 2: document = scrollTab(servicesTab())
        case 3: document = scrollTab(ocrTab())
        case 4: document = scrollTab(ttsTab())
        case 5: document = scrollTab(collectionTab())
        case 6: document = scrollTab(pluginsTab())
        case 7: document = scrollTab(shortcutsTab())
        case 8: document = scrollTab(historyTab())
        case 9: document = scrollTab(proxyTab())
        case 10: document = scrollTab(backupTab())
        case 11: document = scrollTab(migrationTab())
        case 12: document = scrollTab(aboutTab())
        default: document = scrollTab(generalTab())
        }
        let content = settingsPage(document, index: selectedSettingsIndex, showsHeader: selectedSettingsIndex != 12)
        activeTabView = content
        tabCard.addSubview(content)
        activeTabConstraints = [
            content.leadingAnchor.constraint(equalTo: tabCard.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: tabCard.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: tabCard.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: tabCard.bottomAnchor, constant: -16),
        ]
        NSLayoutConstraint.activate(activeTabConstraints)
        load()
        installAutosaveHandlers(in: content)

        // Reset after `load()` has populated dynamic service/plugin lists.
        // Resetting earlier lets AppKit restore the old bottom origin when a
        // list changes height, which clips the first section on a fresh tab.
        if let scroll = document as? NSScrollView {
            let resetToTop = { [weak scroll] in
                guard let scroll else { return }
                scroll.layoutSubtreeIfNeeded()
                scroll.contentView.setBoundsOrigin(.zero)
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            DispatchQueue.main.async(execute: resetToTop)
            DispatchQueue.main.async {
                DispatchQueue.main.async(execute: resetToTop)
            }
        }
    }

    private func installAutosaveHandlers(in root: NSView) {
        func visit(_ view: NSView) {
            if let button = view as? NSButton, button.target == nil, button.action == nil {
                button.target = self
                button.action = #selector(autosaveControlChanged(_:))
            } else if let popup = view as? NSPopUpButton, popup.target == nil, popup.action == nil {
                popup.target = self
                popup.action = #selector(autosaveControlChanged(_:))
            }
            view.subviews.forEach(visit)
        }
        visit(root)
    }

    @objc private func autosaveControlChanged(_ sender: NSControl) {
        guard !isLoadingSettings else { return }
        scheduleAutosave()
    }

    @objc private func editableControlDidEndEditing(_ notification: Notification) {
        guard !isLoadingSettings,
              let control = notification.object as? NSControl,
              control.window === window
        else { return }
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        guard !isLoadingSettings else { return }
        autosaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persistSettings() }
        autosaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func formStack() -> NSStackView {
        let stack = FullWidthStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 28, right: 16)
        return stack
    }

    private func configureSettingsLanguagePopup(_ popup: NSPopUpButton, includeAuto: Bool) {
        popup.removeAllItems()
        popup.addItems(withTitles: languageTitles(includeAuto: includeAuto))
    }

    private func row(_ label: String, _ control: NSView) -> NSView {
        // A plain NSView container (no intrinsic size) so the parent `.width`-
        // aligned stack stretches it to full width. Inside it the label is pinned
        // to the leading edge and the control fills the rest — guaranteeing every
        // row's label starts at the same left edge regardless of control type.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let labelView = NSTextField(labelWithString: label)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.alignment = .left
        labelView.textColor = .labelColor
        labelView.font = .systemFont(ofSize: 13)
        control.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(labelView)
        container.addSubview(control)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            labelView.widthAnchor.constraint(equalToConstant: 176),
            control.leadingAnchor.constraint(equalTo: labelView.trailingAnchor, constant: 12),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            // Make the container's height follow the control's height, so tall
            // controls (e.g. the multi-checkbox service list) expand the row
            // instead of overflowing and overlapping the rows below.
            container.topAnchor.constraint(lessThanOrEqualTo: control.topAnchor, constant: -2),
            container.bottomAnchor.constraint(greaterThanOrEqualTo: control.bottomAnchor, constant: 2),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
        // Low hugging so the container stretches; control fills remaining width.
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return container
    }

    /// Wraps a control in a full-width, no-intrinsic-size container and pins the
    /// control to the container's leading edge. This is the reliable way to make
    /// a high-hugging control (checkbox/button) left-align inside a `.width`-
    /// aligned vertical stack — the container always stretches to the stack
    /// width (because it has no intrinsic size), and the control sits at its
    /// leading edge regardless of its own hugging priority.
    private func leadingFullWidth(_ control: NSView, minHeight: CGFloat = 28) -> NSView {
        leadingFullWidth(control, trailingInset: 0, minHeight: minHeight)
    }

    /// Variant of `leadingFullWidth` that preserves a trailing breathing space
    /// inside the form. This is used by the plugin list, where a nested detail
    /// stack should stop before the settings page's scroll indicator.
    private func leadingFullWidth(
        _ control: NSView,
        trailingInset: CGFloat,
        minHeight: CGFloat = 28
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // Pin the trailing edge too, so wrapping labels are constrained to
            // the container width and wrap to multiple lines instead of growing
            // one very long line that overflows the window.
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -trailingInset),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
        ])
        // The container fills the stack slot; the control fills its width.
        if let button = control as? NSButton { button.alignment = .left }
        if let popup = control as? NSPopUpButton { popup.alignment = .left }
        if let label = control as? NSTextField {
            // Make wrapping labels prefer to wrap rather than expand.
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return container
    }

    /// Aligns body content to the text column established by a section header:
    /// icon at the section leading edge, then 18pt icon width plus a 10pt gap.
    /// This keeps notes, controls, and action buttons from protruding left of
    /// the title and its explanation text.
    private func sectionTextAligned(_ control: NSView, minHeight: CGFloat = 28) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
        ])
        return container
    }

    /// Left-aligns a standalone control (checkbox/popup) at the form's left
    /// edge, consistent with `row(...)` labels and `note(...)` text. Uses
    /// `leadingFullWidth` so it is immune to the stack's right-aligning of
    /// intrinsic-size controls.
    private func indented(_ control: NSView) -> NSView {
        leadingFullWidth(control)
    }

    private func note(_ text: String) -> NSView {
        let label = AutoWrappingLabel(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.truncatesLastVisibleLine = false
        label.cell?.wraps = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return leadingFullWidth(label, minHeight: 0)
    }

    private func sectionHeader(_ title: String, detail: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        let detailLabel = AutoWrappingLabel(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping

        let header = NSStackView(views: [titleLabel, detailLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 2, right: 0)
        return leadingFullWidth(header, minHeight: 0)
    }

    /// Creates a flat settings section. About is the only page that uses
    /// explicit content cards; all regular settings pages share this open
    /// layout so section titles and rows sit on one left-aligned grid.
    private func settingsSection(
        _ title: String,
        icon: String,
        detail: String? = nil,
        showsHeader: Bool = true,
        alignBodyToHeaderText: Bool = true,
        views: [NSView]
    ) -> NSView {
        let content = FullWidthStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 6, left: 18, bottom: 8, right: 18)
        if showsHeader {
            content.addArrangedSubview(settingsSectionHeader(title, icon: icon, detail: detail))
        }
        views.forEach {
            if alignBodyToHeaderText {
                content.addArrangedSubview(sectionTextAligned($0, minHeight: 0))
            } else {
                content.addArrangedSubview($0)
            }
        }
        return content
    }

    private func settingsSectionHeader(_ title: String, icon: String, detail: String?) -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let symbol = NSImageView(
            image: NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage()
        )
        symbol.setAccessibilityElement(false)
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.imageScaling = .scaleProportionallyDown
        symbol.contentTintColor = PythiaDesign.themeColor()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(titleLabel)
        if let detail, !detail.isEmpty {
            let detailLabel = AutoWrappingLabel(wrappingLabelWithString: detail)
            detailLabel.font = .systemFont(ofSize: 11)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.maximumNumberOfLines = 2
            detailLabel.lineBreakMode = .byWordWrapping
            detailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textStack.addArrangedSubview(detailLabel)
        }

        header.addSubview(symbol)
        header.addSubview(textStack)
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            symbol.topAnchor.constraint(equalTo: header.topAnchor, constant: 2),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            symbol.heightAnchor.constraint(equalToConstant: 18),
            textStack.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: header.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        return header
    }

    private func load() {
        // `themeColorWell.color = ...` sends the color-well action on some
        // AppKit releases. Suppress that programmatic notification while a
        // page is being rebuilt, otherwise themeColorChanged() calls showTab(),
        // which calls load() again and traps the main thread in a callback
        // loop.
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        let preferences = Preferences.shared
        selectLanguage(preferences.sourceLanguage, in: sourceLanguagePopup)
        selectLanguage(preferences.targetLanguage, in: targetLanguagePopup)
        selectLanguage(preferences.translateSecondLanguage, in: secondTargetLanguagePopup)
        openAIKeyField.stringValue = preferences.openAIKey
        openAINameField.stringValue = preferences.openAICompatibleName
        openAIBaseURLField.stringValue = preferences.openAIBaseURL
        selectPopup(openAICompatibleAPIPopup, value: preferences.openAICompatibleAPI, mapping: ["openai": "OpenAI", "anthropic": "Anthropic"])
        openAIModelField.stringValue = preferences.openAIModel
        deepLKeyField.stringValue = preferences.deepLKey
        baiduAppIDField.stringValue = preferences.baiduAppID
        baiduSecretField.stringValue = preferences.baiduSecret
        youdaoAppKeyField.stringValue = preferences.youdaoAppKey
        youdaoSecretField.stringValue = preferences.youdaoSecret
        libreURLField.stringValue = preferences.libreTranslateURL
        libreKeyField.stringValue = preferences.libreTranslateKey
        reloadServiceLists()
        selectLanguage(preferences.recognizeLanguage, in: recognizeLanguagePopup)
        recognizeAutoCopyCheckbox.state = preferences.recognizeAutoCopy ? .on : .off
        recognizeDeleteNewlineCheckbox.state = preferences.recognizeDeleteNewline ? .on : .off
        hotkeySelectionField.stringValue = preferences.hotkeySelectionTranslate
        hotkeyInputField.stringValue = preferences.hotkeyInputTranslate
        hotkeyOCRTranslateField.stringValue = preferences.hotkeyOCRTranslate
        hotkeyOCRRecognizeField.stringValue = preferences.hotkeyOCRRecognize
        proxyEnabledCheckbox.state = preferences.proxyEnabled ? .on : .off
        proxyHostField.stringValue = preferences.proxyHost
        proxyPortField.stringValue = preferences.proxyPort
        selectPopup(themePopup, value: preferences.theme, mapping: ["system": "跟随系统", "light": "浅色", "dark": "深色"])
        themeColorWell.color = PythiaDesign.themeColor()
        selectPopup(autoCopyPopup, value: preferences.translateAutoCopy, mapping: ["disable": "不自动复制", "source": "复制原文", "target": "复制译文", "source_target": "复制原文和译文"])
        selectPopup(windowPositionPopup, value: preferences.translateWindowPosition, mapping: ["center": "居中", "mouse": "鼠标附近", "remember": "记住位置"])
        closeOnBlurCheckbox.state = preferences.translateCloseOnBlur ? .on : .off
        alwaysOnTopCheckbox.state = preferences.translateAlwaysOnTop ? .on : .off
        rememberWindowSizeCheckbox.state = preferences.translateRememberWindowSize ? .on : .off
        // Translate behavior / appearance / general / OCR / proxy / backup.
        translateDeleteNewlineCheckbox.state = preferences.translateDeleteNewline ? .on : .off
        smartTargetCheckbox.state = preferences.smartTargetLanguage ? .on : .off
        hideSourceCheckbox.state = preferences.hideSource ? .on : .off
        hideLanguageCheckbox.state = preferences.hideLanguage ? .on : .off
        dynamicTranslateCheckbox.state = preferences.dynamicTranslate ? .on : .off
        incrementalTranslateCheckbox.state = preferences.incrementalTranslate ? .on : .off
        appFontField.stringValue = preferences.appFont
        appFontSizeField.stringValue = "\(preferences.appFontSize)"
        appFallbackFontField.stringValue = preferences.appFallbackFont
        selectPopup(trayClickPopup, value: preferences.trayClickEvent, mapping: ["config": "显示设置", "translate": "显示翻译窗口", "history": "显示历史记录"])
        launchAtLoginCheckbox.state = preferences.launchAtLogin ? .on : .off
        checkUpdateCheckbox.state = preferences.checkUpdate ? .on : .off
        serverPortField.stringValue = "\(preferences.serverPort)"
        historyDisableCheckbox.state = preferences.historyDisable ? .on : .off
        recognizeHideWindowCheckbox.state = preferences.recognizeHideWindow ? .on : .off
        recognizeCloseOnBlurCheckbox.state = preferences.recognizeCloseOnBlur ? .on : .off
        proxyUsernameField.stringValue = preferences.proxyUsername
        proxyPasswordField.stringValue = preferences.proxyPassword
        noProxyField.stringValue = preferences.noProxy
        selectPopup(backupTypePopup, value: preferences.backupType, mapping: ["local": "本地", "webdav": "WebDAV"])
        webdavURLField.stringValue = preferences.webdavURL
        webdavUsernameField.stringValue = preferences.webdavUsername
        webdavPasswordField.stringValue = preferences.webdavPassword
        webdavHistoryAutoSyncCheckbox.state = preferences.webdavHistoryAutoSync ? .on : .off
        webdavHistorySyncIntervalField.stringValue = "\(preferences.webdavHistorySyncIntervalValue)"
        selectPopup(webdavHistorySyncIntervalUnitPopup, value: preferences.webdavHistorySyncIntervalUnit, mapping: ["minute": "分钟", "hour": "小时", "day": "天", "week": "周"])
        refreshWebDAVHistorySyncStatus()
        updateWebDAVFieldsVisibility()
        updateWebDAVAutoSyncControls()
        clipboardCheckbox.state = preferences.clipboardMonitoring ? .on : .off
        compactTranslationWindowCheckbox.state = preferences.compactTranslationWindow ? .on : .off
        floatingSelectionButtonCheckbox.state = preferences.experimentalFloatingSelectionButton ? .on : .off
        refreshPlugins()
        if let plugin = PluginManager.shared.plugins().first(where: { $0.name == preferences.pluginName || $0.title == preferences.pluginName }) {
            let represented = (plugin.legacyDirectory as NSString?)?.lastPathComponent ?? plugin.name
            if let item = pluginPopup.itemArray.first(where: { ($0.representedObject as? String) == represented }) {
                pluginPopup.select(item)
                rebuildPluginConfigFields()
                updatePluginPathLabel()
            }
        }
    }

    private func persistSettings() {
        guard !isLoadingSettings else { return }
        let preferences = Preferences.shared
        let requestedAutoSync = webdavHistoryAutoSyncCheckbox.state == .on
        let webdavAddress = webdavURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var effectiveAutoSync = requestedAutoSync
        var autoSyncWarning: String?
        if requestedAutoSync && webdavAddress.isEmpty {
            effectiveAutoSync = false
            webdavHistoryAutoSyncCheckbox.state = .off
            autoSyncWarning = "WebDAV 地址为空，自动同步保持关闭"
        }
        let typedSyncInterval = Int(webdavHistorySyncIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let syncIntervalUnit = selectedPopupValue(webdavHistorySyncIntervalUnitPopup, mapping: ["minute": "分钟", "hour": "小时", "day": "天", "week": "周"])
        let secondsPerUnit = ["minute": 60, "hour": 3_600, "day": 86_400, "week": 604_800][syncIntervalUnit] ?? 3_600
        let maximumInterval = (366 * 86_400) / secondsPerUnit
        let validTypedInterval = typedSyncInterval.flatMap { (1...maximumInterval).contains($0) ? $0 : nil }
        let syncIntervalValue = validTypedInterval ?? preferences.webdavHistorySyncIntervalValue
        if requestedAutoSync && validTypedInterval == nil {
            effectiveAutoSync = false
            webdavHistoryAutoSyncCheckbox.state = .off
            autoSyncWarning = "自动同步间隔无效，自动同步保持关闭"
        }
        preferences.sourceLanguage = selectedLanguageCode(sourceLanguagePopup)
        preferences.targetLanguage = selectedLanguageCode(targetLanguagePopup)
        persistServiceFields()
        preferences.translateServiceList = serviceOrderList.orderedEnabledServices
        preferences.translateServiceOrder = serviceOrderList.orderedServices
        preferences.recognizeServiceList = recognizeServiceList.orderedEnabledServices
        preferences.ttsServiceList = ttsServiceList.orderedEnabledServices
        preferences.collectionServiceList = collectionServiceList.orderedEnabledServices
        preferences.recognizeLanguage = selectedLanguageCode(recognizeLanguagePopup)
        preferences.recognizeAutoCopy = recognizeAutoCopyCheckbox.state == .on
        preferences.recognizeDeleteNewline = recognizeDeleteNewlineCheckbox.state == .on
        preferences.hotkeySelectionTranslate = hotkeySelectionField.stringValue.isEmpty ? "⇧⌘E" : hotkeySelectionField.stringValue
        preferences.hotkeyInputTranslate = hotkeyInputField.stringValue.isEmpty ? "⇧⌘D" : hotkeyInputField.stringValue
        preferences.hotkeyOCRTranslate = hotkeyOCRTranslateField.stringValue.isEmpty ? "⇧⌘O" : hotkeyOCRTranslateField.stringValue
        preferences.hotkeyOCRRecognize = hotkeyOCRRecognizeField.stringValue.isEmpty ? "⇧⌘R" : hotkeyOCRRecognizeField.stringValue
        let duplicateHotkeyWarning = duplicateHotkeyWarning([
            "划词翻译": preferences.hotkeySelectionTranslate,
            "输入翻译": preferences.hotkeyInputTranslate,
            "截图翻译": preferences.hotkeyOCRTranslate,
            "截图 OCR": preferences.hotkeyOCRRecognize,
        ])
        preferences.proxyEnabled = proxyEnabledCheckbox.state == .on
        preferences.proxyHost = proxyHostField.stringValue
        preferences.proxyPort = proxyPortField.stringValue
        preferences.theme = selectedPopupValue(themePopup, mapping: ["system": "跟随系统", "light": "浅色", "dark": "深色"])
        preferences.themeColorHex = themeColorWell.color.potHexRGB
        preferences.translateAutoCopy = selectedPopupValue(autoCopyPopup, mapping: ["disable": "不自动复制", "source": "复制原文", "target": "复制译文", "source_target": "复制原文和译文"])
        preferences.translateWindowPosition = selectedPopupValue(windowPositionPopup, mapping: ["center": "居中", "mouse": "鼠标附近", "remember": "记住位置"])
        preferences.translateCloseOnBlur = closeOnBlurCheckbox.state == .on
        preferences.translateAlwaysOnTop = alwaysOnTopCheckbox.state == .on
        preferences.translateRememberWindowSize = rememberWindowSizeCheckbox.state == .on
        preferences.translateDeleteNewline = translateDeleteNewlineCheckbox.state == .on
        preferences.smartTargetLanguage = smartTargetCheckbox.state == .on
        preferences.translateSecondLanguage = selectedLanguageCode(secondTargetLanguagePopup)
        preferences.hideSource = hideSourceCheckbox.state == .on
        preferences.hideLanguage = hideLanguageCheckbox.state == .on
        preferences.dynamicTranslate = dynamicTranslateCheckbox.state == .on
        preferences.incrementalTranslate = incrementalTranslateCheckbox.state == .on
        let fontWarning = normalizeAndPersistFontSettings(preferences)
        preferences.trayClickEvent = selectedPopupValue(trayClickPopup, mapping: ["config": "显示设置", "translate": "显示翻译窗口", "history": "显示历史记录"])
        preferences.launchAtLogin = launchAtLoginCheckbox.state == .on
        preferences.checkUpdate = checkUpdateCheckbox.state == .on
        let rawServerPort = Int(serverPortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 60828
        let normalizedServerPort = (1...65_535).contains(rawServerPort) ? rawServerPort : 60828
        preferences.serverPort = normalizedServerPort
        serverPortField.stringValue = "\(normalizedServerPort)"
        preferences.historyDisable = historyDisableCheckbox.state == .on
        preferences.recognizeHideWindow = recognizeHideWindowCheckbox.state == .on
        preferences.recognizeCloseOnBlur = recognizeCloseOnBlurCheckbox.state == .on
        preferences.proxyUsername = proxyUsernameField.stringValue
        preferences.proxyPassword = proxyPasswordField.stringValue
        preferences.noProxy = noProxyField.stringValue
        preferences.backupType = selectedPopupValue(backupTypePopup, mapping: ["local": "本地", "webdav": "WebDAV"])
        preferences.webdavURL = webdavAddress
        preferences.webdavUsername = webdavUsernameField.stringValue
        preferences.webdavPassword = webdavPasswordField.stringValue
        preferences.webdavHistoryAutoSync = effectiveAutoSync
        preferences.webdavHistorySyncIntervalUnit = syncIntervalUnit
        preferences.webdavHistorySyncIntervalValue = syncIntervalValue
        webdavHistorySyncIntervalField.stringValue = "\(preferences.webdavHistorySyncIntervalValue)"
        if let pluginName = currentPluginName {
            preferences.pluginName = pluginName
        } else {
            preferences.pluginName = ""
        }
        for name in pluginListFields.keys {
            do {
                try PluginManager.shared.setPluginConfig(collectPluginConfig(for: name), forPluginName: name)
            } catch {
                showInfoBanner("插件 \(name) 自动保存失败：\(error.localizedDescription)")
            }
        }
        preferences.clipboardMonitoring = clipboardCheckbox.state == .on
        preferences.compactTranslationWindow = compactTranslationWindowCheckbox.state == .on
        preferences.experimentalFloatingSelectionButton = floatingSelectionButtonCheckbox.state == .on
        updateSidebarSelection()
        PythiaAppDelegate.shared?.applyClipboardPreference()
        let runtimeWarning = PythiaAppDelegate.shared?.applyRuntimePreferences()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        let portWarning = rawServerPort == normalizedServerPort ? nil : "外部服务端口无效，已恢复为 60828"
        let credentialWarning = preferences.consumeCredentialStorageError().map { "凭据未能保存到本地：\($0)" }
        let warning = [autoSyncWarning, duplicateHotkeyWarning, portWarning, fontWarning, runtimeWarning, credentialWarning]
            .compactMap { $0 }
            .joined(separator: "；")
        if !warning.isEmpty {
            showInfoBanner("设置已自动保存；\(warning)")
        }
    }

    private func duplicateHotkeyWarning(_ hotkeys: [String: String]) -> String? {
        var buckets: [String: [String]] = [:]
        for (name, value) in hotkeys {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            buckets[key, default: []].append(name)
        }
        let duplicates = buckets
            .filter { $0.value.count > 1 }
            .map { "\($0.value.sorted().joined(separator: "、")) 共用 \($0.key.uppercased())" }
            .sorted()
        guard !duplicates.isEmpty else { return nil }
        return "快捷键重复：\(duplicates.joined(separator: "；"))"
    }

    private func normalizeAndPersistFontSettings(_ preferences: Preferences) -> String? {
        var warnings: [String] = []

        let rawFont = appFontField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawFont.isEmpty || rawFont.lowercased() == "default" {
            preferences.appFont = "default"
            appFontField.stringValue = "default"
        } else if NSFont(name: rawFont, size: 16) != nil {
            preferences.appFont = rawFont
        } else {
            preferences.appFont = "default"
            appFontField.stringValue = "default"
            warnings.append("界面字体不存在，已恢复默认")
        }

        let rawFallback = appFallbackFontField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawFallback.isEmpty || rawFallback.lowercased() == "default" {
            preferences.appFallbackFont = "default"
            appFallbackFontField.stringValue = "default"
        } else if NSFont(name: rawFallback, size: 16) != nil {
            preferences.appFallbackFont = rawFallback
        } else {
            preferences.appFallbackFont = "default"
            appFallbackFontField.stringValue = "default"
            warnings.append("回退字体不存在，已恢复默认")
        }

        let rawSize = Int(appFontSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 16
        let normalizedSize = min(28, max(11, rawSize))
        preferences.appFontSize = normalizedSize
        appFontSizeField.stringValue = "\(normalizedSize)"
        if rawSize != normalizedSize {
            warnings.append("界面字号已限制在 11-28")
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: "；")
    }

    private func reloadServiceLists() {
        let preferences = Preferences.shared
        let knownTranslateServices = Set(PluginManager.shared.translationServiceOptions().map(\.id))
        let savedOrder = preferences.translateServiceOrder
        let customIDs = (savedOrder + preferences.translateServiceList).filter { !$0.isEmpty && !knownTranslateServices.contains($0) }
        serviceOrderList.load(orderedServices: savedOrder, enabledServices: preferences.translateServiceList, customIDs: customIDs)

        let knownRecognizeServices = Set(PluginManager.shared.serviceOptions(for: "recognize").map(\.id))
        let recognizeCustomIDs = preferences.recognizeServiceList.filter { !$0.isEmpty && !knownRecognizeServices.contains($0) }
        recognizeServiceList.load(orderedEnabled: preferences.recognizeServiceList, customIDs: recognizeCustomIDs)

        let knownTTSServices = Set(PluginManager.shared.serviceOptions(for: "tts").map(\.id))
        let ttsCustomIDs = preferences.ttsServiceList.filter { !$0.isEmpty && !knownTTSServices.contains($0) }
        ttsServiceList.load(orderedEnabled: preferences.ttsServiceList, customIDs: ttsCustomIDs)

        let knownCollectionServices = Set(PluginManager.shared.serviceOptions(for: "collection").map(\.id))
        let collectionCustomIDs = preferences.collectionServiceList.filter { !$0.isEmpty && !knownCollectionServices.contains($0) }
        collectionServiceList.load(orderedEnabled: preferences.collectionServiceList, customIDs: collectionCustomIDs)
    }

    @objc private func themeColorChanged() {
        guard !isLoadingSettings else { return }
        Preferences.shared.themeColorHex = themeColorWell.color.potHexRGB
        updateSidebarSelection()
        // Re-color the live translation window's icon buttons / titles now.
        PythiaAppDelegate.shared?.applyRuntimePreferences()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        // Recreate the visible page so the large title and About hero use the
        // new theme color immediately, without requiring a window reopen.
        persistSettings()
        showTab(index: selectedSettingsIndex)
    }

    @objc private func trayClickEventChanged() {
        Preferences.shared.trayClickEvent = selectedPopupValue(
            trayClickPopup,
            mapping: ["config": "显示设置", "translate": "显示翻译窗口", "history": "显示历史记录"]
        )
        scheduleAutosave()
    }

    private func selectPopup(_ popup: NSPopUpButton, value: String, mapping: [String: String]) {
        // Match by key first; fall back to matching by value (handles legacy
        // data that may have stored the display title instead of the key).
        let title = mapping[value]
            ?? mapping.first(where: { $0.value == value })?.value
            ?? mapping.values.first
            ?? ""
        popup.selectItem(withTitle: title)
    }

    private func selectedPopupValue(_ popup: NSPopUpButton, mapping: [String: String]) -> String {
        let title = popup.titleOfSelectedItem ?? ""
        return mapping.first(where: { $0.value == title })?.key ?? mapping.keys.sorted().first ?? ""
    }

    @objc private func requestPermissions() {
        let accessibilityGranted = SelectionReader.shared.requestAccessibilityPermission()
        let screenWasGranted = OCRService.shared.hasScreenCapturePermission
        let screenGranted = screenWasGranted || OCRService.shared.requestScreenCapturePermission()
        if screenGranted && !screenWasGranted {
            showInfoBanner("屏幕录制权限已启用，Pythia 将自动重启使权限生效。")
            PythiaAppDelegate.shared?.relaunchAfterPermissionChange()
        } else if accessibilityGranted && screenGranted {
            showInfoBanner("辅助功能与屏幕录制权限均已启用。")
        } else {
            showInfoBanner("请在系统设置中允许 Pythia 使用辅助功能与屏幕录制。")
        }
    }

    @objc private func checkForUpdates() {
        setAboutUpdateBusy(true)
        showUpdateBanner("正在检查更新…", kind: .info, duration: nil)
        PythiaUpdateChecker.shared.check { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setAboutUpdateBusy(false)
                switch result {
                case .success(let info):
                    if info.isNewer {
                        self.showUpdateAvailable(info)
                    } else {
                        self.showUpdateBanner(
                            "当前版本 \(info.currentVersion) 已是最新版本。",
                            kind: .success
                        )
                    }
                case .failure(let error):
                    self.showUpdateBanner(
                        "检查更新失败：\(error.localizedDescription)",
                        kind: .error
                    )
                }
            }
        }
    }

    private func setAboutUpdateBusy(_ busy: Bool) {
        aboutCheckButton?.isEnabled = !busy
    }

    private func showUpdateAvailable(_ info: PythiaUpdateInfo) {
        // Keep the main-window action in sync with the About-page banner so a
        // manual check also exposes the same one-click hot update beside the
        // Pythia title.
        PythiaAppDelegate.shared?.showAvailableUpdateOnMain(info)
        let openRelease: (() -> Void)? = info.releaseURL.map { url in
            { [weak self] in
                self?.dismissUpdateBanner()
                NSWorkspace.shared.open(url)
            }
        }
        let startUpdate: (() -> Void)? = info.assetURL == nil ? nil : { [weak self] in
            self?.dismissUpdateBanner()
            self?.startHotUpdate(info)
        }
        showUpdateBanner(
            "发现新版本 \(info.latestVersion)：\(info.releaseName)",
            kind: .success,
            primaryTitle: startUpdate == nil ? nil : "立即更新",
            primaryAction: startUpdate,
            secondaryTitle: openRelease == nil ? nil : "打开发布页",
            secondaryAction: openRelease
        )
    }

    private func showUpdateBanner(
        _ message: String,
        kind: PythiaTopInfoBannerKind,
        duration: TimeInterval? = 5,
        primaryTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        updateBannerGeneration += 1
        let generation = updateBannerGeneration
        updateBannerDismissWorkItem?.cancel()
        updateBannerDismissWorkItem = nil
        updateBanner.configure(
            message: message,
            kind: kind,
            primaryTitle: primaryTitle,
            primaryAction: primaryAction,
            secondaryTitle: secondaryTitle,
            secondaryAction: secondaryAction
        )
        updateBanner.alphaValue = 1
        updateBanner.isHidden = false

        guard let duration else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.updateBannerGeneration == generation else { return }
            self.dismissUpdateBanner()
        }
        updateBannerDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func dismissUpdateBanner() {
        updateBannerGeneration += 1
        updateBannerDismissWorkItem?.cancel()
        updateBannerDismissWorkItem = nil
        updateBanner.isHidden = true
        updateBanner.alphaValue = 1
    }

    /// Hot update: download the release DMG, verify its signing identity,
    /// replace /Applications/Pythia.app, and relaunch. Falls back to opening
    /// the DMG when /Applications is not writable.
    private func startHotUpdate(_ info: PythiaUpdateInfo) {
        setAboutUpdateBusy(true)
        showUpdateBanner("正在下载 \(info.latestVersion)…", kind: .info, duration: nil)
        PythiaUpdateInstaller.shared.download(
            info: info,
            progress: { [weak self] fraction in
                DispatchQueue.main.async {
                    self?.showUpdateBanner(
                        "正在下载 \(info.latestVersion)… \(Int(fraction * 100))%",
                        kind: .info,
                        duration: nil
                    )
                }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let dmgURL):
                    self.showUpdateBanner("下载完成，正在校验并安装…", kind: .info, duration: nil)
                    PythiaUpdateInstaller.shared.install(from: dmgURL) { [weak self] installResult in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.setAboutUpdateBusy(false)
                            switch installResult {
                            case .success(.installed(let appURL, let rollbackURL)):
                                self.showUpdateBanner("版本 \(info.latestVersion) 安装完成，正在重启…", kind: .success)
                                self.relaunch(updatedApp: appURL, rollbackURL: rollbackURL)
                            case .success(.openedInstaller(let url)):
                                self.showUpdateBanner(
                                    "已打开 \(url.lastPathComponent)，请将 Pythia 拖入「应用程序」完成更新。",
                                    kind: .success
                                )
                            case .failure(let error):
                                self.showUpdateBanner("更新失败：\(error.localizedDescription)", kind: .error)
                            }
                        }
                    }
                case .failure(let error):
                    self.setAboutUpdateBusy(false)
                    self.showUpdateBanner("更新失败：\(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    private func relaunch(updatedApp appURL: URL, rollbackURL: URL?) {
        PythiaUpdateInstaller.shared.relaunch(appURL: appURL, rollbackURL: rollbackURL) { [weak self] _ in
            self?.showInfoBanner(
                "更新已安装，请退出当前 Pythia 后重新打开 /Applications/Pythia.app。",
                isError: true
            )
        }
    }

    @objc private func openPluginFolder() {
        try? FileManager.default.createDirectory(
            at: PluginManager.shared.pluginsDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(PluginManager.shared.pluginsDirectory)
    }

    @objc private func openPluginDevelopmentGuide() {
        guard let url = URL(string: "https://github.com/douxy1994/Pythia/blob/master/Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md") else {
            showAlert("插件开发指南地址无效。")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openGitHubProject() {
        guard let url = URL(string: "https://github.com/douxy1994/Pythia") else {
            showAlert("GitHub 项目地址无效。")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func deleteSelectedPlugin() {
        guard let name = currentPluginName else {
            showAlert("请先选择一个插件。")
            return
        }
        let displayName = (pluginPopup.titleOfSelectedItem ?? name)
            .components(separatedBy: " · ")
            .first ?? name
        deletePlugin(named: name, displayName: displayName)
    }

    private func deletePlugin(named name: String, displayName: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除「\(displayName)」？"
        alert.informativeText = "插件文件、本机配置及其在翻译、OCR、TTS 和生词本服务中的引用都会被删除。此操作无法撤销。"
        alert.addButton(withTitle: "删除插件")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try PluginManager.shared.deletePlugin(name: name)
            refreshPlugins()
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            showAlert("已删除插件「\(displayName)」。")
        } catch {
            showAlert("删除插件失败：\(error.localizedDescription)")
        }
    }

    @objc private func installPlugin() {
        let panel = NSOpenPanel()
        panel.title = "安装 Pythia 插件"
        panel.message = "优先选择 .pythia；也支持兼容 .potext。"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [
                UTType(filenameExtension: "pythia") ?? .data,
                UTType(filenameExtension: "potext") ?? .data,
            ]
        } else {
            panel.allowedFileTypes = ["pythia", "potext"]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let message = try PluginManager.shared.installPlugin(from: url)
            refreshPlugins()
            load()
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            showAlert(message)
        } catch {
            showAlert("安装插件失败：\(error.localizedDescription)")
        }
    }

    @objc private func refreshPlugins() {
        rebuildPluginPopup()
        rebuildPluginConfigFields()
        rebuildPluginList()
        updatePluginPathLabel()
        reloadServiceLists()
        pluginTestResultLabel.stringValue = ""
    }

    @objc private func reconvertSelectedPlugin() {
        guard let name = currentPluginName else {
            showAlert("请先选择一个插件。")
            return
        }
        do {
            let target = try PluginManager.shared.convertLegacyPlugin(name: name, replaceExisting: true)
            refreshPlugins()
            if let item = pluginPopup.itemArray.first(where: { ($0.representedObject as? String) == name }) {
                pluginPopup.select(item)
            }
            updatePluginPathLabel()
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            showAlert("已重新转换为 \(target.lastPathComponent)。原 .potext 备份保持不变。")
        } catch {
            showAlert("重新转换失败，插件继续使用当前可用版本：\(error.localizedDescription)")
        }
    }

    @objc private func renamePlugin() {
        guard let name = currentPluginName else {
            showAlert("请先选择一个插件。")
            return
        }
        let currentTitle = (pluginPopup.titleOfSelectedItem ?? name)
            .components(separatedBy: " · ")
            .first ?? name
        let alert = NSAlert()
        alert.messageText = "重命名插件"
        alert.informativeText = "只修改 Pythia 中显示的名称，不会改动插件目录、服务标识或已有配置。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = currentTitle
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            showAlert("插件名称不能为空。")
            return
        }
        PluginManager.shared.renamePluginDisplay(name: name, displayName: newName)
        rebuildPluginPopup()
        if let item = pluginPopup.itemArray.first(where: { ($0.representedObject as? String) == name }) {
            pluginPopup.select(item)
        }
        rebuildPluginConfigFields()
        updatePluginPathLabel()
        reloadServiceLists()
        pluginTestResultLabel.stringValue = "已重命名为 \(newName)"
        pluginTestResultLabel.textColor = PythiaDesign.themeColor()
        PythiaAppDelegate.shared?.setStatus("已重命名插件为 \(newName)")
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func migrateConfig() {
        let configMessage = MigrationService.shared.migrateFromTauriPot()
        let pluginMessage = PluginManager.shared.importLegacyPluginsFromOldPot()
        load()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        showAlert("\(configMessage)\n\(pluginMessage)")
    }

    @objc private func importLegacyPlugins() {
        let message = PluginManager.shared.importLegacyPluginsFromOldPot()
        load()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        showAlert(message)
    }

    @objc private func resetTranslateServices() {
        let builtIns = PythiaProvider.allCases
            .filter { $0 != .plugin }
            .map(\.rawValue)
        serviceOrderList.load(orderedServices: builtIns, enabledServices: builtIns, customIDs: [])
    }

    /// Prompts for a custom service ID (e.g. plugin:custom-name) and appends it
    /// to the service list, enabled.
    @objc private func addCustomServiceID() {
        let alert = NSAlert()
        alert.messageText = "添加自定义服务 ID"
        alert.informativeText = "输入服务标识符，例如 plugin:custom-name。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let id = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        serviceOrderList.appendCustom(id: id)
    }

    @objc private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Pythia-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Use the shared snapshot builder so local export includes history
            // (same as WebDAV backup).
            let historyCount = HistoryStore.shared.records.count
            guard let data = PythiaBackupService.configSnapshotData() else {
                showAlert("生成配置失败。")
                return
            }
            try data.write(to: url, options: [.atomic])
            showAlert("可移植设置和 \(historyCount) 条历史记录已导出。API Key、WebDAV 账号、快捷键、窗口设置、插件配置和密码不会写入备份。")
        } catch {
            showAlert("导出配置失败：\(error.localizedDescription)")
        }
    }

    @objc private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let importResult = try PythiaBackupService.importBackupData(data)
            PythiaAppDelegate.shared?.applyRuntimePreferences()
            load()
            let sensitiveText = importResult.skippedSensitiveCount > 0 ? "已跳过 \(importResult.skippedSensitiveCount) 个敏感字段；API Key、密码和插件配置请在本机设置页重新填写或使用迁移功能导入。" : ""
            showAlert("配置已导入。\(sensitiveText)")
        } catch {
            showAlert("导入配置失败：\(error.localizedDescription)")
        }
    }

    @objc private func exportHistoryFromSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pythia-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = HistoryStore.shared.records.count
            try HistoryStore.shared.export(to: url)
            showAlert("已导出 \(count) 条历史记录。")
        } catch {
            showAlert("导出历史失败：\(error.localizedDescription)")
        }
    }

    @objc private func backupToWebDAV() {
        // Read the CURRENT field values (not the persisted ones) so the user
        // does not have to click "保存" before backing up. Persist them too.
        let urlValue = webdavURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = webdavUsernameField.stringValue
        let password = webdavPasswordField.stringValue
        guard !urlValue.isEmpty else {
            showAlert("请先填写 WebDAV 地址。")
            return
        }
        // Persist what was typed so a later save() keeps it consistent.
        let prefs = Preferences.shared
        prefs.webdavURL = urlValue
        prefs.webdavUsername = user
        prefs.webdavPassword = password
        let historyCount = HistoryStore.shared.records.count
        guard let data = PythiaBackupService.configSnapshotData() else {
            showAlert("生成配置失败。")
            return
        }
        webdavTestResultLabel.stringValue = "备份中…"
        webdavTestResultLabel.textColor = .secondaryLabelColor
        PythiaBackupService.backupToWebDAV(base: urlValue, user: user, password: password, data: data) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if let errorMsg = result.errorMessage {
                    self.webdavTestResultLabel.stringValue = "✗ 备份失败：\(errorMsg)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.showAlert("WebDAV 备份失败：\(errorMsg)")
                } else if result.isSuccess {
                    self.webdavTestResultLabel.stringValue = "✓ 已备份配置和 \(historyCount) 条历史记录到 WebDAV（HTTP \(result.httpCode)）"
                    self.webdavTestResultLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.2, alpha: 1)
                    self.showAlert("已备份配置和 \(historyCount) 条历史记录到 WebDAV。")
                } else {
                    let hint = PythiaBackupService.webDAVErrorHint(code: result.httpCode)
                    self.webdavTestResultLabel.stringValue = "✗ 备份失败（HTTP \(result.httpCode)）\(hint)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.showAlert("WebDAV 备份失败（HTTP \(result.httpCode)）。\(hint)")
                }
            }
        }
    }

    @objc private func syncHistoryWithWebDAV() {
        let urlValue = webdavURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = webdavUsernameField.stringValue
        let password = webdavPasswordField.stringValue
        guard !urlValue.isEmpty else {
            showAlert("请先填写 WebDAV 地址。")
            return
        }
        let prefs = Preferences.shared
        prefs.webdavURL = urlValue
        prefs.webdavUsername = user
        prefs.webdavPassword = password
        webdavTestResultLabel.stringValue = "正在同步历史…"
        webdavTestResultLabel.textColor = .secondaryLabelColor
        PythiaBackupService.syncHistoryToWebDAV(base: urlValue, user: user, password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if let errorMsg = result.errorMessage {
                    self.webdavTestResultLabel.stringValue = "✗ 历史同步失败：\(errorMsg)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.refreshWebDAVHistorySyncStatus()
                    self.showAlert("WebDAV 历史同步失败：\(errorMsg)")
                } else if result.isSuccess {
                    let conflictText = result.conflictCount > 0 ? "，\(result.conflictCount) 条冲突已标记" : ""
                    self.webdavTestResultLabel.stringValue = "✓ 历史同步完成：远程 \(result.downloadedCount) 条，本机 \(result.visibleCount) 条\(conflictText)"
                    self.webdavTestResultLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.2, alpha: 1)
                    self.refreshWebDAVHistorySyncStatus()
                    self.showAlert("历史同步完成。远程读取 \(result.downloadedCount) 条，上传 \(result.uploadedCount) 条，本机可见 \(result.visibleCount) 条\(conflictText)。")
                } else {
                    let hint = PythiaBackupService.webDAVErrorHint(code: result.httpCode)
                    self.webdavTestResultLabel.stringValue = "✗ 历史同步失败（HTTP \(result.httpCode)）\(hint)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.refreshWebDAVHistorySyncStatus()
                    self.showAlert("WebDAV 历史同步失败（HTTP \(result.httpCode)）。\(hint)")
                }
            }
        }
    }

    @objc private func restoreFromWebDAV() {
        // Read the CURRENT field values (not the persisted ones).
        let urlValue = webdavURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = webdavUsernameField.stringValue
        let password = webdavPasswordField.stringValue
        guard !urlValue.isEmpty else {
            showAlert("请先填写 WebDAV 地址。")
            return
        }
        let prefs = Preferences.shared
        prefs.webdavURL = urlValue
        prefs.webdavUsername = user
        prefs.webdavPassword = password
        let auth = PythiaBackupService.webDAVAuthHeader(user: user, password: password)
        let urls = [
            PythiaBackupService.webDAVBackupFileURL(base: urlValue),
            PythiaBackupService.legacyWebDAVBackupFileURL(base: urlValue),
            PythiaBackupService.oldestWebDAVBackupFileURL(base: urlValue),
        ]
        webdavTestResultLabel.stringValue = "恢复中…"
        webdavTestResultLabel.textColor = .secondaryLabelColor
        PythiaBackupService.fetchFirstWebDAVBackup(urls: urls, auth: auth) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.webdavTestResultLabel.stringValue = "✗ 恢复失败：\(error.localizedDescription)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.showAlert("WebDAV 恢复失败：\(error.localizedDescription)")
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    let hint = PythiaBackupService.webDAVErrorHint(code: http.statusCode)
                    self.webdavTestResultLabel.stringValue = "✗ 恢复失败（HTTP \(http.statusCode)）\(hint)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.showAlert("WebDAV 恢复失败（HTTP \(http.statusCode)）。\(hint)")
                    return
                }
                guard let data else {
                    self.webdavTestResultLabel.stringValue = "✗ 恢复失败：备份文件格式无效"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.showAlert("恢复失败：备份文件格式无效。")
                    return
                }
                let importResult: PythiaConfigImportResult
                do {
                    importResult = try PythiaBackupService.importBackupData(data)
                } catch {
                    self.webdavTestResultLabel.stringValue = "✗ 恢复失败：\(error.localizedDescription)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    self.showAlert("恢复失败：\(error.localizedDescription)")
                    return
                }
                PythiaAppDelegate.shared?.applyRuntimePreferences()
                self.load()
                let historyText = importResult.restoredHistoryCount > 0 ? "和 \(importResult.restoredHistoryCount) 条历史记录" : ""
                let sensitiveText = importResult.skippedSensitiveCount > 0 ? "，已跳过 \(importResult.skippedSensitiveCount) 个敏感字段" : ""
                self.webdavTestResultLabel.stringValue = "✓ 已从 WebDAV 恢复配置\(historyText)"
                self.webdavTestResultLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.2, alpha: 1)
                self.showAlert("已从 WebDAV 恢复配置\(historyText)\(sensitiveText)。")
            }
        }
    }

    /// Tests WebDAV connectivity with a PROPFIND on the base URL. Reports a
    /// human-readable status (HTTP code + hint) into webdavTestResultLabel.
    @objc private func testWebDAVConnection() {
        let urlValue = webdavURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = webdavUsernameField.stringValue
        let password = webdavPasswordField.stringValue
        guard !urlValue.isEmpty else {
            webdavTestResultLabel.stringValue = "✗ 请先填写 WebDAV 地址"
            webdavTestResultLabel.textColor = .systemRed
            return
        }
        // Persist what was typed.
        let prefs = Preferences.shared
        prefs.webdavURL = urlValue
        prefs.webdavUsername = user
        prefs.webdavPassword = password
        webdavTestResultLabel.stringValue = "测试中，正在确认备份目录…"
        webdavTestResultLabel.textColor = .secondaryLabelColor
        PythiaBackupService.testWebDAVConnection(base: urlValue, user: user, password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error = result.errorMessage {
                    self.webdavTestResultLabel.stringValue = result.httpCode == -1 ? "✗ 无法连接：\(error)" : "✗ 无法创建/确认目录：\(error)"
                    self.webdavTestResultLabel.textColor = .systemRed
                    return
                }
                if result.isSuccess {
                    self.webdavTestResultLabel.stringValue = "✓ 连通正常（HTTP \(result.httpCode)），备份目录可用"
                    self.webdavTestResultLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.2, alpha: 1)
                } else {
                    let hint = PythiaBackupService.webDAVErrorHint(code: result.httpCode)
                    self.webdavTestResultLabel.stringValue = "✗ 连接失败（HTTP \(result.httpCode)）\(hint)"
                    self.webdavTestResultLabel.textColor = .systemRed
                }
            }
        }
    }

    /// Presents the same transient top information strip used by update
    /// checking for settings-page results and runtime reminders.
    func showInfoBanner(_ message: String, isError: Bool = false) {
        showUpdateBanner(message, kind: isError ? .error : .info)
    }

    /// Used by the app delegate's background update check so startup updates
    /// use the same non-modal presentation as a manual check.
    func showAvailableUpdateBanner(_ info: PythiaUpdateInfo) {
        showUpdateAvailable(info)
    }

    private func showAlert(_ message: String) {
        showInfoBanner(message)
    }
}

enum PythiaTopInfoBannerKind {
    case info
    case success
    case error

    var iconName: String {
        switch self {
        case .info, .success:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    func backgroundColor() -> NSColor {
        switch self {
        case .info, .success:
            return PythiaDesign.themeColor()
        case .error:
            return .systemRed
        }
    }
}

/// A compact transient banner matching AI Memory's top information strip.
/// It owns only presentation; SettingsWindowController supplies the actions.
final class PythiaTopInfoBannerView: AdaptiveLiquidGlassView {
    var onDismiss: (() -> Void)?

    private let iconView = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let actions = NSStackView()
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)
    private let dismissButton = NSButton(
        image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭提示") ?? NSImage(),
        target: nil,
        action: nil
    )
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?

    init() {
        super.init(cornerRadius: 14, interactive: true)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = PythiaDesign.themeColor()

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.maximumNumberOfLines = 1
        messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureActionButton(primaryButton, action: #selector(primaryButtonClicked(_:)))
        configureActionButton(secondaryButton, action: #selector(secondaryButtonClicked(_:)))

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.isBordered = false
        dismissButton.bezelStyle = .inline
        dismissButton.imagePosition = .imageOnly
        dismissButton.contentTintColor = .secondaryLabelColor
        dismissButton.toolTip = "关闭提示"
        dismissButton.target = self
        dismissButton.action = #selector(dismissButtonClicked(_:))

        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6
        actions.addArrangedSubview(primaryButton)
        actions.addArrangedSubview(secondaryButton)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [iconView, messageLabel, spacer, actions, dismissButton])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 10)
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),
            dismissButton.widthAnchor.constraint(equalToConstant: 18),
            dismissButton.heightAnchor.constraint(equalToConstant: 18),
        ])
        configure(
            message: "",
            kind: .info,
            primaryTitle: nil,
            primaryAction: nil,
            secondaryTitle: nil,
            secondaryAction: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        message: String,
        kind: PythiaTopInfoBannerKind,
        primaryTitle: String?,
        primaryAction: (() -> Void)?,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) {
        iconView.image = NSImage(systemSymbolName: kind.iconName, accessibilityDescription: nil)
        iconView.contentTintColor = kind.backgroundColor()
        messageLabel.textColor = .labelColor
        primaryButton.contentTintColor = kind.backgroundColor()
        secondaryButton.contentTintColor = kind.backgroundColor()
        messageLabel.stringValue = message

        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        primaryButton.title = primaryTitle ?? ""
        primaryButton.isHidden = primaryTitle == nil || primaryAction == nil
        secondaryButton.title = secondaryTitle ?? ""
        secondaryButton.isHidden = secondaryTitle == nil || secondaryAction == nil
        primaryButton.sizeToFit()
        secondaryButton.sizeToFit()
    }

    private func configureActionButton(_ button: NSButton, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryPushIn)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .white
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @objc private func primaryButtonClicked(_ sender: NSButton) {
        primaryAction?()
    }

    @objc private func secondaryButtonClicked(_ sender: NSButton) {
        secondaryAction?()
    }

    @objc private func dismissButtonClicked(_ sender: NSButton) {
        onDismiss?()
    }
}
