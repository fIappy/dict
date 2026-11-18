// Re-flows the custom passages in the app's store and in the shipped library.
//
// The Udemy passages arrived as subtitle scripts (one cue per line, no
// punctuation); `reflowPassage` merges the fragments into sentences and gives
// them terminal marks. This script applies it to every passage that still looks
// like raw cues, leaving hand-written passages (which are punctuated) alone.
//
//   dart run tool/reflow_custom_passages.dart --dry-run   # report only
//   dart run tool/reflow_custom_passages.dart             # write
//
// Reflow only merges cues; the course still repeats whole sentences across
// lessons and leaves two-word cues behind. Run
// `dart run tool/clean_custom_passages.dart --group Udemy` after a rebuild to
// drop those.

import 'dart:convert';
import 'dart:io';

import 'package:local_dict/core/custom/custom_text.dart';
import 'package:local_dict/core/custom/passage_reflow.dart';

import 'custom_store.dart';

String get _appData => Directory(
      '${Platform.environment['APPDATA']}\\com.example\\local_dict',
    ).path;

String get _storePath => '$_appData\\shared_preferences.json';
const String _storeKey = 'flutter.custom_texts';
const String _groupsKey = 'flutter.custom_groups';
const String _seedPath = 'assets/seed/custom_home.json';

int _sentences(String body) => splitSentences(body).length;

/// Before/after sentence counts and line counts for one passage.
({int sentencesBefore, int sentencesAfter, bool changed}) _measure(String body) {
  final reflowed = reflowPassage(body);
  return (
    sentencesBefore: _sentences(body),
    sentencesAfter: _sentences(reflowed),
    changed: reflowed != body,
  );
}

/// Chapters of the subtitle script: `# ----- Title -----` then one cue per line.
Map<String, List<String>> _readSource(String path) {
  final chapters = <String, List<String>>{};
  final header = RegExp(r'^# -{5} (.+?) -{5}\s*$');
  String? title;
  for (final raw in File(path).readAsLinesSync()) {
    final match = header.firstMatch(raw);
    if (match != null) {
      title = match.group(1)!.trim();
      chapters[title] = <String>[];
      continue;
    }
    if (raw.startsWith('#')) continue;
    final line = raw.trim();
    if (title != null && line.isNotEmpty) chapters[title]!.add(line);
  }
  return chapters;
}

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final sourceIndex = args.indexOf('--from-source');
  final source = sourceIndex >= 0 && sourceIndex + 1 < args.length
      ? _readSource(args[sourceIndex + 1])
      : const <String, List<String>>{};

  final store = jsonDecode(File(_storePath).readAsStringSync()) as Map<String, dynamic>;
  final texts = (jsonDecode(store[_storeKey] as String? ?? '[]') as List)
      .cast<Map<String, dynamic>>();

  var changed = 0;
  var sentencesBefore = 0;
  var sentencesAfter = 0;
  var rebuilt = 0;
  for (final text in texts) {
    final title = (text['title'] as String? ?? '').trim();
    var body = text['body'] as String? ?? '';
    final cues = source[title];
    if (cues != null) {
      body = '$title\n${cues.join('\n')}';
      rebuilt++;
    }
    final measure = _measure(body);
    sentencesBefore += measure.sentencesBefore;
    sentencesAfter += measure.sentencesAfter;
    if (!measure.changed) continue;
    changed++;
    text['body'] = reflowPassage(body);
  }
  stdout.writeln('store: ${texts.length} passages, $rebuilt rebuilt from source, '
      '$changed reflowed, sentences $sentencesBefore -> $sentencesAfter');

  final seedFile = File(_seedPath);
  final seed = jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>;
  final seedTexts = (seed['texts'] as List).cast<Map<String, dynamic>>();
  var seedChanged = 0;
  var seedBefore = 0;
  var seedAfter = 0;
  var seedRebuilt = 0;
  for (final text in seedTexts) {
    final title = (text['title'] as String? ?? '').trim();
    var body = text['body'] as String? ?? '';
    final cues = source[title];
    if (cues != null) {
      body = '$title\n${cues.join('\n')}';
      seedRebuilt++;
    }
    final measure = _measure(body);
    seedBefore += measure.sentencesBefore;
    seedAfter += measure.sentencesAfter;
    if (!measure.changed) continue;
    seedChanged++;
    text['body'] = reflowPassage(body);
  }
  stdout.writeln('seed: ${seedTexts.length} passages, $seedRebuilt rebuilt, '
      '$seedChanged reflowed, sentences $seedBefore -> $seedAfter');

  final cleanIndex = args.indexOf('--clean');
  final cleanNeedle = cleanIndex >= 0 && cleanIndex + 1 < args.length
      ? args[cleanIndex + 1]
      : null;
  if (cleanNeedle != null) {
    final storeGroups =
        (jsonDecode(store[_groupsKey] as String? ?? '[]') as List)
            .cast<Map<String, dynamic>>();
    final seedGroups =
        (seed['groups'] as List? ?? const []).cast<Map<String, dynamic>>();
    final storeClean = cleanGroupTexts(
      texts,
      groupIds: groupIdsNamed(storeGroups, cleanNeedle),
      keepEmpty: false,
    );
    final seedClean = cleanGroupTexts(
      seedTexts,
      groupIds: groupIdsNamed(seedGroups, cleanNeedle),
      keepEmpty: false,
    );
    stdout.writeln('clean "$cleanNeedle": store ${storeClean.before} -> '
        '${storeClean.after} (${storeClean.emptied.length} emptied), seed '
        '${seedClean.before} -> ${seedClean.after} '
        '(${seedClean.emptied.length} emptied)');
  }

  if (dryRun) {
    final sample = seedTexts.firstWhere(
      (text) => (text['title'] as String? ?? '') == 'Promo (part 1)',
      orElse: () => seedTexts.first,
    );
    stdout.writeln('\n--- sample: ${sample['title']} ---');
    stdout.writeln(reflowPassage(sample['body'] as String? ?? ''));
    return;
  }

  File(_storePath).copySync('$_storePath.bak-reflow');
  store[_storeKey] = jsonEncode(texts);
  File(_storePath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(store));

  seed['texts'] = seedTexts;
  seed['version'] = ((seed['version'] as num?)?.toInt() ?? 1) + 1;
  seedFile.copySync('$_storePath.bak-seed');
  seedFile.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(seed),
  );
  stdout.writeln('written: store + seed (version ${seed['version']})');
}
