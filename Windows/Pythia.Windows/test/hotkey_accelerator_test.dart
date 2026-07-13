import 'package:flutter_test/flutter_test.dart';
import 'package:pythia_windows/core/hotkey_accelerator.dart';

void main() {
  test('normalizes aliases and modifier order for native registration', () {
    expect(
      HotkeyAccelerator.parse('shift + control + p').canonical,
      'Ctrl+Shift+P',
    );
    expect(
      HotkeyAccelerator.parse('meta+option+f12').canonical,
      'Alt+Win+F12',
    );
  });

  test('rejects missing modifier, missing key, and unsupported key', () {
    expect(() => HotkeyAccelerator.parse('P'), throwsFormatException);
    expect(() => HotkeyAccelerator.parse('Ctrl+Alt'), throwsFormatException);
    expect(
      () => HotkeyAccelerator.parse('Ctrl+Alt+Comma'),
      throwsFormatException,
    );
  });

  test('detects duplicate actions after normalization', () {
    expect(
      HotkeyAccelerator.duplicateCanonicalValues({
        '显示窗口': 'Ctrl+Alt+P',
        '划词翻译': 'alt+ctrl+p',
        '截图翻译': 'Ctrl+Alt+S',
      }),
      {
        'Ctrl+Alt+P': ['显示窗口', '划词翻译']
      },
    );
  });

  test('supports every key token accepted by the native parser', () {
    for (final key in [
      'A',
      '9',
      'F1',
      'F24',
      'Space',
      'Tab',
      'Enter',
      'Escape',
      'Left',
      'Right',
      'Up',
      'Down',
    ]) {
      expect(HotkeyAccelerator.parse('Ctrl+$key').key, key);
    }
  });
}
