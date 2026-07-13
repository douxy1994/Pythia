import Foundation
import XCTest
@testable import PythiaCore

final class NodeRuntimeResolverTests: XCTestCase {
    func testResolvesExecutableFromPathFirst() throws {
        let root = try makeTemporaryDirectory()
        let pathDirectory = root.appendingPathComponent("custom-bin", isDirectory: true)
        let node = pathDirectory.appendingPathComponent("node")
        try makeExecutable(at: node)

        let resolved = NodeRuntimeResolver.resolve(
            environment: ["PATH": pathDirectory.path],
            homeDirectory: root,
            standardCandidates: []
        )

        XCTAssertEqual(resolved, node)
    }

    func testResolvesNVMDefaultMajorVersionWithoutShellInitialization() throws {
        let home = try makeTemporaryDirectory()
        let nvm = home.appendingPathComponent(".nvm", isDirectory: true)
        let alias = nvm.appendingPathComponent("alias/default")
        try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("22\n".utf8).write(to: alias)
        let older = nvm.appendingPathComponent("versions/node/v22.1.0/bin/node")
        let expected = nvm.appendingPathComponent("versions/node/v22.22.0/bin/node")
        try makeExecutable(at: older)
        try makeExecutable(at: expected)

        let resolved = NodeRuntimeResolver.resolve(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: home,
            standardCandidates: []
        )

        XCTAssertEqual(resolved, expected)
    }

    func testFallsBackToNewestInstalledNVMVersion() throws {
        let home = try makeTemporaryDirectory()
        let nvm = home.appendingPathComponent(".nvm", isDirectory: true)
        let older = nvm.appendingPathComponent("versions/node/v20.19.0/bin/node")
        let expected = nvm.appendingPathComponent("versions/node/v24.1.0/bin/node")
        try makeExecutable(at: older)
        try makeExecutable(at: expected)

        let resolved = NodeRuntimeResolver.resolve(
            environment: [:],
            homeDirectory: home,
            standardCandidates: []
        )

        XCTAssertEqual(resolved, expected)
    }

    func testReturnsNilWhenNoRuntimeExists() throws {
        let home = try makeTemporaryDirectory()

        let resolved = NodeRuntimeResolver.resolve(
            environment: ["PATH": "/missing"],
            homeDirectory: home,
            standardCandidates: []
        )

        XCTAssertNil(resolved)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PythiaCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
