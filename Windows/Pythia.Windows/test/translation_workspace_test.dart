import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/ui/source_text_field.dart';
import 'package:pythia_windows/ui/translation_workspace.dart';

void main() {
  testWidgets('vertical growth is assigned only to the result region',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    Widget app(double height) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 700,
                height: height,
                child: PythiaTranslationWorkspace(
                  sourceController: controller,
                  sourceFocusNode: focusNode,
                  onSubmit: () {},
                  sourceLanguageLabel: '自动检测',
                  targetLanguageLabel: '简体中文',
                  results: const [],
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(520));
    final sourceBefore =
        tester.getSize(find.byKey(PythiaSourceTextField.regionKey)).height;
    final resultsBefore = tester
        .getSize(find.byKey(PythiaTranslationWorkspace.resultsRegionKey))
        .height;

    await tester.pumpWidget(app(720));
    final sourceAfter =
        tester.getSize(find.byKey(PythiaSourceTextField.regionKey)).height;
    final resultsAfter = tester
        .getSize(find.byKey(PythiaTranslationWorkspace.resultsRegionKey))
        .height;

    expect(sourceBefore, PythiaSourceTextField.height);
    expect(sourceAfter, sourceBefore);
    expect(resultsAfter - resultsBefore, 200);
  });
}
