import AppKit
import Foundation

enum PythiaUpdateInstallError: LocalizedError {
    case missingAsset
    case downloadFailed(String)
    case mountFailed(String)
    case appNotFoundInDMG
    case signatureMismatch(String)
    case installFailed(String)
    case downloadInProgress
    case installInProgress

    var errorDescription: String? {
        switch self {
        case .missingAsset:
            "该版本没有可安装的 macOS DMG 附件。"
        case .downloadFailed(let detail):
            "下载更新失败：\(detail)"
        case .mountFailed(let detail):
            "无法打开下载的 DMG：\(detail)"
        case .appNotFoundInDMG:
            "DMG 中没有找到 Pythia.app。"
        case .signatureMismatch(let detail):
            "下载的 App 签名与项目稳定身份不一致，已中止安装：\(detail)"
        case .installFailed(let detail):
            "安装更新失败：\(detail)"
        case .downloadInProgress:
            "已有更新下载正在进行中。"
        case .installInProgress:
            "已有更新正在下载或安装中。"
        }
    }
}

enum PythiaUpdateInstallOutcome {
    /// /Applications/Pythia.app was replaced; caller should relaunch.
    case installed(app: URL, rollback: URL?)
    /// The app is not running from a writable /Applications; the DMG was
    /// opened for manual install.
    case openedInstaller(URL)
}

/// In-app ("hot") updater: downloads the release DMG, verifies the bundled
/// app's signing identity, replaces /Applications/Pythia.app when the user can
/// write there, and lets the caller relaunch. Mirrors the checks in
/// script/package_release.sh — only builds signed by the project's stable
/// identity are ever installed.
final class PythiaUpdateInstaller: NSObject {
    static let shared = PythiaUpdateInstaller()

    private let expectedRequirement = #"identifier "com.douxy.pythia" and certificate leaf = H"a493ef6f181ec595f5216b01a4e2008778c4a592""#
    private let applicationsURL = URL(fileURLWithPath: "/Applications/Pythia.app")

    private var progressHandler: ((Double) -> Void)?
    private var downloadCompletion: ((Result<URL, Error>) -> Void)?
    private var expectedBytes: Int64 = 0
    private var destinationURL: URL?
    private var downloadSession: URLSession?
    private enum Activity: Equatable { case idle, downloading, downloaded, installing }
    private let activityLock = NSLock()
    private var activity: Activity = .idle
    private var lastReportedProgress = -1.0

    // MARK: - Download

