import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HotkeyRecorderField extends StatefulWidget {
  final TextEditingController controller;
  final String label;

  const HotkeyRecorderField({
    super.key,
    required this.controller,
    required this.label,
  });

  @override
  State<HotkeyRecorderField> createState() => _HotkeyRecorderFieldState();
}

class _HotkeyRecorderFieldState extends State<HotkeyRecorderField> {
  final focusNode = FocusNode();
  bool recording = false;
  String? errorText;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      recording = true;
      errorText = null;
    });
    focusNode.requestFocus();
  }

  void _stopRecording() {
    setState(() {
      recording = false;
      errorText = null;
    });
    focusNode.unfocus();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!recording || event is! KeyDownEvent) return;
    final keyboard = HardwareKeyboard.instance;
    final key = _tokenForKey(event.logicalKey);
    if (key == null) return;
    final modifiers = <String>[
      if (keyboard.isControlPressed) 'Ctrl',
      if (keyboard.isAltPressed) 'Alt',
      if (keyboard.isShiftPressed) 'Shift',
      if (keyboard.isMetaPressed) 'Win',
    ];
    if (key == 'Escape' && modifiers.isEmpty) {
      _stopRecording();
      return;
    }
    if (modifiers.isEmpty) {
      setState(() => errorText = '请同时按下 Ctrl、Alt、Shift 或 Win');
      return;
    }
    widget.controller.text = [...modifiers, key].join('+');
    _stopRecording();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: KeyboardListener(
        focusNode: focusNode,
        onKeyEvent: _handleKeyEvent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _startRecording,
          child: InputDecorator(
            isFocused: recording,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: errorText,
              helperText: recording ? '请按下快捷键，Esc 取消' : '点击后直接按下新的组合键',
              suffixIcon: IconButton(
                tooltip: recording ? '取消录制' : '录制快捷键',
                onPressed: recording ? _stopRecording : _startRecording,
                icon: Icon(recording ? Icons.close : Icons.keyboard_outlined),
              ),
            ),
            child: SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) => Text(
                    recording ? '正在录制…' : widget.controller.text,
                    style: TextStyle(
                      color: recording ? colors.primary : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _tokenForKey(LogicalKeyboardKey key) {
  final label = key.keyLabel;
  if (RegExp(r'^[A-Za-z0-9]$').hasMatch(label)) return label.toUpperCase();
  final functionIndex = _functionKeys.indexOf(key);
  if (functionIndex >= 0) return 'F${functionIndex + 1}';
  return _namedKeys[key];
}

final _namedKeys = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.escape: 'Escape',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
};

const _functionKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
  LogicalKeyboardKey.f20,
  LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22,
  LogicalKeyboardKey.f23,
  LogicalKeyboardKey.f24,
];
