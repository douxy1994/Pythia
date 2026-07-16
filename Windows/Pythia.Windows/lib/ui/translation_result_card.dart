import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/translation_service.dart';

class PythiaTranslationResultCard extends StatefulWidget {
  final PythiaTranslationResult result;

  const PythiaTranslationResultCard({
    super.key,
    required this.result,
  });

  @override
  State<PythiaTranslationResultCard> createState() =>
      _PythiaTranslationResultCardState();
}

class _PythiaTranslationResultCardState
    extends State<PythiaTranslationResultCard> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final colors = Theme.of(context).colorScheme;
    final content = result.isSuccess ? result.text : result.errorMessage!;
    return Card(
      color: result.isSuccess ? colors.surfaceContainer : colors.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => expanded = !expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      result.serviceName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (result.isSuccess)
                    IconButton(
                      tooltip: '复制译文',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: result.text),
                      ),
                    ),
                  IconButton(
                    key: Key('result-toggle-${result.serviceId}'),
                    tooltip: expanded ? '收起' : '展开',
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: () => setState(() => expanded = !expanded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SelectableText(
                      content,
                      key: Key('result-content-${result.serviceId}'),
                      style: TextStyle(
                        color: result.isSuccess
                            ? colors.onSurface
                            : colors.onErrorContainer,
                        height: 1.45,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
