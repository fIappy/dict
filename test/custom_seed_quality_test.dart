import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The shipped library is the publishing machine's own store, so its wording
  // is not a curation artefact to police — the pipeline is. What must hold is
  // that publishing and merging ship every passage exactly once: a duplicated
  // id or body is the failure a merge bug produces, and it lands in every
  // install of the next build.
  test('the shipped library carries every passage exactly once', () async {
    final raw = await rootBundle.loadString('assets/seed/custom_home.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final groups = (seed['groups'] as List).cast<Map<String, dynamic>>();
    final texts = (seed['texts'] as List).cast<Map<String, dynamic>>();

    final ids = <String>{};
    final duplicateIds = <String>[];
    final bodiesByGroup = <String, Set<String>>{};
    final duplicateBodies = <String>[];
    final empty = <String>[];

    final groupIds = groups.map((g) => g['id'] as String).toSet();
    for (final text in texts) {
      final id = text['id'] as String? ?? '';
      final body = text['body'] as String? ?? '';
      if (!ids.add(id)) duplicateIds.add(id);
      if (body.trim().isEmpty) empty.add(id);
      final group = text['groupId'] as String? ?? '';
      expect(group.isEmpty || groupIds.contains(group), isTrue,
          reason: 'a passage points at a group the library lost: $group');
      final seen = bodiesByGroup.putIfAbsent(group, () => <String>{});
      if (!seen.add(body)) duplicateBodies.add(id);
    }

    expect(duplicateIds, isEmpty, reason: 'an id is in the library twice');
    expect(duplicateBodies, isEmpty,
        reason: 'two passages of one group carry the same body');
    expect(empty, isEmpty, reason: 'a passage with no text');
    expect(texts, isNotEmpty);
  });
}
