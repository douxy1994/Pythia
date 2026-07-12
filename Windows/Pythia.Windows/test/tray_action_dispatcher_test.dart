import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/platform/tray_action_dispatcher.dart';

void main() {
  test('dispatches every supported tray action to its callback', () async {
    final calls = <String>[];
    final dispatcher = TrayActionDispatcher(
      onInputTranslate: () async => calls.add('input'),
      onOpenSettings: () async => calls.add('settings'),
      onOpenHistory: () async => calls.add('history'),
      onSyncHistory: () async => calls.add('sync'),
      onQuit: () async => calls.add('quit'),
    );

    expect(await dispatcher.dispatch(TrayActions.inputTranslate), isTrue);
    expect(await dispatcher.dispatch(TrayActions.openSettings), isTrue);
    expect(await dispatcher.dispatch(TrayActions.openHistory), isTrue);
    expect(await dispatcher.dispatch(TrayActions.syncHistory), isTrue);
    expect(await dispatcher.dispatch(TrayActions.quit), isTrue);
    expect(calls, ['input', 'settings', 'history', 'sync', 'quit']);
  });

  test('returns false for unknown tray action', () async {
    final dispatcher = TrayActionDispatcher(
      onInputTranslate: () async {},
      onOpenSettings: () async {},
      onOpenHistory: () async {},
      onSyncHistory: () async {},
      onQuit: () async {},
    );

    expect(await dispatcher.dispatch('unknown'), isFalse);
  });
}
