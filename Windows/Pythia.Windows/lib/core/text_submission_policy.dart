enum TextSubmissionDecision { ignore, submit, insertLineBreak }

class TextSubmissionPolicy {
  const TextSubmissionPolicy._();

  static TextSubmissionDecision resolve({
    required bool isKeyDown,
    required bool isEnter,
    required bool isComposing,
    required bool isShiftPressed,
    required bool isControlPressed,
    required bool isAltPressed,
    required bool isMetaPressed,
  }) {
    if (!isKeyDown || !isEnter || isComposing) {
      return TextSubmissionDecision.ignore;
    }
    if (isShiftPressed) {
      return TextSubmissionDecision.insertLineBreak;
    }
    if (isControlPressed || isAltPressed || isMetaPressed) {
      return TextSubmissionDecision.ignore;
    }
    return TextSubmissionDecision.submit;
  }
}
