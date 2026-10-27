import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/custom/custom_text.dart';
import 'package:local_dict/core/custom/playback_order.dart';
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

    test('segments keep the line breaks and line up with the sentences', () {
      final segments = passageSegments('One.\nTwo.\n\nThree.');
      expect(segments.where((s) => s.isSentence).map((s) => s.text),
          ['One.', 'Two.', 'Three.']);
      expect(segments.where((s) => s.isSentence).map((s) => s.sentenceIndex),
          [0, 1, 2]);
      expect(segments.map((s) => s.separator).toList(),
          ['\n', '\n\n', '']);
      // The same rule as playback, so a highlight index means the same line.
      expect(splitSentences('One.\nTwo.\n\nThree.'),
          segments.where((s) => s.isSentence).map((s) => s.text).toList());
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
      final queue = provider.queueFor(PlaybackOrder.sequential);
      expect(queue.map((e) => e.text), ['One.', 'Two.', 'Three.']);
      expect(queue.every((e) => !e.isPhrase), isTrue);

      provider.selectGroup(CustomTextProvider.ungroupedId);
      expect(provider.queueFor(PlaybackOrder.sequential).single.text, 'in charge of');
    });

    test('shuffle reorders the articles, never their sentences', () async {
      final provider = CustomTextProvider();
      await provider.initialize();
      final group = await provider.addGroup('随机');
      await provider.add(body: 'A1. A2.', groupId: group!.id);
      await provider.add(body: 'B1. B2.', groupId: group.id);
      await provider.add(body: 'C1. C2.', groupId: group.id);
      provider.selectGroup(group.id);

      final ordered = provider.queueFor(PlaybackOrder.sequential);
      final shuffled = provider.queueFor(PlaybackOrder.shuffle, random: Random(7));

      // Same lines, and each article still reads top to bottom: every chunk of
      // two starts a new article.
      expect(shuffled.map((e) => e.text).toSet(), ordered.map((e) => e.text).toSet());
      expect(shuffled.length, ordered.length);
      for (var i = 0; i < shuffled.length; i += 2) {
        expect(shuffled[i + 1].text, endsWith('2.'));
        expect(shuffled[i].text.substring(0, 1), shuffled[i + 1].text.substring(0, 1));
      }
      final firstLetters =
          [for (var i = 0; i < shuffled.length; i += 2) shuffled[i].text.substring(0, 1)];
      expect(firstLetters, isNot(['A', 'B', 'C']));
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

  group('reading from a position', () {
    const body = 'I put my bag down.\nI turned on the light.\n\nI sat down.';

    test('a click inside a sentence starts that sentence', () {
      // Offset 3 is inside "I put my bag down."
      expect(sentencesFrom(body, 3).first, 'I put my bag down.');
      // Offset just past the first sentence starts the second one.
      final second = body.indexOf('I turned');
      expect(sentencesFrom(body, second).first, 'I turned on the light.');
    });

    test('everything from that sentence to the end comes back in order', () {
      final from = sentencesFrom(body, body.indexOf('I sat'));
      expect(from, ['I sat down.']);
      expect(sentencesFrom(body, 0), hasLength(3));
    });

    test('a position past the end still yields the last sentence', () {
      expect(sentencesFrom(body, body.length + 50), ['I sat down.']);
    });

    test('ranges cover the text without overlapping', () {
      final ranges = sentenceRanges(body);
      expect(ranges.first.start, 0);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].start, greaterThanOrEqualTo(ranges[i - 1].end));
      }
      expect(ranges.last.end, body.length);
    });
  });
}
