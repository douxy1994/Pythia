import Foundation

/// Stores sensitive settings without touching macOS Keychain.
///
/// Pythia deliberately keeps this file outside UserDefaults and applies
/// owner-only permissions. The application's portable backup path never reads
/// this store.
final class LocalCredentialStore {
    static let shared = LocalCredentialStore()

    private let directoryURL: URL
    private let fileURL: URL
    private let lock = NSLock()
    private var values: [String: String]

    private init() {
        directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pythia", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("credentials.json")

        try? Self.enforcePrivateDirectory(at: directoryURL)
        values = Self.load(from: fileURL)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? Self.enforcePrivateFile(at: fileURL)
        }
    }

    func read(namespace: String, key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[storageKey(namespace: namespace, key: key)]
    }

    func write(_ value: String, namespace: String, key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var updated = values
        updated[storageKey(namespace: namespace, key: key)] = value
        try persist(updated)
        values = updated
    }

    func delete(namespace: String, key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let account = storageKey(namespace: namespace, key: key)
        guard values[account] != nil else { return }
        var updated = values
        updated.removeValue(forKey: account)
        try persist(updated)
        values = updated
    }

    private func storageKey(namespace: String, key: String) -> String {
        "\(namespace):\(key)"
    }

    private func persist(_ snapshot: [String: String]) throws {
        try Self.enforcePrivateDirectory(at: directoryURL)
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: [.atomic])
        try Self.enforcePrivateFile(at: fileURL)
    }

    private static func load(from url: URL) -> [String: String] {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        return object.reduce(into: [String: String]()) { result, pair in
            guard let value = pair.value as? String, !value.isEmpty else { return }
            result[pair.key] = value
        }
    }

    private static func enforcePrivateDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func enforcePrivateFile(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
}
