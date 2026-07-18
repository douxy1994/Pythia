import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/history_record.dart';
import 'package:pythia_windows/core/settings_model.dart';
import 'package:pythia_windows/core/webdav_sync.dart';
import 'package:pythia_windows/main.dart';
import 'package:pythia_windows/platform/credential_store.dart';

class _HistoryRepository implements HistoryRepository {
  @override
  Future<void> backupBeforeSync() async {}

  @override
  Future<String> deviceId() async => 'test-device';

  @override
  Future<List<PythiaHistoryRecord>> readAllForSync() async => const [];

  @override
  Future<void> replaceAllFromSync(List<PythiaHistoryRecord> records) async {}
}

void main() {
  for (final scale in <double>[1.0, 1.25, 1.5, 2.0]) {
    testWidgets('settings shell does not overflow at ${scale * 100}% DPI',
        (tester) async {
      tester.view.devicePixelRatio = scale;
      tester.view.physicalSize = const Size(1180, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SettingsDialog(
            settings: const PythiaSettings(),
            credentialStore: const UnsupportedCredentialStore(),
            historyRepository: _HistoryRepository(),
            pluginManager: null,
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Pythia 设置'), findsOneWidget);
      expect(find.text('保存历史记录'), findsOneWidget);
    });
  }

  testWidgets(
      'settings uses navigable sections without overflowing at 150% DPI',
      (tester) async {
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(1180, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsDialog(
          settings: const PythiaSettings(),
          credentialStore: const UnsupportedCredentialStore(),
          historyRepository: _HistoryRepository(),
          pluginManager: null,
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Pythia 设置'), findsOneWidget);
    expect(find.text('OCR'), findsOneWidget);
    expect(find.text('保存历史记录'), findsOneWidget);
    expect(find.text('启用 Google 翻译'), findsNothing);

    await tester.tap(find.text('翻译服务').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('启用 Google 翻译'), findsOneWidget);
    expect(find.text('保存历史记录'), findsNothing);
  });
}
