import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/ui/hotkey_recorder_field.dart';

void main() {
  testWidgets('records a supported Windows global shortcut', (tester) async {
    final controller = TextEditingController(text: 'Ctrl+Alt+P');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HotkeyRecorderField(
          controller: controller,
          label: '显示窗口快捷键',
        ),
      ),
    ));

    await tester.tap(find.byType(HotkeyRecorderField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.text, 'Ctrl+Alt+K');
    expect(find.text('Ctrl+Alt+K'), findsOneWidget);
  });

  testWidgets('escape cancels recording without changing the shortcut',
      (tester) async {
    final controller = TextEditingController(text: 'Ctrl+Alt+P');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HotkeyRecorderField(
          controller: controller,
          label: '显示窗口快捷键',
        ),
      ),
    ));

    await tester.tap(find.byType(HotkeyRecorderField));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(controller.text, 'Ctrl+Alt+P');
    expect(find.text('Ctrl+Alt+P'), findsOneWidget);
  });
}
