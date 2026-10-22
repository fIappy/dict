import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/custom/custom_text.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Custom text model', () {
    test('a passage is split at sentence ends and line breaks', () {
      const body = 'I wake up at seven. I make coffee!\n'
          'Do I read before work? Yes；我读一会儿。\n'
          'Then I leave.';
      expect(splitSentences(body), [
        'I wake up at seven.',
        'I make coffee!',
        'Do I read before work?',
        'Yes；我读一会儿。',
        'Then I leave.',
      ]);
    });

    test('a phrase is one utterance, a passage is its sentences', () {
      final phrase = CustomText(
        id: 'a',
        kind: CustomTextKind.phrase,
        body: ' on the house ',
        createdAt: DateTime(2026),
      );
      expect(phrase.utterances, ['on the house']);

      final passage = CustomText(
        id: 'b',
        kind: CustomTextKind.passage,
        body: 'One. Two.',
        createdAt: DateTime(2026),
      );
      expect(passage.utterances, ['One.', 'Two.']);
    });

    test('the list label falls back to the first line and is truncated', () {
      final unnamed = CustomText(
        id: 'c',
        kind: CustomTextKind.phrase,
        body: '\n  the early bird catches the worm  ',
        createdAt: DateTime(2026),
      );
      expect(unnamed.label, 'the early bird catches the worm');

      final long = CustomText(
        id: 'd',
        kind: CustomTextKind.passage,
        body: 'x' * 80,
        createdAt: DateTime(2026),
      );
      expect(long.label.length, 49);
      expect(long.label.endsWith('…'), isTrue);
    });

    test('json round-trips kind, group and body', () {
      final item = CustomText(
        id: 'e',
        kind: CustomTextKind.passage,
        body: 'Hello there.',
        title: 'Greeting',
        groupId: 'g1',
        createdAt: DateTime(2026, 10, 20, 9, 30),
      );
      final restored = CustomText.fromJson(item.toJson());
      expect(restored.id, 'e');
      expect(restored.kind, CustomTextKind.passage);
      expect(restored.body, 'Hello there.');
      expect(restored.title, 'Greeting');
      expect(restored.groupId, 'g1');
      expect(restored.createdAt, item.createdAt);
    });
  });

  group('Custom text store', () {
    test('entries and groups survive a restart', () async {
      final first = CustomTextProvider();
      await first.initialize();
      final group = await first.addGroup('商务');
      await first.add(
        kind: CustomTextKind.phrase,
        body: 'at your earliest convenience',
        groupId: group!.id,
      );

      final second = CustomTextProvider();
      await second.initialize();
      expect(second.allTexts.single.body, 'at your earliest convenience');
      expect(second.allTexts.single.groupId, group.id);
      expect(second.groups.single.name, '商务');
    });

    test('the tab and the group filter pick the list', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final work = await provider.addGroup('工作');
      await provider.add(kind: CustomTextKind.phrase, body: 'a');
      await provider.add(
          kind: CustomTextKind.phrase, body: 'b', groupId: work!.id);
      await provider.add(kind: CustomTextKind.passage, body: 'c. d.');

      expect(provider.visibleTexts.map((e) => e.body), ['a', 'b']);

      provider.selectKind(CustomTextKind.passage);
      expect(provider.visibleTexts.map((e) => e.body), ['c. d.']);

      provider.selectKind(CustomTextKind.phrase);
      provider.setGroupFilter(work.id);
      expect(provider.visibleTexts.map((e) => e.body), ['b']);

      provider.setGroupFilter(CustomTextProvider.ungroupedFilter);
      expect(provider.visibleTexts.map((e) => e.body), ['a']);
    });

    test('deleting a group keeps its entries, ungrouped', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final group = await provider.addGroup('临时');
      await provider.add(
          kind: CustomTextKind.phrase, body: 'keep me', groupId: group!.id);

      await provider.removeGroup(group.id);

      expect(provider.groups, isEmpty);
      expect(provider.allTexts.single.groupId, isNull);
      expect(provider.groupFilter, isNull);
    });

    test('the playback queue walks the visible list, passages by sentence', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      await provider.add(kind: CustomTextKind.phrase, body: 'in charge of');
      await provider.add(kind: CustomTextKind.passage, body: 'One. Two.');
      await provider.add(kind: CustomTextKind.passage, body: 'Three.');

      provider.selectKind(CustomTextKind.passage);
      final queue = provider.playbackQueue;
      expect(queue.map((e) => e.text), ['One.', 'Two.', 'Three.']);
      expect(queue.every((e) => !e.isPhrase), isTrue);

      provider.selectKind(CustomTextKind.phrase);
      expect(provider.playbackQueue.single.isPhrase, isTrue);
    });

    test('updating the group moves the entry without touching the body', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final item = await provider.add(kind: CustomTextKind.phrase, body: 'body');
      final group = await provider.addGroup('归档');

      await provider.update(item.copyWith(groupId: group!.id));

      expect(provider.allTexts.single.groupId, group.id);
      expect(provider.allTexts.single.body, 'body');

      await provider.update(provider.allTexts.single.copyWith(clearGroup: true));
      expect(provider.allTexts.single.groupId, isNull);
    });
  });
}
