import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class SelectionReader {
    static let shared = SelectionReader()

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    func selectedText(targetApplication: NSRunningApplication? = nil, completion: @escaping (String) -> Void) {
        guard accessibilityTrusted() else {
            completion("")
            return
        }

        let target = validExternalApplication(targetApplication)
        let read: () -> Void = { [weak self] in
            guard let self else { completion(""); return }
            if let text = self.readAccessibilitySelection(targetApplication: target), !text.isEmpty {
                completion(text)
                return
            }
            self.readClipboardFallback(targetApplication: target, completion: completion)
        }

        // When the user clicks Pythia's own "划词" button, Pythia becomes the
        // active app before this method runs. Reactivate the app that owns the
        // selected text, then read/copy from that app.
        if let target, !target.isActive {
            activate(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: read)
        } else {
            read()
        }
    }

    func accessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibilityPermission() -> Bool {
        return accessibilityTrusted(prompt: true)
    }

    private func readAccessibilitySelection(targetApplication: NSRunningApplication?) -> String? {
        guard accessibilityTrusted(prompt: false) else { return nil }

        if let target = validExternalApplication(targetApplication) {
            let appElement = AXUIElementCreateApplication(target.processIdentifier)
            var focused: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let element = focused {
                return selectedText(from: element as! AXUIElement)
            }
            return selectedText(from: appElement)
        }

        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success else {
            return nil
        }
        guard let element = focused else { return nil }
        return selectedText(from: element as! AXUIElement)
    }

    private func selectedText(from axElement: AXUIElement) -> String? {
        // Path 1: kAXSelectedTextAttribute (works for most native text views).
        var selected: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
           let text = selected as? String, !text.isEmpty {
            return text
        }

        // Path 2: some apps (e.g. browsers) expose only the selected text range;
        // fetch the string for that range.
        var rangeValue: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let range = rangeValue {
            var rangeStruct = CFRange(location: 0, length: 0)
            if AXValueGetValue(range as! AXValue, .cfRange, &rangeStruct), rangeStruct.length > 0 {
                let axValue = AXValueCreate(.cfRange, &rangeStruct)
                var string: AnyObject?
                if let axValue,
                   AXUIElementCopyParameterizedAttributeValue(axElement, "AXStringForRange" as CFString, axValue, &string) == .success,
                   let text = string as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func readClipboardFallback(targetApplication: NSRunningApplication?, completion: @escaping (String) -> Void) {
        // Mirror the legacy pot macOS strategy: record NSPasteboard.changeCount
        // before/after sending ⌘C; only treat the clipboard as a real selection
        // if it actually changed. Otherwise ⌘C copied nothing (no selection),
        // and we must NOT return stale clipboard contents. Save and restore the
        // original clipboard.
        if let target = validExternalApplication(targetApplication), !target.isActive {
            activate(target)
        }
        let pasteboard = NSPasteboard.general
        let original = capturePasteboard(pasteboard)
        let changeBefore = pasteboard.changeCount
        let copyAndWait: (@escaping (Bool) -> Void) -> Void = { [weak self] done in
            guard let self else { done(false); return }
            self.sendCopyShortcut()
            self.waitForClipboardChange(from: changeBefore, remainingChecks: 16, completion: done)
        }
        copyAndWait { [weak self] changed in
            guard let self else { completion(""); return }
            if changed {
                let result = pasteboard.string(forType: .string) ?? ""
                self.restorePasteboard(original, to: pasteboard)
                completion(result)
                return
            }
            copyAndWait { [weak self] changedAfterRetry in
                guard let self else { completion(""); return }
                let result = changedAfterRetry ? (pasteboard.string(forType: .string) ?? "") : ""
                self.restorePasteboard(original, to: pasteboard)
                completion(result)
            }
        }
    }

    private func waitForClipboardChange(from changeCount: Int, remainingChecks: Int, completion: @escaping (Bool) -> Void) {
        if NSPasteboard.general.changeCount != changeCount {
            completion(true)
            return
        }
        guard remainingChecks > 0 else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.waitForClipboardChange(from: changeCount, remainingChecks: remainingChecks - 1, completion: completion)
        }
    }

    private func capturePasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
        } ?? []
        return PasteboardSnapshot(items: items)
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = snapshot.items.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }

    private func sendCopyShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func validExternalApplication(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app,
              !app.isTerminated,
              app.processIdentifier != pid_t(ProcessInfo.processInfo.processIdentifier) else {
            return nil
        }
        return app
    }
}
