import 'dart:math' as math;

/// The theme vocabulary in COCA order, most frequent first, duplicates dropped.
///
/// [rankOf] returns the COCA rank of a word, or null when it is not in the
/// list; those words go after every known rank.
List<String> rankByFrequency(
  Iterable<String> words,
  int? Function(String word) rankOf,
) {
  final seen = <String>{};
  final ranked = <(String, int)>[];
  for (final raw in words) {
    final word = raw.trim().toLowerCase();
    if (word.isEmpty || !seen.add(word)) continue;
    ranked.add((word, rankOf(word) ?? _unknownRank));
  }
  ranked.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final entry in ranked) entry.$1];
}

const int _unknownRank = 1 << 30;

/// Picks the words a passage must use out of a theme's frequency-ranked list.
///
/// [ranked] is the theme vocabulary sorted by COCA rank, most frequent first,
/// so position 200 in the list is "the 200th most common word of this theme".
/// Only the chosen band is sent to the model — the rest of the list stays out
/// of the prompt.
///
/// A long band cannot always fit: a 100-word band in a 200-word passage would
/// read as a word list. When the band is wider than one word per ten words of
/// passage, every band member still gets a fair chance: the band is sampled
/// evenly, so the spread stays the same.
List<String> wordsInBand(
  List<String> ranked, {
  required int from,
  required int to,
  required int length,
}) {
  if (ranked.isEmpty) return const [];

  final start = from.clamp(1, ranked.length);
  final end = to.clamp(start, ranked.length);
  final band = ranked.sublist(start - 1, end);

  final budget = math.max(3, length ~/ 10);
  if (band.length <= budget) return List<String>.unmodifiable(band);

  final picked = <String>[];
  for (var i = 0; i < budget; i++) {
    picked.add(band[(i * band.length / budget).floor()]);
  }
  return List<String>.unmodifiable(picked);
}
