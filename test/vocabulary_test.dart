import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/providers/vocabulary_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('星标', () {
    test('加星与减星都限制在 0…5', () async {
      final vocabulary = VocabularyProvider();
      await vocabulary.initialize();

      expect(vocabulary.starsOf('paper'), 0);
      for (var i = 0; i < 7; i++) {
        await vocabulary.addStar('paper');
      }
      expect(vocabulary.starsOf('paper'), VocabularyProvider.maxStars);

      for (var i = 0; i < 9; i++) {
        await vocabulary.removeStar('paper');
      }
      expect(vocabulary.starsOf('paper'), 0);
    });

    test('星数写进存储，重开仍在', () async {
      final first = VocabularyProvider();
      await first.initialize();
      await first.setStars('paper', 3);
      await first.setStars('oil', 1);
      expect(first.starredCount, 2);

      final second = VocabularyProvider();
      await second.initialize();
      expect(second.starsOf('paper'), 3);
      expect(second.starsOf('oil'), 1);
      expect(second.starsOf('phone'), 0);
      expect(second.starredCount, 2);
    });

    test('坏掉的存储不会拖垮窗口', () async {
      SharedPreferences.setMockInitialValues({'vocab_stars_v1': 'not json'});
      final vocabulary = VocabularyProvider();
      await vocabulary.initialize();
      expect(vocabulary.starsOf('paper'), 0);
    });
  });

  group('星标种子', () {
    test('只补没有评过星的词', () async {
      final vocabulary = VocabularyProvider();
      await vocabulary.initialize();
      await vocabulary.setStars('already', 4);

      final added = vocabulary.mergeSeed({
        'already': 2,
        'fresh': 3,
        'zero': 0,
      });

      expect(added, 1, reason: 'already 有星、zero 不是有效星数');
      expect(vocabulary.starsOf('already'), 4, reason: '读者的星不被覆盖');
      expect(vocabulary.starsOf('fresh'), 3);
      expect(vocabulary.starsOf('zero'), 0);
    });

    test('应用自带星表只灌一次', () async {
      final first = VocabularyProvider();
      await first.initialize();
      await first.ensureSeeded();
      expect(first.starredCount, greaterThan(500),
          reason: '主题文件里标了 * 的词都该带星');

      // 读者改一颗星后重新初始化：种子版本没变，不再灌入。
      await first.setStars('the', 5);
      final second = VocabularyProvider();
      await second.initialize();
      await second.ensureSeeded();
      expect(second.starsOf('the'), 5);
      expect(second.starredCount, first.starredCount);
    });
  });

  group('筛词', () {
    late VocabularyProvider vocabulary;
    const words = ['a', 'b', 'c', 'd'];

    setUp(() async {
      vocabulary = VocabularyProvider();
      await vocabulary.initialize();
      await vocabulary.setStars('a', 1);
      await vocabulary.setStars('b', 2);
      await vocabulary.setStars('c', 2);
      await vocabulary.setStars('d', 3);
    });

    test('不限星数返回全部，顺序不变', () {
      expect(vocabulary.filtered(words), words);
    });

    test('只看带星', () async {
      await vocabulary.setFilter(StarFilter.starred);
      expect(vocabulary.filtered(words), ['a', 'b', 'c', 'd']);
    });

    test('恰好 n 星', () async {
      await vocabulary.setFilter(StarFilter.exact, stars: 2);
      expect(vocabulary.filtered(words), ['b', 'c']);
      await vocabulary.setFilter(StarFilter.exact, stars: 1);
      expect(vocabulary.filtered(words), ['a']);
    });

    test('至少 n 星', () async {
      await vocabulary.setFilter(StarFilter.atLeast, stars: 2);
      expect(vocabulary.filtered(words), ['b', 'c', 'd']);
      await vocabulary.setFilter(StarFilter.atLeast, stars: 3);
      expect(vocabulary.filtered(words), ['d']);
    });

    test('筛掉所有词时返回空表', () async {
      await vocabulary.setFilter(StarFilter.atLeast, stars: 5);
      expect(vocabulary.filtered(words), isEmpty);
    });

    test('筛选写进存储，重开仍在', () async {
      await vocabulary.setFilter(StarFilter.atLeast, stars: 3);
      final reopened = VocabularyProvider();
      await reopened.initialize();
      expect(reopened.filter, StarFilter.atLeast);
      expect(reopened.filterStars, 3);
    });
  });

  group('朗读设置与顺序', () {
    test('默认美音，切换后记住', () async {
      final vocabulary = VocabularyProvider();
      await vocabulary.initialize();
      expect(vocabulary.accent, 'us');
      expect(vocabulary.accentLabel, '美音');

      await vocabulary.toggleAccent();
      expect(vocabulary.accent, 'uk');
      expect(vocabulary.accentLabel, '英音');

      final reopened = VocabularyProvider();
      await reopened.initialize();
      expect(reopened.accent, 'uk');
    });

    test('打乱是一次性的排列，恢复后回到原序', () {
      final vocabulary = VocabularyProvider();
      const words = ['a', 'b', 'c', 'd', 'e'];
      expect(vocabulary.arrange(words), words);

      vocabulary.shuffle(words, random: Random(3));
      final shuffled = vocabulary.arrange(words);
      expect(shuffled.toSet(), words.toSet());
      expect(shuffled, isNot(words));
      expect(vocabulary.arrange(words), shuffled,
          reason: '同一份乱序不能每帧都变');

      vocabulary.restoreOrder();
      expect(vocabulary.arrange(words), words);
    });

    test('筛词后仍按乱序的相对次序显示', () {
      final vocabulary = VocabularyProvider();
      const words = ['a', 'b', 'c', 'd', 'e', 'f'];
      vocabulary.shuffle(words, random: Random(11));
      final shuffled = vocabulary.arrange(words);

      final picked = [for (final word in shuffled) if (word != 'c') word];
      expect(vocabulary.arrange(picked), picked);
    });
  });

  group('释义显隐', () {
    test('默认全隐藏，点一下开、再点一下关', () async {
      final vocabulary = VocabularyProvider();
      await vocabulary.initialize();

      expect(vocabulary.isRevealed('paper'), isFalse);
      vocabulary.toggleGloss('paper');
      expect(vocabulary.isRevealed('paper'), isTrue);
      vocabulary.toggleGloss('paper');
      expect(vocabulary.isRevealed('paper'), isFalse);
    });

    test('一键全部显示与全部隐藏', () async {
      final vocabulary = VocabularyProvider();
      await vocabulary.initialize();

      vocabulary.toggleGloss('paper');
      vocabulary.toggleRevealAll();
      expect(vocabulary.revealAll, isTrue);
      expect(vocabulary.isRevealed('oil'), isTrue, reason: '整表都翻开');
      expect(vocabulary.isRevealed('paper'), isTrue);

      vocabulary.toggleRevealAll();
      expect(vocabulary.revealAll, isFalse);
      expect(vocabulary.isRevealed('paper'), isFalse,
          reason: '收起时逐个翻开的记录也一并清掉');
    });
  });
}
