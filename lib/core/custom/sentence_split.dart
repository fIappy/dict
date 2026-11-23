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
  // "way:." is the double mark older builds shipped; the colon already pauses.
  final text = line.trim().replaceAllMapped(
    RegExp(r'([:;])\.$'),
    (match) => match.group(1)!,
  );
  if (text.isEmpty) return pieces;

  var start = 0;
  for (final match in _terminal.allMatches(text)) {
    final before = text.substring(0, match.start + 1);
    final tail = RegExp(r'(\S+)$').firstMatch(before)?.group(1) ?? '';
    final token = tail.replaceAll(RegExp(r'''[”’"').]+$'''), '');
    if (match.group(1) == '.' && _abbreviation.hasMatch(token)) continue;
    // "3. I turned on my computer." — a numbered list item, not two sentences.
    final lead = text.substring(start, match.start).trim();
    if (match.group(1) == '.' && RegExp(r'^\d{1,3}$').hasMatch(lead)) continue;
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
      for (final clause in _splitClauses(part)) {
        final closed = _close(clause);
        if (closed.isNotEmpty) out.add(closed);
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Clauses inside a line that never got sentence marks.
//
// The Udemy transcripts and the YouTube captions arrive as one breath: "Subject
// “Lisa” before it we have the indicative word “does”, because Lisa is a she
// and after it we have our verb “drink” without the ending “s”." Read as one
// utterance that runs out of air, so the rule set below cuts where English
// itself puts a full stop — before a coordinating or subordinating conjunction
// that introduces a new subject and verb, after a tag question ("… right"),
// before a wh-question embedded after a finished clause.
//
// Precision beats coverage on purpose: a wrong break turns one long line into
// two fragments, which sounds worse than the run-on. Every rule therefore wants
// four words and a finite verb on both sides, and every rule skips text inside
// quotes — the quote's own punctuation is not the line's.

/// Lines shorter than this keep their commas: a 60-character caption is one
/// clause in practice, and the clause rules would only cut it in half.
const int _clauseSplitLength = 90;

final RegExp _clauseCoord =
    RegExp(r',\s+(and|but|so|because|then|or)\b', caseSensitive: false);
final RegExp _bareConjunction =
    RegExp(r'\s+(because|so|but)\b\s', caseSensitive: false);
final RegExp _tagWord =
    RegExp(r'\s+(right|okay)\b,?\s+', caseSensitive: false);
final RegExp _andAfter =
    RegExp(r'\s+and\s+(after|before)\b', caseSensitive: false);
final RegExp _whQuestion = RegExp(
  r'\b(what|why|where|who|when|how)\s+'
  r'(is|are|was|were|do|does|did|can|could|would|will|should)\b',
  caseSensitive: false,
);
final RegExp _subordinate = RegExp(
  r'\s+(because|if|when|unless|although|though|which)\b',
  caseSensitive: false,
);
final RegExp _andAdverb =
    RegExp(r'\s+(and then|and now|and so)\b', caseSensitive: false);

/// A clause needs a verb before it can be a sentence.
final RegExp _finiteVerb = RegExp(
  r'\b(is|are|was|were|do|does|did|have|has|had|can|could|would|will|should|'
  r'mean|means|make|makes|take|takes|live|lives|say|says|go|goes|get|gets|'
  r'use|uses|need|needs|want|wants|see|sees|like|likes|call|calls|think|know|'
  r'change|changes|put|puts|talk|talks|give|gives|find|finds|let|lets|'
  r'not|no|never|\w+ed)\b',
  caseSensitive: false,
);

final RegExp _clauseSubject = RegExp(
  r'^(i|you|he|she|it|we|they|the|this|that|these|those|there|my|your|his|'
  r'her|their|our|some|most|many|people|nobody|everybody|everyone|a|an)\b',
  caseSensitive: false,
);

const Set<String> _auxAfterSubject = {
  'is', 'are', 'was', 'were', 'does', 'do', 'did', 'has', 'have', 'had',
  'can', 'could', 'would', 'will', 'should',
};

/// Words a conjunction must not follow: a clause rarely ends on one, and a
/// split behind "the" or "to" cuts a noun phrase in half.
const Set<String> _notBeforeConjunction = {
  'that', 'and', 'or', 'but', 'so', 'because', 'to', 'the', 'a', 'an', 'of',
  'in', 'on', 'for', 'with', 'at', 'by',
};

const Set<String> _determiners = {
  'the', 'a', 'an', 'its', 'your', 'my', 'his', 'her', 'their', 'our', 'this',
  'that', 'in', 'on', 'at', 'to',
};

List<bool> _quotedFlags(String text) {
  final flags = List<bool>.filled(text.length, false);
  final closers = <String>[];
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '“' || char == '‘') {
      closers.add(char == '“' ? '”' : '’');
      flags[i] = true;
      continue;
    }
    if (char == '"') {
      if (closers.isNotEmpty && closers.last == '"') {
        closers.removeLast();
      } else {
        closers.add('"');
      }
      flags[i] = true;
      continue;
    }
    if (closers.isNotEmpty && char == closers.last) {
      closers.removeLast();
      flags[i] = true;
      continue;
    }
    flags[i] = closers.isNotEmpty;
  }
  return flags;
}

