import XCTest
@testable import PythiaCore

final class ReleaseVersionPolicyTests: XCTestCase {
    func testRejectsLegacyReleaseWithoutPythiaIdentity() {
        XCTAssertNil(PythiaReleaseVersionPolicy.version(tagName: "3.0.8", releaseName: "3.0.8"))
        XCTAssertNil(PythiaReleaseVersionPolicy.version(tagName: "v3.0.8", releaseName: "Pot 3.0.8"))
    }

    func testAcceptsPythiaIdentityFromTagOrReleaseName() {
        XCTAssertEqual(
            PythiaReleaseVersionPolicy.version(tagName: "pythia-v1.0.1", releaseName: "1.0.1"),
            "1.0.1"
        )
        XCTAssertEqual(
            PythiaReleaseVersionPolicy.version(tagName: "v1.0.2", releaseName: "Pythia 1.0.2"),
            "1.0.2"
        )
    }
}
