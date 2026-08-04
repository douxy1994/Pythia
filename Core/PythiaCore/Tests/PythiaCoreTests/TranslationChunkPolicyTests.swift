import XCTest
@testable import PythiaCore

final class TranslationChunkPolicyTests: XCTestCase {
    func testShortTextRemainsOneRequest() {
        let text = String(repeating: "a", count: 1_800)
        let chunks = TranslationChunkPolicy.chunks(for: text)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].original, text)
    }

    func testLongTextReassemblesExactlyAndPrefersParagraphs() {
        let text = String(repeating: "第一段。", count: 450) + "\n\n" + String(repeating: "Second paragraph. ", count: 180)
        let chunks = TranslationChunkPolicy.chunks(for: text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.map(\.original).joined(), text)
        XCTAssertTrue(chunks.dropLast().contains { $0.original.hasSuffix("\n") || $0.original.hasSuffix("。") || $0.original.hasSuffix(". ") })
    }

    func testNumericTokensNeverCrossBoundaries() {
        let tokens = ["1.24", "1,240.50", "1\u{202F}240,50", "2026-08-04", "12:30", "v1.2.1", "-1.24", "6.02e-23"]
        for token in tokens {
            let prefix = String(repeating: "x", count: 19)
            let text = prefix + token + String(repeating: "y", count: 24)
            let chunks = TranslationChunkPolicy.chunks(for: text, maxCharacters: 20)
            XCTAssertEqual(chunks.map(\.original).joined(), text, token)
            XCTAssertTrue(chunks.contains { $0.original.contains(token) }, "split numeric token: \(token) in \(chunks.map(\.original))")
        }
    }

    func testExtendedGraphemeClustersRemainWhole() {
        let cluster = "👨‍👩‍👧‍👦e\u{301}🇸🇬"
        let text = String(repeating: "界", count: 17) + cluster + String(repeating: "文", count: 20)
        let chunks = TranslationChunkPolicy.chunks(for: text, maxCharacters: 18)
        XCTAssertEqual(chunks.map(\.original).joined(), text)
        XCTAssertTrue(chunks.contains { $0.original.contains(cluster.first!) || $0.original.contains("e\u{301}") })
        XCTAssertFalse(chunks.contains { $0.original.unicodeScalars.last?.properties.isJoinControl == true })
    }

    func testWhitespaceEnvelopePreservesBlankLinesAndLists() {
        let text = "\n\n  - item one\n  - item two\n\n"
        let chunk = TranslationChunkPolicy.chunks(for: text, maxCharacters: 100)[0]
        XCTAssertEqual(chunk.leadingWhitespace, "\n\n  ")
        XCTAssertEqual(chunk.body, "- item one\n  - item two")
        XCTAssertEqual(chunk.trailingWhitespace, "\n\n")
        XCTAssertEqual(chunk.leadingWhitespace + chunk.body + chunk.trailingWhitespace, text)
    }

    func testRetryableStatusClassification() {
        for status in [408, 409, 425, 429, 500, 503, 599] {
            XCTAssertTrue(TranslationRetryPolicy.isRetryableHTTPStatus(status), "\(status)")
        }
        for status in [400, 401, 403, 404, 422] {
            XCTAssertFalse(TranslationRetryPolicy.isRetryableHTTPStatus(status), "\(status)")
        }
    }

    func testRetryAfterSecondsAndHTTPDateAreBounded() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(TranslationRetryPolicy.retryDelay(retryAfter: "0", retryNumber: 1, now: now), 0.75)
        XCTAssertEqual(TranslationRetryPolicy.retryDelay(retryAfter: "999", retryNumber: 1, now: now), 60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        let date = formatter.string(from: now.addingTimeInterval(30))
        XCTAssertEqual(TranslationRetryPolicy.retryDelay(retryAfter: date, retryNumber: 1, now: now), 30, accuracy: 0.01)
        XCTAssertEqual(TranslationRetryPolicy.retryDelay(retryAfter: nil, retryNumber: 1, now: now), 0.75)
        XCTAssertEqual(TranslationRetryPolicy.retryDelay(retryAfter: nil, retryNumber: 2, now: now), 2)
    }
}
