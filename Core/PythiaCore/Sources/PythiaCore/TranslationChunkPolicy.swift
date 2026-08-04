import Foundation

public struct TranslationChunk: Equatable, Sendable {
    public let original: String
    public let leadingWhitespace: String
    public let body: String
    public let trailingWhitespace: String

    public init(original: String, leadingWhitespace: String, body: String, trailingWhitespace: String) {
        self.original = original
        self.leadingWhitespace = leadingWhitespace
        self.body = body
        self.trailingWhitespace = trailingWhitespace
    }
}

public enum TranslationChunkPolicy {
    public static let defaultLimit = 1_800

    public static func chunks(for text: String, maxCharacters: Int = defaultLimit) -> [TranslationChunk] {
        guard !text.isEmpty else { return [] }
        let limit = max(1, maxCharacters)
        let characters = Array(text)
        guard characters.count > limit else { return [envelope(text)] }

        let protectedBoundaries = numericTokenInteriorBoundaries(in: text)
        var result: [TranslationChunk] = []
        var cursor = 0

        while cursor < characters.count {
            let hardEnd = min(characters.count, cursor + limit)
            if hardEnd == characters.count {
                result.append(envelope(String(characters[cursor...])))
                break
            }

            let minimum = min(hardEnd, cursor + max(1, Int(Double(limit) * 0.55)))
            var preferred: [Int?] = [nil, nil, nil]
            if minimum < hardEnd {
                for boundary in (minimum...hardEnd).reversed() where !protectedBoundaries.contains(boundary) {
                    guard let priority = boundaryPriority(characters: characters, boundary: boundary) else { continue }
                    if preferred[priority] == nil { preferred[priority] = boundary }
                }
            }

            var end = preferred.compactMap { $0 }.first ?? hardEnd
            if protectedBoundaries.contains(end) {
                var backward = end
                while backward > cursor && protectedBoundaries.contains(backward) { backward -= 1 }
                if backward > cursor {
                    end = backward
                } else {
                    var forward = end
                    while forward < characters.count && protectedBoundaries.contains(forward) { forward += 1 }
                    end = forward
                }
            }
            if end <= cursor { end = min(characters.count, cursor + limit) }
            result.append(envelope(String(characters[cursor..<end])))
            cursor = end
        }

        return result
    }

    private static func boundaryPriority(characters: [Character], boundary: Int) -> Int? {
        guard boundary > 0, boundary <= characters.count else { return nil }
        let previous = characters[boundary - 1]
        if previous == "\n" || previous == "\r" { return 0 }
        if "。！？!?；;：:".contains(previous) { return 1 }
        if previous == "." {
            if boundary == characters.count || characters[boundary].isWhitespace { return 1 }
        }
        if ",，".contains(previous), boundary < characters.count, characters[boundary].isWhitespace { return 2 }
        return nil
    }

    private static func envelope(_ text: String) -> TranslationChunk {
        let leadingEnd = text.firstIndex(where: { !$0.isWhitespace }) ?? text.endIndex
        let leading = String(text[..<leadingEnd])
        guard leadingEnd != text.endIndex else {
            return TranslationChunk(original: text, leadingWhitespace: text, body: "", trailingWhitespace: "")
        }
        let trailingStart = text.lastIndex(where: { !$0.isWhitespace }).map { text.index(after: $0) } ?? leadingEnd
        return TranslationChunk(
            original: text,
            leadingWhitespace: leading,
            body: String(text[leadingEnd..<trailingStart]),
            trailingWhitespace: String(text[trailingStart...])
        )
    }

    private static func numericTokenInteriorBoundaries(in text: String) -> Set<Int> {
        let pattern = #"(?:[vV])?[+\-−＋－]?(?:(?:\p{Nd}{1,3}(?:[,\u00A0\u202F ]\p{Nd}{3})+(?:[.]\p{Nd}+)?)|(?:\p{Nd}+(?:[.,，．]\p{Nd}+)*))(?:[eE][+\-−]?\p{Nd}+)?(?:(?:[\-－/:：／])\p{Nd}+(?:[.,，．]\p{Nd}+)*)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var protected = Set<Int>()
        for match in regex.matches(in: text, range: fullRange) {
            guard let range = Range(match.range, in: text) else { continue }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            guard end - start > 1 else { continue }
            for boundary in (start + 1)..<end { protected.insert(boundary) }
        }
        return protected
    }
}

public enum TranslationRetryPolicy {
    public static let retryableHTTPStatusCodes: Set<Int> = [408, 409, 425, 429]

    public static func isRetryableHTTPStatus(_ status: Int) -> Bool {
        retryableHTTPStatusCodes.contains(status) || (500...599).contains(status)
    }

    public static func retryDelay(retryAfter: String?, retryNumber: Int, now: Date = Date()) -> TimeInterval {
        if let raw = retryAfter?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if let seconds = TimeInterval(raw), seconds.isFinite {
                return min(60, max(0.75, seconds))
            }
            for format in ["EEE',' dd MMM yyyy HH':'mm':'ss z", "EEEE',' dd-MMM-yy HH':'mm':'ss z", "EEE MMM d HH':'mm':'ss yyyy"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) {
                    return min(60, max(0.75, date.timeIntervalSince(now)))
                }
            }
        }
        return retryNumber <= 1 ? 0.75 : 2.0
    }
}
