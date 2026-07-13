import AppKit
import Foundation

let languageOptions: [(code: String, title: String)] = [
    ("auto", "自动检测"),
    ("zh-CN", "简体中文"),
    ("zh-TW", "繁體中文"),
    ("en", "English"),
    ("ja", "日本語"),
    ("ko", "한국어"),
    ("fr", "Français"),
    ("de", "Deutsch"),
    ("es", "Español"),
    ("it", "Italiano"),
    ("pt", "Português"),
    ("ru", "Русский"),
    ("ar", "العربية"),
    ("hi", "हिन्दी"),
]

func languageTitles(includeAuto: Bool) -> [String] {
    languageOptions
        .filter { includeAuto || $0.code != "auto" }
        .map { "\($0.title)  \($0.code)" }
}

func selectedLanguageCode(_ popup: NSPopUpButton) -> String {
    let title = popup.titleOfSelectedItem ?? ""
    return languageOptions.first { title.hasSuffix("  \($0.code)") }?.code ?? title
}

func selectLanguage(_ code: String, in popup: NSPopUpButton) {
    let normalized = code.isEmpty ? "auto" : code
    if let item = popup.itemArray.first(where: { $0.title.hasSuffix("  \(normalized)") }) {
        popup.select(item)
    } else if let item = popup.itemArray.first(where: { $0.title.hasSuffix("  auto") }) {
        popup.select(item)
    } else {
        popup.selectItem(at: 0)
    }
}

final class PythiaTextView: NSScrollView {
    let textView = SubmitTextView()
    private let isScrollable: Bool
    var onSubmit: (() -> Void)? {
        get { textView.onSubmit }
        set { textView.onSubmit = newValue }
    }
    var onTextChanged: (() -> Void)? {
        get { textView.onTextChanged }
        set { textView.onTextChanged = newValue }
    }

    init(placeholder: String, editable: Bool = true, scrollable: Bool = true) {
        isScrollable = scrollable
        super.init(frame: .zero)
        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = scrollable
        hasHorizontalScroller = false
        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = placeholder
        documentView = textView
        applyTextAppearance()
        applyFontPreferences()
        // Allow horizontal stretch so PythiaTextView fills its container width.
        // NSScrollView has no intrinsic width; without this Auto Layout lets the
        // clip view hug it down to a sliver inside stack views.
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTextAppearance()
    }

    func setPlainText(_ value: String) {
        textView.string = value
        applyTextAppearance()
    }

