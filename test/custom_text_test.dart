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

    test('a body without punctuation is a single sentence', () {
      final oneLiner = CustomText(
        id: 'a',
        body: ' on the house ',
        createdAt: DateTime(2026),
      );
      expect(oneLiner.utterances, ['on the house']);
    });

    test('the list label falls back to the first line and is truncated', () {
      final unnamed = CustomText(
        id: 'c',
        body: '\n  the early bird catches the worm  ',
        createdAt: DateTime(2026),
      );
      expect(unnamed.label, 'the early bird catches the worm');

      final long = CustomText(
        id: 'd',
        body: 'x' * 80,
        createdAt: DateTime(2026),
      );
      expect(long.label.length, 49);
      expect(long.label.endsWith('…'), isTrue);
    });

    test('json round-trips body, title and group', () {
      final item = CustomText(
        id: 'e',
        body: 'Hello there.',
        title: 'Greeting',
        groupId: 'g1',
        createdAt: DateTime(2026, 10, 20, 9, 30),
      );
      final restored = CustomText.fromJson(item.toJson());
      expect(restored.id, 'e');
      expect(restored.body, 'Hello there.');
      expect(restored.title, 'Greeting');
      expect(restored.groupId, 'g1');
      expect(restored.createdAt, item.createdAt);
    });

    test('an entry stored as a phrase by the old build loads as a passage', () {
      // The old wire format carried kind: 'phrase'; it is ignored, and a body
      // without sentence punctuation plays as its single sentence.
      final stored = CustomText.fromJson(const {
        'id': 'legacy',
        'kind': 'phrase',
        'body': 'on the house',
        'title': '',
        'groupId': null,
        'createdAt': '2026-10-20T09:30:00.000',
      });
      expect(stored.utterances, ['on the house']);
      expect(stored.toJson().containsKey('kind'), isFalse,
          reason: 'the field is dropped the next time the store is written');
    });
  });

  group('Custom text store', () {
    test('entries and groups survive a restart', () async {
      final first = CustomTextProvider();
      await first.initialize();
      final group = await first.addGroup('商务');
      await first.add(
        body: 'at your earliest convenience',
        groupId: group!.id,
      );

      final second = CustomTextProvider();
      await second.initialize();
      expect(second.allTexts.single.body, 'at your earliest convenience');
      expect(second.allTexts.single.groupId, group.id);
      expect(second.groups.single.name, '商务');
    });

    test('the group is the top level', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final work = await provider.addGroup('工作');
      await provider.add(body: 'a');
      await provider.add(body: 'b', groupId: work!.id);
      await provider.add(body: 'c. d.', groupId: work.id);

      // 未分组 is the default bucket and holds only the ungrouped entries.
      expect(provider.selectedGroupId, CustomTextProvider.ungroupedId);
      expect(provider.visibleTexts.map((e) => e.body), ['a']);
      expect(provider.countIn(work.id), 2);

      provider.selectGroup(work.id);
      expect(provider.visibleTexts.map((e) => e.body), ['b', 'c. d.']);
    });

    test('deleting a group keeps its entries, ungrouped', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final group = await provider.addGroup('临时');
      await provider.add(body: 'keep me', groupId: group!.id);
      provider.selectGroup(group.id);

      await provider.removeGroup(group.id);

      expect(provider.groups, isEmpty);
      expect(provider.allTexts.single.groupId, isNull);
      expect(provider.selectedGroupId, CustomTextProvider.ungroupedId);
    });

    test('the playback queue walks the open group, by sentence', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final work = await provider.addGroup('工作');
      await provider.add(body: 'in charge of');
      await provider.add(body: 'One. Two.', groupId: work!.id);
      await provider.add(body: 'Three.', groupId: work.id);

      provider.selectGroup(work.id);
      expect(provider.playbackQueue.map((e) => e.text), ['One.', 'Two.', 'Three.']);
      expect(provider.playbackQueue.every((e) => !e.isPhrase), isTrue);

      provider.selectGroup(CustomTextProvider.ungroupedId);
      expect(provider.playbackQueue.single.text, 'in charge of');
    });

    test('updating the group moves the entry without touching the body', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final item = await provider.add(body: 'body');
      final group = await provider.addGroup('归档');

      await provider.update(item.copyWith(groupId: group!.id));

      expect(provider.allTexts.single.groupId, group.id);
      expect(provider.allTexts.single.body, 'body');

      await provider.update(provider.allTexts.single.copyWith(clearGroup: true));
      expect(provider.allTexts.single.groupId, isNull);
    });
  });
}