int _wordCount(String text) => RegExp(r"[\w’']+").allMatches(text).length;

String _previousWord(String text) {
  final match = RegExp(r"[\w’']+$").firstMatch(text.trimRight());
  return match?.group(0)?.toLowerCase() ?? '';
}

/// Where group [group] starts inside [match]. Dart's [Match] only exposes the
/// whole match's start, and every pattern here has a literal prefix.
int _groupStart(RegExpMatch match, int group) {
  final whole = match.group(0) ?? '';
  final piece = match.group(group);
  if (piece == null || piece.isEmpty) return match.start;
  final offset = whole.indexOf(piece);
  return match.start + (offset < 0 ? 0 : offset);
}

/// Whether [text] opens like a new clause: a subject with a verb nearby, or a
/// name followed by "is/does/…" ("Lisa is a she").
bool _startsClause(String text) {
  final trimmed = text.trimLeft();
  final head = RegExp(r"^([\w’'-]+)\s+([\w’'-]+)").firstMatch(trimmed);
  if (head == null) return false;
  final window = trimmed.length > 70 ? trimmed.substring(0, 70) : trimmed;
  if (_clauseSubject.hasMatch(trimmed) && _finiteVerb.hasMatch(window)) {
    return true;
  }
  return _auxAfterSubject.contains(head.group(2)!.toLowerCase());
}