    func applyTextAppearance() {
        let color = resolvedBodyTextColor()
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes[.foregroundColor] = color
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: storage.length))
        }
    }

    func applyFontPreferences() {
        let preferences = Preferences.shared
        let size = CGFloat(max(11, min(28, preferences.appFontSize)))
        let name = preferences.appFont.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = preferences.appFallbackFont.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFont: NSFont
        if !name.isEmpty, name.lowercased() != "default", let custom = NSFont(name: name, size: size) {
            resolvedFont = custom
        } else {
            resolvedFont = .systemFont(ofSize: size)
        }
        let displayFont = Self.font(resolvedFont, withFallbackNamed: fallbackName, size: size)
        textView.font = displayFont
        textView.typingAttributes[.font] = displayFont
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.font, value: displayFont, range: NSRange(location: 0, length: storage.length))
        }
    }

    private static func font(_ baseFont: NSFont, withFallbackNamed fallbackName: String, size: CGFloat) -> NSFont {
        guard !fallbackName.isEmpty,
              fallbackName.lowercased() != "default",
              let fallbackFont = NSFont(name: fallbackName, size: size)
        else {
            return baseFont
        }
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .cascadeList: [fallbackFont.fontDescriptor]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? baseFont
    }

    private func resolvedBodyTextColor() -> NSColor {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .white : .black
    }

    // Non-scrollable instances (result cards) must not swallow the scroll wheel.
    // Walk up the view hierarchy to the enclosing scroll view and let it scroll
    // when the cursor is over a result card, not just over the scrollbar.
    override func scrollWheel(with event: NSEvent) {
        if isScrollable {
            super.scrollWheel(with: event)
            return
        }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? NSScrollView, scroll !== self, scroll.hasVerticalScroller || scroll.hasHorizontalScroller {
                scroll.scrollWheel(with: event)
                return
            }
            ancestor = view.superview
        }
        nextResponder?.scrollWheel(with: event)
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        guard let container = textView.textContainer, let lm = textView.layoutManager else { return 44 }
        let contentWidth = max(240, width - 8)
        // Force a fresh measurement layout against the given width: stop width
        // tracking, set the container to the desired width, invalidate the
        // whole glyph range, then ensure layout completes synchronously.
        container.widthTracksTextView = false
        container.size = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        container.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.string.count), actualCharacterRange: nil)
        lm.ensureLayout(for: container)
        let glyphRange = lm.glyphRange(for: container)
        let used = lm.boundingRect(forGlyphRange: glyphRange, in: container).height
        container.widthTracksTextView = true
        return max(44, ceil(used + textView.textContainerInset.height * 2 + 6))
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onTextChanged: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    // Handle only the bare Return key as submit; forward everything else
    // (including Cmd+V paste and normal typing) to the standard text view
    // machinery via performKeyEquivalent/keyDown.
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isBareReturn = isReturn
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.command)
            && !flags.contains(.control)
        let hadMarkedText = hasMarkedText()
        let inputMethodHandledEvent = isBareReturn
            ? (inputContext?.handleEvent(event) ?? false)
            : false

        if TextSubmissionPolicy.shouldSubmit(
            isReturn: isReturn,
            hasMarkedText: hadMarkedText || hasMarkedText(),
            inputMethodHandledEvent: inputMethodHandledEvent,
            hasShift: flags.contains(.shift),
            hasOption: flags.contains(.option),
            hasCommand: flags.contains(.command)
        ) {
            onSubmit?()
            return
        }
        if inputMethodHandledEvent {
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChanged?()
    }
}

/// A text field that records a keyboard shortcut instead of accepting typed
/// text. When it becomes first responder it clears and waits for the next key
/// combination, then displays it as "⇧⌘E" style symbols.
final class HotkeyRecorderField: NSTextField {
    private var recording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBezeled = true
        alignment = .center
        // A bezeled, non-editable text field can report an inflated intrinsic
        // content size that bloats its row and leaves large gaps. Pin a sane size.
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        // Force a standard single-line control height so the field never claims
        // a tall intrinsic size that would stretch its row container.
        var s = super.intrinsicContentSize
        s.height = 24
        return s
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { beginRecording() }
        return ok
    }

    private func beginRecording() {
        recording = true
        stringValue = "按下快捷键…"
        textColor = .secondaryLabelColor
    }

    // Capture the key combination. performKeyEquivalent fires for modifier+key
    // combos before they reach the field editor.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        record(event: event, flags: flags)
        return true
    }

    // While recording, swallow ordinary key events too.
    override func keyDown(with event: NSEvent) {
        if recording {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            record(event: event, flags: flags)
            return
        }
        super.keyDown(with: event)
    }

    // Escape cancels recording without changing the value.
    override func cancelOperation(_ sender: Any?) {
        if recording {
            recording = false
            textColor = .labelColor
            window?.makeFirstResponder(nil)
        } else {
            super.cancelOperation(sender)
        }
    }

    static func format(flags: NSEvent.ModifierFlags, character: String) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + character.uppercased()
    }

    private func record(event: NSEvent, flags: NSEvent.ModifierFlags) {
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) || flags.contains(.shift) else {
            return
        }
        guard let key = ShortcutKeyMap.displayName(forKeyCode: event.keyCode, fallback: event.charactersIgnoringModifiers),
              !key.isEmpty
        else { return }
        stringValue = Self.format(flags: flags, character: key)
        textColor = .labelColor
        recording = false
        window?.makeFirstResponder(nil)
    }
}

final class CardView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor.textBackgroundColor.withAlphaComponent(0.78).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.52).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

