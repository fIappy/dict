// Engine: Dart (pure) | Target: lib/core/custom
//
// Trims a group of subtitle-derived passages for playback.
//
// A course transcript repeats its example sentences across lessons and leaves
// one- or two-word cues in between. Read top to bottom that sounds like the
// same line over and over, broken up by "An exam" / "Not really". The rules
// here keep the first place a sentence is said and drop the later copies, and
// drop the cues that never became a sentence at all.

/// A passage reduced to what still gets read: its title plus whole sentences.
class CleanedPassage {
  const CleanedPassage({required this.title, required this.sentences});

  final String title;
  final List<String> sentences;

  bool get isEmpty => sentences.isEmpty;

  /// The passage as the app stores it: title on the first line, then one
  /// sentence per line.
  String get body => [if (title.isNotEmpty) title, ...sentences].join('\n');
}

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _words = RegExp(r"[A-Za-z0-9']+");
final RegExp _divider = RegExp(r'^[-=_*~]{3,}$');
final RegExp _quotes = RegExp(r'''^[\s"'“”‘’]+|[\s.!?…,;:"'“”‘’]+$''');

/// The identity two lines share when they are the same sentence.
///
/// Case, spacing and the closing mark are not part of it: "Why not?" and
/// "why not." are one sentence as far as a listener is concerned.
String sentenceKey(String line) => line.trim().toLowerCase().replaceAll(_whitespace, ' ').replaceAll(_quotes, '');

/// Whether [line] carries no sentence of its own.
///
/// A single word never does. A short phrase only does when the transcript
/// closed it with a mark ("Are you nervous?"), because that is the writer
/// saying the phrase *was* the utterance; "An exam" or "Not really" are pieces
/// of the sentence before or after them.
bool isFragmentLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return true;
  if (_divider.hasMatch(trimmed)) return false;
  final words = _words.allMatches(trimmed).length;
  if (words <= 1) return true;
  if (words <= 3 && !RegExp(r'[.?!]$').hasMatch(trimmed)) return true;
  return false;
}

/// Splits a stored body into its title line and sentences.
CleanedPassage passageFromBody(String body) {
  final lines = body.split('\n');
  var index = 0;
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  final title = index < lines.length ? lines[index].trim() : '';
  final sentences = [
    for (var i = index + 1; i < lines.length; i++)
      if (lines[i].trim().isNotEmpty) lines[i].trim(),
  ];
  return CleanedPassage(title: title, sentences: sentences);
}

/// [passages] with fragments and already-said sentences removed.
///
/// The first passage that says a sentence keeps it; every later one loses that
/// sentence, so the group as a whole never repeats a line. A passage whose
/// sentences were all repeats comes back empty — the caller decides whether to
/// keep an empty chapter.
List<CleanedPassage> cleanPassages(List<CleanedPassage> passages) {
  final seen = <String>{};
  final cleaned = <CleanedPassage>[];
  for (final passage in passages) {
    final kept = <String>[];
    for (final line in passage.sentences) {
      final trimmed = line.trim();
      if (isFragmentLine(trimmed)) continue;
      if (!_divider.hasMatch(trimmed)) {
        final key = sentenceKey(trimmed);
        if (!seen.add(key)) continue;
      }
      kept.add(trimmed);
    }
    cleaned.add(CleanedPassage(title: passage.title, sentences: kept));
  }
  return cleaned;
}
