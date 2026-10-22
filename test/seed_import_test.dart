import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ai/ai_archive.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install gets the built-in 家庭场景 library', () async {
    final provider = CustomTextProvider();
    await provider.initialize();
    expect(provider.allTexts, isEmpty);

    await provider.ensureSeeded();

    expect(provider.groups.map((g) => g.name), contains('家庭场景'));
    expect(provider.allTexts, isNotEmpty);
    final first = provider.allTexts.first;
    expect(first.body, contains('\n\n'),
        reason: 'the seed keeps its clusters of variants');
    expect(first.title, isNotEmpty);

    // Survives a restart without being imported twice.
    final again = CustomTextProvider();
    await again.initialize();
    expect(again.allTexts, hasLength(provider.allTexts.length));
  });

  test('a library the reader already built is never overwritten', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.custom_texts':
          '[{"id":"mine","body":"My own line.","title":"Mine","createdAt":"2026-01-01T00:00:00"}]',
      'flutter.custom_groups': '[]',
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    await provider.ensureSeeded();

    expect(provider.allTexts, hasLength(1));
    expect(provider.allTexts.single.title, 'Mine');
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

  test('an AI archive with work in it is left alone', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.ai_archive_v1':
          '[{"id":"x","sceneId":"s","sceneLabel":"S","kind":"passage","level":"easy",'
              '"createdAt":1,"model":"m","title":"Mine","text":"Body."}]',
    });
    final seeded = await AiArchiveStore().ensureSeeded();
    expect(seeded, hasLength(1));
    expect(seeded.single.title, 'Mine');
  });
}
