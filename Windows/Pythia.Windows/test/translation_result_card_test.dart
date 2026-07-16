import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/translation_service.dart';
import 'package:pythia_windows/ui/translation_result_card.dart';

void main() {
  testWidgets('result card expands and collapses independently',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PythiaTranslationResultCard(
          result: PythiaTranslationResult(
            serviceId: 'google',
            serviceName: 'Google',
            text: '你好',
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('result-content-google')), findsOneWidget);
    await tester.tap(find.byKey(const Key('result-toggle-google')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result-content-google')), findsNothing);
  });

  testWidgets('failed service is rendered as an error card', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PythiaTranslationResultCard(
          result: PythiaTranslationResult.failure(
            serviceId: 'deepl',
            serviceName: 'DeepL',
            errorMessage: '认证失败',
          ),
        ),
      ),
    ));

    expect(find.text('认证失败'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });
}
