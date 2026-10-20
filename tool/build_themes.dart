// ignore_for_file: avoid_print
//
// Engine: Dart (standalone, `dart run`) | Target: assets/data/themes.json
// Build: dart run tool/build_themes.dart            (rebuild the asset)
//        dart run tool/build_themes.dart --pending  (also write the work queue)
// Deps:  coca-20000.txt, tool/themes_lexicon.json, tool/themes_batches/*.txt
//
// The 主题 asset, merged from two sources:
//
//  1. `tool/themes_lexicon.json` — the taxonomy (scenes, facets, hints) plus the
//     hand-curated word lists that started the module.
//  2. `tool/themes_batches/NNN.txt` — per-word assignments for the rest of the
//     COCA list. One line per word:
//
//         word<TAB>scene:facet[,scene:facet]…
//
//     `#` starts a comment, blank lines are ignored, and tabs or spaces both
//     separate the word from its placements.
//
// Batches win over the curated lists, so a later batch can correct an earlier
// placement. `(scene, word)` is unique; a word may sit in up to three scenes,
// which is what "一个词汇可以在多个场景出现" asks for.
//
// This file only merges and validates — the classification itself is authored.
// `--pending` writes the words that still have no placement, in COCA order, so
// the next segment can take the top of that list and carry on; the queue shrinks
// by itself as batches land.
//
// See tool/THEMES_PLAN.md for the procedure.

import 'dart:convert';
import 'dart:io';

const int maxScenesPerWord = 3;
const int batchSize = 400;

