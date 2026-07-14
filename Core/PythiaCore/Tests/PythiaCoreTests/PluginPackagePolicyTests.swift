import XCTest
@testable import PythiaCore

final class PluginPackagePolicyTests: XCTestCase {
    func testAcceptsAnyPotextFileName() {
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "plugin.google.potext"))
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "阿里云翻译.potext"))
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "custom-translator.POTEXT"))
    }

    func testRejectsFilesWithoutPotextExtension() {
        XCTAssertFalse(PluginPackagePolicy.accepts(fileName: "plugin.google.zip"))
        XCTAssertFalse(PluginPackagePolicy.accepts(fileName: "plugin.google"))
        XCTAssertFalse(PluginPackagePolicy.accepts(fileName: "potext"))
    }

    func testDisplayNameDoesNotAppendLegacyPluginType() {
        XCTAssertEqual(
            PluginPackagePolicy.displayName(
                alias: nil,
                declaredDisplay: "阿里云翻译",
                declaredName: "aliyun",
                fallback: "custom-file"
            ),
            "阿里云翻译"
        )
        XCTAssertEqual(
            PluginPackagePolicy.displayName(
                alias: "我的翻译服务",
                declaredDisplay: "阿里云翻译",
                declaredName: "aliyun",
                fallback: "custom-file"
            ),
            "我的翻译服务"
        )
    }
}
