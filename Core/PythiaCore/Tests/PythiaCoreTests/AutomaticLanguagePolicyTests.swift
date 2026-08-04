import XCTest
@testable import PythiaCore

final class AutomaticLanguagePolicyTests: XCTestCase {
    func testPureChineseDefaultsToEnglish() {
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "今天天气很好。", selectedTarget: "zh-CN"),
            "en"
        )
    }

    func testPureEnglishDefaultsToSimplifiedChinese() {
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "The weather is good today.", selectedTarget: "en"),
            "zh-CN"
        )
    }

    func testChineseDominantMixedTextDefaultsToEnglish() {
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "今天 weather 很好", selectedTarget: "zh-CN"),
            "en"
        )
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "把 API 返回的 token 写入 UserDefaults 缓存", selectedTarget: "zh-CN"),
            "en"
        )
    }

    func testEnglishDominantMixedTextDefaultsToSimplifiedChinese() {
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "please translate 中文 for me", selectedTarget: "en"),
            "zh-CN"
        )
    }

    func testEvenlyMixedTextKeepsSelectedTarget() {
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "你好 hello world", selectedTarget: "en"),
            "en"
        )
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "你好 hello world", selectedTarget: "zh-CN"),
            "zh-CN"
        )
    }

    func testTextWithoutChineseOrEnglishKeepsSelectedTarget() {
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "12345", selectedTarget: "ja"),
            "ja"
        )
    }
}