    func download(
        info: PythiaUpdateInfo,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        activityLock.lock()
        guard activity == .idle else {
            activityLock.unlock()
            completion(.failure(PythiaUpdateInstallError.downloadInProgress))
            return
        }
        activity = .downloading
        activityLock.unlock()
        guard let assetURL = info.assetURL, let assetName = info.assetName else {
            setActivity(.idle)
            completion(.failure(PythiaUpdateInstallError.missingAsset))
            return
        }
        lastReportedProgress = -1
        progressHandler = progress
        downloadCompletion = completion
        expectedBytes = info.assetSize

        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pythia/Updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: assetName).lastPathComponent
        let destination = root.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: destination)
        destinationURL = destination

        var request = URLRequest(url: assetURL)
        request.setValue("Pythia", forHTTPHeaderField: "User-Agent")
        let session = URLSession(
            configuration: PythiaNetworkSession.configuration(for: assetURL),
            delegate: self,
            delegateQueue: nil
        )
        downloadSession = session
        session.downloadTask(with: PythiaNetworkSession.requestWithProxyAuthorization(request)).resume()
    }

    // MARK: - Install

    /// Runs entirely on a background queue; completion fires on the main queue.
    func install(
        from dmgURL: URL,
        completion: @escaping (Result<PythiaUpdateInstallOutcome, Error>) -> Void
    ) {
        activityLock.lock()
        guard activity == .downloaded else {
            activityLock.unlock()
            completion(.failure(PythiaUpdateInstallError.installInProgress))
            return
        }
        activity = .installing
        activityLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result<PythiaUpdateInstallOutcome, Error> {
                try performInstall(from: dmgURL)
            }
            setActivity(.idle)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func performInstall(from dmgURL: URL) throws -> PythiaUpdateInstallOutcome {
        let mountOutput = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", dmgURL.path]) { detail in
            PythiaUpdateInstallError.mountFailed(detail)
        }
        let mountPoint = Self.parseMountPoint(from: mountOutput)
        // Registered right after attach so a parse failure still detaches.
        defer {
            if let mountPoint {
                _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mountPoint]) { _ in
                    PythiaUpdateInstallError.mountFailed("")
                }
            }
        }
        guard let mountPoint else {
            throw PythiaUpdateInstallError.mountFailed(mountOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let mountedApp = URL(fileURLWithPath: mountPoint).appendingPathComponent("Pythia.app")
        guard FileManager.default.fileExists(atPath: mountedApp.path) else {
            throw PythiaUpdateInstallError.appNotFoundInDMG
        }
        try verifyStableIdentity(of: mountedApp)

        // Only replace in place when this process is the /Applications copy and
        // the directory is writable; otherwise hand the DMG to the user.
        let runningURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard runningURL == applicationsURL,
              FileManager.default.isWritableFile(atPath: "/Applications")
        else {
            DispatchQueue.main.async { NSWorkspace.shared.open(dmgURL) }
            return .openedInstaller(dmgURL)
        }

        // Atomic-ish swap: rename the old bundle aside first and keep it until
        // the relaunch helper confirms the replacement survives startup.
        let staging = URL(fileURLWithPath: "/Applications/.Pythia-update-\(UUID().uuidString)")
        let sidecar = URL(fileURLWithPath: "/Applications/.Pythia-old-\(UUID().uuidString)")
        var movedOld = false
        do {
            try FileManager.default.copyItem(at: mountedApp, to: staging)
            if FileManager.default.fileExists(atPath: applicationsURL.path) {
                try FileManager.default.moveItem(at: applicationsURL, to: sidecar)
                movedOld = true
            }
            do {
                try FileManager.default.moveItem(at: staging, to: applicationsURL)
            } catch {
                if movedOld { try? FileManager.default.moveItem(at: sidecar, to: applicationsURL) }
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw PythiaUpdateInstallError.installFailed(error.localizedDescription)
        }
        return .installed(app: applicationsURL, rollback: movedOld ? sidecar : nil)
    }

    /// Relaunches only after the current process exits. The old bundle stays
    /// beside the replacement until the new process has remained alive for a
    /// short health window; a launch failure restores and reopens the old app.
    func relaunch(
        appURL: URL,
        rollbackURL: URL?,
        failure: @escaping (Error) -> Void
    ) {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            """
            while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
            /usr/bin/open -n "$2"
            newpid=""
            i=0
            while [ "$i" -lt 60 ]; do
              newpid=$(/bin/ps -axo pid=,command= | /usr/bin/awk -v exe="$2/Contents/MacOS/Pythia" '$2 == exe { print $1; exit }')
              [ -n "$newpid" ] && break
              i=$((i + 1)); /bin/sleep 0.25
            done
            if [ -n "$newpid" ]; then
              /bin/sleep 8
              if /bin/kill -0 "$newpid" 2>/dev/null; then
                [ -n "$3" ] && /bin/rm -rf "$3"
                exit 0
              fi
            fi
            if [ -n "$3" ] && [ -e "$3" ]; then
              /bin/rm -rf "$2"
              /bin/mv "$3" "$2"
              /usr/bin/open -n "$2"
            fi
            """,
            "pythia-relaunch",
            "\(ProcessInfo.processInfo.processIdentifier)",
            appURL.path,
            rollbackURL?.path ?? "",
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            failure(error)
        }
    }

    private func verifyStableIdentity(of app: URL) throws {
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) { detail in
            PythiaUpdateInstallError.signatureMismatch(detail)
        }
        let description = try run("/usr/bin/codesign", ["-d", "-r-", app.path]) { detail in
            PythiaUpdateInstallError.signatureMismatch(detail)
        }
        guard let requirement = description
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("designated => ") })
            .map({ String($0.dropFirst("designated => ".count)) }),
              requirement == expectedRequirement
        else {
            throw PythiaUpdateInstallError.signatureMismatch(description.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func parseMountPoint(from output: String) -> String? {
        for line in output.split(separator: "\n").reversed() {
            guard let last = line.split(separator: "\t").last, last.hasPrefix("/Volumes") else { continue }
            return String(last)
        }
        return nil
    }

    @discardableResult
    private func run(
        _ launchPath: String,
        _ arguments: [String],
        errorMapper: (String) -> PythiaUpdateInstallError
    ) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw errorMapper(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func finishDownload(with result: Result<URL, Error>) {
        activityLock.lock()
        guard activity == .downloading else {
            activityLock.unlock()
            return
        }
        switch result {
        case .success: activity = .downloaded
        case .failure: activity = .idle
        }
        activityLock.unlock()
        let completion = downloadCompletion
        progressHandler = nil
        downloadCompletion = nil
        destinationURL = nil
        downloadSession = nil
        DispatchQueue.main.async { completion?(result) }
    }

    private func setActivity(_ next: Activity) {
        activityLock.lock()
        activity = next
        activityLock.unlock()
    }
}

extension PythiaUpdateInstaller: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        guard expected > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(expected))
        // Throttle to whole-percent steps so fast links don't flood the main queue.
        guard fraction - lastReportedProgress >= 0.01 || fraction >= 1 else { return }
        lastReportedProgress = fraction
        DispatchQueue.main.async { self.progressHandler?(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        defer { session.finishTasksAndInvalidate() }
        guard let destination = destinationURL else { return }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw PythiaUpdateInstallError.downloadFailed("HTTP \(http.statusCode)")
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finishDownload(with: .success(destination))
        } catch {
            finishDownload(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        session.finishTasksAndInvalidate()
        finishDownload(with: .failure(PythiaUpdateInstallError.downloadFailed(error.localizedDescription)))
    }
}
