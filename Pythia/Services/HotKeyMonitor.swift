import AppKit
import Carbon
import Foundation

enum ShortcutKeyMap {
    static let displayToKeyCode: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "Space": UInt32(kVK_Space), "Tab": UInt32(kVK_Tab), "Return": UInt32(kVK_Return),
        "Esc": UInt32(kVK_Escape), "←": UInt32(kVK_LeftArrow), "→": UInt32(kVK_RightArrow),
        "↑": UInt32(kVK_UpArrow), "↓": UInt32(kVK_DownArrow),
        "F1": UInt32(kVK_F1), "F2": UInt32(kVK_F2), "F3": UInt32(kVK_F3), "F4": UInt32(kVK_F4),
        "F5": UInt32(kVK_F5), "F6": UInt32(kVK_F6), "F7": UInt32(kVK_F7), "F8": UInt32(kVK_F8),
        "F9": UInt32(kVK_F9), "F10": UInt32(kVK_F10), "F11": UInt32(kVK_F11), "F12": UInt32(kVK_F12),
    ]

    private static let keyCodeToDisplay: [UInt16: String] = {
        var result: [UInt16: String] = [:]
        for (display, code) in displayToKeyCode {
            result[UInt16(code)] = display
        }
        return result
    }()

    static func keyCode(forShortcut shortcut: String) -> UInt32? {
        let key = keyToken(in: shortcut)
        return displayToKeyCode[key] ?? displayToKeyCode[key.uppercased()]
    }

    static func displayName(forKeyCode keyCode: UInt16, fallback: String?) -> String? {
        if let display = keyCodeToDisplay[keyCode] { return display }
        let value = (fallback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value == " " { return "Space" }
        guard !value.isEmpty else { return nil }
        return value.uppercased()
    }

    static func keyToken(in shortcut: String) -> String {
        var value = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["⌘", "⇧", "⌥", "⌃"] {
            value = value.replacingOccurrences(of: marker, with: "")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class HotKeyMonitor {
    private struct HotKeyInstallResult {
        var warnings: [String]
        var registeredCount: Int
        var hasWorkingEventHandler: Bool
    }

    private struct HotKeyRegistrationResult {
        var warning: String?
        var didRegister: Bool
    }

    private var eventHandler: EventHandlerRef?
    private var selectionHotKey: EventHotKeyRef?
    private var inputHotKey: EventHotKeyRef?
    private var ocrHotKey: EventHotKeyRef?
    private var ocrRecognizeHotKey: EventHotKeyRef?
    private var fallbackMonitor: Any?
    var onTranslateSelection: (() -> Void)?
    var onInputTranslate: (() -> Void)?
    var onOCR: (() -> Void)?
    var onOCRRecognize: (() -> Void)?

    @discardableResult
    func start() -> String? {
        stop()
        let result = installCarbonHotKeys()
        var warnings = result.warnings
        let shouldEnableFallback = !result.hasWorkingEventHandler || result.registeredCount < 4
        if shouldEnableFallback {
            fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleFallback(event)
            }
            warnings.append("已启用备用快捷键监听")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "；")
    }

    func stop() {
        if let selectionHotKey { UnregisterEventHotKey(selectionHotKey) }
        if let inputHotKey { UnregisterEventHotKey(inputHotKey) }
        if let ocrHotKey { UnregisterEventHotKey(ocrHotKey) }
        if let ocrRecognizeHotKey { UnregisterEventHotKey(ocrRecognizeHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let fallbackMonitor { NSEvent.removeMonitor(fallbackMonitor) }
        selectionHotKey = nil
        inputHotKey = nil
        ocrHotKey = nil
        ocrRecognizeHotKey = nil
        eventHandler = nil
        fallbackMonitor = nil
    }

    private func installCarbonHotKeys() -> HotKeyInstallResult {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1: monitor.onTranslateSelection?()
                case 2: monitor.onInputTranslate?()
                case 3: monitor.onOCR?()
                case 4: monitor.onOCRRecognize?()
                default: break
                }
            }
            return noErr
        }
        var warnings: [String] = []
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if handlerStatus != noErr {
            warnings.append("系统快捷键监听安装失败：\(handlerStatus)")
        }
        var registeredCount = 0
        for registration in [
            register(name: "划词翻译", shortcut: Preferences.shared.hotkeySelectionTranslate, fallbackKey: UInt32(kVK_ANSI_E), id: 1, ref: &selectionHotKey),
            register(name: "输入翻译", shortcut: Preferences.shared.hotkeyInputTranslate, fallbackKey: UInt32(kVK_ANSI_D), id: 2, ref: &inputHotKey),
            register(name: "截图翻译", shortcut: Preferences.shared.hotkeyOCRTranslate, fallbackKey: UInt32(kVK_ANSI_O), id: 3, ref: &ocrHotKey),
            register(name: "截图 OCR", shortcut: Preferences.shared.hotkeyOCRRecognize, fallbackKey: UInt32(kVK_ANSI_R), id: 4, ref: &ocrRecognizeHotKey),
        ] {
            if registration.didRegister {
                registeredCount += 1
            }
            if let warning = registration.warning {
                warnings.append(warning)
            }
        }
        return HotKeyInstallResult(
            warnings: warnings,
            registeredCount: registeredCount,
            hasWorkingEventHandler: handlerStatus == noErr
        )
    }

    private func register(name: String, shortcut: String, fallbackKey: UInt32, id: UInt32, ref: inout EventHotKeyRef?) -> HotKeyRegistrationResult {
        let parsed = parseShortcut(shortcut)
        let hotKeyID = EventHotKeyID(signature: fourCharCode("POTK"), id: id)
        let status = RegisterEventHotKey(
            parsed.keyCode ?? fallbackKey,
            parsed.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else {
            return HotKeyRegistrationResult(warning: "\(name) 快捷键 \(shortcut) 注册失败：\(status)", didRegister: false)
        }
        if parsed.keyCode == nil {
            return HotKeyRegistrationResult(warning: "\(name) 快捷键 \(shortcut) 不支持，已使用默认按键", didRegister: true)
        }
        return HotKeyRegistrationResult(warning: nil, didRegister: true)
    }

    private func parseShortcut(_ shortcut: String) -> (keyCode: UInt32?, modifiers: UInt32) {
        var modifiers: UInt32 = 0
        if shortcut.contains("⌘") { modifiers |= UInt32(cmdKey) }
        if shortcut.contains("⇧") { modifiers |= UInt32(shiftKey) }
        if shortcut.contains("⌥") { modifiers |= UInt32(optionKey) }
        if shortcut.contains("⌃") { modifiers |= UInt32(controlKey) }
        if modifiers == 0 { modifiers = UInt32(cmdKey | shiftKey) }
        let key = ShortcutKeyMap.keyCode(forShortcut: shortcut)
        return (key, modifiers)
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: UInt32 = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + scalar.value
        }
        return result
    }

    private func handleFallback(_ event: NSEvent) {
        if matches(event, shortcut: Preferences.shared.hotkeySelectionTranslate, fallback: "e") {
            onTranslateSelection?()
        } else if matches(event, shortcut: Preferences.shared.hotkeyInputTranslate, fallback: "d") {
            onInputTranslate?()
        } else if matches(event, shortcut: Preferences.shared.hotkeyOCRTranslate, fallback: "o") {
            onOCR?()
        } else if matches(event, shortcut: Preferences.shared.hotkeyOCRRecognize, fallback: "r") {
            onOCRRecognize?()
        }
    }

    private func matches(_ event: NSEvent, shortcut: String, fallback: String) -> Bool {
        let parsed = parseShortcut(shortcut)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let needCommand = parsed.modifiers & UInt32(cmdKey) != 0
        let needShift = parsed.modifiers & UInt32(shiftKey) != 0
        let needOption = parsed.modifiers & UInt32(optionKey) != 0
        let needControl = parsed.modifiers & UInt32(controlKey) != 0
        guard flags.contains(.command) == needCommand,
              flags.contains(.shift) == needShift,
              flags.contains(.option) == needOption,
              flags.contains(.control) == needControl
        else { return false }
        if let keyCode = parsed.keyCode {
            return event.keyCode == UInt16(keyCode)
        }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let target = ShortcutKeyMap.keyToken(in: shortcut).lowercased()
        return chars == (target.isEmpty ? fallback : target)
    }
}
