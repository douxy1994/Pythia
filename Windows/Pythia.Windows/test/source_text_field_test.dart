import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/ui/source_text_field.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late int submissions;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    submissions = 0;
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            child: PythiaSourceTextField(
              controller: controller,
              focusNode: focusNode,
              onSubmit: () => submissions += 1,
              languageLabel: '自动检测',
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(PythiaSourceTextField.inputKey));
    await tester.pump();
  }

  testWidgets('source editor has a fixed height', (tester) async {
    await pumpEditor(tester);

    expect(
      tester.getSize(find.byKey(PythiaSourceTextField.regionKey)).height,
      PythiaSourceTextField.height,
    );
  });

  testWidgets('plain Enter submits once', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(
      find.byKey(PythiaSourceTextField.inputKey),
      'hello',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(submissions, 1);
  });

  testWidgets('Shift+Enter does not submit', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(submissions, 0);
  });

  testWidgets('Enter does not submit while the IME has composing text',
      (tester) async {
    await pumpEditor(tester);
    controller.value = const TextEditingValue(
      text: 'ni',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(submissions, 0);
  });
}