void main(List<String> argv) {
  final writePending = argv.contains('--pending');
  final args = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--') && argv[i] != '--pending' && i + 1 < argv.length) {
      args[argv[i].substring(2)] = argv[++i];
    }
  }
  final cocaPath = args['coca'] ?? 'coca-20000.txt';
  final lexiconPath = args['lexicon'] ?? 'tool/themes_lexicon.json';
  final batchesDir = args['batches'] ?? 'tool/themes_batches';
  final outPath = args['out'] ?? 'assets/data/themes.json';
  final pendingPath = args['pending-out'] ?? 'tool/themes_pending.txt';

  // ---------------------------------------------------------------- taxonomy
  final lexicon = jsonDecode(File(lexiconPath).readAsStringSync()) as Map<String, dynamic>;
  final facets = [
    for (final f in lexicon['facets'] as List) (f['id'] as String, f['label'] as String),
  ];
  final facetOrder = {for (var i = 0; i < facets.length; i++) facets[i].$1: i};
  final facetLabels = {for (final f in facets) f.$1: f.$2};
  final sceneOrder = <String>[];
  final sceneLabels = <String, String>{};
  final sceneHints = <String, String>{};

  // ---------------------------------------------------------------- frequency
  final rank = <String, int>{};
  final coca = File(cocaPath).readAsLinesSync();
  for (var i = 0; i < coca.length; i++) {
    final word = coca[i].trim().toLowerCase();
    if (word.isNotEmpty) rank.putIfAbsent(word, () => i + 1);
  }

  // scene id -> word -> facet. The first scene registration wins the order.
  final placements = <String, Map<String, String>>{};
  final errors = <String>[];

  void place(String scene, String word, String facet, String origin) {
    if (!facetLabels.containsKey(facet)) {
      errors.add('$origin: unknown facet "$facet" for "$word"');
      return;
    }
    final words = placements.putIfAbsent(scene, () => {});
    words[word] = facet; // later sources override earlier ones
  }

  void noteScene(Map<String, dynamic> scene) {
    final id = scene['id'] as String;
    if (sceneLabels.containsKey(id)) {
      errors.add('duplicate scene id "$id"');
      return;
    }
    sceneOrder.add(id);
    sceneLabels[id] = scene['label'] as String;
    sceneHints[id] = (scene['hint'] ?? '') as String;
  }

  // ------------------------------------------------------- 1. curated lexicon
  for (final raw in lexicon['scenes'] as List) {
    final scene = raw as Map<String, dynamic>;
    noteScene(scene);
    final groups = (scene['groups'] ?? const {}) as Map<String, dynamic>;
    groups.forEach((facet, list) {
      for (final word in list as List) {
        final w = (word as String).trim().toLowerCase();
        if (w.isEmpty) continue;
        if (!rank.containsKey(w)) {
          errors.add('lexicon/${scene['id']}: "$w" is not in COCA');
          continue;
        }
        place(scene['id'] as String, w, facet, 'lexicon/${scene['id']}');
      }
    });
  }

  // --------------------------------------------------------------- 2. batches
  final dir = Directory(batchesDir);
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.txt')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  var batchLines = 0;
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final split = line.split(RegExp(r'[\t ]+'));
      if (split.length < 2) {
        errors.add('$name:${i + 1}: expected "word  scene:facet"');
        continue;
      }
      final word = split[0].toLowerCase();
      if (!rank.containsKey(word)) {
        errors.add('$name:${i + 1}: "$word" is not in COCA');
        continue;
      }
      final seen = <String>{};
      for (final token in split[1].split(',')) {
        final parts = token.split(':');
        if (parts.length != 2) {
          errors.add('$name:${i + 1}: bad placement "$token"');
          continue;
        }
        final scene = parts[0].trim();
        if (!sceneLabels.containsKey(scene)) {
          errors.add('$name:${i + 1}: unknown scene "$scene"');
          continue;
        }
        if (!seen.add(scene)) {
          errors.add('$name:${i + 1}: "$word" lists scene "$scene" twice');
          continue;
        }
        place(scene, word, parts[1].trim(), '$name:${i + 1}');
      }
      if (seen.length > maxScenesPerWord) {
        errors.add('$name:${i + 1}: "$word" is in ${seen.length} scenes (max $maxScenesPerWord)');
      }
      batchLines++;
    }
  }

  // --------------------------------------------------------------- 3. output
  var placementsTotal = 0;
  final placedWords = <String>{};
  final scenes = <Map<String, dynamic>>[];
  for (final scene in sceneOrder) {
    final words = placements[scene];
    if (words == null || words.isEmpty) continue;
    final byFacet = <String, List<String>>{};
    words.forEach((word, facet) {
      (byFacet[facet] ??= []).add(word);
      placementsTotal++;
      placedWords.add(word);
    });
    final ids = byFacet.keys.toList()
      ..sort((a, b) => (facetOrder[a] ?? 99).compareTo(facetOrder[b] ?? 99));
    final groups = <Map<String, dynamic>>[];
    for (final id in ids) {
      final list = byFacet[id]!..sort((a, b) => rank[a]!.compareTo(rank[b]!));
      groups.add({'id': id, 'label': facetLabels[id], 'words': list});
    }
    scenes.add({
      'id': scene,
      'label': sceneLabels[scene],
      'hint': sceneHints[scene] ?? '',
      'count': groups.fold<int>(0, (sum, g) => sum + (g['words'] as List).length),
      'groups': groups,
    });
  }
  scenes.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

  File(outPath).writeAsStringSync(jsonEncode({
    'version': 2,
    'source': 'COCA ${rank.length} words',
    'coverage': placedWords.length,
    'total': rank.length,
    'facets': [
      for (final f in facets) {'id': f.$1, 'label': f.$2},
    ],
    'scenes': scenes,
  }));

  // --------------------------------------------------------------- 4. report
  final coverage = placedWords.length / rank.length * 100;
  print('scenes        : ${scenes.length}');
  print('placements    : $placementsTotal (${placedWords.length} distinct words)');
  print('batch lines   : $batchLines from ${files.length} file(s)');
  print('coverage      : ${coverage.toStringAsFixed(1)}% of ${rank.length} COCA words');
  print('file          : $outPath (${(File(outPath).lengthSync() / 1024).toStringAsFixed(0)} KB)');

  if (writePending) {
    final pending = [
      for (final entry in rank.entries)
        if (!placedWords.contains(entry.key)) entry.key,
    ]..sort((a, b) => rank[a]!.compareTo(rank[b]!));
    final buffer = StringBuffer()
      ..writeln('# Words with no placement yet, in COCA frequency order.')
      ..writeln('# Take the next $batchSize lines, classify them, and write')
      ..writeln('# tool/themes_batches/NNN.txt. Rerun to shrink this list.')
      ..writeln('# Remaining: ${pending.length} (${(pending.length / batchSize).ceil()} batches)');
    for (final word in pending) {
      buffer.writeln(word);
    }
    File(pendingPath).writeAsStringSync(buffer.toString());
    print('pending       : ${pending.length} words -> $pendingPath');
  }

  if (errors.isNotEmpty) {
    print('');
    print('PROBLEMS (${errors.length}):');
    for (final error in errors.take(40)) {
      print('  $error');
    }
    if (errors.length > 40) print('  … and ${errors.length - 40} more');
    exitCode = 1;
  }
}
