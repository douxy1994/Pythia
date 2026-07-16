import 'package:flutter/material.dart';

import '../core/translation_service.dart';
import 'source_text_field.dart';
import 'translation_result_card.dart';

class PythiaTranslationWorkspace extends StatelessWidget {
  static const resultsRegionKey = Key('pythia-results-region');

  final TextEditingController sourceController;
  final FocusNode sourceFocusNode;
  final VoidCallback? onSubmit;
  final VoidCallback? onCopySource;
  final VoidCallback? onPasteSource;
  final VoidCallback? onStripNewlines;
  final VoidCallback? onClearSource;
  final VoidCallback? onCopyResults;
  final String sourceLanguageLabel;
  final String targetLanguageLabel;
  final List<PythiaTranslationResult> results;

  const PythiaTranslationWorkspace({
    super.key,
    required this.sourceController,
    required this.sourceFocusNode,
    required this.onSubmit,
    this.onCopySource,
    this.onPasteSource,
    this.onStripNewlines,
    this.onClearSource,
    this.onCopyResults,
    required this.sourceLanguageLabel,
    required this.targetLanguageLabel,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PythiaSourceTextField(
          controller: sourceController,
          focusNode: sourceFocusNode,
          onSubmit: onSubmit,
          languageLabel: sourceLanguageLabel,
          actions: [
            IconButton(
              tooltip: '复制原文',
              visualDensity: VisualDensity.compact,
              onPressed: onCopySource,
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            IconButton(
              tooltip: '粘贴',
              visualDensity: VisualDensity.compact,
              onPressed: onPasteSource,
              icon: const Icon(Icons.content_paste_outlined, size: 18),
            ),
            IconButton(
              tooltip: '删除换行',
              visualDensity: VisualDensity.compact,
              onPressed: onStripNewlines,
              icon: const Icon(Icons.format_clear, size: 18),
            ),
            IconButton(
              tooltip: '清空原文',
              visualDensity: VisualDensity.compact,
              onPressed: onClearSource,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          key: resultsRegionKey,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '译文（$targetLanguageLabel）',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '复制全部译文',
                        visualDensity: VisualDensity.compact,
                        onPressed: results.any((result) => result.isSuccess)
                            ? onCopyResults
                            : null,
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Text(
                            '译文将在这里按服务顺序显示',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemCount: results.length,
                          itemBuilder: (context, index) =>
                              PythiaTranslationResultCard(
                            key: ValueKey(results[index].serviceId),
                            result: results[index],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
