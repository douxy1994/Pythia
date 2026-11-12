import XCTest
@testable import PythiaCore

final class SelectionTextPolicyTests: XCTestCase {
    func testCopyRestoresAllParagraphsAfterPartialAXFlattening() {
        let copied = "Title\n\nFirst paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let ax = "Title\n\nFirst paragraph. Second paragraph. Third paragraph."
        let selected = SelectionTextPolicy.preferredText(accessibilityText: ax, copiedText: copied)
        XCTAssertEqual(selected, copied)
        let chunks = TranslationChunkPolicy.linePreservingChunks(for: selected)
        XCTAssertEqual(chunks.filter { !$0.body.isEmpty }.count, 4)
        XCTAssertEqual(TranslationChunkPolicy.reassemble(chunks, translations: chunks.map { $0.body.uppercased() }), copied.uppercased())
    }

    func testCopyRestoresCompletelyFlattenedAXSelection() {
        let copied = "One\r\n\r\n  Two\u{2028}Three\u{2029}四"
        XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: "One Two Three 四", copiedText: copied), copied)
    }

    func testMoreStructuredAXIsRetainedForIdenticalContent() {
        let ax = "One\n\nTwo\n\nThree"
        XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: ax, copiedText: "One Two Three"), ax)
    }

    func testCopyFailureFallsBackWithoutLosingAXContent() {
        for copy in ["", " \n\t"] {
            XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: "One\nTwo", copiedText: copy), "One\nTwo")
        }
        XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: nil, copiedText: ""), "")
        XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: nil, copiedText: "One\nTwo"), "One\nTwo")
    }

    func testFreshCopyWinsOverTruncatedOrDifferentAXText() {
        XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: "One", copiedText: "One\nTwo"), "One\nTwo")
        XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: "Old\n\nUnrelated\nText", copiedText: "New selection"), "New selection")
    }

    func testDoesNotInventParagraphsFromPunctuation() {
        let text = "One sentence. Another sentence! 1.24, v1.2.5."
        XCTAssertEqual(SelectionTextPolicy.preferredText(accessibilityText: text, copiedText: text), text)
    }
}
