import AppKit
import Foundation
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let tabTitles = ["通用", "翻译", "服务", "OCR", "TTS", "生词本", "插件", "快捷键", "历史", "代理", "备份", "迁移", "关于"]
    private let sidebarStack = FlippedStackView()
    private var sidebarItems: [SettingsSidebarItemView] = []
    private var selectedSettingsIndex = 0
    private let tabCard = NSVisualEffectView()
    private var activeTabView: NSView?
    private var activeTabConstraints: [NSLayoutConstraint] = []
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let secondTargetLanguagePopup = NSPopUpButton()
    private let openAIKeyField = NSSecureTextField()
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
    private let clipboardCheckbox = NSButton(checkboxWithTitle: "监听剪贴板", target: nil, action: nil)
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
    private let saveStatusLabel = NSTextField(labelWithString: "")
    private let aboutUpdateStatusLabel = NSTextField(labelWithString: "")
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
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
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
        window.minSize = NSSize(width: 820, height: 560)
        super.init(window: window)
        window.delegate = self
        recognizeServiceList.optionProvider = { PluginManager.shared.serviceOptions(for: "recognize") }
        ttsServiceList.optionProvider = { PluginManager.shared.serviceOptions(for: "tts") }
        collectionServiceList.optionProvider = { PluginManager.shared.serviceOptions(for: "collection") }
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

        let title = NSTextField(labelWithString: "设置")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = .labelColor
        content.addSubview(title)

        let sidebarMaterial = NSVisualEffectView()
        sidebarMaterial.translatesAutoresizingMaskIntoConstraints = false
        sidebarMaterial.material = .sidebar
        sidebarMaterial.blendingMode = .withinWindow
        sidebarMaterial.state = .active
        sidebarMaterial.wantsLayer = true
        sidebarMaterial.layer?.cornerRadius = 18
        sidebarMaterial.layer?.cornerCurve = .continuous
        sidebarMaterial.layer?.masksToBounds = true
        sidebarMaterial.layer?.borderWidth = 1
        sidebarMaterial.layer?.borderColor = PythiaDesign.glassBorderColor(for: content.effectiveAppearance).cgColor
        content.addSubview(sidebarMaterial)

        let sidebarScroll = NSScrollView()
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.hasHorizontalScroller = false
        sidebarScroll.drawsBackground = false
        sidebarScroll.borderType = .noBorder
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .width
        sidebarStack.spacing = 4
        sidebarStack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.documentView = sidebarStack
        sidebarMaterial.addSubview(sidebarScroll)
        buildSidebarItems()

        tabCard.translatesAutoresizingMaskIntoConstraints = false
        tabCard.material = .contentBackground
        tabCard.blendingMode = .withinWindow
        tabCard.state = .active
        tabCard.wantsLayer = true
        tabCard.layer?.cornerRadius = 20
        tabCard.layer?.cornerCurve = .continuous
        tabCard.layer?.masksToBounds = true
        tabCard.layer?.borderWidth = 1
        tabCard.layer?.borderColor = PythiaDesign.glassBorderColor(for: content.effectiveAppearance).cgColor
        content.addSubview(tabCard)
        showTab(index: 0)

        let buttons = NSStackView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.spacing = 10
        saveStatusLabel.textColor = PythiaDesign.themeColor()
        saveStatusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        buttons.addArrangedSubview(saveStatusLabel)
        buttons.addArrangedSubview(PillButton("保存", target: self, action: #selector(save)))
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),

            sidebarMaterial.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            sidebarMaterial.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            sidebarMaterial.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),
            sidebarMaterial.widthAnchor.constraint(equalToConstant: 168),

            sidebarScroll.leadingAnchor.constraint(equalTo: sidebarMaterial.leadingAnchor, constant: 8),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebarMaterial.trailingAnchor, constant: -8),
            sidebarScroll.topAnchor.constraint(equalTo: sidebarMaterial.topAnchor, constant: 10),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebarMaterial.bottomAnchor, constant: -10),
            sidebarStack.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor),
            sidebarStack.heightAnchor.constraint(greaterThanOrEqualTo: sidebarScroll.contentView.heightAnchor),

            tabCard.leadingAnchor.constraint(equalTo: sidebarMaterial.trailingAnchor, constant: 16),
            tabCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            tabCard.topAnchor.constraint(equalTo: sidebarMaterial.topAnchor),
            tabCard.bottomAnchor.constraint(equalTo: sidebarMaterial.bottomAnchor),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            buttons.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    private func buildSidebarItems() {
        sidebarStack.arrangedSubviews.forEach { item in
            sidebarStack.removeArrangedSubview(item)
            item.removeFromSuperview()
        }
        sidebarItems = tabTitles.enumerated().map { index, title in
            SettingsSidebarItemView(title: title, index: index, target: self, action: #selector(sidebarItemClicked(_:)))
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
        stack.addArrangedSubview(row("翻译服务", serviceOrderList))
        stack.addArrangedSubview(note("主界面翻译会同时请求此处勾选的服务，并按此处顺序在译文区分组显示。"))
        stack.addArrangedSubview(row("外观", themePopup))
        stack.addArrangedSubview(row("主题色", themeColorWell))
        stack.addArrangedSubview(row("界面字体", appFontField))
        stack.addArrangedSubview(row("界面字号", appFontSizeField))
        stack.addArrangedSubview(row("回退字体", appFallbackFontField))
        stack.addArrangedSubview(row("源语言", sourceLanguagePopup))
        stack.addArrangedSubview(row("目标语言", targetLanguagePopup))
        autoCopyPopup.removeAllItems()
        autoCopyPopup.addItems(withTitles: ["不自动复制", "复制原文", "复制译文", "复制原文和译文"])
        stack.addArrangedSubview(row("自动复制", autoCopyPopup))
        stack.addArrangedSubview(indented(clipboardCheckbox))
        stack.addArrangedSubview(row("托盘点击", trayClickPopup))
        stack.addArrangedSubview(indented(launchAtLoginCheckbox))
        stack.addArrangedSubview(indented(checkUpdateCheckbox))
        stack.addArrangedSubview(note("开机启动使用 macOS 登录项注册。如果系统要求批准，请在「系统设置 > 通用 > 登录项」允许 Pythia。"))
        stack.addArrangedSubview(row("外部服务端口", serverPortField))
        // System permissions (辅助功能 / 屏幕录制) only need to be requested once;
        // keep the action here in 通用 instead of in the always-visible footer.
        let permButtons = NSStackView()
        permButtons.orientation = .horizontal
        permButtons.spacing = 10
        permButtons.addArrangedSubview(PillButton("请求系统权限", target: self, action: #selector(requestPermissions)))
        stack.addArrangedSubview(leadingFullWidth(permButtons, minHeight: 0))
        stack.addArrangedSubview(note("点击后请在系统设置中允许「辅助功能」（划词翻译需要）；截图 OCR 还需要「屏幕录制」权限。"))
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
        stack.addArrangedSubview(leadingFullWidth(svcButtons, minHeight: 0))
        stack.addArrangedSubview(note("自定义 ID 示例：plugin:custom-name。服务的启用与排序请在「通用」页操作。"))
        stack.addArrangedSubview(note("翻译行为（与原版一致）："))
        stack.addArrangedSubview(indented(translateDeleteNewlineCheckbox))
        stack.addArrangedSubview(indented(smartTargetCheckbox))
        stack.addArrangedSubview(row("第二目标语言", secondTargetLanguagePopup))
        stack.addArrangedSubview(note("启用智能目标语言时，自动检测到中文会翻译到第二目标语言；检测到非中文会翻译到通用页的目标语言；中英文混合内容仍以当前目标语言为准。"))
        stack.addArrangedSubview(indented(hideSourceCheckbox))
        stack.addArrangedSubview(indented(hideLanguageCheckbox))
        stack.addArrangedSubview(indented(dynamicTranslateCheckbox))
        stack.addArrangedSubview(indented(incrementalTranslateCheckbox))
        stack.addArrangedSubview(note("窗口："))
        stack.addArrangedSubview(row("翻译窗口位置", windowPositionPopup))
        stack.addArrangedSubview(indented(closeOnBlurCheckbox))
        stack.addArrangedSubview(indented(alwaysOnTopCheckbox))
        stack.addArrangedSubview(indented(rememberWindowSizeCheckbox))
        return stack
    }

    private func servicesTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(row("OpenAI API key", openAIKeyField))
        stack.addArrangedSubview(row("OpenAI 模型", openAIModelField))
        stack.addArrangedSubview(row("DeepL API key", deepLKeyField))
        stack.addArrangedSubview(row("百度 AppID", baiduAppIDField))
        stack.addArrangedSubview(row("百度密钥", baiduSecretField))
        stack.addArrangedSubview(row("有道 AppKey", youdaoAppKeyField))
        stack.addArrangedSubview(row("有道密钥", youdaoSecretField))
        stack.addArrangedSubview(row("LibreTranslate URL", libreURLField))
        stack.addArrangedSubview(row("LibreTranslate Key", libreKeyField))
        return stack
    }

    private func ocrTab() -> NSView {
        let stack = formStack()
        configureSettingsLanguagePopup(recognizeLanguagePopup, includeAuto: true)
        stack.addArrangedSubview(row("OCR 服务", recognizeServiceList))
        stack.addArrangedSubview(note("内置系统 OCR 使用 macOS Vision；旧版 recognize 插件会在导入或安装后自动列在这里，可启用和调整顺序。"))
        stack.addArrangedSubview(row("OCR 语言", recognizeLanguagePopup))
        stack.addArrangedSubview(indented(recognizeAutoCopyCheckbox))
        stack.addArrangedSubview(indented(recognizeDeleteNewlineCheckbox))
        stack.addArrangedSubview(indented(recognizeHideWindowCheckbox))
        stack.addArrangedSubview(indented(recognizeCloseOnBlurCheckbox))
        stack.addArrangedSubview(note("截图 OCR 会按上方启用顺序逐个尝试：系统 OCR 和旧版 recognize 插件都可参与；某个服务失败或返回空结果时会自动尝试下一个。"))
        return stack
    }

    private func ttsTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(row("TTS 服务", ttsServiceList))
        stack.addArrangedSubview(note("内置 macOS Speech 会按目标语言自动选择系统语音；旧版 TTS 插件会在导入或安装后自动列在这里。"))
        return stack
    }

    private func collectionTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(row("生词本服务", collectionServiceList))
        stack.addArrangedSubview(note("旧版 collection 插件会在导入或安装后自动列在这里。服务启用和顺序会随配置备份/恢复。"))
        return stack
    }

    private func pluginsTab() -> NSView {
        let stack = formStack()

        stack.addArrangedSubview(sectionHeader(
            "安装新插件",
            detail: "支持 .pythia 和 .potext 格式，优先推荐 .pythia。.potext 会先自动转换，转换失败时再使用兼容模式运行。"
        ))
        let installButtons = NSStackView()
        installButtons.orientation = .horizontal
        installButtons.spacing = 10
        installButtons.addArrangedSubview(PillButton("安装插件", target: self, action: #selector(installPlugin)))
        installButtons.addArrangedSubview(PillButton("打开插件目录", target: self, action: #selector(openPluginFolder)))
        installButtons.addArrangedSubview(PillButton("插件开发指南", target: self, action: #selector(openPluginDevelopmentGuide)))
        stack.addArrangedSubview(leadingFullWidth(installButtons, minHeight: 0))

        stack.addArrangedSubview(sectionHeader("已安装插件", detail: "选择插件后可查看格式和位置、修改显示名称、刷新或彻底删除。"))
        rebuildPluginPopup()
        pluginPopup.target = self
        pluginPopup.action = #selector(pluginSelectionChanged)
        stack.addArrangedSubview(row("当前插件", pluginPopup))
        pluginPathLabel.lineBreakMode = .byTruncatingMiddle
        pluginPathLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(row("插件目录", pluginPathLabel))
        pluginMetadataLabel.textColor = .secondaryLabelColor
        pluginMetadataLabel.maximumNumberOfLines = 3
        stack.addArrangedSubview(row("插件信息", pluginMetadataLabel))
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(PillButton("重命名插件", target: self, action: #selector(renamePlugin)))
        buttons.addArrangedSubview(PillButton("刷新插件", target: self, action: #selector(refreshPlugins)))
        buttons.addArrangedSubview(PillButton("重新转换 .potext", target: self, action: #selector(reconvertSelectedPlugin)))
        buttons.addArrangedSubview(PillButton("删除插件", target: self, action: #selector(deleteSelectedPlugin), tintColor: .systemRed))
        stack.addArrangedSubview(leadingFullWidth(buttons, minHeight: 0))

        stack.addArrangedSubview(sectionHeader("插件配置", detail: "配置项由所选插件提供。保存后可直接测试当前插件是否可用。"))
        pluginConfigStack.orientation = .vertical
        pluginConfigStack.alignment = .width
        pluginConfigStack.spacing = 8
        pluginConfigStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(pluginConfigStack)
        let configButtons = NSStackView()
        configButtons.orientation = .horizontal
        configButtons.spacing = 10
        configButtons.addArrangedSubview(PillButton("保存插件配置", target: self, action: #selector(savePluginConfig)))
        configButtons.addArrangedSubview(PillButton("测试连通性", target: self, action: #selector(testPluginConnection)))
        stack.addArrangedSubview(leadingFullWidth(configButtons, minHeight: 0))
        pluginTestResultLabel.lineBreakMode = .byTruncatingTail
        pluginTestResultLabel.maximumNumberOfLines = 1
        pluginTestResultLabel.font = .systemFont(ofSize: 12)
        // Result row: caption + result, both at the left edge, baseline-aligned.
        let pluginResultCaption = NSTextField(labelWithString: "检测结果：")
        pluginResultCaption.font = .systemFont(ofSize: 12)
        pluginResultCaption.textColor = .secondaryLabelColor
        let pluginResultBox = NSStackView()
        pluginResultBox.orientation = .horizontal
        pluginResultBox.alignment = .firstBaseline
        pluginResultBox.spacing = 6
        pluginResultBox.addArrangedSubview(pluginResultCaption)
        pluginResultBox.addArrangedSubview(pluginTestResultLabel)
        stack.addArrangedSubview(leadingFullWidth(pluginResultBox, minHeight: 0))
        stack.addArrangedSubview(note("选中插件后会显示它需要的配置项。Manifest 标记为 secret 的密钥保存在仅当前用户可读的 Pythia 本地凭据文件中，不访问 macOS 钥匙串，也不会弹出钥匙串密码框。点「测试连通性」可验证当前插件。"))
        stack.addArrangedSubview(note("原生命令插件：也可放入 JSON/.potplugin，包含 name、command、arguments、environment。待翻译文本会通过 stdin 和 POT_TEXT 环境变量传入。"))
        rebuildPluginConfigFields()
        updatePluginPathLabel()
        return stack
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

    private func runPluginConnectionTest(serviceID: String, type: String) {
        switch type {
        case "translate":
            testTranslatePluginConnection(serviceID: serviceID)
        case "recognize":
            testRecognizePluginConnection(serviceID: serviceID)
        case "tts":
            testTTSPluginConnection(serviceID: serviceID)
        case "collection":
            testCollectionPluginConnection(serviceID: serviceID)
        default:
            pluginTestResultLabel.stringValue = "✗ 不支持的插件类型：\(type)"
            pluginTestResultLabel.textColor = .systemRed
        }
    }

    private func testTranslatePluginConnection(serviceID: String) {
        pluginTestResultLabel.stringValue = "检测中…"
        pluginTestResultLabel.textColor = .secondaryLabelColor
        TranslationService.shared.translateService(
            identifier: serviceID,
            text: "hello",
            sourceLanguage: "auto",
            targetLanguage: Preferences.shared.targetLanguage.isEmpty ? "zh-CN" : Preferences.shared.targetLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let output):
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.pluginTestResultLabel.stringValue = "✓ 连通正常：hello → \(trimmed)"
                    self.pluginTestResultLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.2, alpha: 1)
                case .failure(let error):
                    self.pluginTestResultLabel.stringValue = "✗ 失败：\(error.localizedDescription)"
                    self.pluginTestResultLabel.textColor = .systemRed
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
        stack.addArrangedSubview(row("划词翻译", hotkeySelectionField))
        stack.addArrangedSubview(row("输入翻译", hotkeyInputField))
        stack.addArrangedSubview(row("截图翻译", hotkeyOCRTranslateField))
        stack.addArrangedSubview(row("截图 OCR", hotkeyOCRRecognizeField))
        stack.addArrangedSubview(note("格式示例：⇧⌘E、⌥⌘D、⌃⇧R。保存后会重新注册系统级快捷键。"))
        return stack
    }

    private func backupTab() -> NSView {
        let stack = formStack()
        backupTypePopup.removeAllItems()
        backupTypePopup.addItems(withTitles: ["本地", "WebDAV"])
        backupTypePopup.target = self
        backupTypePopup.action = #selector(backupTypeChanged)
        stack.addArrangedSubview(row("备份方式", backupTypePopup))

        // Add the WebDAV-specific rows directly to the main form (so they share
        // the exact same left edge as "备份方式"), but keep references so we can
        // show/hide them when 备份方式 changes.
        let urlRow = row("WebDAV 地址", webdavURLField)
        let userRow = row("WebDAV 用户名", webdavUsernameField)
        let passRow = row("WebDAV 密码", webdavPasswordField)
        webdavHistorySyncIntervalField.placeholderString = "1"
        webdavHistorySyncIntervalUnitPopup.removeAllItems()
        webdavHistorySyncIntervalUnitPopup.addItems(withTitles: ["分钟", "小时", "天", "周"])
        webdavHistoryAutoSyncCheckbox.target = self
        webdavHistoryAutoSyncCheckbox.action = #selector(webDAVAutoSyncChanged)
        let autoSyncRow = indented(webdavHistoryAutoSyncCheckbox)
        let intervalControls = NSStackView()
        intervalControls.orientation = .horizontal
        intervalControls.alignment = .centerY
        intervalControls.spacing = 8
        intervalControls.addArrangedSubview(webdavHistorySyncIntervalField)
        intervalControls.addArrangedSubview(webdavHistorySyncIntervalUnitPopup)
        webdavHistorySyncIntervalField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        webdavHistorySyncIntervalUnitPopup.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let intervalRow = row("自动同步间隔", intervalControls)
        webdavHistorySyncStatusLabel.lineBreakMode = .byWordWrapping
        webdavHistorySyncStatusLabel.maximumNumberOfLines = 3
        webdavHistorySyncStatusLabel.font = .systemFont(ofSize: 12)
        webdavHistorySyncStatusLabel.textColor = .secondaryLabelColor
        let statusRow = leadingFullWidth(webdavHistorySyncStatusLabel, minHeight: 0)
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
        let resultRow = leadingFullWidth(resultBox, minHeight: 0)
        webdavRows = [urlRow, userRow, passRow, autoSyncRow, intervalRow, statusRow, resultRow]
        webdavRows.forEach { stack.addArrangedSubview($0) }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(PillButton("导出配置到本地", target: self, action: #selector(exportConfig)))
        buttons.addArrangedSubview(PillButton("从本地导入配置", target: self, action: #selector(importConfig)))
        buttons.addArrangedSubview(PillButton("导出历史到本地", target: self, action: #selector(exportHistoryFromSettings)))
        let localButtonsRow = leadingFullWidth(buttons, minHeight: 0)
        stack.addArrangedSubview(localButtonsRow)
        localActionButtons = localButtonsRow

        let webdavButtons = NSStackView()
        webdavButtons.orientation = .horizontal
        webdavButtons.spacing = 10
        webdavButtons.addArrangedSubview(PillButton("测试 WebDAV 连通性", target: self, action: #selector(testWebDAVConnection)))
        webdavButtons.addArrangedSubview(PillButton("同步历史", target: self, action: #selector(syncHistoryWithWebDAV)))
        webdavButtons.addArrangedSubview(PillButton("备份到 WebDAV", target: self, action: #selector(backupToWebDAV)))
        webdavButtons.addArrangedSubview(PillButton("从 WebDAV 恢复", target: self, action: #selector(restoreFromWebDAV)))
        let webdavButtonsRow = leadingFullWidth(webdavButtons, minHeight: 0)
        stack.addArrangedSubview(webdavButtonsRow)
        webdavActionButtons = webdavButtonsRow

        let localNote = note("本地导出/导入即时生效，文件保存在你选择的位置。")
        let webdavNote = note("坚果云需用应用专属密码（非登录密码）。历史同步使用 /Pythia/history/history.json；配置备份仍兼容旧备份目录。")
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
    }

    private func updateWebDAVAutoSyncControls() {
        let enabled = webdavHistoryAutoSyncCheckbox.state == .on
        webdavHistorySyncIntervalField.isEnabled = enabled
        webdavHistorySyncIntervalUnitPopup.isEnabled = enabled
    }

    /// Shows or hides the WebDAV fields depending on 备份方式.
    @objc private func backupTypeChanged() {
        updateWebDAVFieldsVisibility()
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
        stack.addArrangedSubview(indented(proxyEnabledCheckbox))
        stack.addArrangedSubview(row("代理主机", proxyHostField))
        stack.addArrangedSubview(row("代理端口", proxyPortField))
        stack.addArrangedSubview(row("代理用户名", proxyUsernameField))
        stack.addArrangedSubview(row("代理密码", proxyPasswordField))
        stack.addArrangedSubview(row("不代理地址", noProxyField))
        stack.addArrangedSubview(note("保存后会设置当前进程的 http_proxy/https_proxy/all_proxy 环境变量。"))
        return stack
    }

    private func historyTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(indented(historyDisableCheckbox))
        stack.addArrangedSubview(note("关闭后不会记录任何翻译历史。已有的历史可在历史窗口手动清除。"))
        return stack
    }

    private func migrationTab() -> NSView {
        let stack = formStack()
        stack.addArrangedSubview(note("迁移会扫描本机旧 Pot/Tauri 配置目录，导入可识别的语言和服务密钥字段。旧 Pot 插件会直接转换为 .pythia；转换成功后，Pythia 不保留旧插件或 .potext 备份。密钥写入仅当前用户可读的 Pythia 本地凭据文件，不访问 macOS 钥匙串，也不会输出到日志。"))
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(PillButton("导入旧版配置和插件", target: self, action: #selector(migrateConfig)))
        buttons.addArrangedSubview(PillButton("仅导入旧版插件", target: self, action: #selector(importLegacyPlugins)))
        stack.addArrangedSubview(buttons)
        stack.addArrangedSubview(note("外部调用 API：127.0.0.1:60828，支持 /translate、/selection_translate、/input_translate、/ocr_recognize、/ocr_translate、/config。"))
        return stack
    }

    private func aboutTab() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.shadowColor = NSColor.black.cgColor
        icon.layer?.shadowOpacity = 0.16
        icon.layer?.shadowRadius = 18
        icon.layer?.shadowOffset = NSSize(width: 0, height: -6)

        let nameLabel = NSTextField(labelWithString: "Pythia")
        nameLabel.font = .systemFont(ofSize: 34, weight: .bold)
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .center

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let versionText = build.isEmpty ? "版本 \(version)" : "版本 \(version)（\(build)）"
        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        versionLabel.textColor = PythiaDesign.themeColor()
        versionLabel.alignment = .center

        let descriptionLabel = NSTextField(labelWithString: "多服务翻译与插件平台")
        descriptionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .center

        let updateButton = PillButton("检查更新", target: self, action: #selector(checkForUpdates))
        updateButton.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "检查更新")
        updateButton.imagePosition = .imageLeading
        updateButton.imageHugsTitle = true

        let githubButton = PillButton("GitHub 项目", target: self, action: #selector(openGitHubProject))
        githubButton.image = NSImage(systemSymbolName: "link", accessibilityDescription: "GitHub 项目")
        githubButton.imagePosition = .imageLeading
        githubButton.imageHugsTitle = true

        let actionStack = NSStackView(views: [updateButton, githubButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 10

        aboutUpdateStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        aboutUpdateStatusLabel.textColor = .secondaryLabelColor
        aboutUpdateStatusLabel.alignment = .center
        aboutUpdateStatusLabel.maximumNumberOfLines = 1

        let copyrightLabel = NSTextField(labelWithString: "© 2026 Pythia Contributors · GPL-3.0")
        copyrightLabel.font = .systemFont(ofSize: 11)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center

        let hero = NSStackView(views: [
            icon,
            nameLabel,
            versionLabel,
            descriptionLabel,
            actionStack,
            aboutUpdateStatusLabel,
            copyrightLabel,
        ])
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.orientation = .vertical
        hero.alignment = .centerX
        hero.spacing = 9
        hero.setCustomSpacing(16, after: icon)
        hero.setCustomSpacing(3, after: nameLabel)
        hero.setCustomSpacing(18, after: descriptionLabel)
        hero.setCustomSpacing(6, after: actionStack)
        hero.setCustomSpacing(18, after: aboutUpdateStatusLabel)
        container.addSubview(hero)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 124),
            icon.heightAnchor.constraint(equalToConstant: 124),
            hero.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hero.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -6),
            hero.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            hero.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            hero.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 20),
            hero.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
            aboutUpdateStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
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
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    /// The window width the user has chosen (set by real user resizing). Restored
    /// after every tab switch so the window does not shrink to a tab's fitting size.
    private var settingsUserWidth: CGFloat = 900

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

    private func showTab(index: Int) {
        selectedSettingsIndex = max(0, min(index, tabTitles.count - 1))
        updateSidebarSelection()
        NSLayoutConstraint.deactivate(activeTabConstraints)
        activeTabConstraints.removeAll()
        activeTabView?.removeFromSuperview()
        let content: NSView
        switch selectedSettingsIndex {
        case 1: content = scrollTab(translateTab())
        case 2: content = scrollTab(servicesTab())
        case 3: content = scrollTab(ocrTab())
        case 4: content = scrollTab(ttsTab())
        case 5: content = scrollTab(collectionTab())
        case 6: content = scrollTab(pluginsTab())
        case 7: content = scrollTab(shortcutsTab())
        case 8: content = scrollTab(historyTab())
        case 9: content = scrollTab(proxyTab())
        case 10: content = scrollTab(backupTab())
        case 11: content = scrollTab(migrationTab())
        case 12: content = aboutTab()
        default: content = scrollTab(generalTab())
        }
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
    }

    private func formStack() -> NSStackView {
        let stack = FullWidthStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 14, bottom: 14, right: 14)
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
        control.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(labelView)
        container.addSubview(control)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            labelView.widthAnchor.constraint(equalToConstant: 150),
            control.leadingAnchor.constraint(equalTo: labelView.trailingAnchor, constant: 12),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            // Make the container's height follow the control's height, so tall
            // controls (e.g. the multi-checkbox service list) expand the row
            // instead of overflowing and overlapping the rows below.
            container.topAnchor.constraint(lessThanOrEqualTo: control.topAnchor, constant: -2),
            container.bottomAnchor.constraint(greaterThanOrEqualTo: control.bottomAnchor, constant: 2),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
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
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
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

    private func load() {
        let preferences = Preferences.shared
        selectLanguage(preferences.sourceLanguage, in: sourceLanguagePopup)
        selectLanguage(preferences.targetLanguage, in: targetLanguagePopup)
        selectLanguage(preferences.translateSecondLanguage, in: secondTargetLanguagePopup)
        openAIKeyField.stringValue = preferences.openAIKey
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

    @objc private func save() {
        let preferences = Preferences.shared
        let requestedAutoSync = webdavHistoryAutoSyncCheckbox.state == .on
        let webdavAddress = webdavURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if requestedAutoSync && webdavAddress.isEmpty {
            showAlert("启用自动同步前，请先填写 WebDAV 地址。")
            return
        }
        guard let syncIntervalValue = Int(webdavHistorySyncIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), syncIntervalValue > 0 else {
            showAlert("自动同步间隔必须是大于 0 的整数。")
            return
        }
        let syncIntervalUnit = selectedPopupValue(webdavHistorySyncIntervalUnitPopup, mapping: ["minute": "分钟", "hour": "小时", "day": "天", "week": "周"])
        let secondsPerUnit = ["minute": 60, "hour": 3_600, "day": 86_400, "week": 604_800][syncIntervalUnit] ?? 3_600
        guard syncIntervalValue <= (366 * 86_400) / secondsPerUnit else {
            showAlert("自动同步间隔不能超过 366 天。")
            return
        }
        preferences.sourceLanguage = selectedLanguageCode(sourceLanguagePopup)
        preferences.targetLanguage = selectedLanguageCode(targetLanguagePopup)
        preferences.openAIKey = openAIKeyField.stringValue
        preferences.openAIModel = openAIModelField.stringValue.isEmpty ? "gpt-4o-mini" : openAIModelField.stringValue
        preferences.deepLKey = deepLKeyField.stringValue
        preferences.baiduAppID = baiduAppIDField.stringValue
        preferences.baiduSecret = baiduSecretField.stringValue
        preferences.youdaoAppKey = youdaoAppKeyField.stringValue
        preferences.youdaoSecret = youdaoSecretField.stringValue
        preferences.libreTranslateURL = libreURLField.stringValue.isEmpty ? "https://libretranslate.com" : libreURLField.stringValue
        preferences.libreTranslateKey = libreKeyField.stringValue
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
        preferences.webdavHistoryAutoSync = requestedAutoSync
        preferences.webdavHistorySyncIntervalUnit = syncIntervalUnit
        preferences.webdavHistorySyncIntervalValue = syncIntervalValue
        webdavHistorySyncIntervalField.stringValue = "\(preferences.webdavHistorySyncIntervalValue)"
        if let pluginName = currentPluginName {
            preferences.pluginName = pluginName
        } else {
            preferences.pluginName = ""
        }
        preferences.clipboardMonitoring = clipboardCheckbox.state == .on
        updateSidebarSelection()
        saveStatusLabel.textColor = PythiaDesign.themeColor()
        PythiaAppDelegate.shared?.applyClipboardPreference()
        let runtimeWarning = PythiaAppDelegate.shared?.applyRuntimePreferences()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        window?.title = "Pythia 设置 - 已保存"
        let portWarning = rawServerPort == normalizedServerPort ? nil : "外部服务端口无效，已恢复为 60828"
        let credentialWarning = preferences.consumeCredentialStorageError().map { "凭据未能保存到本地：\($0)" }
        let warning = [duplicateHotkeyWarning, portWarning, fontWarning, runtimeWarning, credentialWarning]
            .compactMap { $0 }
            .joined(separator: "；")
        saveStatusLabel.stringValue = warning.isEmpty ? "已保存" : "已保存，\(warning)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.saveStatusLabel.stringValue = ""
            self?.window?.title = "Pythia 设置"
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
        Preferences.shared.themeColorHex = themeColorWell.color.potHexRGB
        saveStatusLabel.textColor = PythiaDesign.themeColor()
        updateSidebarSelection()
        // Re-color the live translation window's icon buttons / titles now.
        PythiaAppDelegate.shared?.applyRuntimePreferences()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func trayClickEventChanged() {
        Preferences.shared.trayClickEvent = selectedPopupValue(
            trayClickPopup,
            mapping: ["config": "显示设置", "translate": "显示翻译窗口", "history": "显示历史记录"]
        )
        saveStatusLabel.textColor = PythiaDesign.themeColor()
        saveStatusLabel.stringValue = "托盘点击已应用"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard self?.saveStatusLabel.stringValue == "托盘点击已应用" else { return }
            self?.saveStatusLabel.stringValue = ""
        }
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
        _ = SelectionReader.shared.requestAccessibilityPermission()
        let alert = NSAlert()
        alert.messageText = "已请求权限"
        alert.informativeText = "请在系统设置中允许辅助功能；截图 OCR 还需要屏幕录制权限。"
        alert.runModal()
    }

    @objc private func checkForUpdates() {
        saveStatusLabel.textColor = .secondaryLabelColor
        saveStatusLabel.stringValue = "正在检查更新..."
        aboutUpdateStatusLabel.textColor = .secondaryLabelColor
        aboutUpdateStatusLabel.stringValue = "正在检查更新..."
        PythiaUpdateChecker.shared.check { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let info):
                    self.saveStatusLabel.textColor = PythiaDesign.themeColor()
                    self.saveStatusLabel.stringValue = info.isNewer ? "发现新版本 \(info.latestVersion)" : "当前已是最新版本"
                    self.aboutUpdateStatusLabel.textColor = PythiaDesign.themeColor()
                    self.aboutUpdateStatusLabel.stringValue = self.saveStatusLabel.stringValue
                    self.showUpdateResult(info)
                case .failure(let error):
                    self.saveStatusLabel.textColor = .systemRed
                    self.saveStatusLabel.stringValue = "更新检查失败"
                    self.aboutUpdateStatusLabel.textColor = .systemRed
                    self.aboutUpdateStatusLabel.stringValue = "更新检查失败"
                    let alert = NSAlert()
                    alert.messageText = "更新检查失败"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func showUpdateResult(_ info: PythiaUpdateInfo) {
        let alert = NSAlert()
        if info.isNewer {
            alert.messageText = "发现新版本 \(info.latestVersion)"
            alert.informativeText = "当前版本：\(info.currentVersion)\n发布版本：\(info.releaseName)"
            alert.addButton(withTitle: "打开发布页")
            alert.addButton(withTitle: "稍后")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn, let url = info.releaseURL {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.messageText = "当前已是最新版本"
            alert.informativeText = "当前版本：\(info.currentVersion)"
            alert.runModal()
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

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Pythia"
        alert.informativeText = message
        alert.runModal()
    }
}