extension NSColor {
    convenience init?(potHex: String) {
        var value = potHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((number >> 16) & 0xff) / 255.0,
            green: CGFloat((number >> 8) & 0xff) / 255.0,
            blue: CGFloat(number & 0xff) / 255.0,
            alpha: 1.0
        )
    }

    var potHexRGB: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        let red = max(0, min(255, Int(round(color.redComponent * 255))))
        let green = max(0, min(255, Int(round(color.greenComponent * 255))))
        let blue = max(0, min(255, Int(round(color.blueComponent * 255))))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum PythiaDesign {
    static let avocado = NSColor(calibratedRed: 0.50, green: 0.72, blue: 0.28, alpha: 1.0)
    static let avocadoSoft = NSColor(calibratedRed: 0.50, green: 0.72, blue: 0.28, alpha: 0.22)
    static let skySoft = NSColor(calibratedRed: 0.55, green: 0.78, blue: 0.96, alpha: 0.12)
    static let blushSoft = NSColor(calibratedRed: 0.98, green: 0.70, blue: 0.78, alpha: 0.10)

    static func themeColor() -> NSColor {
        NSColor(potHex: Preferences.shared.themeColorHex) ?? avocado
    }

    static func glassBorderColor(for appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.white.withAlphaComponent(0.55)
    }

    static func glassShadowColor(for appearance: NSAppearance) -> CGColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return (dark ? NSColor.black.withAlphaComponent(0.46) : NSColor.black.withAlphaComponent(0.16)).cgColor
    }

    static func selectionFillColor(for appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return themeColor().withAlphaComponent(dark ? 0.72 : 0.84)
    }
}

final class MaterialCardView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 22
        layer?.shadowOffset = NSSize(width: 0, height: -8)
        updateGlass()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGlass()
    }

    private func updateGlass() {
        layer?.borderColor = PythiaDesign.glassBorderColor(for: effectiveAppearance).cgColor
        layer?.shadowColor = PythiaDesign.glassShadowColor(for: effectiveAppearance)
    }
}

final class GlassIconButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    var isActiveIcon = false {
        didSet { updateGlass() }
    }

    init(systemName: String, accessibility: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: systemName, accessibilityDescription: accessibility)
        toolTip = accessibility
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .inline
        controlSize = .small
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        updateGlass()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateGlass()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateGlass()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor
        super.mouseDown(with: event)
        updateGlass()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGlass()
    }

    private func updateGlass() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = PythiaDesign.themeColor()
        contentTintColor = isActiveIcon ? theme : theme.withAlphaComponent(dark ? 0.92 : 0.86)
        let hoverFill = dark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.075)
        let activeFill = theme.withAlphaComponent(dark ? 0.24 : 0.18)
        layer?.backgroundColor = (isActiveIcon ? activeFill : (isHovering ? hoverFill : .clear)).cgColor
        layer?.borderWidth = isHovering || isActiveIcon ? 0.7 : 0
        layer?.borderColor = PythiaDesign.glassBorderColor(for: effectiveAppearance).cgColor
        layer?.shadowOpacity = isHovering ? 0.20 : 0
        layer?.shadowRadius = isHovering ? 12 : 0
        layer?.shadowOffset = NSSize(width: 0, height: -3)
        layer?.shadowColor = PythiaDesign.glassShadowColor(for: effectiveAppearance)
    }
}

final class LiquidGlassBackgroundView: NSVisualEffectView {
    var enhancedGlass = false {
        didSet { updateGlass() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .windowBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        updateGlass()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGlass()
    }

    private func updateGlass() {
        material = enhancedGlass ? .popover : .windowBackground
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(enhancedGlass ? 0.88 : 0.96)
            .cgColor
    }
}

final class SettingsSidebarItemView: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    let index: Int
    var isActive: Bool = false {
        didSet { updateAppearance() }
    }

    init(title: String, index: Int, target: AnyObject?, action: Selector?) {
        self.index = index
        super.init(frame: .zero)
        self.target = target
        self.action = action
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isActive ? PythiaDesign.selectionFillColor(for: effectiveAppearance).cgColor : NSColor.clear.cgColor
        titleLabel.textColor = isActive ? .white : .labelColor
        titleLabel.font = .systemFont(ofSize: 15, weight: isActive ? .semibold : .regular)
    }
}

