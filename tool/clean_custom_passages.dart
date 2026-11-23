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

import 'package:local_dict/core/custom/sentence_split.dart';

import 'custom_store.dart';

const String _seedPath = 'assets/seed/custom_home.json';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final keepEmpty = args.contains('--keep-empty');
  final split = args.contains('--split');
  final all = args.contains('--all');
  final noClean = args.contains('--no-clean');
  final audit = args.contains('--audit');
  final groupIndex = args.indexOf('--group');
  final needle = groupIndex >= 0 && groupIndex + 1 < args.length
      ? args[groupIndex + 1]
      : 'Udemy';

  final library = LocalLibrary.read();
  final texts = library.texts;
  final groups = library.groups;
  final ids = all
      ? {for (final group in groups) (group['id'] as String?) ?? ''}
      : groupIdsNamed(groups, needle);
  if (ids.isEmpty) {
    stderr.writeln('no group matches "$needle"');
    exitCode = 1;
    return;
  }

  // Splits inside each line and keeps the blank lines between a passage's
  // clusters: the 家庭场景 set groups its variants that way, and rebuilding the
  // body from a flat sentence list flattened them.
  ({int before, int after}) splitGroup(
    List<Map<String, dynamic>> items,
    Set<String> groups,
  ) {
    var splitBefore = 0;
    var splitAfter = 0;
    for (final text in items) {
      if (!groups.contains(text['groupId'])) continue;
      final body = text['body'] as String? ?? '';
      final title = (text['title'] as String? ?? '').trim();
      final out = <String>[];
      var seenTitle = false;
      for (final line in body.split('\n')) {
        if (line.trim().isEmpty) {
          out.add('');
          continue;
        }
        // Many bodies repeat the title as their first line and some do not;
        // only the repeated one is a heading (no full stop, no splitting).
        if (!seenTitle && title.isNotEmpty && line.trim() == title) {
          seenTitle = true;
          out.add(line.trim());
          continue;
        }
        seenTitle = true;
        splitBefore++;
        final parts = splitSentenceLine(line.trim());
        splitAfter += parts.length;
        out.addAll(parts);
      }
      text['body'] = out.join('\n').trim();
    }
    return (before: splitBefore, after: splitAfter);
  }

  final storeSplit = split ? splitGroup(texts, ids) : null;

  final storeResult = noClean
      ? (
          before: storeSplit!.after,
          after: storeSplit.after,
          emptied: const <String>[],
        )
      : cleanGroupTexts(texts, groupIds: ids, keepEmpty: keepEmpty);
  if (storeSplit != null) {
    stdout.writeln('split (store): ${storeSplit.before} -> ${storeSplit.after}');
  }
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
  final seedIds = all
      ? {for (final group in seedGroups) (group['id'] as String?) ?? ''}
      : groupIdsNamed(seedGroups, needle);
  final seedSplit = split ? splitGroup(seedTexts, seedIds) : null;
  final seedResult = noClean
      ? (
          before: seedSplit!.after,
          after: seedSplit.after,
          emptied: const <String>[],
        )
      : cleanGroupTexts(seedTexts, groupIds: seedIds, keepEmpty: keepEmpty);
  if (seedSplit != null) {
    stdout.writeln('split (seed): ${seedSplit.before} -> ${seedSplit.after}');
  }
  stdout.writeln('seed: ${seedIds.length} group(s), sentences '
      '${seedResult.before} -> ${seedResult.after}, '
      '${seedResult.emptied.length} emptied');

  if (audit) {
    final report = _auditReport(seedTexts, seedGroups);
    final file = File('build/custom_passages_audit.txt');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(report.text);
    stdout.writeln('audit: ${report.lines} line(s) in ${file.path}');
    return;
  }

  if (dryRun) {
    stdout.writeln('dry run: nothing written');
    return;
  }

  library.save();

  seed['texts'] = seedTexts;
  seed['version'] = ((seed['version'] as num?)?.toInt() ?? 1) + 1;
  seedFile.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(seed),
  );
  stdout.writeln('written: store + seed (version ${seed['version']})');
}


/// Every line the splitter still cannot cut, for a human or a model to look at.
///
/// A caption with no conjunction, no tag and no question word carries nothing
/// a rule can hold on to; rewriting those by hand (or with a model) is the only
/// honest next step. The report names the group and passage so a fix can be
/// pasted back into the same place.
({String text, int lines}) _auditReport(
  List<Map<String, dynamic>> texts,
  List<Map<String, dynamic>> groups,
) {
  final names = {
    for (final group in groups) (group['id'] as String? ?? ''): group['name'],
  };
  final buffer = StringBuffer();
  final longPattern = RegExp(r'[.!?…]\s*[A-Z“"‘]');
  bool closed(String line) {
    var text = line.trimRight();
    const closers = {'”', '"', "'", '’', ')', ']'};
    while (text.isNotEmpty && closers.contains(text[text.length - 1])) {
      text = text.substring(0, text.length - 1).trimRight();
    }
    return text.isNotEmpty && '.!?…'.contains(text[text.length - 1]);
  }
  var count = 0;
  for (final text in texts) {
    final body = text['body'] as String? ?? '';
    final title = text['title'] as String? ?? '';
    final group = names[text['groupId']] ?? '';
    final lines = body.split('\n');
    final offenders = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if ((trimmed.length > 110 && !longPattern.hasMatch(trimmed)) ||
          !closed(trimmed)) {
        offenders.add(trimmed);
      }
    }
    if (offenders.isEmpty) continue;
    buffer.writeln('## $group / $title');
    for (final line in offenders) {
      buffer.writeln(line);
      count++;
    }
    buffer.writeln();
  }
  return (text: buffer.toString(), lines: count);
}
