import 'dart:async';

import 'webdav_sync_schedule.dart';

typedef PeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class WebDavAutoSyncScheduler {
  final PeriodicTimerFactory timerFactory;
  Timer? _timer;

  WebDavAutoSyncScheduler({
    PeriodicTimerFactory? timerFactory,
  }) : timerFactory = timerFactory ?? Timer.periodic;

  bool get isScheduled => _timer?.isActive ?? false;

  void configure({
    required bool enabled,
    required bool hasWebDavAddress,
    required WebDavSyncSchedule schedule,
    required Future<void> Function() synchronize,
  }) {
    cancel();
    if (!enabled || !hasWebDavAddress) return;
    final validated = schedule.validated();
    _timer = timerFactory(Duration(seconds: validated.seconds), (_) {
      synchronize();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
