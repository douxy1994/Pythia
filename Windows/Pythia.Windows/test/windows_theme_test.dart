import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/ui/windows_theme.dart';

void main() {
  test('Windows themes use opaque Fluent-style surfaces and Segoe UI', () {
    final light = pythiaWindowsTheme(Brightness.light);
    final dark = pythiaWindowsTheme(Brightness.dark);

    expect(light.textTheme.bodyMedium?.fontFamily, 'Segoe UI');
    expect(dark.textTheme.bodyMedium?.fontFamily, 'Segoe UI');
    expect(light.scaffoldBackgroundColor.a, 1);
    expect(dark.scaffoldBackgroundColor.a, 1);
    expect(light.inputDecorationTheme.filled, isTrue);
    expect(dark.inputDecorationTheme.filled, isTrue);
    expect(light.appBarTheme.surfaceTintColor, Colors.transparent);
    expect(dark.appBarTheme.surfaceTintColor, Colors.transparent);
  });
}
