import 'dart:async';

typedef HistorySyncTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

class HistoryChangeSyncScheduler {
  final Duration debounce;
  final HistorySyncTimerFactory timerFactory;
  Timer? _timer;
  bool _enabled = false;
  bool _hasWebDavAddress = false;
  Future<void> Function()? _synchronize;

  HistoryChangeSyncScheduler({
    this.debounce = const Duration(seconds: 10),
    HistorySyncTimerFactory? timerFactory,
  }) : timerFactory = timerFactory ?? Timer.new;

  void configure({
    required bool enabled,
    required bool hasWebDavAddress,
    required Future<void> Function() synchronize,
  }) {
    _enabled = enabled;
    _hasWebDavAddress = hasWebDavAddress;
    _synchronize = synchronize;
    if (!enabled || !hasWebDavAddress) cancel();
  }

  void historyChanged() {
    if (!_enabled || !_hasWebDavAddress || _synchronize == null) return;
    _timer?.cancel();
    _timer = timerFactory(debounce, () {
      _timer = null;
      _synchronize!();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
