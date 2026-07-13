class HotkeyAccelerator {
  static const _modifierAliases = {
    'ctrl': 'Ctrl',
    'control': 'Ctrl',
    'alt': 'Alt',
    'option': 'Alt',
    'shift': 'Shift',
    'win': 'Win',
    'super': 'Win',
    'meta': 'Win',
  };
  static const _modifierOrder = ['Ctrl', 'Alt', 'Shift', 'Win'];
  static const _namedKeys = {
    'space': 'Space',
    'tab': 'Tab',
    'enter': 'Enter',
    'return': 'Enter',
    'esc': 'Escape',
    'escape': 'Escape',
    'left': 'Left',
    'right': 'Right',
    'up': 'Up',
    'down': 'Down',
  };

  final Set<String> modifiers;
  final String key;

  const HotkeyAccelerator._(this.modifiers, this.key);

  String get canonical => [
        for (final modifier in _modifierOrder)
          if (modifiers.contains(modifier)) modifier,
        key,
      ].join('+');

  factory HotkeyAccelerator.parse(String raw) {
    final modifiers = <String>{};
    String? key;
    for (final rawToken in raw.split('+')) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;
      final lower = token.toLowerCase();
      final modifier = _modifierAliases[lower];
      if (modifier != null) {
        modifiers.add(modifier);
        continue;
      }
      final parsedKey = _parseKey(lower);
      if (parsedKey == null || key != null) {
        throw const FormatException('快捷键必须包含一个受支持的按键');
      }
      key = parsedKey;
    }
    if (modifiers.isEmpty) {
      throw const FormatException('全局快捷键至少需要一个修饰键');
    }
    if (key == null) {
      throw const FormatException('快捷键缺少主按键');
    }
    return HotkeyAccelerator._(Set.unmodifiable(modifiers), key);
  }

  static Map<String, List<String>> duplicateCanonicalValues(
    Map<String, String> actions,
  ) {
    final grouped = <String, List<String>>{};
    for (final entry in actions.entries) {
      final canonical = HotkeyAccelerator.parse(entry.value).canonical;
      grouped.putIfAbsent(canonical, () => []).add(entry.key);
    }
    grouped.removeWhere((_, labels) => labels.length < 2);
    return grouped;
  }

  static String? _parseKey(String lower) {
    if (lower.length == 1) {
      final code = lower.codeUnitAt(0);
      final isLetter = code >= 0x61 && code <= 0x7a;
      final isDigit = code >= 0x30 && code <= 0x39;
      if (isLetter || isDigit) return lower.toUpperCase();
    }
    if (lower.startsWith('f')) {
      final number = int.tryParse(lower.substring(1));
      if (number != null && number >= 1 && number <= 24) return 'F$number';
    }
    return _namedKeys[lower];
  }
}
