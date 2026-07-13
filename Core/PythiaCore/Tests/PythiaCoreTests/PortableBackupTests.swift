import Foundation
import XCTest
@testable import PythiaCore

final class PortableBackupTests: XCTestCase {
    func testPortableBackupRoundTripUsesSharedSchema() throws {
        let record = PythiaHistoryRecord(
            id: "record-1",
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: "en",
            targetLanguage: "zh-CN",
            service: "Local",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: "mac-test"
        )
        let backup = PythiaPortableBackup(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            settings: PythiaPortableSettings(
                sourceLanguage: "en",
                targetLanguage: "zh-CN",
                enabledTranslateServices: ["Local"],
                saveHistory: true,
                themeMode: "system"
            ),
            history: [record]
        )

        let data = try PythiaPortableBackupCodec.encode(backup)
        let decoded = try PythiaPortableBackupCodec.decode(data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded, backup)
        XCTAssertEqual(object["product"] as? String, "Pythia")
        XCTAssertEqual(object["sensitiveFieldsOmitted"] as? Bool, true)
        XCTAssertNil((object["settings"] as? [String: Any])?["webdavPassword"])
    }

    func testDecoderRejectsForeignAndUnsafeBackup() throws {
        let foreign = Data(#"{"schemaVersion":1,"product":"Other","createdAt":"2026-07-13T00:00:00Z","sensitiveFieldsOmitted":true,"settings":{},"history":[]}"#.utf8)
        let unsafe = Data(#"{"schemaVersion":1,"product":"Pythia","createdAt":"2026-07-13T00:00:00Z","sensitiveFieldsOmitted":false,"settings":{},"history":[]}"#.utf8)

        XCTAssertThrowsError(try PythiaPortableBackupCodec.decode(foreign))
        XCTAssertThrowsError(try PythiaPortableBackupCodec.decode(unsafe))
    }
}
