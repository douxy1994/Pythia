import AppKit
import AVFoundation
import Foundation

final class TranslatorWindowController: NSWindowController, AVSpeechSynthesizerDelegate, NSWindowDelegate {
    private static let defaultWindowSize = NSSize(width: 1120, height: 720)
    private static let fixedSourceTextHeight: CGFloat = 180
    private enum ContentMode {
        case translation
        case recognition
    }

    private let sourceView = PythiaTextView(placeholder: "", editable: true)
    private let resultScroll = NSScrollView()
    private let resultStack = FlippedStackView()
    private var sourceHeightConstraint: NSLayoutConstraint?
    private var resultViews: [String: PythiaTextView] = [:]
    private var resultOrder: [String] = []
    private var resultHeightConstraints: [String: NSLayoutConstraint] = [:]
    private var resultCollapseButtons: [String: NSButton] = [:]
    private var resultRetranslateButtons: [String: NSButton] = [:]
    private var collapsedResultKeys = Set<String>()
    private var failedResultKeys = Set<String>()
    private let servicePicker = TranslationServicePickerButton()
    private let pinWindowButton = GlassIconButton(systemName: "pin", accessibility: "窗口置顶", target: nil, action: nil)
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "就绪")
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var pluginAudioPlayer: AVAudioPlayer?
    private let sourcePanelTitle = NSTextField(labelWithString: "原文")
    private let resultPanelTitle = NSTextField(labelWithString: "译文")
    private weak var sourcePanelContainer: NSView?
    private var languageControls: [NSView] = []
    private var sourcePanelTopConstraint: NSLayoutConstraint?
    private var resultPanelTopToSourceConstraint: NSLayoutConstraint?
    private var resultPanelTopToHeaderConstraint: NSLayoutConstraint?
    private weak var backgroundView: LiquidGlassBackgroundView?
    private var dynamicTranslateWorkItem: DispatchWorkItem?
    private var resultHeightRefreshWorkItem: DispatchWorkItem?
    private var hasPresentedWindow = false
    private var isApplyingWindowPlacement = false
    private var contentMode: ContentMode = .translation

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Pythia"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 600)
        super.init(window: window)
        window.delegate = self
        speechSynthesizer.delegate = self
        buildUI()
        sourceView.onSubmit = { [weak self] in
            self?.dynamicTranslateWorkItem?.cancel()
            self?.translate()
        }
        sourceView.onTextChanged = { [weak self] in
            self?.handleSourceTextChanged()
        }
        reloadPreferences()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadPreferences), name: .preferencesChanged, object: nil)
        // Keep the source text box fixed; long source text scrolls internally
        // while the result panel absorbs all vertical window resizing.
        sourceHeightConstraint = sourceView.heightAnchor.constraint(equalToConstant: Self.fixedSourceTextHeight)
        sourceHeightConstraint?.priority = .required
        sourceHeightConstraint?.isActive = true
        updateSourceHeight()
    }

    /// Keep the source box at a stable height. The source text view owns its
    /// own scrollbar, so window resizing should only increase/decrease the
    /// translation result area.
    private func updateSourceHeight() {
        sourceHeightConstraint?.constant = Self.fixedSourceTextHeight
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus(with text: String? = nil) {
        if let text, !text.isEmpty {
            sourceView.setPlainText(text)
        }
        updateSourceHeight()
        applyWindowPlacementForPresentation()
        hasPresentedWindow = true
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showForInputTranslation() {
        clearInput()
        showAndFocus()
        window?.makeFirstResponder(sourceView.textView)
        status("请输入文本，按回车翻译")
    }

    private func applyWindowPlacementForPresentation() {
        guard let window else { return }
        isApplyingWindowPlacement = true
        defer { isApplyingWindowPlacement = false }
        let preferences = Preferences.shared
        let savedFrame = savedWindowFrame()
        var frame = window.frame

        if preferences.translateRememberWindowSize, let savedFrame {
            frame.size = savedFrame.size
        } else if !window.isVisible {
            frame.size = Self.defaultWindowSize
        }

        switch preferences.translateWindowPosition {
        case "remember":
            if let savedFrame {
                frame.origin = savedFrame.origin
                if preferences.translateRememberWindowSize {
                    frame.size = savedFrame.size
                }
            } else if !window.isVisible {
                window.setFrame(frame, display: false)
                window.center()
                frame = window.frame
            }
        case "mouse":
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
            frame.origin = NSPoint(x: mouse.x + 18, y: mouse.y - frame.height - 18)
            if frame.minY < visible.minY {
                frame.origin.y = min(visible.maxY - frame.height, mouse.y + 18)
            }
        default:
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? frame
            frame.origin = NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            )
        }

        window.setFrame(clampedFrame(frame), display: false)
    }

    private func savedWindowFrame() -> NSRect? {
        let raw = Preferences.shared.translateWindowFrame
        guard !raw.isEmpty else { return nil }
        let rect = NSRectFromString(raw)
        guard rect.width >= 100, rect.height >= 100 else { return nil }
        return rect
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.size.width = min(max(result.width, window?.minSize.width ?? 900), visible.width)
        result.size.height = min(max(result.height, window?.minSize.height ?? 600), visible.height)
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        return result
    }

    private func persistWindowFrame() {
        guard hasPresentedWindow, !isApplyingWindowPlacement, let window else { return }
        Preferences.shared.translateWindowFrame = NSStringFromRect(window.frame)
    }

    func windowDidMove(_ notification: Notification) {
        persistWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        updateSourceHeight()
        scheduleResultHeightRefresh()
        persistWindowFrame()
    }

    func windowDidResignKey(_ notification: Notification) {
        let preferences = Preferences.shared
        switch contentMode {
        case .translation:
            guard preferences.translateCloseOnBlur else { return }
        case .recognition:
            guard preferences.recognizeCloseOnBlur else { return }
        }
        window?.orderOut(nil)
    }

    func translate(_ text: String? = nil, completion: ((Result<String, Error>) -> Void)? = nil) {
        contentMode = .translation
        dynamicTranslateWorkItem?.cancel()
        let usesProvidedText = text?.isEmpty == false
        if let text, !text.isEmpty {
            sourceView.setPlainText(text)
        }
        updateSourceHeight()
        let input = sourceView.textView.string
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearResults()
            status("没有可翻译的文本")
            completion?(.failure(TranslationError.requestFailed("没有可翻译的文本")))
            return
        }
        status("翻译中...")
        if usesProvidedText {
            selectLanguage(Preferences.shared.sourceLanguage, in: sourceLanguagePopup)
            selectLanguage(Preferences.shared.targetLanguage, in: targetLanguagePopup)
            updatePanelTitles()
        } else {
            let sourceLanguage = selectedLanguageCode(sourceLanguagePopup)
            let targetLanguage = selectedLanguageCode(targetLanguagePopup)
            Preferences.shared.sourceLanguage = sourceLanguage.isEmpty ? "auto" : sourceLanguage
            Preferences.shared.targetLanguage = targetLanguage.isEmpty ? "zh-CN" : targetLanguage
        }
        let requestedSourceLanguage = Preferences.shared.sourceLanguage
        var requestedTargetLanguage = Preferences.shared.targetLanguage
        // Automatic direction: pure Chinese -> English, pure English -> Chinese;
        // mixed Chinese/English keeps the target selected by the user.
        if requestedSourceLanguage.lowercased() == "auto" {
            let smartTarget = AutomaticLanguagePolicy.targetLanguage(
                for: input,
                selectedTarget: requestedTargetLanguage
            )
            requestedTargetLanguage = smartTarget
            selectLanguage(smartTarget, in: targetLanguagePopup)
            updatePanelTitles()
        }
        let services = activeTranslationServices()
        guard !services.isEmpty else {
            let error = TranslationError.requestFailed("请先在设置中选择至少一个翻译服务。")
            showSingleResult(title: "Pythia", text: error.localizedDescription)
            status("没有可用服务")
            completion?(.failure(error))
            return
        }
        let effectiveLanguages = TranslationService.resolvedLanguages(
            text: input,
            sourceLanguage: requestedSourceLanguage,
            targetLanguage: requestedTargetLanguage
        )
        prepareResultCards(for: services)
        var completed = 0
        var succeeded = 0
        var failed = 0
        var firstSuccess: String?
        var firstError: Error?
        var finishedServices = Set<String>()

        let finishService: (String, Result<String, Error>) -> Void = { [weak self] service, result in
            guard let self else { return }
            guard !finishedServices.contains(service) else { return }
            finishedServices.insert(service)
            completed += 1
            // A finished service (success or failure) may be re-translated.
            self.resultRetranslateButtons[service]?.isEnabled = true
            let displayName = PluginManager.shared.displayName(forServiceIdentifier: service)
            switch result {
            case .success(let output):
                succeeded += 1
                failedResultKeys.remove(service)
                let finalOutput = Preferences.shared.translateDeleteNewline ? Self.compactWhitespace(output) : output
                if firstSuccess == nil {
                    firstSuccess = finalOutput
                }
                self.setResult(finalOutput, for: service)
                HistoryStore.shared.add(PythiaHistoryRecord(
                    sourceText: input,
                    translatedText: finalOutput,
                    sourceLanguage: effectiveLanguages.source,
                    targetLanguage: effectiveLanguages.target,
                    service: displayName,
                    deviceId: ""
                ))
            case .failure(let error):
                failed += 1
                failedResultKeys.insert(service)
                if firstError == nil {
                    firstError = error
                }
                self.setResult(error.localizedDescription, for: service)
            }
            if completed == services.count {
                if let firstSuccess {
                    self.applyAutoCopyAfterTranslation(source: input)
                    self.status(failed > 0 ? "部分服务失败，\(succeeded)/\(services.count) 个成功" : "翻译完成")
                    completion?(.success(firstSuccess))
                } else {
                    self.status("翻译失败")
                    completion?(.failure(firstError ?? TranslationError.requestFailed("翻译失败")))
                }
            } else {
                self.status("翻译中 \(completed)/\(services.count)")
            }
        }

        for service in services {
            let serviceTimeout = timeoutInterval(forServiceIdentifier: service, text: input)
            let timeout = DispatchWorkItem {
                finishService(service, .failure(TranslationError.requestFailed("服务超时：\(PluginManager.shared.displayName(forServiceIdentifier: service)) 未在 \(Int(serviceTimeout)) 秒内返回。")))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + serviceTimeout, execute: timeout)
            TranslationService.shared.translateService(
                identifier: service,
                text: input,
                sourceLanguage: effectiveLanguages.source,
                targetLanguage: effectiveLanguages.target
            ) { [weak self] result in
                DispatchQueue.main.async {
                    guard self != nil else { return }
                    timeout.cancel()
                    finishService(service, result)
                }
            }
        }
    }

    private func timeoutInterval(forServiceIdentifier service: String, text: String) -> TimeInterval {
        let characterCount = text.count
        let lower = service.lowercased()
        if lower.hasPrefix("plugin:") {
            let chunkCount = TranslationService.estimatedTranslationChunkCount(for: text)
            let basePerChunk: TimeInterval = 300
            return min(7_200, max(basePerChunk, Double(chunkCount) * basePerChunk))
        }
        if lower == PythiaProvider.local.rawValue.lowercased() {
            return 10
        }
        return min(600, max(90, 90 + Double(characterCount) / 40.0))
    }

    private func handleSourceTextChanged() {
        updateSourceHeight()
        let preferences = Preferences.shared
        guard preferences.dynamicTranslate || preferences.incrementalTranslate else { return }

        let input = sourceView.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count >= 2 else {
            dynamicTranslateWorkItem?.cancel()
            clearResults()
            status(input.isEmpty ? "就绪" : "等待更多输入")
            return
        }

        dynamicTranslateWorkItem?.cancel()
        let delay: TimeInterval = preferences.incrementalTranslate ? 0.45 : 0.9
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let latest = self.sourceView.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard latest == input else { return }
            self.translate(latest)
        }
        dynamicTranslateWorkItem = work
        status("等待自动翻译...")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func recognizeScreen(translateAfterRecognition: Bool) {
        contentMode = translateAfterRecognition ? .translation : .recognition
        status("正在识别屏幕...")
        OCRService.shared.recognizeScreen { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    let finalText = Preferences.shared.recognizeDeleteNewline ? Self.compactWhitespace(text) : text
                    self?.sourceView.setPlainText(finalText)
                    if Preferences.shared.recognizeAutoCopy {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(finalText, forType: .string)
                    }
                    if Preferences.shared.recognizeHideWindow, !translateAfterRecognition {
                        self?.window?.orderOut(nil)
                    }
                    if translateAfterRecognition {
                        self?.translate(finalText)
                    } else {
                        self?.contentMode = .recognition
                        self?.status(Preferences.shared.recognizeAutoCopy ? "OCR 完成，已复制" : "OCR 完成")
                    }
                case .failure(let error):
                    self?.contentMode = translateAfterRecognition ? .translation : .recognition
                    self?.showSingleResult(title: "OCR", text: error.localizedDescription)
                    self?.status("OCR 失败")
                }
            }
        }
    }

    func speakResult() {
        let text = combinedResultText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status("没有可朗读的译文")
            return
        }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            status("已停止朗读")
            return
        }
        if pluginAudioPlayer?.isPlaying == true {
            pluginAudioPlayer?.stop()
            pluginAudioPlayer = nil
            status("已停止朗读")
            return
        }
        if let service = Preferences.shared.ttsServiceList.first,
           service.lowercased().hasPrefix("plugin:") {
            speakWithLegacyPlugin(serviceIdentifier: service, text: text)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredSpeechVoice(for: Preferences.shared.targetLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
        status("正在朗读译文")
    }

    private func speakWithLegacyPlugin(serviceIdentifier: String, text: String) {
        status("正在调用 TTS 插件...")
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceIdentifier,
            expectedType: "tts",
            input: text,
            sourceLanguage: Preferences.shared.targetLanguage,
            targetLanguage: Preferences.shared.targetLanguage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let output):
                    do {
                        let audioData = try Self.audioData(fromLegacyTTSOutput: output)
                        let player = try AVAudioPlayer(data: audioData)
                        self.pluginAudioPlayer = player
                        player.prepareToPlay()
                        player.play()
                        self.status("正在朗读译文")
                    } catch {
                        self.status("TTS 插件返回的音频无效")
                        self.showSingleResult(title: "TTS", text: error.localizedDescription)
                    }
                case .failure(let error):
                    self.status("TTS 插件失败")
                    self.showSingleResult(title: "TTS", text: error.localizedDescription)
                }
            }
        }
    }

    private static func audioData(fromLegacyTTSOutput output: String) throws -> Data {
        var value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("data:"),
           let comma = value.firstIndex(of: ",") {
            value = String(value[value.index(after: comma)...])
        }
        if value.hasPrefix("\""), value.hasSuffix("\""),
           let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            value = decoded
        }
        guard let audioData = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]), !audioData.isEmpty else {
            throw TranslationError.requestFailed("TTS 插件没有返回可播放的 base64 音频。")
        }
        return audioData
    }

    func copyResult() {
        let text = combinedResultText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status("没有可复制的译文")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status("已复制译文")
    }

    func copySource() {
        let text = sourceView.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status("没有可复制的原文")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status("已复制原文")
    }

    func addCurrentResultToCollection() {
        let source = sourceView.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            status("没有可加入生词本的原文")
            return
        }
        let target = collectionTargetText()
        guard !target.isEmpty else {
            status("请先完成翻译，再加入生词本")
            return
        }
        let services = Preferences.shared.collectionServiceList.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !services.isEmpty else {
            status("请先在设置中启用生词本服务")
            return
        }

        status("正在加入生词本...")
        var completed = 0
        var succeeded = 0
        var firstError: Error?
        for service in services {
            PluginManager.shared.runLegacyService(
                serviceIdentifier: service,
                expectedType: "collection",
                input: source,
                sourceLanguage: Preferences.shared.sourceLanguage,
                targetLanguage: Preferences.shared.targetLanguage,
                targetPayload: target
            ) { [weak self] result in
                DispatchQueue.main.async {
                    completed += 1
                    switch result {
                    case .success:
                        succeeded += 1
                    case .failure(let error):
                        if firstError == nil { firstError = error }
                    }
                    guard completed == services.count else {
                        self?.status("正在加入生词本 \(completed)/\(services.count)")
                        return
                    }
                    if succeeded == services.count {
                        self?.status("已加入生词本")
                    } else if succeeded > 0 {
                        self?.status("部分生词本服务失败，\(succeeded)/\(services.count) 个成功")
                    } else {
                        self?.status("加入生词本失败：\(firstError?.localizedDescription ?? "未知错误")")
                    }
                }
            }
        }
    }

    @objc private func copyResultForService(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue,
              let textView = resultViews[key] else {
            status("没有可复制的服务译文")
            return
        }
        let text = textView.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status("没有可复制的服务译文")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status("已复制 \(PluginManager.shared.displayName(forServiceIdentifier: key)) 译文")
    }

    @objc private func retranslateResultForService(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        retranslateService(key)
    }

    /// Re-runs a single service card with the current input and language
    /// settings, without disturbing the other cards.
    private func retranslateService(_ service: String) {
        let input = sourceView.textView.string
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status("没有可翻译的文本")
            return
        }
        guard resultViews[service] != nil else { return }
        // Resolve languages exactly as translate() does so the retry uses the
        // same effective source/target languages.
        let requestedSourceLanguage = Preferences.shared.sourceLanguage
        var requestedTargetLanguage = Preferences.shared.targetLanguage
        if requestedSourceLanguage.lowercased() == "auto" {
            requestedTargetLanguage = AutomaticLanguagePolicy.targetLanguage(
                for: input,
                selectedTarget: requestedTargetLanguage
            )
        }
        let effectiveLanguages = TranslationService.resolvedLanguages(
            text: input,
            sourceLanguage: requestedSourceLanguage,
            targetLanguage: requestedTargetLanguage
        )
        let displayName = PluginManager.shared.displayName(forServiceIdentifier: service)
        resultRetranslateButtons[service]?.isEnabled = false
        failedResultKeys.remove(service)
        setResult("等待 \(displayName) 返回...", for: service)
        status("正在重新翻译 \(displayName)...")

        var finished = false
        let finishOnce: (Result<String, Error>) -> Void = { [weak self] result in
            guard let self, !finished else { return }
            finished = true
            self.resultRetranslateButtons[service]?.isEnabled = true
            switch result {
            case .success(let output):
                self.failedResultKeys.remove(service)
                let finalOutput = Preferences.shared.translateDeleteNewline ? Self.compactWhitespace(output) : output
                self.setResult(finalOutput, for: service)
                HistoryStore.shared.add(PythiaHistoryRecord(
                    sourceText: input,
                    translatedText: finalOutput,
                    sourceLanguage: effectiveLanguages.source,
                    targetLanguage: effectiveLanguages.target,
                    service: displayName,
                    deviceId: ""
                ))
                self.status("已重新翻译 \(displayName)")
            case .failure(let error):
                self.failedResultKeys.insert(service)
                self.setResult(error.localizedDescription, for: service)
                self.status("重新翻译失败：\(displayName)")
            }
        }

        let serviceTimeout = timeoutInterval(forServiceIdentifier: service, text: input)
        let timeout = DispatchWorkItem {
            finishOnce(.failure(TranslationError.requestFailed("服务超时：\(displayName) 未在 \(Int(serviceTimeout)) 秒内返回。")))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + serviceTimeout, execute: timeout)
        TranslationService.shared.translateService(
            identifier: service,
            text: input,
            sourceLanguage: effectiveLanguages.source,
            targetLanguage: effectiveLanguages.target
        ) { result in
            DispatchQueue.main.async {
                timeout.cancel()
                finishOnce(result)
            }
        }
    }

    func clearInput() {
        dynamicTranslateWorkItem?.cancel()
        sourceView.setPlainText("")
        clearResults()
        status("已清空")
    }

    func setStatus(_ text: String) {
        status(text)
    }

    func showMessage(title: String, text: String, status statusText: String) {
        showSingleResult(title: title, text: text)
        status(statusText)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = false

        let background = LiquidGlassBackgroundView()
        background.translatesAutoresizingMaskIntoConstraints = false
        backgroundView = background
        content.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .width
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let title = NSTextField(labelWithString: "Pythia")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = .labelColor
        titleRow.addArrangedSubview(icon)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(NSView())
        pinWindowButton.target = self
        pinWindowButton.action = #selector(toggleAlwaysOnTop)
        titleRow.addArrangedSubview(pinWindowButton)

        let controlsRow = NSStackView()
        controlsRow.orientation = .horizontal
        controlsRow.alignment = .centerY
        controlsRow.spacing = 10

        servicePicker.onChange = { services in
            let existingOrder = Preferences.shared.translateServiceOrder
            Preferences.shared.translateServiceList = services
            Preferences.shared.translateServiceOrder = services + existingOrder.filter { !services.contains($0) }
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        }

        configureLanguagePopup(sourceLanguagePopup, includeAuto: true)
        configureLanguagePopup(targetLanguagePopup, includeAuto: false)
        configureResultList()

        let translateButton = PillButton("翻译", target: self, action: #selector(translateButtonClicked))
        let selectionButton = PillButton("划词", target: self, action: #selector(selectionButtonClicked))
        let ocrButton = PillButton("截图翻译", target: self, action: #selector(ocrButtonClicked))
        let swapButton = PillButton("⇄", target: self, action: #selector(swapLanguages))
        languageControls = [sourceLanguagePopup, swapButton, targetLanguagePopup]

        controlsRow.addArrangedSubview(servicePicker)
        controlsRow.addArrangedSubview(sourceLanguagePopup)
        controlsRow.addArrangedSubview(swapButton)
        controlsRow.addArrangedSubview(targetLanguagePopup)
        controlsRow.addArrangedSubview(NSView())
        controlsRow.addArrangedSubview(selectionButton)
        controlsRow.addArrangedSubview(ocrButton)
        controlsRow.addArrangedSubview(translateButton)
        header.addArrangedSubview(titleRow)
        header.addArrangedSubview(controlsRow)
        content.addSubview(header)

        let sourceHeaderButtons: [NSView] = [
            makeCopyButton(action: #selector(copySourceButtonClicked)),
            makeIconButton(systemName: "doc.on.clipboard", accessibility: "粘贴", action: #selector(pasteSourceClicked)),
            makeIconButton(systemName: "text.append", accessibility: "删除换行", action: #selector(stripNewlinesClicked)),
            makeIconButton(systemName: "trash", accessibility: "清空输入框", action: #selector(clearSourceClicked)),
        ]
        let sourcePanel = panel(title: "原文", view: sourceView, headerControls: sourceHeaderButtons)
        let resultPanel = panel(title: "译文", view: resultScroll, boxed: false)
        sourcePanelContainer = sourcePanel
        sourcePanel.translatesAutoresizingMaskIntoConstraints = false
        resultPanel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sourcePanel)
        content.addSubview(resultPanel)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addArrangedSubview(statusLabel)
        footer.addArrangedSubview(NSView())
        let clearInputButton = PillButton("清空", target: self, action: #selector(clearInputButtonClicked))
        let copyButton = PillButton("复制译文", target: self, action: #selector(copyResultButtonClicked))
        let collectionButton = PillButton("收藏", target: self, action: #selector(collectionButtonClicked))
        let speakButton = PillButton("朗读", target: self, action: #selector(speakButtonClicked))
        footer.addArrangedSubview(clearInputButton)
        footer.addArrangedSubview(copyButton)
        footer.addArrangedSubview(collectionButton)
        footer.addArrangedSubview(speakButton)
        content.addSubview(footer)

        let guide = content.safeAreaLayoutGuide
        sourcePanelTopConstraint = sourcePanel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18)
        resultPanelTopToSourceConstraint = resultPanel.topAnchor.constraint(equalTo: sourcePanel.bottomAnchor, constant: 14)
        resultPanelTopToHeaderConstraint = resultPanel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18)
        resultPanelTopToHeaderConstraint?.isActive = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: guide.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            header.heightAnchor.constraint(equalToConstant: 92),

            footer.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -18),
            footer.heightAnchor.constraint(equalToConstant: 36),

            sourcePanelTopConstraint!,
            sourcePanel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            sourcePanel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            resultPanelTopToSourceConstraint!,
            resultPanel.leadingAnchor.constraint(equalTo: sourcePanel.leadingAnchor),
            resultPanel.trailingAnchor.constraint(equalTo: sourcePanel.trailingAnchor),
            resultPanel.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
        ])
        // Make the source panel hug its content vertically (so it does not grow
        // with the window / leave blank space), while the result panel absorbs
        // all the extra height when the window is stretched.
        sourcePanel.setContentHuggingPriority(.required, for: .vertical)
        sourcePanel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        resultPanel.setContentHuggingPriority(.defaultLow, for: .vertical)
        resultPanel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func configureLanguagePopup(_ popup: NSPopUpButton, includeAuto: Bool) {
        popup.removeAllItems()
        popup.addItems(withTitles: languageTitles(includeAuto: includeAuto))
        popup.target = self
        popup.action = #selector(languageChanged)
        popup.widthAnchor.constraint(equalToConstant: 132).isActive = true
    }

    private func configureResultList() {
        resultScroll.borderType = .noBorder
        resultScroll.drawsBackground = false
        // The outer result box scrolls vertically only when the total of all
        // service cards exceeds the box height; each card itself is never
        // scrollable and grows to fit its own content.
        resultScroll.hasVerticalScroller = true
        resultScroll.autohidesScrollers = true
        resultScroll.hasHorizontalScroller = false
        resultScroll.contentView.automaticallyAdjustsContentInsets = false
        resultScroll.contentView.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        resultStack.orientation = .vertical
        resultStack.alignment = .width
        resultStack.spacing = 14
        resultStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        resultStack.translatesAutoresizingMaskIntoConstraints = false
        resultScroll.documentView = resultStack
        NSLayoutConstraint.activate([
            resultStack.widthAnchor.constraint(equalTo: resultScroll.contentView.widthAnchor),
        ])
    }

    private func panel(title: String, view: NSView, headerControls: [NSView] = [], boxed: Bool = true) -> NSView {
        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.alignment = .width
        wrapper.spacing = 8
        wrapper.distribution = .fill
        let label = title == "原文" ? sourcePanelTitle : resultPanelTitle
        label.stringValue = title
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        view.translatesAutoresizingMaskIntoConstraints = false
        let bodyView: NSView
        if boxed {
            let box = MaterialCardView()
            box.translatesAutoresizingMaskIntoConstraints = false
            box.setContentHuggingPriority(.defaultLow, for: .horizontal)
            box.setContentHuggingPriority(.defaultLow, for: .vertical)
            box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            box.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            if title == "原文" {
                box.heightAnchor.constraint(equalToConstant: Self.fixedSourceTextHeight + 2).isActive = true
                box.setContentHuggingPriority(.required, for: .vertical)
                box.setContentCompressionResistancePriority(.required, for: .vertical)
            }
            box.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 1),
                view.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -1),
                view.topAnchor.constraint(equalTo: box.topAnchor, constant: 1),
                view.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -1),
            ])
            bodyView = box
        } else {
            bodyView = view
            bodyView.setContentHuggingPriority(.defaultLow, for: .vertical)
            bodyView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        }
        wrapper.addArrangedSubview(bodyView)
        // Build the header: either a bare title, or a row with the title on the
        // left and an optional set of trailing controls (icon buttons).
        if !headerControls.isEmpty {
            let headerRow = NSStackView()
            headerRow.orientation = .horizontal
            headerRow.alignment = .centerY
            headerRow.spacing = 8
            headerRow.addArrangedSubview(label)
            headerRow.addArrangedSubview(NSView())
            for control in headerControls {
                headerRow.addArrangedSubview(control)
            }
            wrapper.insertArrangedSubview(headerRow, at: 0)
            headerRow.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor).isActive = true
            headerRow.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor).isActive = true
        } else {
            wrapper.insertArrangedSubview(label, at: 0)
        }
        // Pin the body to both edges of the wrapper so its width is always the
        // full wrapper width. Without this, views with no intrinsic width can
        // collapse to a sliver inside stack views.
        bodyView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor).isActive = true
        bodyView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor).isActive = true
        // Keep the panel title flush left, not centered.
        label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor).isActive = true
        return wrapper
    }

    @objc private func translateButtonClicked() {
        translate()
    }

    @objc private func copySourceButtonClicked() {
        copySource()
    }

    @objc private func pasteSourceClicked() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            status("剪贴板没有可粘贴的文本")
            return
        }
        sourceView.textView.insertText(text, replacementRange: sourceView.textView.selectedRange())
        updateSourceHeight()
        status("已粘贴")
    }

    @objc private func stripNewlinesClicked() {
        let raw = sourceView.textView.string
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status("没有可处理的原文")
            return
        }
        // Collapse all runs of whitespace/newlines into single spaces so
        // multi-paragraph text becomes one compact paragraph.
        let compact = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        sourceView.setPlainText(compact)
        updateSourceHeight()
        status("已删除换行")
    }

    @objc private func clearSourceClicked() {
        sourceView.setPlainText("")
        updateSourceHeight()
        clearResults()
        status("已清空")
    }

    @objc private func selectionButtonClicked() {
        PythiaAppDelegate.shared?.translateSelection()
    }

    @objc private func ocrButtonClicked() {
        recognizeScreen(translateAfterRecognition: true)
    }

    @objc private func swapLanguages() {
        let source = selectedLanguageCode(sourceLanguagePopup)
        let target = selectedLanguageCode(targetLanguagePopup)
        selectLanguage(target.isEmpty ? "auto" : target, in: sourceLanguagePopup)
        selectLanguage(source == "auto" ? "en" : source, in: targetLanguagePopup)
        Preferences.shared.sourceLanguage = selectedLanguageCode(sourceLanguagePopup)
        Preferences.shared.targetLanguage = selectedLanguageCode(targetLanguagePopup)
        status("已交换语言")
    }

    @objc private func copyResultButtonClicked() {
        copyResult()
    }

    @objc private func clearInputButtonClicked() {
        clearInput()
    }

    @objc private func speakButtonClicked() {
        speakResult()
    }

    @objc private func collectionButtonClicked() {
        addCurrentResultToCollection()
    }

    @objc private func toggleAlwaysOnTop() {
        let next = !Preferences.shared.translateAlwaysOnTop
        Preferences.shared.translateAlwaysOnTop = next
        applyAlwaysOnTopPreference()
        updatePinWindowButton()
        status(next ? "翻译窗口已置顶" : "翻译窗口取消置顶")
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func languageChanged() {
        Preferences.shared.sourceLanguage = selectedLanguageCode(sourceLanguagePopup)
        Preferences.shared.targetLanguage = selectedLanguageCode(targetLanguagePopup)
        updatePanelTitles()
    }

    @objc private func reloadPreferences() {
        servicePicker.reloadOptions(selected: Preferences.shared.translateServiceList)
        selectLanguage(Preferences.shared.sourceLanguage, in: sourceLanguagePopup)
        selectLanguage(Preferences.shared.targetLanguage, in: targetLanguagePopup)
        updatePanelTitles()
        applyRuntimeTranslationPreferences()
    }

    private func status(_ text: String) {
        statusLabel.stringValue = text
    }

    private func updatePanelTitles() {
        sourcePanelTitle.stringValue = "原文（\(selectedLanguageDisplay(sourceLanguagePopup))）"
        resultPanelTitle.stringValue = "译文（\(selectedLanguageDisplay(targetLanguagePopup))）"
    }

    private func selectedLanguageDisplay(_ popup: NSPopUpButton) -> String {
        let title = popup.titleOfSelectedItem ?? ""
        return title.components(separatedBy: "  ").first ?? title
    }

    func loadRecord(_ record: TranslationRecord) {
        sourceView.setPlainText(record.source)
        showSingleResult(title: record.provider, text: record.result)
        showAndFocus()
    }

    func applyVisualPreferences() {
        // Re-apply the theme color to dynamically-created icon buttons and
        // service titles so they follow the color chosen in settings.
        let color = PythiaDesign.themeColor()
        func refresh(_ view: NSView) {
            if let button = view as? NSButton, !button.isBordered {
                button.contentTintColor = color
            }
            if let field = view as? NSTextField, view is NSTextField, field != sourcePanelTitle, field != resultPanelTitle {
                // result card titles use the theme color too
            }
            view.subviews.forEach { refresh($0) }
        }
        if let content = window?.contentView {
            refresh(content)
        }
        sourceView.applyTextAppearance()
        sourceView.applyFontPreferences()
        resultViews.values.forEach { $0.applyTextAppearance() }
        resultViews.values.forEach { $0.applyFontPreferences() }
        scheduleResultHeightRefresh()

        // Re-apply title colors by walking the result stack.
        resultStack.arrangedSubviews.forEach { section in
            section.subviews.forEach { sub in
                if let stack = sub as? NSStackView {
                    stack.arrangedSubviews.forEach { inner in
                        if let label = inner as? NSTextField {
                            label.textColor = color
                        }
                    }
                }
            }
        }
        window?.contentView?.needsDisplay = true
        window?.contentView?.subviews.forEach { $0.needsDisplay = true }
    }

    private func applyRuntimeTranslationPreferences() {
        let preferences = Preferences.shared
        languageControls.forEach { $0.isHidden = preferences.hideLanguage }
        sourcePanelContainer?.isHidden = preferences.hideSource
        resultPanelTopToSourceConstraint?.isActive = !preferences.hideSource
        resultPanelTopToHeaderConstraint?.isActive = preferences.hideSource
        window?.alphaValue = 1.0
        sourceView.applyFontPreferences()
        resultViews.values.forEach { $0.applyFontPreferences() }
        scheduleResultHeightRefresh()
        applyAlwaysOnTopPreference()
        updatePinWindowButton()
        updateSourceHeight()
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func applyAlwaysOnTopPreference() {
        window?.level = Preferences.shared.translateAlwaysOnTop ? .floating : .normal
    }

    private func updatePinWindowButton() {
        let isPinned = Preferences.shared.translateAlwaysOnTop
        pinWindowButton.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin",
            accessibilityDescription: isPinned ? "取消置顶" : "窗口置顶"
        )
        pinWindowButton.toolTip = isPinned ? "取消置顶" : "窗口置顶"
        pinWindowButton.isActiveIcon = isPinned
    }

    private func applyAutoCopyAfterTranslation(source: String) {
        let mode = Preferences.shared.translateAutoCopy
        let result = combinedResultText().trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        switch mode {
        case "source":
            value = source
        case "target":
            value = result
        case "source_target":
            value = [source, result].filter { !$0.isEmpty }.joined(separator: "\n\n")
        default:
            return
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func compactWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func activeTranslationServices() -> [String] {
        var seen = Set<String>()
        let configured = Preferences.shared.translateServiceList
            .map { TranslationService.canonicalServiceIdentifier($0) }
            .filter { !$0.isEmpty }
        let services = configured.isEmpty ? [Preferences.shared.provider.rawValue] : configured
        return services.filter { service in
            let key = service.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func prepareResultCards(for services: [String]) {
        clearResults()
        resultScroll.hasVerticalScroller = true
        for service in services {
            let displayName = PluginManager.shared.displayName(forServiceIdentifier: service)
            let textView = PythiaTextView(placeholder: "等待 \(displayName) 返回...", editable: false, scrollable: false)
            textView.setPlainText("等待 \(displayName) 返回...")
            let height = textView.heightAnchor.constraint(equalToConstant: 104)
            height.isActive = true
            resultHeightConstraints[service] = height

            makeResultSection(key: service, title: displayName, textView: textView, showRetranslate: true)
            resultViews[service] = textView
            resultOrder.append(service)
            scheduleResultHeightRefresh()
        }
        scrollResultsToTop()
    }

    /// Builds one independent translation-result card. Each service gets its
    /// own MaterialCard, copy action, and disclosure control so multi-service
    /// output does not visually collapse into one shared translation box.
    private func makeResultSection(key: String, title: String, textView: PythiaTextView, showRetranslate: Bool = false) {
        let card = MaterialCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = PythiaDesign.themeColor()
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail

        let collapseButton = makeIconButton(systemName: "chevron.down", accessibility: "收起 \(title)", action: #selector(toggleResultSection))
        collapseButton.identifier = NSUserInterfaceItemIdentifier(key)
        resultCollapseButtons[key] = collapseButton

        let copyButton = makeCopyButton(action: #selector(copyResultForService))
        copyButton.identifier = NSUserInterfaceItemIdentifier(key)

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.addArrangedSubview(collapseButton)
        headerRow.addArrangedSubview(titleLabel)
        headerRow.addArrangedSubview(NSView())
        if showRetranslate {
            // Re-translate this service with the current input. Enabled only
            // after the service has returned a result (or an error).
            let retranslateButton = makeIconButton(systemName: "arrow.clockwise", accessibility: "重新翻译", action: #selector(retranslateResultForService))
            retranslateButton.identifier = NSUserInterfaceItemIdentifier(key)
            retranslateButton.isEnabled = false
            resultRetranslateButtons[key] = retranslateButton
            headerRow.addArrangedSubview(retranslateButton)
        }
        headerRow.addArrangedSubview(copyButton)

        content.addArrangedSubview(headerRow)
        content.addArrangedSubview(textView)
        card.addSubview(content)

        resultStack.addArrangedSubview(card)

        let pad: CGFloat = 14
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: resultStack.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: resultStack.trailingAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -pad),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            headerRow.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            textView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
    }

    /// A borderless system copy-icon button (no text), styled like a toolbar
    /// icon and tinted with the theme color. Use the standard init then set
    /// target/action explicitly — the NSButton(image:target:action:) init does
    /// not reliably wire the action.
    private func makeIconButton(systemName: String, accessibility: String, action: Selector) -> NSButton {
        GlassIconButton(systemName: systemName, accessibility: accessibility, target: self, action: action)
    }

    private func makeCopyButton(action: Selector) -> NSButton {
        makeIconButton(systemName: "doc.on.doc", accessibility: "复制", action: action)
    }

    @objc private func toggleResultSection(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue,
              let textView = resultViews[key]
        else { return }
        if collapsedResultKeys.contains(key) {
            collapsedResultKeys.remove(key)
            sender.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "收起")
            sender.toolTip = "收起 \(PluginManager.shared.displayName(forServiceIdentifier: key))"
            textView.isHidden = false
            resultHeightConstraints[key]?.isActive = true
            updateResultHeight(for: key)
        } else {
            collapsedResultKeys.insert(key)
            sender.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "展开")
            sender.toolTip = "展开 \(PluginManager.shared.displayName(forServiceIdentifier: key))"
            resultHeightConstraints[key]?.isActive = false
            textView.isHidden = true
        }
        resultStack.layoutSubtreeIfNeeded()
    }

    private func setResult(_ text: String, for provider: String) {
        guard let textView = resultViews[provider] else { return }
        textView.setPlainText(text)
        updateResultHeight(for: provider)
        scheduleResultHeightRefresh()
    }

    private func showSingleResult(title: String, text: String) {
        clearResults()
        resultScroll.hasVerticalScroller = true
        let textView = PythiaTextView(placeholder: "", editable: false, scrollable: false)
        textView.setPlainText(text)
        let height = textView.heightAnchor.constraint(equalToConstant: 104)
        height.isActive = true
        resultHeightConstraints[title] = height

        makeResultSection(key: title, title: title, textView: textView)
        resultViews[title] = textView
        resultOrder.append(title)
        scheduleResultHeightRefresh()
        scrollResultsToTop()
    }

    private func scheduleResultHeightRefresh() {
        resultHeightRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.resultStack.layoutSubtreeIfNeeded()
            self.resultOrder.forEach { self.updateResultHeight(for: $0) }
            self.resultStack.layoutSubtreeIfNeeded()
        }
        resultHeightRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
    }

    private func updateResultHeight(for key: String) {
        guard !collapsedResultKeys.contains(key) else { return }
        guard let textView = resultViews[key], let constraint = resultHeightConstraints[key] else { return }
        resultStack.layoutSubtreeIfNeeded()
        let width = max(240, textView.bounds.width)
        constraint.constant = textView.fittingHeight(for: width)
    }

    private func clearResults() {
        resultScroll.hasVerticalScroller = false
        NSLayoutConstraint.deactivate(Array(resultHeightConstraints.values))
        resultHeightConstraints.removeAll()
        resultCollapseButtons.removeAll()
        resultRetranslateButtons.removeAll()
        collapsedResultKeys.removeAll()
        resultHeightRefreshWorkItem?.cancel()
        resultHeightRefreshWorkItem = nil
        resultViews.removeAll()
        resultOrder.removeAll()
        failedResultKeys.removeAll()
        resultStack.arrangedSubviews.forEach { view in
            resultStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        scrollResultsToTop()
    }

    private func scrollResultsToTop() {
        resultScroll.contentView.scroll(to: .zero)
        resultScroll.reflectScrolledClipView(resultScroll.contentView)
    }

    private func combinedResultText() -> String {
        resultOrder.compactMap { provider in
            guard let text = resultViews[provider]?.textView.string.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return "\(PluginManager.shared.displayName(forServiceIdentifier: provider))\n\(text)"
        }.joined(separator: "\n\n")
    }

    private func collectionTargetText() -> String {
        let results = resultOrder.compactMap { provider -> String? in
            guard !failedResultKeys.contains(provider) else { return nil }
            guard let text = resultViews[provider]?.textView.string.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            if resultOrder.count <= 1 {
                return text
            }
            return "\(PluginManager.shared.displayName(forServiceIdentifier: provider))\n\(text)"
        }
        return results.joined(separator: "\n\n")
    }

    private func preferredSpeechVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let normalized = languageCode.lowercased()
        let preferredLanguages: [String]
        if normalized.hasPrefix("zh") {
            preferredLanguages = normalized.contains("tw") || normalized.contains("hk") ? ["zh-TW", "zh-HK", "zh-Hant"] : ["zh-CN", "zh-Hans", "zh"]
        } else if normalized.hasPrefix("ja") {
            preferredLanguages = ["ja-JP", "ja"]
        } else if normalized.hasPrefix("ko") {
            preferredLanguages = ["ko-KR", "ko"]
        } else if normalized.hasPrefix("fr") {
            preferredLanguages = ["fr-FR", "fr"]
        } else if normalized.hasPrefix("de") {
            preferredLanguages = ["de-DE", "de"]
        } else if normalized.hasPrefix("es") {
            preferredLanguages = ["es-ES", "es"]
        } else if normalized.hasPrefix("en") {
            preferredLanguages = ["en-US", "en-GB", "en"]
        } else {
            preferredLanguages = [normalized.replacingOccurrences(of: "_", with: "-"), normalized]
        }

        for language in preferredLanguages {
            if let voice = AVSpeechSynthesisVoice(language: language) {
                return voice
            }
        }
        let normalizedPrefixes = preferredLanguages.map { $0.lowercased() }
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            let language = voice.language.lowercased()
            if normalizedPrefixes.contains(where: { language.hasPrefix($0) }) {
                return voice
            }
        }
        return nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.status("朗读完成")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.status("已停止朗读")
        }
    }
}