/// A drag-to-reorder, toggleable list of translation services built on
/// NSTableView (native drag-and-drop reordering). Each row is
/// `[启用 checkbox] 服务名`. The row order IS the display order in the
/// translation result area, and only enabled (checked) services participate in
/// translation. Like the legacy pot app, selection and ordering live together.
final class ServiceOrderListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    /// Called whenever the enabled set or the order changes; receives the
    /// current ordered list of ENABLED service IDs (display order).
    var onChange: (([String]) -> Void)?
    var optionProvider: () -> [(id: String, title: String)] = {
        PluginManager.shared.translationServiceOptions()
    }

    /// All known services in their current display order: (id, title).
    private var items: [(id: String, title: String)] = []
    /// IDs currently enabled (checked).
    private var enabled: Set<String> = []

    private let tableView: NSTableView = {
        let tv = NSTableView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.headerView = nil
        tv.backgroundColor = .clear
        tv.rowSizeStyle = .default
        tv.intercellSpacing = NSSize(width: 0, height: 4)
        tv.allowsColumnResizing = false
        tv.allowsMultipleSelection = false
        tv.allowsEmptySelection = true
        // Enable drag-to-reorder.
        tv.setDraggingSourceOperationMask(.move, forLocal: true)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("service"))
        column.resizingMask = .autoresizingMask
        column.width = 400
        tv.addTableColumn(column)
        return tv
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = tableView
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([.string])
        // Tall enough to show several rows even before layout settles.
        heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The ordered list of enabled service IDs (this is what gets written to
    /// `translateServiceList`; order == display order).
    var orderedEnabledServices: [String] {
        items.filter { enabled.contains($0.id) }.map(\.id)
    }

    var orderedServices: [String] {
        items.map(\.id)
    }

    /// Rebuilds the list. `orderedEnabled` drives both the enabled set and the
    /// initial ordering: its order is preserved for known services; any known
    /// service not in it is appended at the end (unchecked). `customIDs` are
    /// extra (possibly unknown) IDs to append at the very end.
    func load(orderedEnabled: [String], customIDs: [String]) {
        load(orderedServices: orderedEnabled, enabledServices: orderedEnabled, customIDs: customIDs)
    }

    /// Rebuilds the list using a complete persisted order plus a separate enabled
    /// list. This preserves manual ordering of disabled services across plugin
    /// installs, refreshes, tab switches, and save/load cycles.
    func load(orderedServices: [String], enabledServices: [String], customIDs: [String]) {
        let allOptions = optionProvider()
        let optionMap = Dictionary(allOptions.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

        enabled = Set(enabledServices)

        var seen = Set<String>()
        var ordered: [(id: String, title: String)] = []
        for id in orderedServices + enabledServices + customIDs {
            let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append((id: key, title: optionMap[key] ?? key))
        }
        for option in allOptions where !seen.contains(option.id) {
            seen.insert(option.id)
            ordered.append(option)
        }
        items = ordered
        tableView.reloadData()
    }

    /// Refreshes the known-service set while preserving order/enabled state.
    func reloadOptions() {
        load(orderedServices: orderedServices, enabledServices: orderedEnabledServices, customIDs: [])
    }

    /// Inserts a custom service ID (e.g. `plugin:custom-name`) at the top,
    /// enabled by default. New services should become the first active service
    /// instead of resetting the user's existing order.
    func appendCustom(id: String) {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !items.contains(where: { $0.id == key }) else { return }
        items.insert((id: key, title: key), at: 0)
        enabled.insert(key)
        tableView.reloadData()
        fireChange()
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row]
        let cell = ServiceOrderRowCell()
        cell.configure(
            title: item.title,
            enabled: enabled.contains(item.id),
            onChange: { [weak self] isOn in
                guard let self else { return }
                if isOn { self.enabled.insert(item.id) } else { self.enabled.remove(item.id) }
                self.fireChange()
            },
            onDelete: { [weak self] in
                self?.removeService(id: item.id)
            }
        )
        return cell
    }

    func tableView(_ tableView: NSTableView, rowHeight row: Int) -> CGFloat { 30 }

    /// Removes a service from the list. For plugin services (id starts with
    /// "plugin:"), offers to also delete the plugin's files; for built-in or
    /// custom IDs, just removes from the list (built-ins can be restored via
    /// "重置为内置服务").
    private func removeService(id: String) {
        let isPlugin = id.lowercased().hasPrefix("plugin:")
        let pluginDirName: String? = isPlugin ? String(id.dropFirst("plugin:".count)) : nil
        let title = items.first(where: { $0.id == id })?.title ?? id

        let alert = NSAlert()
        alert.messageText = "移除「\(title)」"
        if let dir = pluginDirName {
            alert.informativeText = "从服务列表移除此插件。是否同时删除插件文件（无法撤销）？"
            alert.addButton(withTitle: "移除并删除文件")
            alert.addButton(withTitle: "仅从列表移除")
            alert.addButton(withTitle: "取消")
            let choice = alert.runModal()
            switch choice {
            case .alertFirstButtonReturn:
                PluginManager.shared.deletePlugin(name: dir)
            case .alertSecondButtonReturn:
                break
            default:
                return
            }
        } else {
            alert.informativeText = "从服务列表移除「\(title)」。内置服务可稍后用「重置为内置服务」恢复。"
            alert.addButton(withTitle: "移除")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        items.removeAll { $0.id == id }
        enabled.remove(id)
        tableView.reloadData()
        fireChange()
    }

    // Drag-to-reorder: validate same-table move.
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let source = info.draggingSource as? NSTableView, source === tableView,
              let from = info.draggingPasteboard.string(forType: .string),
              let fromIndex = Int(from), items.indices.contains(fromIndex),
              row >= 0, row <= items.count else {
            return false
        }
        var toIndex = row
        // When dropping ON a row, treat as insert before that row.
        if dropOperation == .on { toIndex = row }
        let moved = items.remove(at: fromIndex)
        // Adjust destination index after removal.
        let insertIndex = min(items.count, fromIndex < toIndex ? toIndex - 1 : toIndex)
        items.insert(moved, at: insertIndex)
        tableView.reloadData()
        fireChange()
        return true
    }

    // Write the source row index when a drag begins.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let pb = NSPasteboardItem()
        pb.setString(String(row), forType: .string)
        return pb
    }

    private func fireChange() {
        onChange?(orderedEnabledServices)
    }
}

