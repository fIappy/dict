import 'package:flutter/material.dart';

import '../../core/ai/annotation.dart';
import '../../core/custom/custom_text.dart';
import 'speakable_selection.dart';

/// Generated English with two marks on it: theme vocabulary in red, and the
/// collocations the model flagged underlined.
///
/// Caches annotation spans and sentence segmentation across highlight-only
/// rebuilds while a passage is being read aloud.
class AnnotatedText extends StatefulWidget {
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
  State<AnnotatedText> createState() => _AnnotatedTextState();
}

class _AnnotatedTextState extends State<AnnotatedText> {
  List<AnnotatedSpan>? _wholeSpans;
  List<({PassageSegment segment, List<AnnotatedSpan> spans})>? _segmentSpans;

  @override
  void didUpdateWidget(covariant AnnotatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        !identical(oldWidget.themeWords, widget.themeWords) ||
        !identical(oldWidget.phrases, widget.phrases)) {
      _wholeSpans = null;
      _segmentSpans = null;
    }
  }

  List<AnnotatedSpan> _cachedWholeSpans() => _wholeSpans ??= annotateText(
        widget.text,
        themeWords: widget.themeWords,
        phrases: widget.phrases,
      );

  List<({PassageSegment segment, List<AnnotatedSpan> spans})>
      _cachedSegmentSpans() {
    if (_segmentSpans != null) return _segmentSpans!;
    final segments = passageSegments(widget.text);
    return _segmentSpans = [
      for (final seg in segments)
        (
          segment: seg,
          spans: annotateText(
            seg.text,
            themeWords: widget.themeWords,
            phrases: widget.phrases,
          ),
        ),
    ];
  }

  static TextSpan _buildAnnotatedSpan(
    List<AnnotatedSpan> spans,
    Color error,
  ) =>
      TextSpan(
        children: [
          for (final span in spans)
            TextSpan(
              text: span.text,
              style: TextStyle(
                color: span.isThemeWord ? error : null,
                fontWeight: span.isThemeWord ? FontWeight.w600 : null,
                decoration: span.isPhrase ? TextDecoration.underline : null,
                decorationStyle:
                    span.isPhrase ? TextDecorationStyle.dotted : null,
                decorationColor:
                    span.isPhrase ? error.withValues(alpha: 0.7) : null,
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final speaking = widget.speakingIndex;

    if (speaking == null) {
      return SpeakableText.rich(
        _buildAnnotatedSpan(_cachedWholeSpans(), error),
        style: widget.style,
      );
    }

    final segments = _cachedSegmentSpans();
    return SpeakableText.rich(
      TextSpan(
        children: [
          for (final entry in segments) ...[
            TextSpan(
              children: [_buildAnnotatedSpan(entry.spans, error)],
              style: entry.segment.sentenceIndex == speaking
                  ? TextStyle(
                      color: error,
                      fontWeight: FontWeight.w700,
                      backgroundColor: error.withValues(alpha: 0.08),
                    )
                  : null,
            ),
            if (entry.segment.separator.isNotEmpty)
              TextSpan(text: entry.segment.separator),
          ],
        ],
      ),
      style: widget.style,
    );
  }
}
