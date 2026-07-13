import AppKit
import Foundation

struct PythiaUpdateInfo {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseURL: URL?
    let isNewer: Bool
}

final class PythiaUpdateChecker {
    static let shared = PythiaUpdateChecker()

    private let releasesURL = URL(string: "https://api.github.com/repos/douxy1994/Pythia/releases?per_page=20")!

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
                    isNewer: false
                )))
                return
            }
            let object = match.object
            let latest = match.version
            let tag = (object["tag_name"] as? String) ?? latest
            let releaseName = (object["name"] as? String) ?? tag
            let htmlURL = (object["html_url"] as? String).flatMap(URL.init(string:))
            completion(.success(PythiaUpdateInfo(
                currentVersion: current,
                latestVersion: latest,
                releaseName: releaseName,
                releaseURL: htmlURL,
                isNewer: Self.compareVersions(latest, current) == .orderedDescending
            )))
        }.resume()
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