/// A single row in the service order list: drag handle + checkbox + title + delete.
private final class ServiceOrderRowCell: NSTableCellView {
    private let handle = NSImageView()
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let deleteButton = NSButton()
    private var onToggle: ((Bool) -> Void)?
    private var onDelete: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Drag handle (visual affordance; the whole row is draggable).
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动排序")
        handle.contentTintColor = .tertiaryLabelColor
        handle.imageAlignment = .alignCenter
        handle.toolTip = "拖动以调整顺序"

        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.target = self
        checkbox.action = #selector(toggle)
        checkbox.font = .systemFont(ofSize: 13)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isBordered = false
        deleteButton.bezelStyle = .inline
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.toolTip = "从列表移除"
        deleteButton.target = self
        deleteButton.action = #selector(deleteAction)

        addSubview(handle)
        addSubview(checkbox)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            handle.centerYAnchor.constraint(equalTo: centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 18),
            handle.heightAnchor.constraint(equalToConstant: 18),
            checkbox.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 4),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, enabled: Bool,
                   onChange: @escaping (Bool) -> Void,
                   onDelete: @escaping () -> Void) {
        checkbox.title = title
        checkbox.state = enabled ? .on : .off
        onToggle = onChange
        self.onDelete = onDelete
    }

    @objc private func toggle() {
        onToggle?(checkbox.state == .on)
    }

    @objc private func deleteAction() {
        onDelete?()
    }
}

/// A simple checkbox-only list of services, used inside the translator
/// window's quick service picker popover (no ordering needed there).
final class ServiceChecklistView: NSStackView {
    var onChange: (([String]) -> Void)?
    private var boxes: [NSButton] = []
    private var options: [(id: String, title: String)] = []
    private var orderedSelection: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        reloadOptions()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadOptions() {
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        boxes.removeAll()
        options = PluginManager.shared.translationServiceOptions(orderedBy: Preferences.shared.translateServiceOrder)
        options.forEach { option in
            let box = NSButton(checkboxWithTitle: option.title, target: nil, action: nil)
            box.identifier = NSUserInterfaceItemIdentifier(option.id)
            box.target = self
            box.action = #selector(selectionChanged(_:))
            box.font = .systemFont(ofSize: 13)
            boxes.append(box)
            addArrangedSubview(box)
        }
        selectedServices = orderedSelection
    }

