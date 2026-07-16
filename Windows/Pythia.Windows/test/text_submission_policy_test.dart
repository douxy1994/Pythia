import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/text_submission_policy.dart';

void main() {
  TextSubmissionDecision resolve({
    bool isKeyDown = true,
    bool isEnter = true,
    bool isComposing = false,
    bool shift = false,
    bool control = false,
    bool alt = false,
    bool meta = false,
  }) {
    return TextSubmissionPolicy.resolve(
      isKeyDown: isKeyDown,
      isEnter: isEnter,
      isComposing: isComposing,
      isShiftPressed: shift,
      isControlPressed: control,
      isAltPressed: alt,
      isMetaPressed: meta,
    );
  }

  test('plain Enter submits after composition has ended', () {
    expect(resolve(), TextSubmissionDecision.submit);
  });

  test('Enter is left to the input method while composing', () {
    expect(
      resolve(isComposing: true),
      TextSubmissionDecision.ignore,
    );
  });

  test('Shift+Enter inserts a line break instead of submitting', () {
    expect(
      resolve(shift: true),
      TextSubmissionDecision.insertLineBreak,
    );
  });

  test('modified Enter and key-up events do not submit', () {
    expect(resolve(control: true), TextSubmissionDecision.ignore);
    expect(resolve(alt: true), TextSubmissionDecision.ignore);
    expect(resolve(meta: true), TextSubmissionDecision.ignore);
    expect(resolve(isKeyDown: false), TextSubmissionDecision.ignore);
  });
}
