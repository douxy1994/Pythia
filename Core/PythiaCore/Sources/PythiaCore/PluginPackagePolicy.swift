import Foundation

public enum PluginPackagePolicy {
    public static func accepts(fileName: String) -> Bool {
        URL(fileURLWithPath: fileName).pathExtension.caseInsensitiveCompare("potext") == .orderedSame
    }

    public static func displayName(
        alias: String?,
        declaredDisplay: String?,
        declaredName: String?,
        fallback: String
    ) -> String {
        [alias, declaredDisplay, declaredName, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallback
    }
}
