import Foundation

public enum AutomaticLanguagePolicy {
    /// Picks the target language by dominant script: compare the number of
    /// Chinese characters against the number of English *words* (maximal
    /// runs of ASCII letters). A Chinese sentence with a few embedded
    /// English terms or abbreviations is therefore treated as Chinese and
    /// translated to English, instead of falling back to the selected
    /// target as soon as a single ASCII letter appears.
    public static func targetLanguage(for text: String, selectedTarget: String) -> String {
        let target = selectedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTarget = target.isEmpty ? "zh-CN" : target
        var chineseCount = 0
        var englishWordCount = 0
        var inEnglishWord = false

        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x4E00...0x9FFF).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0x20000...0x2A6DF).contains(value) {
                chineseCount += 1
                inEnglishWord = false
            } else if (0x0041...0x005A).contains(value)
                || (0x0061...0x007A).contains(value) {
                if !inEnglishWord {
                    englishWordCount += 1
                    inEnglishWord = true
                }
            } else {
                inEnglishWord = false
            }
        }

        if chineseCount > 0 && englishWordCount == 0 { return "en" }
        if englishWordCount > 0 && chineseCount == 0 { return "zh-CN" }
        if chineseCount > englishWordCount { return "en" }
        if englishWordCount > chineseCount { return "zh-CN" }
        return fallbackTarget
    }
}
