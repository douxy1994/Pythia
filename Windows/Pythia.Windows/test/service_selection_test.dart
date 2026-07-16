import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/service_selection.dart';

void main() {
  test('newly selected service moves to the top without resetting order', () {
    final next = TranslateServiceSelection.toggle(
      current: const ['google', 'local'],
      serviceId: 'deepl',
      selected: true,
    );

    expect(next, ['deepl', 'google', 'local']);
  });

  test('deselecting a service preserves the relative order of the rest', () {
    final next = TranslateServiceSelection.toggle(
      current: const ['deepl', 'google', 'local'],
      serviceId: 'google',
      selected: false,
    );

    expect(next, ['deepl', 'local']);
  });

  test('selection never becomes empty', () {
    final next = TranslateServiceSelection.toggle(
      current: const ['local'],
      serviceId: 'local',
      selected: false,
    );

    expect(next, ['local']);
  });

  test('moving a service changes only its position', () {
    final next = TranslateServiceSelection.move(
      current: const ['deepl', 'google', 'local'],
      serviceId: 'deepl',
      offset: 1,
    );

    expect(next, ['google', 'deepl', 'local']);
  });
}
