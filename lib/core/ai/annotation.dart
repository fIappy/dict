/// One run of text with the marks it carries.
class AnnotatedSpan {
  const AnnotatedSpan({
    required this.text,
    required this.isThemeWord,
    required this.isPhrase,
  });

  final String text;

  /// The token is part of the open theme's vocabulary.
  final bool isThemeWord;

  /// The run is inside a collocation the model called out.
  final bool isPhrase;

  @override
  String toString() =>
      '"$text"${isThemeWord ? ' theme' : ''}${isPhrase ? ' phrase' : ''}';
}

final RegExp _token = RegExp(r"[A-Za-z][A-Za-z'’-]*");

/// Slices [text] so the view can mark two things independently:
///
/// * tokens that belong to the theme's vocabulary (plurals and simple
///   inflections match their base form), and
/// * the spans the model reported as fixed collocations.
///
/// Both can cover the same characters — "take care of" may itself contain a
/// theme word — so the marks are flags on a span, not a nesting.
List<AnnotatedSpan> annotateText(
  String text, {
  required Set<String> themeWords,
  List<String> phrases = const [],
}) {
  if (text.isEmpty) return const [];

  final lower = text.toLowerCase();
  final marks = <_Mark>[];

  for (final match in _token.allMatches(text)) {
    // "coach's" and "coaches'" are still the theme word underneath.
    final word = match
        .group(0)!
        .toLowerCase()
        .replaceAll(RegExp(r"['’]s$"), '')
        .replaceAll(RegExp(r"['’’-]+$"), '');
    if (!_isThemeWord(word, themeWords)) continue;
    marks.add(_Mark(match.start, match.end, theme: true));
  }

  for (final phrase in phrases) {
    final needle = phrase.toLowerCase().trim();
    if (needle.isEmpty) continue;
    var from = 0;
    while (true) {
      final at = lower.indexOf(needle, from);
      if (at < 0) break;
      from = at + needle.length;
      final before = at == 0 ? 0x20 : lower.codeUnitAt(at - 1);
      final after = from >= lower.length ? 0x20 : lower.codeUnitAt(from);
      if (_isLetter(before) || _isLetter(after)) continue;
      marks.add(_Mark(at, from, phrase: true));
    }
  }

  if (marks.isEmpty) {
    return [AnnotatedSpan(text: text, isThemeWord: false, isPhrase: false)];
  }

  // Cut at every mark boundary, then read the flags of each slice.
  final cuts = <int>{0, text.length};
  for (final mark in marks) {
    cuts.add(mark.start);
    cuts.add(mark.end);
  }
  final sorted = cuts.toList()..sort();

  final spans = <AnnotatedSpan>[];
  for (var i = 0; i + 1 < sorted.length; i++) {
    final start = sorted[i];
    final end = sorted[i + 1];
    if (start >= end) continue;
    var theme = false;
    var phrase = false;
    for (final mark in marks) {
      if (mark.start <= start && mark.end >= end) {
        theme = theme || mark.theme;
        phrase = phrase || mark.phrase;
      }
    }
    spans.add(AnnotatedSpan(
      text: text.substring(start, end),
      isThemeWord: theme,
      isPhrase: phrase,
    ));
  }
  return spans;
}

/// A plural or a simple inflection counts as the theme word: a passage about
/// 体育运动 saying "coaches" is still using "coach".
bool _isThemeWord(String token, Set<String> themeWords) {
  if (themeWords.contains(token)) return true;
  for (final suffix in const ['s', 'es', 'ed', 'd', 'ing']) {
    if (!token.endsWith(suffix)) continue;
    final stem = token.substring(0, token.length - suffix.length);
    if (stem.length < 3) continue;
    if (themeWords.contains(stem)) return true;
  }
  return false;
}

bool _isLetter(int code) =>
    (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

class _Mark {
  const _Mark(this.start, this.end, {this.theme = false, this.phrase = false});

  final int start;
  final int end;
  final bool theme;
  final bool phrase;
}
