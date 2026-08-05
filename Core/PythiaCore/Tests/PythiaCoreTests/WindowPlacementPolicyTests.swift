import Foundation
import XCTest
@testable import PythiaCore

final class WindowPlacementPolicyTests: XCTestCase {
    func testCompactWindowKeepsPreferredSizeOnRetinaWorkspace() {
        let fitted = PythiaWindowPlacementPolicy.fittedSize(
            preferred: CGSize(width: 680, height: 430),
            minimum: CGSize(width: 480, height: 280),
            visibleFrame: CGRect(x: 0, y: 62, width: 1512, height: 887)
        )
        XCTAssertEqual(fitted, CGSize(width: 680, height: 430))
    }

    func testCompactWindowShrinksBelowNominalMinimumWhenDisplayIsSmaller() {
        let fitted = PythiaWindowPlacementPolicy.fittedSize(
            preferred: CGSize(width: 680, height: 430),
            minimum: CGSize(width: 480, height: 280),
            visibleFrame: CGRect(x: 0, y: 0, width: 460, height: 260)
        )
        XCTAssertEqual(fitted, CGSize(width: 460, height: 260))
    }

    func testFrameClampsIntoNegativeOriginSecondaryDisplay() {
        let visible = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        let frame = PythiaWindowPlacementPolicy.clampedFrame(
            CGRect(x: -2050, y: -80, width: 680, height: 430),
            minimum: CGSize(width: 480, height: 280),
            visibleFrame: visible
        )
        XCTAssertEqual(frame.origin, CGPoint(x: -1920, y: 25))
        XCTAssertLessThanOrEqual(frame.origin.x + frame.size.width, visible.origin.x + visible.size.width)
        XCTAssertLessThanOrEqual(frame.origin.y + frame.size.height, visible.origin.y + visible.size.height)
    }

    func testBestScreenUsesLargestIntersectionAfterCrossScreenMove() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        ]
        XCTAssertEqual(
            PythiaWindowPlacementPolicy.bestScreenIndex(
                for: CGRect(x: -1400, y: 200, width: 900, height: 600),
                screens: screens
            ),
            1
        )
    }
}
