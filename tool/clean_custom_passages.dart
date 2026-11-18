// Drops the repeats and the fragments from a group of custom passages.
//
// The Udemy course repeats the same example sentences in every lesson and
// leaves one- or two-word cues between them. Played as a group that is mostly
// deja vu, so this script keeps the first place each sentence is said, drops
// the copies, and drops the cues that never became a sentence.
//
//   dart run tool/clean_custom_passages.dart --dry-run          # report only
//   dart run tool/clean_custom_passages.dart --group Udemy      # write
//
// `--keep-empty` keeps chapters whose every line was a repeat; the default
// removes them because a title with nothing under it plays nothing.

import 'dart:convert';
import 'dart:io';

import 'custom_store.dart';

String get _appData =>
    '${Platform.environment['APPDATA']}\\com.example\\local_dict';

String get _storePath => '$_appData\\shared_preferences.json';
const String _storeTextsKey = 'flutter.custom_texts';
const String _storeGroupsKey = 'flutter.custom_groups';
const String _seedPath = 'assets/seed/custom_home.json';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final keepEmpty = args.contains('--keep-empty');
  final groupIndex = args.indexOf('--group');
  final needle = groupIndex >= 0 && groupIndex + 1 < args.length
      ? args[groupIndex + 1]
      : 'Udemy';

  final store = jsonDecode(File(_storePath).readAsStringSync())
      as Map<String, dynamic>;
  final texts = (jsonDecode(store[_storeTextsKey] as String? ?? '[]') as List)
      .cast<Map<String, dynamic>>();
  final groups = (jsonDecode(store[_storeGroupsKey] as String? ?? '[]') as List)
      .cast<Map<String, dynamic>>();
  final ids = groupIdsNamed(groups, needle);
  if (ids.isEmpty) {
    stderr.writeln('no group matches "$needle"');
    exitCode = 1;
    return;
  }

  final storeResult = cleanGroupTexts(
    texts,
    groupIds: ids,
    keepEmpty: keepEmpty,
  );
  stdout.writeln('store: ${ids.length} group(s), sentences '
      '${storeResult.before} -> ${storeResult.after}, '
      '${storeResult.emptied.length} emptied');
  for (final title in storeResult.emptied) {
    stdout.writeln('  removed: $title');
  }

  final seedFile = File(_seedPath);
  final seed =
      jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>;
  final seedTexts = (seed['texts'] as List).cast<Map<String, dynamic>>();
  final seedGroups = (seed['groups'] as List).cast<Map<String, dynamic>>();
  final seedIds = groupIdsNamed(seedGroups, needle);
  final seedResult = cleanGroupTexts(
    seedTexts,
    groupIds: seedIds,
    keepEmpty: keepEmpty,
  );
  stdout.writeln('seed: ${seedIds.length} group(s), sentences '
      '${seedResult.before} -> ${seedResult.after}, '
      '${seedResult.emptied.length} emptied');

  if (dryRun) {
    stdout.writeln('dry run: nothing written');
    return;
  }

  File(_storePath).copySync('$_storePath.bak-clean');
  store[_storeTextsKey] = jsonEncode(texts);
  File(_storePath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(store));

  seed['texts'] = seedTexts;
  seed['version'] = ((seed['version'] as num?)?.toInt() ?? 1) + 1;
  seedFile.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(seed),
  );
  stdout.writeln('written: store + seed (version ${seed['version']})');
}
