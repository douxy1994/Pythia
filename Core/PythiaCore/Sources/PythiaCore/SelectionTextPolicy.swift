import Foundation

/// Resolve two representations of the same fresh selection without guessing
/// paragraph boundaries from punctuation or changing the selected words.
public enum SelectionTextPolicy {
    public static func preferredText(accessibilityText: String?, copiedText: String) -> String {
        let accessibility = accessibilityText ?? ""
        guard !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return accessibility
        }
        // A fresh copy is authoritative (AX can also truncate Word selections).
        // Retain AX/RTF instead only if it has the same words and more breaks.
        if visibleContent(accessibility) == visibleContent(copiedText),
           accessibility.filter(\.isNewline).count > copiedText.filter(\.isNewline).count {
            return accessibility
        }
        return copiedText
    }

    private static func visibleContent(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }
}
