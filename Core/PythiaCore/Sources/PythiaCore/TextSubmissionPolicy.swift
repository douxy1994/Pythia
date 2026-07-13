public enum TextSubmissionPolicy {
    public static func shouldSubmit(
        isReturn: Bool,
        hasMarkedText: Bool,
        inputMethodHandledEvent: Bool = false,
        hasShift: Bool,
        hasOption: Bool,
        hasCommand: Bool
    ) -> Bool {
        isReturn && !hasMarkedText && !inputMethodHandledEvent && !hasShift && !hasOption && !hasCommand
    }
}
