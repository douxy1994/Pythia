import AppKit
import Foundation

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()
    private var selectionReadDepth = 0
    private var timer: Timer?
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    var onText: ((String) -> Void)?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // Selection capture temporarily copies and restores the user's clipboard.
    // Neither intermediate value should trigger clipboard auto-translation.
    func beginSelectionRead() {
        selectionReadDepth += 1
    }

    func endSelectionRead() {
        selectionReadDepth = max(0, selectionReadDepth - 1)
        if selectionReadDepth == 0 {
            lastChangeCount = pasteboard.changeCount
        }
    }

    func tick() {
        guard selectionReadDepth == 0 else { return }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        onText?(text)
    }
}
