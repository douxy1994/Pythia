import XCTest
@testable import PythiaCore

final class HistorySyncTests: XCTestCase {
    func testRemoteNewRecordIsAdded() {
        let local = [record(id: "1", text: "hello", updatedAt: 10)]
        let remote = [record(id: "2", text: "world", updatedAt: 20)]

        let result = PythiaHistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(result.merged.map(\.id), ["2", "1"])
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testNewerUpdateWinsForSameRecord() {
        let local = [record(id: "1", text: "old", updatedAt: 10)]
        let remote = [record(id: "1", text: "new", updatedAt: 20)]

        let result = PythiaHistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(result.merged.first?.sourceText, "new")
        XCTAssertEqual(result.merged.first?.syncStatus, .synced)
    }

    func testDeletionWinsOverNewerNonDeletedRecord() {
        let local = [record(id: "1", text: "deleted", updatedAt: 10, deletedAt: 11, status: .pendingDelete)]
        let remote = [record(id: "1", text: "remote edit", updatedAt: 20)]

        let result = PythiaHistoryMerger.merge(local: local, remote: remote)

        XCTAssertNotNil(result.merged.first?.deletedAt)
        XCTAssertEqual(result.merged.first?.syncStatus, .pendingDelete)
    }

    func testEqualTimestampDifferentContentReportsConflict() {
        let local = [record(id: "1", text: "local", updatedAt: 10)]
        let remote = [record(id: "1", text: "remote", updatedAt: 10)]

        let result = PythiaHistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts.first?.syncStatus, .conflict)
    }

    private func record(
        id: String,
        text: String,
        updatedAt: TimeInterval,
        deletedAt: TimeInterval? = nil,
        status: PythiaSyncStatus = .local
    ) -> PythiaHistoryRecord {
        PythiaHistoryRecord(
            id: id,
            sourceText: text,
            translatedText: "translated \(text)",
            sourceLanguage: "auto",
            targetLanguage: "zh-CN",
            service: "Google",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            deviceId: "test-device",
            syncStatus: status,
            deletedAt: deletedAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}
