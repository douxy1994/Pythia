import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/text_submission_policy.dart';

class PythiaSourceTextField extends StatefulWidget {
  static const regionKey = Key('pythia-source-region');
  static const inputKey = Key('pythia-source-input');
  static const double height = 176;

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;
  final String languageLabel;

  const PythiaSourceTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.languageLabel,
  });

  @override
  State<PythiaSourceTextField> createState() => _PythiaSourceTextFieldState();
}

class _PythiaSourceTextFieldState extends State<PythiaSourceTextField> {
  final scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final composing = widget.controller.value.composing;
    final decision = TextSubmissionPolicy.resolve(
      isKeyDown: event is KeyDownEvent,
      isEnter: event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter,
      isComposing: composing.isValid && !composing.isCollapsed,
      isShiftPressed: keyboard.isShiftPressed,
      isControlPressed: keyboard.isControlPressed,
      isAltPressed: keyboard.isAltPressed,
      isMetaPressed: keyboard.isMetaPressed,
    );
    if (decision == TextSubmissionDecision.submit && widget.onSubmit != null) {
      widget.onSubmit!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: PythiaSourceTextField.regionKey,
      height: PythiaSourceTextField.height,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: TextField(
            key: PythiaSourceTextField.inputKey,
            controller: widget.controller,
            focusNode: widget.focusNode,
            scrollController: scrollController,
            expands: true,
            minLines: null,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              labelText: '原文（${widget.languageLabel}）',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ),
    );
  }
}
