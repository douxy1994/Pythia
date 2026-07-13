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

    func testMixedChineseAndEnglishKeepsSelectedTarget() {
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "今天 weather 很好", selectedTarget: "en"),
            "en"
        )
        XCTAssertEqual(
            AutomaticLanguagePolicy.targetLanguage(for: "今天 weather 很好", selectedTarget: "zh-CN"),
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