/// [text] cut at clause boundaries, or [text] unchanged when none is sure.
List<String> _splitClauses(String text) {
  if (text.length < _clauseSplitLength) return [text];
  final quoted = _quotedFlags(text);
  final splits = <int>{};
  final commas = <int>{};

  bool inside(int at) => at >= 0 && at < quoted.length && quoted[at];

  void addSplit(int at) {
    if (at <= 0 || at >= text.length) return;
    final head = text.substring(0, at).trim();
    final tail = text.substring(at).trim();
    if (_wordCount(head) < 4 || _wordCount(tail) < 4) return;
    if (!_finiteVerb.hasMatch(head) || !_finiteVerb.hasMatch(tail)) return;
    splits.add(at);
  }

  void addComma(int at) {
    if (at <= 0 || at >= text.length) return;
    if (_wordCount(text.substring(0, at)) < 5) return;
    if (_wordCount(text.substring(at)) < 3) return;
    commas.add(at);
  }

  // ", and/but/so/because …" already carries the comma: split before the
  // conjunction itself, so the comma goes with the sentence it ends.
  for (final match in _clauseCoord.allMatches(text)) {
    if (inside(match.start)) continue;
    final at = _groupStart(match, 1);
    if (_startsClause(text.substring(at))) addSplit(at);
  }

  // A bare "so/but/because" that joins two clauses.
  for (final match in _bareConjunction.allMatches(text)) {
    final at = _groupStart(match, 1);
    if (inside(at)) continue;
    final head = text.substring(0, at).trimRight();
    if (_wordCount(head) < 6) continue;
    if (_notBeforeConjunction.contains(_previousWord(head))) continue;
    if (!_finiteVerb.hasMatch(head)) continue;
    if (!_startsClause(text.substring(match.end))) continue;
    addSplit(at);
  }

  // "… all in one right so …" — a tag question closes the clause before it.
  for (final match in _tagWord.allMatches(text)) {
    if (inside(match.start)) continue;
    if (match.group(1)!.toLowerCase() == 'right' &&
        RegExp(r'^now\b', caseSensitive: false)
            .hasMatch(text.substring(match.end))) {
      continue;
    }
    final head = text.substring(0, match.start).trimRight();
    if (_wordCount(head) < 6) continue;
    if (_determiners.contains(_previousWord(head))) continue;
    final tail = text.substring(match.end);
    if (!RegExp(r'^(i|you|he|she|we|they|it|there|so|but|and|because|if|what|'
            r'why|how|does|do|is|are)\b',
        caseSensitive: false)
        .hasMatch(tail.trimLeft())) {
      continue;
    }
    if (!_startsClause(tail)) continue;
    addSplit(match.end);
  }

  // "… a she and after it we have …" — the grammar lessons' parallel clauses.
  for (final match in _andAfter.allMatches(text)) {
    final at = match.start + 1;
    if (!inside(at)) addSplit(at);
  }

  // A wh-question said after a finished clause never got its "?".
  for (final match in _whQuestion.allMatches(text)) {
    final at = match.start;
    if (inside(at)) continue;
    final head = text.substring(0, at).trimRight();
    if (_wordCount(head) < 7) continue;
    if (_notBeforeConjunction.contains(_previousWord(head))) continue;
    addSplit(at);
  }

  // Nothing to break, but a long clause still wants a breathe: a comma before
  // the subordinator gives every engine the same pause without inventing a
  // sentence boundary.
  for (final match in _subordinate.allMatches(text)) {
    if (inside(match.start)) continue;
    // ", because" is punctuated already; only the bare join needs a comma.
    if (RegExp(r',\s*$').hasMatch(text.substring(0, match.start))) continue;
    addComma(_groupStart(match, 1));
  }
  for (final match in _andAdverb.allMatches(text)) {
    if (inside(match.start)) continue;
    if (RegExp(r',\s*$').hasMatch(text.substring(0, match.start))) continue;
    addComma(_groupStart(match, 1));
  }

  if (splits.isEmpty && commas.isEmpty) return [text];

  final marks = <(int, bool)>[
    for (final at in splits) (at, true),
    for (final at in commas)
      if (splits.every((other) => (other - at).abs() > 1)) (at, false),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  final pieces = <String>[];
  final buffer = StringBuffer();
  var mark = 0;
  for (var i = 0; i < text.length; i++) {
    if (mark < marks.length && marks[mark].$1 == i) {
      final split = marks[mark].$2;
      mark++;
      if (split) {
        final piece = buffer.toString().trim().replaceFirst(RegExp(r',$'), '');
        if (piece.isNotEmpty) pieces.add(piece);
        buffer.clear();
      } else if (buffer.isNotEmpty &&
          !' ,;'.contains(buffer.toString()[buffer.length - 1])) {
        buffer.write(',');
      }
    }
    buffer.write(text[i]);
  }
  final last = buffer.toString().trim().replaceFirst(RegExp(r',$'), '');
  if (last.isNotEmpty) pieces.add(last);

  // A rule that fires at a clause edge can leave a three-word fragment; it
  // reads with the sentence before it.
  final merged = <String>[];
  for (final piece in pieces) {
    if (merged.isNotEmpty && _wordCount(piece) < 4) {
      merged[merged.length - 1] = '${merged.last} $piece';
    } else {
      merged.add(piece);
    }
  }
  return [for (final piece in merged) _upperFirst(piece)];
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
  // A lead-in that ends on a colon already reads as a pause; "Or example:."
  // is the double mark the old pipeline shipped.
  if (last == ':' || last == ';') return text;
  // A trailing comma at the end of a line is a split seam, not punctuation.
  if (last == ',') return '${text.substring(0, text.length - 1)}.';
  const closers = {'”', '"', '’', ')', ']'};
  if (closers.contains(last)) {
    final before = text[text.length - 2];
    if ('.!?…'.contains(before)) return text;
    // A quoted term — “does”, "right" — must keep its own ending. Putting the
    // full stop inside would change the quoted word; a quoted sentence keeps
    // it inside, as English does.
    if (last == '”' || last == '"' || last == '’') {
      final opening = text.lastIndexOf(
        last == '”' ? '“' : (last == '’' ? '‘' : '"'),
      );
      if (opening >= 0) {
        final inner = text.substring(opening + 1, text.length - 1);
        if (!inner.contains(' ')) return '$text.';
      }
    }
    return '${text.substring(0, text.length - 1)}.$last';
  }
  return '$text.';
}
