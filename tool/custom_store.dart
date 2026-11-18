// Shared by the custom-passage tools: find a group by name and clean it.
//
// Both `clean_custom_passages.dart` and `reflow_custom_passages.dart --clean`
// need the same three steps: pick the group's texts in list order, run
// [cleanPassages], and drop the chapters whose lines were all repeats.

import 'package:local_dict/core/custom/passage_cleanup.dart';

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
