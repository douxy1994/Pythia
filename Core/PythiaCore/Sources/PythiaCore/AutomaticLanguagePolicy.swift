import Foundation

public enum AutomaticLanguagePolicy {
    public static func targetLanguage(for text: String, selectedTarget: String) -> String {
        let target = selectedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTarget = target.isEmpty ? "zh-CN" : target
        var hasChinese = false
        var hasEnglish = false

        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x4E00...0x9FFF).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0x20000...0x2A6DF).contains(value) {
                hasChinese = true
            } else if (0x0041...0x005A).contains(value)
                || (0x0061...0x007A).contains(value) {
                hasEnglish = true
            }
        }

        if hasChinese && !hasEnglish { return "en" }
        if hasEnglish && !hasChinese { return "zh-CN" }
        return fallbackTarget
    }
}
