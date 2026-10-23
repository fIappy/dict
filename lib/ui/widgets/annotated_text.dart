import 'package:flutter/material.dart';

import '../../core/ai/annotation.dart';
import '../../core/custom/custom_text.dart';
import 'speakable_selection.dart';

/// Generated English with two marks on it: theme vocabulary in red, and the
/// collocations the model flagged underlined.
class AnnotatedText extends StatelessWidget {
  const AnnotatedText(
    this.text, {
    super.key,
    required this.themeWords,
    this.phrases = const [],
    this.style,
    this.speakingIndex,
  });

  final String text;
  final Set<String> themeWords;
  final List<String> phrases;
  final TextStyle? style;

  /// Index (in [splitSentences] order) of the sentence being read; that one is
  /// drawn in red while the rest keep the normal colour.
  final int? speakingIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    final speaking = speakingIndex;

    TextSpan spansOf(String source) {
      final spans = annotateText(source, themeWords: themeWords, phrases: phrases);
      return TextSpan(
        children: [
          for (final span in spans)
            TextSpan(
              text: span.text,
              style: TextStyle(
                color: span.isThemeWord ? error : null,
                fontWeight: span.isThemeWord ? FontWeight.w600 : null,
                decoration: span.isPhrase ? TextDecoration.underline : null,
                decorationStyle: span.isPhrase ? TextDecorationStyle.dotted : null,
                decorationColor: span.isPhrase ? error.withValues(alpha: 0.7) : null,
              ),
            ),
        ],
      );
    }

    // Nothing is being read here: one pass, so the paragraph keeps its own
    // line breaks and spacing.
    if (speaking == null) {
      return SpeakableText.rich(spansOf(text), style: style);
    }

    // A sentence is sounding: render sentence by sentence so that one can be
    // red. The words inside each sentence keep their annotations.
    // Line breaks and spacing are kept: the segments carry the separators that
    // were in the source, so a one-sentence-per-line article stays laid out.
    final segments = passageSegments(text);
    return SpeakableText.rich(
      TextSpan(
        children: [
          for (final segment in segments) ...[
            TextSpan(
              children: [spansOf(segment.text)],
              style: segment.sentenceIndex == speaking
                  ? TextStyle(
                      color: error,
                      fontWeight: FontWeight.w700,
                      backgroundColor: error.withValues(alpha: 0.08),
                    )
                  : null,
            ),
            if (segment.separator.isNotEmpty)
              TextSpan(text: segment.separator),
          ],
        ],
      ),
      style: style,
    );
  }
}
