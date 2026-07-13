enum WebDavSyncIntervalUnit {
  minute('minute', '分钟', 60),
  hour('hour', '小时', 3600),
  day('day', '天', 86400),
  week('week', '周', 604800);

  final String storageValue;
  final String label;
  final int seconds;

  const WebDavSyncIntervalUnit(this.storageValue, this.label, this.seconds);

  static WebDavSyncIntervalUnit fromStorage(String? raw) {
    return values.firstWhere(
      (unit) => unit.storageValue == raw,
      orElse: () => WebDavSyncIntervalUnit.hour,
    );
  }
}

class WebDavSyncSchedule {
  static const maxSeconds = 366 * 24 * 60 * 60;

  final int value;
  final WebDavSyncIntervalUnit unit;

  const WebDavSyncSchedule(this.value, this.unit);

  int get seconds => value * unit.seconds;
  int get legacyMinutes => seconds ~/ 60;

  WebDavSyncSchedule validated() {
    if (value <= 0) {
      throw const FormatException('自动同步间隔必须大于 0');
    }
    if (seconds > maxSeconds) {
      throw const FormatException('自动同步间隔不能超过 366 天');
    }
    return this;
  }

  static WebDavSyncSchedule fromLegacyMinutes(int minutes) {
    final safeMinutes = minutes <= 0 ? 60 : minutes;
    if (safeMinutes % 10080 == 0) {
      return WebDavSyncSchedule(
        safeMinutes ~/ 10080,
        WebDavSyncIntervalUnit.week,
      );
    }
    if (safeMinutes % 1440 == 0) {
      return WebDavSyncSchedule(
        safeMinutes ~/ 1440,
        WebDavSyncIntervalUnit.day,
      );
    }
    if (safeMinutes % 60 == 0) {
      return WebDavSyncSchedule(
        safeMinutes ~/ 60,
        WebDavSyncIntervalUnit.hour,
      );
    }
    return WebDavSyncSchedule(safeMinutes, WebDavSyncIntervalUnit.minute);
  }
}
