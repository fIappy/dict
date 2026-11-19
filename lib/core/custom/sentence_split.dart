// Engine: Dart (pure) | Target: lib/core/custom
//
// One line per sentence, even when the transcript arrived with several in one.
//
// The reader speaks a line as one utterance, so "Ok? Let’s go!" said as one
// sentence drops the question and runs the two together. Splitting at the marks
// the text already carries is safe; the harder half is the run-ons that never
// got a mark at all ("… with her He doesn’t want to go with her"), where a
// capital pronoun or determiner after a lowercase word is the only signal.

/// Abbreviations whose full stop is not the end of a sentence.
final RegExp _abbreviation = RegExp(
  r'(?:Mr|Mrs|Ms|Dr|Prof|St|No|vs|etc|e\.g|i\.e|a\.m|p\.m)$',
  caseSensitive: false,
);

/// A sentence mark, an optional closing quote or bracket, then whitespace.
final RegExp _terminal = RegExp(r'''([.!?…])([”’"')]*)(\s+)''');

/// Words that only start a sentence in this material: pronouns (except "I",
/// which also appears mid-sentence), determiners, wh-words, discourse markers.
final RegExp _sentenceStarter = RegExp(
  r'(?:He|She|It|We|They|You|The|This|That|These|Those|My|His|Her|Their|Our|'
  r'There|What|When|Where|Who|Why|How|If|And|But|So|Because|Now|OK|Ok|Yes|No|'
  r'Maybe|Just|Let|Look|Notice|Today|Then|Also|First|Next|Finally|'
  r'Do|Does|Did|Is|Are|Was|Were|Have|Has|Had|Can|Could|Will|Would|Should|'
  r'May|Might|Must)\b',
);

/// A question the transcript never punctuated: "… with her why is he …?"
final RegExp _lowerQuestion = RegExp(
  r'(?:what|why|when|where|who|how)\s+'
  r'(?:is|are|was|were|do|does|did|can|could|will|would|should|have|has|had)\b',
);

/// Lines shorter than this are left alone by the unpunctuated-run-on split: a
/// short line with a capital mid-way is usually a name ("I met Mr. Smith").
const int _runOnLength = 120;

/// [line] cut into one sentence per entry.
///
/// Every piece closes with a sentence mark; pieces the transcript never
/// punctuated get one so the reader still falls at the end.
List<String> splitSentenceLine(String line) {
  final pieces = <String>[];
  final text = line.trim();
  if (text.isEmpty) return pieces;

  var start = 0;
  for (final match in _terminal.allMatches(text)) {
    final before = text.substring(0, match.start + 1);
    final tail = RegExp(r'(\S+)$').firstMatch(before)?.group(1) ?? '';
    final token = tail.replaceAll(RegExp(r'''[”’"').]+$'''), '');
    if (match.group(1) == '.' && _abbreviation.hasMatch(token)) continue;
    // "3.14", "11.30" — a dot between digits is not a full stop.
    final dotIndex = match.start;
    if (dotIndex > 0 &&
        text[dotIndex - 1].isNotEmpty &&
        _isDigit(text[dotIndex - 1]) &&
        match.end < text.length &&
        _isDigit(text[match.end])) {
      continue;
    }
    final rest = text.substring(match.end);
    if (rest.isEmpty) continue;
    final first = rest[0];
    if (!_isUpper(first) && first != '“' && first != '"' && first != '‘') {
      continue;
    }
    pieces.add(text.substring(start, match.end).trim());
    start = match.end;
  }
  pieces.add(text.substring(start).trim());

  final out = <String>[];
  for (final piece in pieces) {
    if (piece.isEmpty) continue;
    final parts = piece.length > _runOnLength ? _splitRunOn(piece) : [piece];
    for (final part in parts) {
      final closed = _close(part);
      if (closed.isNotEmpty) out.add(closed);
    }
  }
  return out;
}

bool _isDigit(String char) => '0123456789'.contains(char);

bool _isUpper(String char) => char.toUpperCase() == char && char.toLowerCase() != char;

/// Splits a long run-on where a new sentence starts at a capital pronoun or
/// determiner after a lowercase word: "… with her He doesn’t want …".
List<String> _splitRunOn(String text) {
  final cuts = <int>[];
  final asksQuestion = text.trimRight().endsWith('?');
  for (final match in RegExp(r'(\s+)').allMatches(text)) {
    final at = match.start;
    if (at == 0) continue;
    final before = text[at - 1];
    if (!_isLower(before) && before != '”' && before != '"' && before != '’') {
      continue;
    }
    final rest = text.substring(match.end);
    final startsSentence = _sentenceStarter.matchAsPrefix(rest) != null;
    final asksAgain = asksQuestion && _lowerQuestion.matchAsPrefix(rest) != null;
    if (!startsSentence && !asksAgain) continue;
    cuts.add(at);
  }
  if (cuts.isEmpty) return [text];

  final parts = <String>[];
  var start = 0;
  for (final at in cuts) {
    final piece = text.substring(start, at).trim();
    if (piece.length >= 30) {
      parts.add(_upperFirst(piece));
      start = at;
    }
  }
  parts.add(_upperFirst(text.substring(start).trim()));
  return parts;
}

bool _isLower(String char) => char.toLowerCase() == char && char.toUpperCase() != char;

/// [piece] with a capital first letter, quotes left alone.
String _upperFirst(String piece) {
  if (piece.isEmpty) return piece;
  final first = piece[0];
  if (_isUpper(first) || !_isLower(first)) return piece;
  return first.toUpperCase() + piece.substring(1);
}

/// [piece] with a sentence mark at the end, inside any closing quote.
String _close(String piece) {
  final text = piece.trim();
  if (text.isEmpty) return text;
  final last = text[text.length - 1];
  if ('.!?…'.contains(last)) return text;
  const closers = {'”', '"', '’', ')', ']'};
  if (closers.contains(last)) {
    final before = text[text.length - 2];
    if ('.!?…'.contains(before)) return text;
    return '${text.substring(0, text.length - 1)}.$last';
  }
  return '$text.';
}
