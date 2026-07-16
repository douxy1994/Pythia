import 'package:flutter/material.dart';

import '../core/service_selection.dart';

class PythiaServiceOption {
  final String id;
  final String label;

  const PythiaServiceOption(this.id, this.label);
}

class PythiaServicePickerButton extends StatelessWidget {
  static const buttonKey = Key('pythia-service-picker-button');
  static const dialogKey = Key('pythia-service-picker-dialog');

  final List<PythiaServiceOption> options;
  final List<String> selectedServiceIds;
  final ValueChanged<List<String>> onSelectionChanged;

  const PythiaServicePickerButton({
    super.key,
    required this.options,
    required this.selectedServiceIds,
    required this.onSelectionChanged,
  });

  Future<void> _open(BuildContext context) async {
    var selected = selectedServiceIds.toList();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final optionById = {for (final option in options) option.id: option};
          final orderedOptions = <PythiaServiceOption>[
            for (final id in selected)
              if (optionById[id] != null) optionById[id]!,
            for (final option in options)
              if (!selected.contains(option.id)) option,
          ];
          void apply(List<String> next) {
            setDialogState(() => selected = next);
            onSelectionChanged(next);
          }

          return AlertDialog(
            key: dialogKey,
            title: const Text('翻译服务'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    '可持续多选；新服务加入顶部，使用箭头调整结果顺序。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final option in orderedOptions)
                    Row(
                      key: Key('service-option-${option.id}'),
                      children: [
                        Checkbox(
                          value: selected.contains(option.id),
                          onChanged: (value) => apply(
                            TranslateServiceSelection.toggle(
                              current: selected,
                              serviceId: option.id,
                              selected: value ?? false,
                            ),
                          ),
                        ),
                        Expanded(child: Text(option.label)),
                        if (selected.contains(option.id)) ...[
                          IconButton(
                            key: Key('service-up-${option.id}'),
                            tooltip: '上移',
                            onPressed: selected.indexOf(option.id) == 0
                                ? null
                                : () => apply(
                                      TranslateServiceSelection.move(
                                        current: selected,
                                        serviceId: option.id,
                                        offset: -1,
                                      ),
                                    ),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            key: Key('service-down-${option.id}'),
                            tooltip: '下移',
                            onPressed: selected.indexOf(option.id) ==
                                    selected.length - 1
                                ? null
                                : () => apply(
                                      TranslateServiceSelection.move(
                                        current: selected,
                                        serviceId: option.id,
                                        offset: 1,
                                      ),
                                    ),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: () => _open(context),
      icon: const Icon(Icons.tune),
      label: Text('服务（${selectedServiceIds.length}）'),
    );
  }
}
