import Foundation

public enum NodeRuntimeResolver {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        preferredCandidates: [URL] = [],
        standardCandidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node"),
            URL(fileURLWithPath: "/usr/bin/node"),
        ],
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []

        candidates.append(contentsOf: preferredCandidates)

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path
                .split(separator: ":", omittingEmptySubsequences: true)
                .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("node") })
        }
        candidates.append(contentsOf: standardCandidates)

        let nvmRoot = homeDirectory.appendingPathComponent(".nvm", isDirectory: true)
        let installedVersions = installedNVMVersions(at: nvmRoot, fileManager: fileManager)
        if let defaultAlias = readNVMDefaultAlias(at: nvmRoot),
           let defaultVersion = installedVersions.first(where: { version($0.lastPathComponent, matches: defaultAlias) }) {
            candidates.append(defaultVersion.appendingPathComponent("bin/node"))
        }
        candidates.append(contentsOf: installedVersions.map { $0.appendingPathComponent("bin/node") })
        candidates.append(homeDirectory.appendingPathComponent(".volta/bin/node"))

        var visited = Set<String>()
        return candidates.first { candidate in
            let path = candidate.standardizedFileURL.path
            guard visited.insert(path).inserted else { return false }
            return fileManager.isExecutableFile(atPath: path)
        }?.standardizedFileURL
    }

    private static func readNVMDefaultAlias(at nvmRoot: URL) -> String? {
        let aliasURL = nvmRoot.appendingPathComponent("alias/default")
        guard let value = try? String(contentsOf: aliasURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static func installedNVMVersions(at nvmRoot: URL, fileManager: FileManager) -> [URL] {
        let versionsRoot = nvmRoot.appendingPathComponent("versions/node", isDirectory: true)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: versionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.sorted { isNewerVersion($0.lastPathComponent, than: $1.lastPathComponent) }
    }

    private static func version(_ installed: String, matches alias: String) -> Bool {
        let normalizedInstalled = installed.trimmingPrefix("v")
        let normalizedAlias = alias.trimmingPrefix("v")
        guard normalizedAlias.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
        return normalizedInstalled == normalizedAlias || normalizedInstalled.hasPrefix(normalizedAlias + ".")
    }

    private static func semanticVersion(_ value: String) -> [Int] {
        value.trimmingPrefix("v").split(separator: ".").map { Int($0) ?? 0 }
    }

    private static func isNewerVersion(_ lhs: String, than rhs: String) -> Bool {
        let left = semanticVersion(lhs)
        let right = semanticVersion(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart != rightPart { return leftPart > rightPart }
        }
        return false
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        first == prefix ? String(dropFirst()) : self
    }
}
