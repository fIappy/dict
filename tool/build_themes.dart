// ignore_for_file: avoid_print
//
// Engine: Dart (standalone, `dart run`) | Target: assets/data/themes.json
// Build: dart run tool/build_themes.dart
// Deps:  coca-20000.txt + tool/themes_lexicon.json (and nothing else)
//
// Builds the 主题 asset.
//
// The scene word lists are **curated** in `tool/themes_lexicon.json`, not derived
// from the dictionary. An earlier attempt read each COCA word's definition out of
// the .mdx and scored it against per-scene keywords; the noise swamped the signal
// — "to " matched half of all definitions, so nearly every verb became an action
// of every scene, and generic seeds ("play", "game", "win") dragged unrelated
// words into sports. Curating the lists and using this script only to *validate*
// them is both better and simpler:
//
//  * a word the lexicon lists but COCA does not have is dropped and reported,
//  * a word listed twice is kept once,
//  * every scene's facets are emitted in the canonical facet order,
//  * within a facet the words are sorted by COCA frequency (the file's line
//    order), which is the order the UI shows them in.
//
// The frequency file is one word per line, most frequent first, so a word's
// 1-based line number is its rank.

import 'dart:convert';
import 'dart:io';

void main(List<String> argv) {
  final args = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) args[argv[i].substring(2)] = argv[++i];
  }
  final cocaPath = args['coca'] ?? 'coca-20000.txt';
  final lexiconPath = args['lexicon'] ?? 'tool/themes_lexicon.json';
  final outPath = args['out'] ?? 'assets/data/themes.json';

  final lexicon = jsonDecode(File(lexiconPath).readAsStringSync()) as Map<String, dynamic>;
  final facets = [
    for (final f in lexicon['facets'] as List) (f['id'] as String, f['label'] as String),
  ];
  final facetOrder = {for (var i = 0; i < facets.length; i++) facets[i].$1: i};

  final rank = <String, int>{};
  final lines = File(cocaPath).readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final word = lines[i].trim().toLowerCase();
    if (word.isNotEmpty) rank.putIfAbsent(word, () => i + 1);
  }

  final missing = <String, List<String>>{};
  final outScenes = <Map<String, dynamic>>[];
  var placements = 0;
  final placed = <String>{};

  for (final raw in lexicon['scenes'] as List) {
    final scene = raw as Map<String, dynamic>;
    final groups = scene['groups'] as Map<String, dynamic>;
    final emitted = <Map<String, dynamic>>[];
    final ids = groups.keys.toList()
      ..sort((a, b) => (facetOrder[a] ?? 99).compareTo(facetOrder[b] ?? 99));
    for (final id in ids) {
      final words = <String>[];
      final seen = <String>{};
      for (final raw in groups[id] as List) {
        final word = (raw as String).trim().toLowerCase();
        if (word.isEmpty || !seen.add(word)) continue;
        if (!rank.containsKey(word)) {
          (missing[scene['id'] as String] ??= []).add(word);
          continue;
        }
        words.add(word);
      }
      if (words.isEmpty) continue;
      words.sort((a, b) => rank[a]!.compareTo(rank[b]!));
      placements += words.length;
      placed.addAll(words);
      emitted.add({
        'id': id,
        'label': facets.firstWhere((f) => f.$1 == id, orElse: () => (id, id)).$2,
        'words': words,
      });
    }
    if (emitted.isEmpty) continue;
    outScenes.add({
      'id': scene['id'],
      'label': scene['label'],
      'hint': scene['hint'] ?? '',
      'count': emitted.fold<int>(0, (sum, g) => sum + (g['words'] as List).length),
      'groups': emitted,
    });
  }

  // A scene list ordered by the scenes' own size makes the biggest themes first,
  // which is a better first screen than the order they were authored in.
  outScenes.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

  final out = {
    'version': 1,
    'source': 'COCA ${rank.length} words',
    'facets': [
      for (final f in facets) {'id': f.$1, 'label': f.$2},
    ],
    'scenes': outScenes,
  };
  File(outPath).writeAsStringSync(jsonEncode(out));

  print('scenes         : ${outScenes.length}');
  print('placements     : $placements (${placed.length} distinct words)');
  print('coca coverage  : ${(placed.length / rank.length * 100).toStringAsFixed(1)}%');
  print('file           : $outPath (${(File(outPath).lengthSync() / 1024).toStringAsFixed(0)} KB)');
  if (missing.isNotEmpty) {
    print('');
    print('not in COCA (dropped — fix the lexicon):');
    for (final entry in missing.entries) {
      print('  ${entry.key}: ${entry.value.join(', ')}');
    }
  }
}
