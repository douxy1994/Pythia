import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/ui/service_picker_button.dart';

void main() {
  testWidgets('service panel stays open for multi-select and supports ordering',
      (tester) async {
    var selected = <String>['google', 'local'];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PythiaServicePickerButton(
          options: const [
            PythiaServiceOption('local', 'Local'),
            PythiaServiceOption('google', 'Google'),
            PythiaServiceOption('deepl', 'DeepL'),
          ],
          selectedServiceIds: selected,
          onSelectionChanged: (next) => selected = next,
        ),
      ),
    ));

    await tester.tap(find.byKey(PythiaServicePickerButton.buttonKey));
    await tester.pumpAndSettle();
    final deepLCheckbox = find.descendant(
      of: find.byKey(const Key('service-option-deepl')),
      matching: find.byType(Checkbox),
    );
    await tester.tap(deepLCheckbox);
    await tester.pump();

    expect(selected, ['deepl', 'google', 'local']);
    expect(find.byKey(PythiaServicePickerButton.dialogKey), findsOneWidget);

    await tester.tap(find.byKey(const Key('service-down-deepl')));
    await tester.pump();

    expect(selected, ['google', 'deepl', 'local']);
    expect(find.byKey(PythiaServicePickerButton.dialogKey), findsOneWidget);
  });
}
