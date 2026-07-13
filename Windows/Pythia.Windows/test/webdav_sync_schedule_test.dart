import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/settings_model.dart';
import 'package:pythia_windows/core/webdav_sync_schedule.dart';

void main() {
  test('converts every selectable unit to an exact timer duration', () {
    expect(
      const WebDavSyncSchedule(15, WebDavSyncIntervalUnit.minute).seconds,
      900,
    );
    expect(
      const WebDavSyncSchedule(2, WebDavSyncIntervalUnit.hour).seconds,
      7200,
    );
    expect(
      const WebDavSyncSchedule(3, WebDavSyncIntervalUnit.day).seconds,
      259200,
    );
    expect(
      const WebDavSyncSchedule(2, WebDavSyncIntervalUnit.week).seconds,
      1209600,
    );
  });

  test('persists the chosen value and unit and retains legacy minutes', () {
    const settings = PythiaSettings(
      webdavHistorySyncIntervalValue: 3,
      webdavHistorySyncIntervalUnit: 'day',
    );
    final json = settings.toJson();
    final restored = PythiaSettings.fromJson(json);

    expect(restored.webdavSyncSchedule.value, 3);
    expect(restored.webdavSyncSchedule.unit, WebDavSyncIntervalUnit.day);
    expect(restored.webdavSyncSchedule.seconds, 259200);
    expect(json['webdavHistorySyncIntervalMinutes'], 4320);
  });

  test('migrates old minute-only settings without changing the interval', () {
    final halfHour = PythiaSettings.fromJson({
      'webdavHistorySyncIntervalMinutes': 30,
    });
    final oneWeek = PythiaSettings.fromJson({
      'webdavHistorySyncIntervalMinutes': 10080,
    });

    expect(halfHour.webdavSyncSchedule.value, 30);
    expect(halfHour.webdavSyncSchedule.unit, WebDavSyncIntervalUnit.minute);
    expect(oneWeek.webdavSyncSchedule.value, 1);
    expect(oneWeek.webdavSyncSchedule.unit, WebDavSyncIntervalUnit.week);
  });

  test('rejects zero and intervals longer than 366 days', () {
    expect(
      () => const WebDavSyncSchedule(0, WebDavSyncIntervalUnit.minute)
          .validated(),
      throwsFormatException,
    );
    expect(
      () =>
          const WebDavSyncSchedule(53, WebDavSyncIntervalUnit.week).validated(),
      throwsFormatException,
    );
  });
}