    var selectedServices: [String] {
        get {
            let available = Set(boxes.compactMap { $0.identifier?.rawValue })
            return orderedSelection.filter { available.contains($0) }
        }
        set {
            let available = Set(boxes.compactMap { $0.identifier?.rawValue })
            var seen = Set<String>()
            orderedSelection = newValue.compactMap { id in
                guard available.contains(id), !seen.contains(id) else { return nil }
                seen.insert(id)
                return id
            }
            let selected = Set(newValue)
            boxes.forEach { box in
                box.state = selected.contains(box.identifier?.rawValue ?? "") ? .on : .off
            }
        }
    }

    @objc private func selectionChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if sender.state == .on {
            orderedSelection.removeAll { $0 == id }
            orderedSelection.insert(id, at: 0)
        } else {
            orderedSelection.removeAll { $0 == id }
        }
        selectedServices = orderedSelection
        onChange?(selectedServices)
    }
}

final class TranslationServicePickerButton: NSButton {
    var onChange: (([String]) -> Void)?
    private var options: [(id: String, title: String)] = []
    private var selectedIDs: [String] = []
    private let popover = NSPopover()

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        controlSize = .large
        font = .systemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(openServiceMenu)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        popover.behavior = .transient
        reloadOptions(selected: Preferences.shared.translateServiceList)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadOptions(selected: [String]) {
        options = PluginManager.shared.translationServiceOptions(orderedBy: Preferences.shared.translateServiceOrder)
        let available = Set(options.map(\.id))
        selectedIDs = selected.filter { available.contains($0) }
        if selectedIDs.isEmpty, let first = options.first?.id {
            selectedIDs = [first]
        }
        updateTitle()
    }

    @objc private func openServiceMenu() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let checklist = ServiceChecklistView()
        checklist.reloadOptions()
        checklist.selectedServices = selectedIDs
        checklist.onChange = { [weak self] services in
            guard let self else { return }
            self.selectedIDs = services
            if self.selectedIDs.isEmpty, let first = self.options.first?.id {
                self.selectedIDs = [first]
                checklist.selectedServices = self.selectedIDs
            }
            self.updateTitle()
            self.onChange?(self.selectedIDs)
        }
        let controller = NSViewController()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        checklist.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(checklist)
        NSLayoutConstraint.activate([
            checklist.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            checklist.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            checklist.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            checklist.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        controller.view = container
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 260, height: min(420, max(180, 32 + options.count * 26)))
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    private func updateTitle() {
        if selectedIDs.count == 1, let id = selectedIDs.first {
            title = PluginManager.shared.displayName(forServiceIdentifier: id)
        } else {
            title = "服务 \(selectedIDs.count)"
        }
    }
}

final class PastelBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        PythiaDesign.skySoft.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 24, dy: 18), xRadius: 24, yRadius: 24).fill()
        PythiaDesign.blushSoft.setFill()
        let blush = NSRect(x: bounds.maxX - 280, y: bounds.minY + 40, width: 220, height: bounds.height - 90)
        NSBezierPath(roundedRect: blush, xRadius: 22, yRadius: 22).fill()
    }
}

final class PastelAccentBar: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        PythiaDesign.themeColor().withAlphaComponent(0.86).setFill()
        path.fill()
        let sky = NSRect(x: bounds.width * 0.38, y: 0, width: bounds.width * 0.32, height: bounds.height)
        PythiaDesign.skySoft.withAlphaComponent(0.85).setFill()
        sky.fill()
        let blush = NSRect(x: bounds.width * 0.70, y: 0, width: bounds.width * 0.30, height: bounds.height)
        PythiaDesign.blushSoft.withAlphaComponent(0.85).setFill()
        blush.fill()
    }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// A window that refuses to shrink narrower than a stored "stable width".
