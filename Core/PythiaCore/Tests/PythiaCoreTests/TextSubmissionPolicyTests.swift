import XCTest
@testable import PythiaCore

final class TextSubmissionPolicyTests: XCTestCase {
    func testReturnDoesNotSubmitWhileInputMethodHasMarkedText() {
        XCTAssertFalse(TextSubmissionPolicy.shouldSubmit(
            isReturn: true,
            hasMarkedText: true,
            hasShift: false,
            hasOption: false,
            hasCommand: false
        ))
    }

    func testPlainReturnSubmitsAfterCompositionEnds() {
        XCTAssertTrue(TextSubmissionPolicy.shouldSubmit(
            isReturn: true,
            hasMarkedText: false,
            hasShift: false,
            hasOption: false,
            hasCommand: false
        ))
    }

    func testReturnDoesNotSubmitWhenInputMethodConsumesEvent() {
        XCTAssertFalse(TextSubmissionPolicy.shouldSubmit(
            isReturn: true,
            hasMarkedText: false,
            inputMethodHandledEvent: true,
            hasShift: false,
            hasOption: false,
            hasCommand: false
        ))
    }

    func testModifiedReturnDoesNotSubmit() {
        XCTAssertFalse(TextSubmissionPolicy.shouldSubmit(
            isReturn: true,
            hasMarkedText: false,
            hasShift: true,
            hasOption: false,
            hasCommand: false
        ))
    }
}
