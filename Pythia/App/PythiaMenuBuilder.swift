import AppKit

extension PythiaAppDelegate {
    /// Installs a standard main menu (App / Edit / View / Window). The Edit menu
    /// is required for Command-V/Command-C/Command-A in text fields because those
    /// commands are dispatched through the responder chain.
    func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = makeAppMenu()

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        editMenuItem.submenu = makeEditMenu()

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        viewMenuItem.submenu = makeViewMenu()

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = makeWindowMenu()
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    func buildMenuBar() {
        configureStatusButton()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let preferences = Preferences.shared
        addMenuItem("显示翻译窗口", action: #selector(showTranslator), to: menu)
        addMenuItem("划词翻译  \(preferences.hotkeySelectionTranslate)", action: #selector(selectionMenu), to: menu)
        addMenuItem("输入翻译  \(preferences.hotkeyInputTranslate)", action: #selector(inputTranslateMenu), to: menu)
        addMenuItem("截图翻译  \(preferences.hotkeyOCRTranslate)", action: #selector(ocrMenu), to: menu)
        addMenuItem("截图 OCR  \(preferences.hotkeyOCRRecognize)", action: #selector(ocrRecognizeMenu), to: menu)
        addMenuItem("加入生词本", action: #selector(collectionMenu), to: menu)
        addMenuItem("朗读译文", action: #selector(speakResult), to: menu)
        addMenuItem("历史记录", action: #selector(historyMenu), to: menu)
        menu.addItem(.separator())

        let clipboard = addMenuItem("监听剪贴板", action: #selector(toggleClipboard), to: menu)
        clipboard.state = preferences.clipboardMonitoring ? .on : .off
        addMenuItem("设置", action: #selector(settingsMenu), to: menu)
        menu.addItem(.separator())
        addMenuItem("退出", action: #selector(quit), keyEquivalent: "q", to: menu)

        statusMenu = menu
        statusItem.menu = nil
    }

    private func makeAppMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 Pythia", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        addMenuItem("历史记录", action: #selector(historyMenu), to: appMenu)
        let settingsItem = addMenuItem("设置...", action: #selector(settingsMenu), keyEquivalent: ",", to: appMenu)
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 Pythia", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 Pythia", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return appMenu
    }

    private func makeEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return editMenu
    }

    private func makeViewMenu() -> NSMenu {
        let viewMenu = NSMenu(title: "显示")
        addMenuItem("显示翻译窗口", action: #selector(showTranslator), to: viewMenu)
        addMenuItem("划词翻译", action: #selector(selectionMenu), to: viewMenu)
        addMenuItem("输入翻译", action: #selector(inputTranslateMenu), to: viewMenu)
        addMenuItem("截图翻译", action: #selector(ocrMenu), to: viewMenu)
        addMenuItem("截图 OCR", action: #selector(ocrRecognizeMenu), to: viewMenu)
        addMenuItem("加入生词本", action: #selector(collectionMenu), to: viewMenu)
        addMenuItem("朗读译文", action: #selector(speakResult), to: viewMenu)
        addMenuItem("历史记录", action: #selector(historyMenu), to: viewMenu)
        return viewMenu
    }

    private func makeWindowMenu() -> NSMenu {
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "全部前置", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        return windowMenu
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(named: "PythiaStatusTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 20, height: 20)
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.title = "Pythia"
        }
        button.toolTip = "Pythia"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @discardableResult
    private func addMenuItem(_ title: String, action: Selector, keyEquivalent: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
        return item
    }
}
