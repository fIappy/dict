import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ai/ai_archive.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install gets the whole built-in library', () async {
    final provider = CustomTextProvider();
    await provider.initialize();
    expect(provider.allTexts, isEmpty);

    await provider.ensureSeeded();

    // The shipped library holds the hand-written 家庭场景 set plus the edited
    // 自定义 content published from the app (Work, Udemy…).
    final names = provider.groups.map((g) => g.name).toList();
    expect(names, contains('家庭场景'));
    expect(names.length, greaterThanOrEqualTo(3));

    final home = provider.groups.firstWhere((g) => g.name == '家庭场景');
    final homeTexts = provider.allTexts.where((t) => t.groupId == home.id);
    expect(homeTexts, isNotEmpty);
    expect(homeTexts.first.body, contains('\n\n'),
        reason: 'the seed keeps its clusters of variants');
    expect(homeTexts.first.title, isNotEmpty);

    // Survives a restart without being imported twice.
    final again = CustomTextProvider();
    await again.initialize();
    await again.ensureSeeded();
    expect(again.allTexts, hasLength(provider.allTexts.length));
  });

  test('the panel opens on a group that has content', () async {
    // A store that remembers 未分组 (empty) while the library lives in groups:
    // opening there showed an empty list even though everything was imported.
    SharedPreferences.setMockInitialValues({
      'flutter.custom_texts':
          '[{"id":"a","body":"One.","title":"A","groupId":"g1","createdAt":"2026-01-01T00:00:00"}]',
      'flutter.custom_groups': '[{"id":"g1","name":"Work"}]',
      'flutter.custom_group': '__ungrouped__',
      'flutter.custom_library_version': 999,
    });
    final provider = CustomTextProvider();
    await provider.initialize();

    expect(provider.selectedGroupId, 'g1');
    expect(provider.visibleTexts.map((t) => t.title), ['A']);
  });

  test('a local edit wins, and the rest of the library is still merged', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.custom_texts':
          '[{"id":"mine","body":"My own line.","title":"Mine","createdAt":"2026-01-01T00:00:00"}]',
      'flutter.custom_groups': '[]',
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    final mine = provider.allTexts.where((t) => t.id == 'mine').single;
    expect(mine.title, 'Mine');
    expect(mine.body, 'My own line.', reason: 'the local text is not overwritten');
    expect(provider.allTexts.length, greaterThan(1),
        reason: 'entries the reader does not have are added next to it');
  });

  test('the same library content is not merged twice', () async {
    final first = CustomTextProvider();
    await first.initialize();
    await first.ensureSeeded();
    final count = first.allTexts.length;

    final prefs = await SharedPreferences.getInstance();
    final fingerprint = prefs.getString('custom_library_fingerprint');
    expect(fingerprint, isNotNull, reason: 'the merge records what it merged');

    final again = CustomTextProvider();
    await again.initialize();
    await again.ensureSeeded();
    expect(again.allTexts, hasLength(count));
  });

  test('a rebuilt library refreshes the shipped passages', () async {
    // What a reader who installed an older build has: the seed's own id, an old
    // body, and a fingerprint from that older file.
    final raw = await rootBundle.loadString('assets/seed/custom_home.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final texts = (seed['texts'] as List).cast<Map<String, dynamic>>();
    final shipped = texts.firstWhere((t) => t['groupId'] != null);
    final oldBody = 'An old copy of this passage.';

    SharedPreferences.setMockInitialValues({
      'flutter.custom_texts': jsonEncode([
        {
          'id': shipped['id'],
          'body': oldBody,
          'title': shipped['title'],
          'groupId': shipped['groupId'],
          'createdAt': '2026-01-01T00:00:00',
        },
      ]),
      'flutter.custom_groups': jsonEncode(seed['groups']),
      'flutter.custom_library_fingerprint': 'an older build',
    });

    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    final refreshed = provider.allTexts.where((t) => t.id == shipped['id']).single;
    expect(refreshed.body, shipped['body'],
        reason: 'the library owns a shipped passage: the fix must land');
    expect(refreshed.body, isNot(oldBody));
  });

  test('an empty AI archive is filled from the shipped examples', () async {
    final store = AiArchiveStore();
    expect(await store.load(), isEmpty);

    final seeded = await store.ensureSeeded();

    expect(seeded, isNotEmpty);
    expect(seeded.first.title, isNotEmpty);
    // Seeded items are real entries the UI can show and delete.
    expect(await store.load(), hasLength(seeded.length));
  });

  test('the AI archive merges the shipped generations around local work', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.ai_archive_v1':
          '[{"id":"x","sceneId":"s","sceneLabel":"S","kind":"passage","level":"easy",'
              '"createdAt":1,"model":"m","title":"Mine","text":"Body."}]',
    });
    final store = AiArchiveStore();
    final seeded = await store.ensureSeeded();

    // The reader's own generation survives untouched…
    expect(seeded.where((item) => item.id == 'x').single.title, 'Mine');
    // …and the library's items are added next to it.
    expect(seeded.length, greaterThan(1));

    // The same version is not merged twice.
    final again = await AiArchiveStore().ensureSeeded();
    expect(again, hasLength(seeded.length));
  });

  test('ai archive v2 migrates legacy seed sceneIds while preserving user items',
      () async {
    final raw = await rootBundle.loadString('assets/seed/ai_archive.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final sample =
        ((seed['items'] as List).first as Map).cast<String, dynamic>();
    final legacyEntry = Map<String, dynamic>.from(sample)
      ..['sceneId'] = 'medical'
      ..['sceneLabel'] = '医疗健康';

    SharedPreferences.setMockInitialValues({
      'flutter.ai_seed_version': 1,
      'flutter.ai_archive_v1': jsonEncode([
        legacyEntry,
        {
          'id': 'user-custom',
          'sceneId': 'custom',
          'sceneLabel': 'Mine',
          'kind': 'passage',
          'level': 'easy',
          'createdAt': 1,
          'model': 'm',
          'title': 'Mine',
          'text': 'Body.',
        },
      ]),
    });

    final migrated = await AiArchiveStore().ensureSeeded();
    final updatedSeed = migrated.where((i) => i.id == sample['id']).single;
    expect(updatedSeed.sceneId, 't29');
    expect(updatedSeed.sceneLabel, '医疗疾病与保健');
    expect(migrated.where((i) => i.id == 'user-custom').single.sceneId, 'custom');
  });

  test('a seed group with the same name joins the local one', () async {
    // The store here predates the seed: same group, different id.
    SharedPreferences.setMockInitialValues({
      'flutter.custom_groups': '[{"id":"local-home","name":"家庭场景"}]',
      'flutter.custom_texts':
          '[{"id":"mine","body":"My own line.","title":"Mine",'
              '"groupId":"local-home","createdAt":"2026-01-01T00:00:00"}]',
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    expect(provider.groups.where((g) => g.name == '家庭场景'), hasLength(1),
        reason: 'never two groups with the same name');
    expect(provider.countIn('local-home'), greaterThan(1),
        reason: 'imported passages land in the group the reader already had');
    expect(provider.allTexts.first.title, 'Mine');
  });

  test('an empty duplicate group is cleaned up on launch', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.custom_groups':
          '[{"id":"local-home","name":"家庭场景"},{"id":"stray","name":"家庭场景"}]',
      'flutter.custom_texts':
          '[{"id":"a","body":"Line.","title":"A","groupId":"local-home",'
              '"createdAt":"2026-01-01T00:00:00"}]',
    });
    final provider = CustomTextProvider();
    await provider.initialize();

    expect(provider.groups.map((g) => g.id), ['local-home']);
  });

  test('a built-in group is put back to its shipped name', () async {
    final raw = await rootBundle.loadString('assets/seed/custom_home.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final group = (seed['groups'] as List).first as Map<String, dynamic>;

    SharedPreferences.setMockInitialValues({
      'flutter.custom_groups':
          jsonEncode([{'id': group['id'], 'name': 'Renamed on this machine'}]),
      'flutter.custom_texts':
          '[{"id":"mine","body":"My own line.","title":"Mine",'
              '"groupId":"${group['id']}","createdAt":"2026-01-01T00:00:00"}]',
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    final shipped = provider.groups.where((g) => g.id == group['id']);
    expect(shipped, hasLength(1), reason: 'one group, not a renamed duplicate');
    expect(shipped.single.name, group['name']);
    expect(provider.allTexts.where((t) => t.id == 'mine').single.groupId,
        group['id'],
        reason: 'the reader\'s own passage stays where it was');
  });

  test('data written on this machine survives a rebuilt library', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.custom_groups': '[{"id":"g-mine","name":"我的分组"}]',
      'flutter.custom_texts':
          '[{"id":"mine","body":"My own line.","title":"Mine",'
              '"groupId":"g-mine","createdAt":"2026-01-01T00:00:00"}]',
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    expect(provider.groups.where((g) => g.id == 'g-mine').single.name, '我的分组',
        reason: 'a group the library does not know is not touched');
    final mine = provider.allTexts.where((t) => t.id == 'mine').single;
    expect(mine.body, 'My own line.');
    expect(mine.groupId, 'g-mine');
    expect(provider.allTexts.length, greaterThan(1),
        reason: 'the shipped passages are added around it');
  });

  test('Oxford Tree levels 0-6 ship clean pure-English stories', () async {
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    final oxfordGroups = provider.groups.where((g) => g.name == '牛津树');
    expect(oxfordGroups, hasLength(1));
    final oxford = oxfordGroups.single;
    expect(oxford.id, 'grp-oxford-tree');

    final shipped = provider.allTexts
        .where((t) => t.groupId == oxford.id && t.id.startsWith('ox_'))
        .toList();
    final perLevel = <String, int>{};
    for (final item in shipped) {
      final level = RegExp(r'^ox_(\d)_').firstMatch(item.id)?.group(1);
      expect(level, isNotNull, reason: '${item.id} should carry its level');
      perLevel.update(level!, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(perLevel.keys.toSet(), {'0', '1', '2', '3', '4', '5', '6'},
        reason: 'every imported level is present');
    expect(perLevel['0'], 27, reason: 'level 0 has 27 source PDFs');

    final cjk = RegExp(r'[\u4e00-\u9fff]');
    for (final item in shipped) {
      final level = RegExp(r'^ox_(\d)_').firstMatch(item.id)!.group(1);
      expect(item.title, contains(' $level · '),
          reason: '${item.id} title marks its level');
      expect(cjk.hasMatch(item.body), isFalse,
          reason: '${item.id} (${item.title}) must contain pure English only');
      expect(item.body.contains('='), isFalse,
          reason: '${item.id} (${item.title}) must not have shifted-space "="');
      expect(item.utterances.length, greaterThanOrEqualTo(30),
          reason: '${item.id} (${item.title}) should hold a full story');
    }
  });

  test('a shipped passage regains its group even when body and title match',
      () async {
    // What an older install looks like after its groups were rebuilt: the text
    // is byte-identical to the library's, but it sits in 未分组. The merge must
    // still put it back where the library files it.
    final raw = await rootBundle.loadString('assets/seed/custom_home.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final groups = (seed['groups'] as List).cast<Map<String, dynamic>>();
    final texts = (seed['texts'] as List).cast<Map<String, dynamic>>();
    final group = groups.firstWhere((g) => (g['name'] as String? ?? '') == '牛津树');
    final shipped = texts.firstWhere((t) => t['groupId'] == group['id']);

    SharedPreferences.setMockInitialValues({
      'flutter.custom_groups': jsonEncode([group]),
      'flutter.custom_texts': jsonEncode([
        {
          'id': shipped['id'],
          'body': shipped['body'],
          'title': shipped['title'],
          'groupId': null,
          'createdAt': '2026-01-01T00:00:00',
        },
      ]),
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    final repaired = provider.allTexts.where((t) => t.id == shipped['id']).single;
    expect(repaired.groupId, group['id'],
        reason: 'the library owns where a shipped passage lives');
  });
}
