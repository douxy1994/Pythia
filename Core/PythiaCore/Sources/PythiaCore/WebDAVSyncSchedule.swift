public enum PythiaWebDAVSyncUnit: String, CaseIterable {
    case minute
    case hour
    case day
    case week

    public var seconds: Int {
        switch self {
        case .minute: return 60
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return 604_800
        }
    }
}

public struct PythiaWebDAVSyncSchedule: Equatable {
    public static let maximumSeconds = 366 * 86_400

    public let value: Int
    public let unit: PythiaWebDAVSyncUnit

    public init?(value: Int, unit: PythiaWebDAVSyncUnit) {
        guard value > 0, value <= Self.maximumSeconds / unit.seconds else { return nil }
        self.value = value
        self.unit = unit
    }

    public var seconds: Int { value * unit.seconds }
    public var legacyMinutes: Int { seconds / 60 }

    public static func fromLegacyMinutes(_ rawMinutes: Int) -> PythiaWebDAVSyncSchedule {
        let minutes = min(max(1, rawMinutes), maximumSeconds / 60)
        if minutes.isMultiple(of: 10_080) {
            return PythiaWebDAVSyncSchedule(value: minutes / 10_080, unit: .week)!
        }
        if minutes.isMultiple(of: 1_440) {
            return PythiaWebDAVSyncSchedule(value: minutes / 1_440, unit: .day)!
        }
        if minutes.isMultiple(of: 60) {
            return PythiaWebDAVSyncSchedule(value: minutes / 60, unit: .hour)!
        }
        return PythiaWebDAVSyncSchedule(
            value: minutes,
            unit: .minute
        )!
    }
}
