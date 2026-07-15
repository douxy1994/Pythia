import XCTest
@testable import PythiaCore

final class PluginPackagePolicyTests: XCTestCase {
    func testAcceptsSupportedPluginPackagesRegardlessOfFileNameCase() {
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "plugin.google.potext"))
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "阿里云翻译.potext"))
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "custom-translator.POTEXT"))
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "echo-translator.pythia"))
        XCTAssertTrue(PluginPackagePolicy.accepts(fileName: "OPENAI.PYTHIA"))
    }

    func testRejectsFilesWithoutSupportedExtension() {
        XCTAssertFalse(PluginPackagePolicy.accepts(fileName: "plugin.google.zip"))
        XCTAssertFalse(PluginPackagePolicy.accepts(fileName: "plugin.google"))
        XCTAssertFalse(PluginPackagePolicy.accepts(fileName: "potext"))
    }

    func testValidTranslatorManifest() throws {
        let manifest = makeManifest()
        XCTAssertNoThrow(try PluginPackagePolicy.validate(manifest, platform: "macos"))
        XCTAssertNoThrow(try PluginPackagePolicy.validate(manifest, platform: "windows"))
    }

    func testRejectsUnsafeEntryAndUnknownPermission() {
        XCTAssertThrowsError(
            try PluginPackagePolicy.validate(makeManifest(entry: "../main.js"), platform: "macos")
        ) { error in
            XCTAssertEqual(error as? PythiaPluginValidationError, .unsafeEntry("../main.js"))
        }
        XCTAssertThrowsError(
            try PluginPackagePolicy.validate(makeManifest(permissions: ["filesystem"]), platform: "macos")
        ) { error in
            XCTAssertEqual(error as? PythiaPluginValidationError, .invalidPermission("filesystem"))
        }
    }

    func testRejectsManifestWithoutCurrentPlatformOrTranslateCapability() {
        XCTAssertThrowsError(
            try PluginPackagePolicy.validate(makeManifest(platforms: ["windows"]), platform: "macos")
        ) { error in
            XCTAssertEqual(error as? PythiaPluginValidationError, .unsupportedPlatform("macos"))
        }
        XCTAssertThrowsError(
            try PluginPackagePolicy.validate(makeManifest(capabilities: []), platform: "macos")
        ) { error in
            XCTAssertEqual(error as? PythiaPluginValidationError, .missingCapability("translate"))
        }
    }

    func testRejectsUnknownConfigurationTypeAndSecretDefault() {
        XCTAssertThrowsError(
            try PluginPackagePolicy.validate(
                makeManifest(configuration: [
                    PythiaPluginConfigurationField(key: "mode", label: "Mode", type: "number")
                ]),
                platform: "macos"
            )
        ) { error in
            XCTAssertEqual(error as? PythiaPluginValidationError, .invalidConfigurationType("number"))
        }
        XCTAssertThrowsError(
            try PluginPackagePolicy.validate(
                makeManifest(configuration: [
                    PythiaPluginConfigurationField(
                        key: "apiKey",
                        label: "API Key",
                        type: "secret",
                        defaultValue: "do-not-store"
                    )
                ]),
                platform: "macos"
            )
        ) { error in
            XCTAssertEqual(error as? PythiaPluginValidationError, .secretDefaultValue("apiKey"))
        }
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

    func testConvertsPotextTranslatorToPythiaManifestAndAdapter() throws {
        let info: [String: Any] = [
            "plugin_type": "translate",
            "id": "plugin.example.echo",
            "display": "Echo",
            "homepage": "https://github.com/example/echo",
            "needs": [
                ["key": "apiKey", "display": "API Key", "type": "input"],
                ["key": "model", "display": "Model", "type": "select", "default": "demo", "options": ["demo": "Demo"]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: info)
        let result = try PotextPluginConverter.convert(
            infoData: data,
            mainJavaScript: "async function translate(text) { return text; }",
            fallbackIdentifier: "fallback"
        )
        XCTAssertEqual(result.manifest.id, "plugin.example.echo")
        XCTAssertEqual(result.manifest.author, "example")
        XCTAssertEqual(result.manifest.configuration.first?.type, "secret")
        XCTAssertEqual(result.manifest.configuration.last?.type, "select")
        XCTAssertEqual(result.manifest.version, "1.0.0")
        XCTAssertTrue(result.mainJavaScript.contains("module.exports.translate"))
        XCTAssertTrue(result.mainJavaScript.contains("__pythiaLegacyTranslate"))
    }

    func testSecretInferenceDoesNotTreatTokenLimitsAsCredentials() throws {
        XCTAssertTrue(PythiaPluginSecretPolicy.isLikelySecretKey("apiKey"))
        XCTAssertTrue(PythiaPluginSecretPolicy.isLikelySecretKey("access_token"))
        XCTAssertFalse(PythiaPluginSecretPolicy.isLikelySecretKey("max_tokens"))

        let data = try JSONSerialization.data(withJSONObject: [
            "plugin_type": "translate",
            "id": "plugin.example.config",
            "display": "Config",
            "needs": [
                ["key": "apiKey", "display": "API Key", "type": "input"],
                ["key": "max_tokens", "display": "Max tokens", "type": "input", "default": "4096"],
            ],
        ])
        let result = try PotextPluginConverter.convert(
            infoData: data,
            mainJavaScript: "async function translate(text) { return text; }",
            fallbackIdentifier: "fallback"
        )
        XCTAssertEqual(result.manifest.configuration.map(\.type), ["secret", "text"])
    }

    func testConverterOnlyAddsNetworkPermissionWhenLegacySourceUsesFetch() throws {
        let info = try JSONSerialization.data(withJSONObject: [
            "plugin_type": "translate",
            "id": "plugin.example.echo",
            "display": "Echo",
            "needs": [],
        ])
        let local = try PotextPluginConverter.convert(
            infoData: info,
            mainJavaScript: "async function translate(text) { return text; }",
            fallbackIdentifier: "fallback"
        )
        XCTAssertEqual(local.manifest.permissions, [])

        let network = try PotextPluginConverter.convert(
            infoData: info,
            mainJavaScript: "async function translate(text, from, to, options) { return options.utils.tauriFetch('https://example.com'); }",
            fallbackIdentifier: "fallback"
        )
        XCTAssertEqual(network.manifest.permissions, ["network"])
    }

    private func makeManifest(
        entry: String = "main.js",
        platforms: [String] = ["macos", "windows"],
        permissions: [String] = ["network"],
        capabilities: [String] = ["translate"],
        configuration: [PythiaPluginConfigurationField] = [
            PythiaPluginConfigurationField(key: "apiKey", label: "API Key", type: "secret")
        ]
    ) -> PythiaPluginManifest {
        PythiaPluginManifest(
            schemaVersion: "1.0",
            id: "com.example.echo",
            name: "Echo Translator",
            version: "1.0.0",
            description: "Returns the input text.",
            author: "Pythia",
            type: "translator",
            entry: entry,
            minimumPythiaVersion: "1.0.0",
            supportedPlatforms: platforms,
            permissions: permissions,
            configuration: configuration,
            capabilities: capabilities
        )
    }
}
