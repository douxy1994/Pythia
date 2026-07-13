import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/webdav_auto_sync_scheduler.dart';
import 'package:pythia_windows/core/webdav_sync_schedule.dart';

void main() {
  test('schedules the exact selected duration and invokes WebDAV sync',
      () async {
    Duration? scheduledDuration;
    void Function(Timer)? periodicCallback;
    final timer = _FakeTimer();
    final scheduler = WebDavAutoSyncScheduler(
      timerFactory: (duration, callback) {
        scheduledDuration = duration;
        periodicCallback = callback;
        return timer;
      },
    );
    var syncCount = 0;

    scheduler.configure(
      enabled: true,
      hasWebDavAddress: true,
      schedule: const WebDavSyncSchedule(3, WebDavSyncIntervalUnit.day),
      synchronize: () async => syncCount += 1,
    );
    periodicCallback!(timer);
    await Future<void>.delayed(Duration.zero);

    expect(scheduledDuration, const Duration(days: 3));
    expect(syncCount, 1);
    expect(scheduler.isScheduled, isTrue);
  });

  test('does not schedule without both opt-in and WebDAV address', () {
    var created = 0;
    final scheduler = WebDavAutoSyncScheduler(
      timerFactory: (_, __) {
        created += 1;
        return _FakeTimer();
      },
    );
    Future<void> sync() async {}

    scheduler.configure(
      enabled: false,
      hasWebDavAddress: true,
      schedule: const WebDavSyncSchedule(1, WebDavSyncIntervalUnit.hour),
      synchronize: sync,
    );
    scheduler.configure(
      enabled: true,
      hasWebDavAddress: false,
      schedule: const WebDavSyncSchedule(1, WebDavSyncIntervalUnit.hour),
      synchronize: sync,
    );

    expect(created, 0);
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