/// NSWindow normally auto-resizes to its content view's fitting size, so when a
/// settings tab with little content is shown the window collapses narrower.
/// Overriding `constrainFrameRect(_:to:)` (the hook NSWindow uses to enforce
/// minSize) lets us clamp the width to the user's chosen value on EVERY frame
/// change — including the content-driven shrink — so the window stays stable
/// across tab switches.
final class StableWindow: NSWindow {
    var stableMinWidth: CGFloat = 820
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var f = super.constrainFrameRect(frameRect, to: screen)
        if f.width < stableMinWidth {
            f.size.width = stableMinWidth
        }
        return f
    }
}

/// A wrapping label that keeps its `preferredMaxLayoutWidth` in sync with its
/// actual width. Plain `NSTextField(wrappingLabelWithString:)` only wraps when
/// `preferredMaxLayoutWidth` is set; a trailing Auto Layout constraint alone is
/// not enough because the field reports its full one-line width as intrinsic
/// size and never re-wraps when the window narrows.
///
/// NOTE: we must NOT call `invalidateIntrinsicContentSize()` here. Doing so from
/// within `layout()` creates a feedback loop (layout → invalidate intrinsic →
/// re-layout) that makes window resizing extremely laggy and prevents smooth
/// (无极) resizing. Setting `preferredMaxLayoutWidth` alone is enough: the text
/// system re-wraps and the field reports an updated fitting height on the next
/// layout pass without a manual invalidation storm.
final class AutoWrappingLabel: NSTextField {
    override func layout() {
        super.layout()
        let w = bounds.width
        if w > 0 && abs(preferredMaxLayoutWidth - w) > 0.5 {
            preferredMaxLayoutWidth = w
        }
    }
}

/// A vertical NSStackView (used for settings forms) that stretches EVERY
/// arranged subview to the stack's full width. This is required because plain
/// `.width` alignment does NOT stretch arbitrary NSView containers — it leaves
/// them at intrinsic size and centers them, which makes `row(...)` labels drift
/// depending on the control's width. By pinning each subview's width to the
/// stack width, every row container fills the form and its leading-pinned label
/// lands at the same left edge.
final class FullWidthStackView: NSStackView {
    override var isFlipped: Bool { true }

    override func addArrangedSubview(_ view: NSView) {
        super.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let c = view.widthAnchor.constraint(equalTo: widthAnchor)
        // Use a high but not required priority so it doesn't fight internal
        // constraints of wrapped controls.
        c.priority = .defaultHigh
        c.isActive = true
    }
}

final class PillButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressing = false
    private let emphasized: Bool

    init(_ title: String, target: AnyObject?, action: Selector?) {
        emphasized = title == "翻译" || title == "保存"
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .inline
        controlSize = .large
        font = .systemFont(ofSize: 13, weight: .semibold)
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        contentTintColor = emphasized ? PythiaDesign.themeColor() : .labelColor
        heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        updateGlass()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateGlass()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressing = false
        updateGlass()
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        updateGlass()
        super.mouseDown(with: event)
        isPressing = false
        updateGlass()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGlass()
    }

    private func updateGlass() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = PythiaDesign.themeColor()
        contentTintColor = emphasized ? theme : (dark ? .white.withAlphaComponent(0.92) : .black.withAlphaComponent(0.74))
        let restingFill = dark ? NSColor.white.withAlphaComponent(0.075) : NSColor.black.withAlphaComponent(0.045)
        let hoverFill = dark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.075)
        let pressFill = theme.withAlphaComponent(dark ? 0.26 : 0.18)
        layer?.backgroundColor = (isPressing ? pressFill : (isHovering ? hoverFill : restingFill)).cgColor
        layer?.borderWidth = isHovering || isPressing ? 0.7 : 0
        layer?.borderColor = PythiaDesign.glassBorderColor(for: effectiveAppearance).cgColor
        layer?.shadowOpacity = isHovering ? 0.18 : 0
        layer?.shadowRadius = isHovering ? 12 : 0
        layer?.shadowOffset = NSSize(width: 0, height: -3)
        layer?.shadowColor = PythiaDesign.glassShadowColor(for: effectiveAppearance)
    }
}
