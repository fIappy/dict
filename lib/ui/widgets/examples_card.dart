import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ExamplesCard extends StatelessWidget {
  final List<String> examples;
  final String targetWord;

  const ExamplesCard({
    super.key,
    required this.examples,
    required this.targetWord,
  });

  @override
  Widget build(BuildContext context) {
    if (examples.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E2430) : const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '精选例句 (${examples.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: examples.length,
              separatorBuilder: (_, _) => const Divider(height: 20),
              itemBuilder: (context, index) {
                final ex = examples[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildHighlightedSentence(ex, targetWord, theme),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: '复制例句',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ex));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已复制例句'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedSentence(String sentence, String word, ThemeData theme) {
    final lowerSentence = sentence.toLowerCase();
    final lowerWord = word.toLowerCase();
    final idx = lowerSentence.indexOf(lowerWord);

    if (idx == -1) {
      return Text(
        sentence,
        style: const TextStyle(fontSize: 14.5, height: 1.5),
      );
    }

    final before = sentence.substring(0, idx);
    final match = sentence.substring(idx, idx + word.length);
    final after = sentence.substring(idx + word.length);

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 14.5,
          height: 1.5,
          color: theme.textTheme.bodyMedium?.color,
        ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
