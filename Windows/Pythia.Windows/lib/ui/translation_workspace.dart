import 'package:flutter/material.dart';

import '../core/translation_service.dart';
import 'source_text_field.dart';
import 'translation_result_card.dart';

class PythiaTranslationWorkspace extends StatelessWidget {
  static const resultsRegionKey = Key('pythia-results-region');

  final TextEditingController sourceController;
  final FocusNode sourceFocusNode;
  final VoidCallback? onSubmit;
  final String sourceLanguageLabel;
  final String targetLanguageLabel;
  final List<PythiaTranslationResult> results;

  const PythiaTranslationWorkspace({
    super.key,
    required this.sourceController,
    required this.sourceFocusNode,
    required this.onSubmit,
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '译文（$targetLanguageLabel）',
                    style: Theme.of(context).textTheme.titleSmall,
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
