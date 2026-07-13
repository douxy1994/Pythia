import Foundation

public enum PythiaReleaseVersionPolicy {
    public static func version(tagName: String, releaseName: String?) -> String? {
        let name = releaseName ?? ""
        guard tagName.range(of: "pythia", options: .caseInsensitive) != nil
                || name.range(of: "pythia", options: .caseInsensitive) != nil else {
            return nil
        }

        let source = tagName.range(of: "pythia", options: .caseInsensitive) != nil ? tagName : name
        let components = source
            .split { !$0.isNumber }
            .compactMap { Int($0) }
        guard !components.isEmpty else { return nil }
        return components.map(String.init).joined(separator: ".")
    }
}
