import AppKit
import Foundation

struct PythiaUpdateInfo {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseURL: URL?
    let isNewer: Bool
    let notes: String
    let assetURL: URL?
    let assetName: String?
    let assetSize: Int64
}

final class PythiaUpdateChecker {
    static let shared = PythiaUpdateChecker()

    private let releasesURL: URL

    private init() {
#if DEBUG
        // Production stays pinned to GitHub, while Debug builds can exercise
        // the full startup-check -> title button -> signed-DMG install flow
        // against a deterministic local fixture.
        if let override = ProcessInfo.processInfo.environment["PYTHIA_UPDATE_RELEASES_URL"],
           let url = URL(string: override) {
            releasesURL = url
            return
        }
#endif
        releasesURL = URL(string: "https://api.github.com/repos/douxy1994/Pythia/releases?per_page=20")!
    }

    func check(completion: @escaping (Result<PythiaUpdateInfo, Error>) -> Void) {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pythia", forHTTPHeaderField: "User-Agent")
        PythiaNetworkSession.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(TranslationError.requestFailed("更新检查失败：HTTP \(http.statusCode)。")))
                return
            }
            guard let data,
                  let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                completion(.failure(TranslationError.requestFailed("更新检查失败：发布信息格式无效。")))
                return
            }
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            guard let match = objects.lazy.compactMap({ object -> (object: [String: Any], version: String)? in
                guard (object["draft"] as? Bool) != true,
                      (object["prerelease"] as? Bool) != true else { return nil }
                let tag = object["tag_name"] as? String ?? ""
                let name = object["name"] as? String
                guard let version = PythiaReleaseVersionPolicy.version(tagName: tag, releaseName: name) else {
                    return nil
                }
                return (object, version)
            }).first else {
                completion(.success(PythiaUpdateInfo(
                    currentVersion: current,
                    latestVersion: current,
                    releaseName: "暂无 Pythia 正式发布",
                    releaseURL: nil,
                    isNewer: false,
                    notes: "",
                    assetURL: nil,
                    assetName: nil,
                    assetSize: 0
                )))
                return
            }
            let object = match.object
            let latest = match.version
            let tag = (object["tag_name"] as? String) ?? latest
            let releaseName = (object["name"] as? String) ?? tag
            let htmlURL = (object["html_url"] as? String).flatMap(URL.init(string:))
            let asset = Self.preferredInstallAsset(in: object)
            completion(.success(PythiaUpdateInfo(
                currentVersion: current,
                latestVersion: latest,
                releaseName: releaseName,
                releaseURL: htmlURL,
                isNewer: Self.compareVersions(latest, current) == .orderedDescending,
                notes: (object["body"] as? String) ?? "",
                assetURL: asset?.url,
                assetName: asset?.name,
                assetSize: asset?.size ?? 0
            )))
        }.resume()
    }

    /// Picks the installable macOS DMG from a GitHub release's asset list.
    /// Prefers exact `Pythia.dmg` naming, then any `pythia…​.dmg`, so a
    /// release with several DMGs (or a look-alike like `NotPythia.dmg`)
    /// resolves deterministically.
    static func preferredInstallAsset(in object: [String: Any]) -> (url: URL, name: String, size: Int64)? {
        func compactName(of asset: [String: Any]) -> String? {
            guard let name = (asset["name"] as? String)?.lowercased(), name.hasSuffix(".dmg") else { return nil }
            return name.replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
        }
        let assets = (object["assets"] as? [[String: Any]] ?? []).filter { asset in
            guard let compact = compactName(of: asset) else { return false }
            return compact.hasPrefix("pythia")
        }
        let chosen = assets.first { compactName(of: $0) == "pythiadmg" } ?? assets.first
        guard let first = chosen,
              let name = first["name"] as? String,
              let url = (first["browser_download_url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        return (url, name, Int64(first["size"] as? Int ?? 0))
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a > b { return .orderedDescending }
            if a < b { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func versionComponents(_ value: String) -> [Int] {
        value
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}
