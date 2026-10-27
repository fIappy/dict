// Engine: Dart (pure) | Target: lib/core/custom
//
// Turns a subtitle script's one-cue-per-line text into sentences.
//
// The Udemy passages were imported from `.srt` transcripts: every line is one
// subtitle cue, usually a fragment without punctuation. The reader then spoke
// each cue as if it were a sentence — a fall at the end of "you don't need learn
// all those horrible grammar rules" followed by a fresh start on "Just repeat
// everything after me" — which is not how the course sounds.
//
// The rules below are deliberately conservative: merge a cue with the previous
// one unless the cue looks like the start of a new sentence, end the sentence
// with `.` (or `?` when it opens like a question), and capitalise its first
// letter. Nothing is reworded, and text that already carries punctuation is left
// exactly as it is.

/// Words that cannot open a sentence: a cue beginning with one of them continues
/// the sentence the previous cue started.
const Set<String> _continuations = {
  'and', 'but', 'or', 'nor', 'so', 'yet', 'because', 'though', 'although',
  'while', 'if', 'when', 'whenever', 'where', 'why', 'how', 'that', 'which',
  'who', 'whom', 'whose', 'to', 'of', 'in', 'on', 'at', 'for', 'with', 'from',
  'by', 'as', 'than', 'then', 'into', 'onto', 'about', 'over', 'under', 'after',
  'before', 'during', 'without', 'within', 'upon', 'whether', 'like', 'just',
  'only', 'very', 'not', 'no', 'yes', 'also', 'already', 'still', 'even', 'well',
  'oh', 'ah', 'um', 'uh', 'okay', 'ok', 'right', 'now', 'here', 'there',
};

/// Words a sentence cannot end on: a cue ending with one of them is mid-clause,
/// so the next cue belongs to it even when it starts with a capital letter.
const Set<String> _cannotEnd = {
  'and', 'but', 'or', 'of', 'to', 'the', 'a', 'an', 'by', 'for', 'with', 'that',
  'which', 'who', 'if', 'when', 'because', 'so', 'as', 'than', 'into', 'on', 'in',
  'at', 'from', 'my', 'your', 'his', 'her', 'their', 'our', 'its', 'this', 'these',
  'those', 'is', 'are', 'was', 'were', 'will', 'would', 'can', 'could', 'should',
  'must', 'have', 'has', 'had', 'not', 'very', 'really', 'just',
};

/// Conjunctions that take a comma when they join two cues inside a sentence.
const Set<String> _commaConjunctions = {
  'and', 'but', 'so', 'yet', 'because', 'which', 'who', 'while', 'although',
  'though',
};

/// Sentence-final marks a cue may already carry.
const String _terminals = '.!?…';

final RegExp _wordStart = RegExp(r"^[A-Za-z']+");

/// Whether [line] ends a sentence on its own.
bool _endsSentence(String line) {
  final trimmed = line.trimRight();
  if (trimmed.isEmpty) return false;
  if (_terminals.contains(trimmed[trimmed.length - 1])) return true;
  // A closing quote or bracket after the mark still ends the sentence.
  final stripped = trimmed.replaceAll(RegExp('''[)\\]"”’']+\$'''), '');
  return stripped.isNotEmpty &&
      _terminals.contains(stripped[stripped.length - 1]);
}

String _firstWord(String line) =>
    _wordStart.firstMatch(line.trimLeft())?.group(0)?.toLowerCase() ?? '';

String _lastWord(String line) {
  final matches = RegExp(r"[A-Za-z']+").allMatches(line.trimRight());
  return matches.isEmpty ? '' : matches.last.group(0)!.toLowerCase();
}

int _wordCount(String text) => RegExp(r"[A-Za-z']+").allMatches(text).length;

/// [line] with its first letter lowered when it only continues the sentence
/// ("And the best part is…" -> "and the best part is…").
String _lowerContinuing(String line) {
  if (!_continuations.contains(_firstWord(line))) return line;
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return trimmed;
  final lowered = trimmed[0].toLowerCase() + trimmed.substring(1);
  // "i" alone is the pronoun, which stays capitalised.
  return RegExp(r'^i\b').hasMatch(lowered) ? 'I${lowered.substring(1)}' : lowered;
}

