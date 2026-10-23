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

  test('a library version already merged is not touched again', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.custom_texts': '[]',
      'flutter.custom_groups': '[]',
      'flutter.custom_library_version': 999,
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    expect(provider.allTexts, isEmpty, reason: 'newer than the shipped version');
    expect(provider.groups, isEmpty);
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
}
