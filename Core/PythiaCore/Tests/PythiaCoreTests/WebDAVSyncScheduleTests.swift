import XCTest
@testable import PythiaCore

final class WebDAVSyncScheduleTests: XCTestCase {
    func testEveryUnitConvertsToExactSeconds() {
        XCTAssertEqual(PythiaWebDAVSyncSchedule(value: 15, unit: .minute)?.seconds, 900)
        XCTAssertEqual(PythiaWebDAVSyncSchedule(value: 2, unit: .hour)?.seconds, 7_200)
        XCTAssertEqual(PythiaWebDAVSyncSchedule(value: 3, unit: .day)?.seconds, 259_200)
        XCTAssertEqual(PythiaWebDAVSyncSchedule(value: 2, unit: .week)?.seconds, 1_209_600)
    }

    func testLegacyMinutesMigrateWithoutChangingDuration() {
        XCTAssertEqual(PythiaWebDAVSyncSchedule.fromLegacyMinutes(30), PythiaWebDAVSyncSchedule(value: 30, unit: .minute))
        XCTAssertEqual(PythiaWebDAVSyncSchedule.fromLegacyMinutes(60), PythiaWebDAVSyncSchedule(value: 1, unit: .hour))
        XCTAssertEqual(PythiaWebDAVSyncSchedule.fromLegacyMinutes(4_320), PythiaWebDAVSyncSchedule(value: 3, unit: .day))
        XCTAssertEqual(PythiaWebDAVSyncSchedule.fromLegacyMinutes(10_080), PythiaWebDAVSyncSchedule(value: 1, unit: .week))
    }

    func testRejectsZeroAndIntervalsLongerThan366Days() {
        XCTAssertNil(PythiaWebDAVSyncSchedule(value: 0, unit: .minute))
        XCTAssertNil(PythiaWebDAVSyncSchedule(value: 53, unit: .week))
    }
}