/// Whether [line] merely *reads* like the start of a new sentence.
///
/// The decision also weighs what the previous cue ended on (see
/// [reflowPassage]): a capital letter after "…and" continues the clause.
bool _startsNewSentence(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return false;
  final first = trimmed[0];
  return first.toUpperCase() == first && first.toLowerCase() != first;
}

/// `sentence` with a terminal mark and a capital first letter.
String _finish(String sentence) {
  var text = sentence.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return text;
  // Only the script knows which lines were questions — it wrote `?` on them.
  // Guessing from the first word turned "Where it's necessary…" into a question.
  if (!_endsSentence(text)) text += '.';

  // "i" is a pronoun in every pass of these scripts.
  text = text.replaceAllMapped(RegExp(r'\bi\b'), (match) => 'I');
  final first = text[0];
  return first.toUpperCase() == first ? text : first.toUpperCase() + text.substring(1);
}

/// The reflowed passage: the title line (if any) kept as-is, then one sentence
/// per line.
///
/// [body] is the passage as stored; the first non-empty line is treated as the
/// heading and left untouched, because these texts start with their own title.
String reflowPassage(String body) {
  final lines = body.replaceAll('\r\n', '\n').split('\n');
  final title = <String>[];
  var index = 0;
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  if (index < lines.length) {
    title.add(lines[index].trim());
    index++;
  }

  final cues = <String>[
    for (var i = index; i < lines.length; i++)
      if (lines[i].trim().isNotEmpty) lines[i].trim(),
  ];

  final sentences = <String>[];
  final buffer = StringBuffer();
  var lastCue = '';

  void flush() {
    final sentence = _finish(buffer.toString());
    buffer.clear();
    if (sentence.isNotEmpty) sentences.add(sentence);
  }

  for (final cue in cues) {
    if (buffer.isNotEmpty && _startsNewSentence(cue)) {
      // A capital letter alone does not start a sentence: not after a cue that
      // cannot end one, and not into a "sentence" of two words, which in these
      // scripts is always a fragment ("And by learning" / "I don't mean…").
      final closes = !_cannotEnd.contains(_lastWord(lastCue));
      // "And phrases" is the tail of a list, not a sentence: a conjunction cue
      // of one or two words never opens one.
      final shortConjunction = _commaConjunctions.contains(_firstWord(cue)) &&
          _wordCount(cue) <= 2;
      if (closes && !shortConjunction && _wordCount(buffer.toString()) >= 4) {
        flush();
      }
    }
    if (buffer.isNotEmpty) {
      final joined = buffer.toString();
      // "words and phrases" is a list, not a clause — a two-word conjunction
      // cue does not earn a comma.
      final needsComma = _commaConjunctions.contains(_firstWord(cue)) &&
          _wordCount(joined) >= 6 &&
          _wordCount(cue) >= 3;
      buffer.write(needsComma ? ', ' : ' ');
      buffer.write(_lowerContinuing(cue));
    } else {
      buffer.write(cue);
    }
    lastCue = cue;
    if (_endsSentence(cue)) flush();
  }
  flush();

  return [if (title.isNotEmpty) title.first, ...sentences].join('\n');
}

/// How many lines of [body] end without a terminal mark — the signal that a
/// passage is still subtitle cues and worth reflowing.
double unpunctuatedShare(String body) {
  final lines = [
    for (final line in body.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty) return 0;
  final unpunctuated = lines.where((line) => !_endsSentence(line)).length;
  return unpunctuated / lines.length;
}

/// Whether [body] looks like an untouched subtitle transcript.
///
/// Already-written passages (家庭场景, Work) have punctuation on nearly every
/// line, so they are left alone.
bool looksLikeSubtitleCues(String body) => unpunctuatedShare(body) > 0.5;
