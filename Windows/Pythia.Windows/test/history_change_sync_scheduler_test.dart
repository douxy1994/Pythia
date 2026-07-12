import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/history_change_sync_scheduler.dart';

void main() {
  test('debounces repeated history changes into one sync', () async {
    final timers = <_FakeTimer>[];
    final callbacks = <void Function()>[];
    final scheduler = HistoryChangeSyncScheduler(
      timerFactory: (duration, callback) {
        expect(duration, const Duration(seconds: 10));
        callbacks.add(callback);
        final timer = _FakeTimer();
        timers.add(timer);
        return timer;
      },
    );
    var syncCount = 0;
    scheduler.configure(
      enabled: true,
      hasWebDavAddress: true,
      synchronize: () async => syncCount += 1,
    );

    scheduler.historyChanged();
    scheduler.historyChanged();
    expect(timers.first.isActive, isFalse);
    callbacks.last();
    await Future<void>.delayed(Duration.zero);

    expect(syncCount, 1);
  });

  test('does not schedule when automatic sync is unavailable', () {
    var timersCreated = 0;
    final scheduler = HistoryChangeSyncScheduler(
      timerFactory: (_, __) {
        timersCreated += 1;
        return _FakeTimer();
      },
    );
    scheduler.configure(
      enabled: false,
      hasWebDavAddress: true,
      synchronize: () async {},
    );

    scheduler.historyChanged();

    expect(timersCreated, 0);
  });
}

class _FakeTimer implements Timer {
  bool active = true;

  @override
  bool get isActive => active;

  @override
  int get tick => 0;

  @override
  void cancel() => active = false;
}
