// Shared by the custom-passage tools: find a group by name and clean it.
//
// Both `clean_custom_passages.dart` and `reflow_custom_passages.dart --clean`
// need the same three steps: pick the group's texts in list order, run
// [cleanPassages], and drop the chapters whose lines were all repeats.

import 'dart:convert';
import 'dart:io';

import 'package:local_dict/core/custom/passage_cleanup.dart';

String get appData =>
    '${Platform.environment['APPDATA']}\\com.example\\local_dict';

/// The app's own 自定义 library, wherever this build keeps it.
///
/// Newer builds keep the passages and groups in `custom_texts.json` /
/// `custom_groups.json`; a store written before that move still has them under
/// the `flutter.custom_*` keys of `shared_preferences.json`. Reads prefer the
/// files and fall back to the preferences, writes go back to the same place.
class LocalLibrary {
  LocalLibrary._(this.texts, this.groups, this._usesFiles);

  final List<Map<String, dynamic>> texts;
  final List<Map<String, dynamic>> groups;
  final bool _usesFiles;

  static String get _prefsPath => '$appData\\shared_preferences.json';
  static String get _textsPath => '$appData\\custom_texts.json';
  static String get _groupsPath => '$appData\\custom_groups.json';

  static LocalLibrary read() {
    final textsFile = File(_textsPath);
    final groupsFile = File(_groupsPath);
    if (textsFile.existsSync() || groupsFile.existsSync()) {
      List<Map<String, dynamic>> load(File file) {
        if (!file.existsSync()) return [];
        return (jsonDecode(file.readAsStringSync()) as List)
            .cast<Map<String, dynamic>>();
      }

      return LocalLibrary._(load(textsFile), load(groupsFile), true);
    }
    final prefs = File(_prefsPath).existsSync()
        ? jsonDecode(File(_prefsPath).readAsStringSync())
            as Map<String, dynamic>
        : <String, dynamic>{};
    List<Map<String, dynamic>> legacy(String key) {
      final raw = prefs[key] as String?;
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    }

    return LocalLibrary._(
      legacy('flutter.custom_texts'),
      legacy('flutter.custom_groups'),
      false,
    );
  }

  void save() {
    if (_usesFiles) {
      File(_textsPath)
          .writeAsStringSync(jsonEncode(texts), flush: true);
      File(_groupsPath)
          .writeAsStringSync(jsonEncode(groups), flush: true);
      return;
    }
    final prefs = jsonDecode(File(_prefsPath).readAsStringSync())
        as Map<String, dynamic>;
    prefs['flutter.custom_texts'] = jsonEncode(texts);
    prefs['flutter.custom_groups'] = jsonEncode(groups);
    File(_prefsPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(prefs),
    );
  }
}

/// Ids of the groups whose name contains [needle] (case-insensitive).
Set<String> groupIdsNamed(
  Iterable<Map<String, dynamic>> groups,
  String needle,
) {
  final lower = needle.toLowerCase();
  return {
    for (final group in groups)
      if ((group['name'] as String? ?? '').toLowerCase().contains(lower))
        group['id'] as String,
  };
}

/// Cleans [texts] in place; returns the line counts and the titles it removed.
({int before, int after, List<String> emptied}) cleanGroupTexts(
  List<Map<String, dynamic>> texts, {
  required Set<String> groupIds,
  required bool keepEmpty,
}) {
  final indexes = [
    for (var i = 0; i < texts.length; i++)
      if (groupIds.contains(texts[i]['groupId'])) i,
  ];
  final passages = [
    for (final i in indexes)
      passageFromBody(texts[i]['body'] as String? ?? ''),
  ];
  final before = passages.fold<int>(0, (sum, p) => sum + p.sentences.length);
  final cleaned = cleanPassages(passages);

  final emptied = <String>[];
  final removed = <int>{};
  for (var k = 0; k < indexes.length; k++) {
    final text = texts[indexes[k]];
    final passage = cleaned[k];
    if (passage.isEmpty && !keepEmpty) {
      emptied.add(passage.title);
      removed.add(indexes[k]);
      continue;
    }
    text['body'] = passage.body;
    if (passage.title.isNotEmpty) text['title'] = passage.title;
  }
  texts.removeWhere((text) => removed.contains(texts.indexOf(text)));
  final after = cleaned.fold<int>(0, (sum, p) => sum + p.sentences.length);
  return (before: before, after: after, emptied: emptied);
}
