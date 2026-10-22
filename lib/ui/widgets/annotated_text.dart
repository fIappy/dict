import 'package:flutter/material.dart';

import '../../core/ai/annotation.dart';
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
  });

  final String text;
  final Set<String> themeWords;
  final List<String> phrases;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final spans = annotateText(text, themeWords: themeWords, phrases: phrases);
    return SpeakableText.rich(
      TextSpan(
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
      ),
      style: style,
    );
  }
}
