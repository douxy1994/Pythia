import AppKit

/// Detects a credible text-selection drag in common document, PDF, browser,
/// and chat applications, then presents a tiny non-activating Pythia button.
/// Text is not copied until the user explicitly clicks the button.
final class FloatingSelectionButtonService: NSObject {
    static let shared = FloatingSelectionButtonService()

    var onSelectionRequested: ((NSRunningApplication, NSPoint) -> Void)?

    private final class SelectionPanel: NSPanel {
        var onClick: (() -> Void)?
        override var canBecomeMain: Bool { false }

        override func sendEvent(_ event: NSEvent) {
            if event.type == .leftMouseUp {
                onClick?()
                return
            }
            super.sendEvent(event)
        }
    }

    private final class SelectionIconButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private static let explicitBundleIDs: Set<String> = [
        "com.microsoft.word",
        "com.kingsoft.wpsoffice.mac",
        "com.apple.preview",
        "com.adobe.acrobat.pro",
        "com.adobe.reader",
        "com.google.chrome",
        "com.apple.safari",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.browser",
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams2",
        "com.tencent.xinwechat",
        "com.tencent.qq",
        "ru.keepcoder.telegram",
        "com.hnc.discord",
    ]

    private static let bundleFragments = [
        "word", "wps", "kingsoft", "pdf", "acrobat", "reader",
        "chrome", "safari", "firefox", "edge", "browser", "arc",
        "slack", "teams", "wechat", "weixin", "telegram", "discord", "qq",
    ]

    private let panel: SelectionPanel
    private let iconButton = SelectionIconButton()
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var dragStart: (point: NSPoint, time: TimeInterval, application: NSRunningApplication)?
    private var selectionApplication: NSRunningApplication?
    private var selectionPoint = NSPoint.zero
    private var hideWorkItem: DispatchWorkItem?
    private var lastHandledEvent: (type: CGEventType, point: NSPoint, time: TimeInterval)?

    private override init() {
        panel = SelectionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 36, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    deinit {
        stop()
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard eventTap == nil, globalMonitor == nil else { return }
        if installEventTap() {
            // The AppKit monitor below remains active as a fallback for macOS
            // configurations where a created tap omits some events.
        }
        // Keep an AppKit monitor active as well: some macOS/TCC combinations
        // create a session tap successfully but do not deliver every event.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if self.panel.isVisible, event.window === self.panel {
                self.buttonClicked()
                return nil
            }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func stop() {
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        dragStart = nil
        hide()
    }

    private func installEventTap() -> Bool {
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<FloatingSelectionButtonService>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = service.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            let point = service.appKitPoint(fromCGEventPoint: event.location)
            DispatchQueue.main.async {
                service.handle(type: type, point: point)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func configurePanel() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onClick = { [weak self] in self?.buttonClicked() }

        let material = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 10
        material.layer?.cornerCurve = .continuous

        iconButton.frame = material.bounds.insetBy(dx: 4, dy: 4)
        iconButton.autoresizingMask = [.width, .height]
        iconButton.isBordered = false
        iconButton.imagePosition = .imageOnly
        iconButton.imageScaling = .scaleProportionallyDown
        iconButton.image = NSApp.applicationIconImage
        iconButton.toolTip = "用 Pythia 翻译选中文字"
        iconButton.setAccessibilityLabel("用 Pythia 翻译选中文字")
        iconButton.target = self
        iconButton.action = #selector(buttonClicked)
        material.addSubview(iconButton)
        panel.contentView = material
    }

    private func handle(_ event: NSEvent) {
        let type: CGEventType
        switch event.type {
        case .leftMouseDown: type = .leftMouseDown
        case .leftMouseUp: type = .leftMouseUp
        case .leftMouseDragged: type = .leftMouseDragged
        default: return
        }
        handle(type: type, point: NSEvent.mouseLocation)
    }

    private func handle(type: CGEventType, point: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastHandledEvent,
           previous.type == type,
           now - previous.time < 0.025,
           hypot(previous.point.x - point.x, previous.point.y - point.y) < 1 {
            return
        }
        lastHandledEvent = (type, point, now)
        switch type {
        case .leftMouseDown:
            if panel.isVisible, panel.frame.contains(point) {
                dragStart = nil
                return
            }
            hide()
            guard let app = NSWorkspace.shared.frontmostApplication,
                  isSupportedSelectionApplication(app) else {
                dragStart = nil
                return
            }
            dragStart = (point, ProcessInfo.processInfo.systemUptime, app)

        case .leftMouseUp:
            if panel.isVisible, panel.frame.contains(point) {
                dragStart = nil
                buttonClicked()
                return
            }
            guard let start = dragStart else { return }
            dragStart = nil
            let end = point
            let distance = hypot(end.x - start.point.x, end.y - start.point.y)
            let duration = ProcessInfo.processInfo.systemUptime - start.time
            guard distance >= 7, duration <= 12,
                  !start.application.isTerminated else { return }
            selectionApplication = start.application
            selectionPoint = end
            show(near: end)

        default:
            break
        }
    }

    private func isSupportedSelectionApplication(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != pid_t(ProcessInfo.processInfo.processIdentifier),
              !app.isTerminated else { return false }
        let identifier = app.bundleIdentifier?.lowercased() ?? ""
        if Self.explicitBundleIDs.contains(identifier) { return true }
        return Self.bundleFragments.contains { identifier.contains($0) }
    }

    /// Quartz mouse events use a top-left global origin while AppKit windows use
    /// a bottom-left global origin. The primary screen's top edge is the stable
    /// bridge between both coordinate spaces, including vertically offset
    /// secondary displays.
    private func appKitPoint(fromCGEventPoint point: NSPoint) -> NSPoint {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: point.x, y: primaryTop - point.y)
    }

    private func show(near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let size = panel.frame.size
        var origin = NSPoint(x: point.x + 10, y: point.y - size.height - 10)
        let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        if origin.x + size.width > visible.maxX { origin.x = point.x - size.width - 10 }
        if origin.y < visible.minY { origin.y = point.y + 10 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel.orderOut(nil)
    }

    @objc private func buttonClicked() {
        guard let app = selectionApplication, !app.isTerminated else {
            hide()
            return
        }
        selectionApplication = nil
        let point = selectionPoint
        hide()
        onSelectionRequested?(app, point)
    }
}
