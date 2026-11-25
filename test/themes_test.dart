import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_dict/core/frequency/frequency_service.dart';
import 'package:local_dict/core/themes/theme_service.dart';
import 'package:local_dict/providers/dictionary_provider.dart';
import 'package:local_dict/providers/themes_provider.dart';
import 'package:local_dict/ui/screens/themes_screen.dart';

/// COCA's file spells a few contractions with a doubled apostrophe (`n''t`);
/// the theme files spell them properly.
String normalize(String word) => word.replaceAll("''", "'");

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The providers remember where the reader was; without the plugin behind
  // SharedPreferences every initialize() would throw.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The frequency file's line order is the rank the generator sorts by.
  Map<String, int> cocaRanks() {
    final ranks = <String, int>{};
    final lines = File('coca-20000.txt').readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final word = normalize(lines[i].trim().toLowerCase());
      if (word.isNotEmpty) ranks.putIfAbsent(word, () => i + 1);
    }
    return ranks;
  }

  group('不限: every theme as one list', () {
    test('deduplicates words and keeps every gloss reachable', () async {
      final themes = ThemesProvider();
      await themes.initialize();

      final any = themes.anyScene;
      expect(any, isNotNull);
      expect(any!.label, '不限');
      expect(any.id, ThemesProvider.anySceneId);

      final all = [for (final scene in themes.scenes) ...scene.words];
      expect(any.words.length, all.toSet().length,
          reason: 'a word in two themes appears once');
      expect(any.words.length, greaterThan(all.length ~/ 2),
          reason: 'the union is not accidentally tiny');

      // A gloss from any theme survives the union.
      final glossed = themes.scenes
          .expand((s) => s.groups)
          .firstWhere((g) => g.glosses.isNotEmpty);
      final word = glossed.glosses.keys.first;
      expect(any.groups.single.glosses[word], glossed.glosses[word]);
    });
  });

  group('Theme data', () {
    test('the asset loads as one flat group per theme', () async {
      final service = ThemeService();
      await service.init();

      expect(service.isLoaded, isTrue);
      expect(service.scenes.length, 57,
          reason: 'the curated taxonomy has 57 themes');
      expect(service.totalWords, 17630);
      for (final scene in service.scenes) {
        expect(scene.label, isNotEmpty);
        expect(scene.id, matches(RegExp(r'^t\d{2}$')));
        expect(scene.groups, hasLength(1),
            reason: '${scene.id} is flat: one group of words');
        expect(scene.count, scene.groups.single.words.length,
            reason: '${scene.id} count drifted');
        expect(scene.count, lessThanOrEqualTo(600),
            reason: '${scene.id} (${scene.label}) should stay focused (<=600 words)');
        expect(scene.words.length, scene.count);
        for (final word in scene.groups.single.words) {
          expect(word, isNotEmpty);
          expect(word, word.toLowerCase(),
              reason: '${scene.id}: "$word" is not lower case');
        }
      }
    });

    test('every word carries its Chinese gloss for the drill', () async {
      final service = ThemeService();
      await service.init();
      for (final scene in service.scenes) {
        final group = scene.groups.single;
        expect(group.glosses.length, group.words.length,
            reason: '${scene.id}: 每个词都该有释义');
        for (final word in group.words) {
          expect(group.glosses[word]?.trim(), isNotEmpty,
              reason: '${scene.id}/$word has no gloss');
        }
      }
    });

    test('every word exists in COCA and is ordered by its rank', () async {
      final ranks = cocaRanks();
      final service = ThemeService();
      await service.init();

      for (final scene in service.scenes) {
        var previous = 0;
        for (final word in scene.words) {
          final rank = ranks[word];
          expect(rank, isNotNull, reason: '${scene.id}: "$word" is not COCA');
          expect(rank!, greaterThan(previous),
              reason: '${scene.id}: "$word" is out of frequency order');
          previous = rank;
        }
      }
    });

    test('the themes partition the vocabulary', () async {
      final service = ThemeService();
      await service.init();
      final seen = <String>{};
      for (final scene in service.scenes) {
        for (final word in scene.words) {
          expect(seen.add(word), isTrue,
              reason: '"$word" sits in ${scene.id} and somewhere else');
        }
      }
      expect(seen.length, service.totalWords);
    });

    test('the themes cover the COCA headwords', () async {
      final ranks = cocaRanks();
      final service = ThemeService();
      await service.init();
      final placed = {for (final scene in service.scenes) ...scene.words};

      // Four COCA entries never made it into the curation — two slash pairs and
      // two spellings that the files fold into their neighbours. They are the
      // only gaps the source data has, so a new gap means words were dropped.
      const known = {'and/or', 'his/her', 'he/she', 'sauté'};
      final missing = ranks.keys.where((word) => !placed.contains(word)).toSet();
      expect(missing.difference(known), isEmpty,
          reason: 'unclassified: ${missing.difference(known)}');
      expect(missing, containsAll(known));
    });

    test('FrequencyService loads 5.4w COCA list and covers theme words',
        () async {
      final expectedJson = json.decode(
        File('assets/data/coca_60000.json').readAsStringSync(),
      ) as List<dynamic>;
      final expectedOrder = expectedJson.cast<String>();
      expect(expectedOrder.length, greaterThan(53000));

      final freq = FrequencyService();
      await freq.init();
      expect(freq.rankedWords, orderedEquals(expectedOrder));

      final themes = ThemeService();
      await themes.init();
      var covered = 0;
      var total = 0;
      for (final scene in themes.scenes) {
        for (final word in scene.words) {
          total++;
          final info = freq.getFrequency(word);
          if (info == null) continue;
          covered++;
          expect(info.rank, isPositive);
          expect(info.frequencyLabel, 'COCA #${info.rank}');
        }
      }
      expect(total, 17630);
      expect(covered, greaterThanOrEqualTo(17550));
      expect(freq.getFrequency('not_in_coca_list'), isNull);
    });
  });

  group('Themes provider', () {
    test('opening a theme shows its words and going back clears it', () async {
      final provider = ThemesProvider();
      await provider.initialize();
      expect(provider.isLoading, isFalse);
      expect(provider.selectedScene, isNull);

      final scene = provider.scenes.first;
      provider.select(scene.id);
      expect(provider.selectedScene?.id, scene.id);
      expect(provider.visibleGroups, hasLength(1));
      expect(provider.visibleWordCount, scene.count);

      provider.backToScenes();
      expect(provider.selectedScene, isNull);
    });

    test('the search box narrows themes, then words inside one', () async {
      final provider = ThemesProvider();
      await provider.initialize();

      provider.setQuery('zzzznotaword');
      expect(provider.visibleScenes, isEmpty);

      provider.setQuery('hospital');
      expect(provider.visibleScenes, isNotEmpty,
          reason: 'a word should find the themes that hold it');

      final scene = provider.visibleScenes.first;
      provider.select(scene.id);
      expect(provider.query, isEmpty, reason: 'opening a theme clears the query');

      provider.setQuery('zzzznotaword');
      expect(provider.visibleGroups, isEmpty);
      expect(provider.visibleWordCount, 0);
    });

    test('a theme longer than a page pages at 50 words', () async {
      final provider = ThemesProvider();
      await provider.initialize();
      // Pick the longest theme (饮食与烹饪, 569 words) to verify pagination.
      final scene = provider.scenes.reduce(
          (a, b) => a.count >= b.count ? a : b);
      provider.select(scene.id);
      final group = provider.visibleGroups.single;
      const size = ThemesProvider.facetPageSize;

      expect(group.words.length, greaterThan(ThemesProvider.facetPageThreshold));
      expect(provider.facetPageCount(group),
          (group.words.length + size - 1) ~/ size);
      expect(provider.facetWords(group), hasLength(size));
      expect(provider.visibleWordCount, group.words.length,
          reason: 'the header keeps the full count');

      final head = provider.facetWords(group).first;
      provider.setFacetPage(group, 1);
      expect(provider.facetPage(group), 1);
      expect(provider.facetWords(group).first, group.words[size]);
      expect(provider.facetWords(group).first, isNot(head));
    });

    test('the shortest theme pages too, and its last page holds the rest',
        () async {
      final provider = ThemesProvider();
      await provider.initialize();
      // The smallest theme (天文与宇宙探索, 63 words) still exceeds one page — every
      // theme in the taxonomy does — so the last page is a partial slice.
      final scene = provider.scenes.reduce(
          (a, b) => a.count <= b.count ? a : b);
      provider.select(scene.id);
      final group = provider.visibleGroups.single;
      const size = ThemesProvider.facetPageSize;

      expect(provider.facetPageCount(group), 2);
      expect(provider.facetWords(group).length, size);
      provider.setFacetPage(group, 1);
      expect(provider.facetWords(group).length, group.words.length - size);
    });

    test('macro domains partition all 57 scenes and filter visibleScenes',
        () async {
      final provider = ThemesProvider();
      await provider.initialize();

      final covered = <String>{};
      for (final domain in ThemesProvider.domains.where((d) => d.id != 'all')) {
        provider.setDomain(domain.id);
        expect(provider.visibleScenes, isNotEmpty,
            reason: '${domain.id} should hold scenes');
        for (final scene in provider.visibleScenes) {
          expect(covered.add(scene.id), isTrue,
              reason: '${scene.id} fell into two domains');
        }
      }
      expect(covered, hasLength(provider.sceneCount));

      provider.setDomain('all');
      expect(provider.visibleScenes, hasLength(provider.sceneCount));
    });
  });

  group('Themes screen', () {
    Future<ThemesProvider> pumpScreen(WidgetTester tester) async {
      final provider = ThemesProvider();
      await provider.initialize();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemesProvider>.value(value: provider),
            ChangeNotifierProvider(create: (_) => DictionaryProvider()),
          ],
          child: const MaterialApp(home: ThemesScreen(isPaneView: true)),
        ),
      );
      await tester.pumpAndSettle();
      return provider;
    }

    testWidgets('lists the themes and opens one to its words', (tester) async {
      final provider = await pumpScreen(tester);
      final first = provider.scenes.first;

      expect(find.text(first.label), findsWidgets);
      await tester.tap(find.text(first.label).first);
      await tester.pumpAndSettle();

      expect(provider.selectedScene?.id, first.id);
      // Flat themes show their words immediately — there is no facet to unfold.
      expect(find.byType(ActionChip), findsWidgets);
      expect(find.text(first.words.first), findsWidgets);
    });

    testWidgets('the longest theme pages in place', (tester) async {
      final provider = await pumpScreen(tester);
      final long = provider.scenes.reduce((a, b) => a.count >= b.count ? a : b);
      await tester.scrollUntilVisible(
        find.text(long.label),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text(long.label).first);
      await tester.pumpAndSettle();

      final group = provider.visibleGroups.single;
      final pages = provider.facetPageCount(group);
      expect(pages, greaterThan(5));
      expect(find.text('第 1 / $pages 页'), findsOneWidget);

      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(provider.facetPage(group), 1);
      expect(find.text('第 2 / $pages 页'), findsOneWidget);
      expect(provider.facetWords(group).first, group.words[ThemesProvider.facetPageSize]);
    });

    testWidgets('the page label jumps to a typed page', (tester) async {
      final provider = await pumpScreen(tester);
      final long = provider.scenes.reduce((a, b) => a.count >= b.count ? a : b);
      await tester.scrollUntilVisible(
        find.text(long.label),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text(long.label).first);
      await tester.pumpAndSettle();

      final group = provider.visibleGroups.single;
      final pages = provider.facetPageCount(group);
      await tester.tap(find.text('第 1 / $pages 页'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '5');
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();

      expect(provider.facetPage(group), 4);
      expect(find.text('第 5 / $pages 页'), findsOneWidget);
      expect(provider.facetWords(group).first,
          group.words[ThemesProvider.facetPageSize * 4]);
    });

    testWidgets('domain filter chips narrow scenes and show reset option',
        (tester) async {
      final provider = await pumpScreen(tester);
      await tester.tap(find.text('自然时空'));
      await tester.pumpAndSettle();

      expect(provider.domainId, 'nature');
      expect(provider.visibleScenes, hasLength(8));
      expect(find.text('50'), findsOneWidget);
      expect(find.text('时间日期与周期'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('天文与宇宙探索'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('57'), findsOneWidget);
      expect(find.text('8 / 57 个场景 · 17630 条归属'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'zzzznotaword');
      await tester.pumpAndSettle();
      expect(find.text('在全部 57 个场景中查看'), findsOneWidget);
      await tester.tap(find.text('在全部 57 个场景中查看'));
      await tester.pumpAndSettle();
      expect(provider.domainId, 'all');
    });

    testWidgets('tapping a word chip highlights it in red and moves on next tap',
        (tester) async {
      final provider = await pumpScreen(tester);
      final first = provider.scenes.first;
      await tester.tap(find.text(first.label).first);
      await tester.pumpAndSettle();

      final words = first.words.take(2).toList();
      final firstWord = words[0];
      final secondWord = words[1];

      ActionChip chipFor(String word) => tester.widget<ActionChip>(
            find.ancestor(
              of: find.text(word),
              matching: find.byType(ActionChip),
            ),
          );

      expect(chipFor(firstWord).backgroundColor, isNull);
      expect(chipFor(secondWord).backgroundColor, isNull);

      await tester.tap(find.text(firstWord));
      await tester.pumpAndSettle();

      final activeFirst = chipFor(firstWord);
      expect(activeFirst.backgroundColor, ThemesScreen.selectedWordChipColor);
      expect(activeFirst.side?.color, ThemesScreen.selectedWordChipColor);
      expect((activeFirst.label as Text).style?.color, Colors.white);
      expect(chipFor(secondWord).backgroundColor, isNull);

      await tester.tap(find.text(secondWord));
      await tester.pumpAndSettle();

      final activeSecond = chipFor(secondWord);
      expect(activeSecond.backgroundColor, ThemesScreen.selectedWordChipColor);
      expect(activeSecond.side?.color, ThemesScreen.selectedWordChipColor);
      expect((activeSecond.label as Text).style?.color, Colors.white);
      expect(chipFor(firstWord).backgroundColor, isNull);

      final dictProvider = tester
          .element(find.byType(ThemesScreen))
          .read<DictionaryProvider>();
      await dictProvider.lookupWord(firstWord.toUpperCase());
      await tester.pumpAndSettle();

      expect(chipFor(firstWord).backgroundColor, ThemesScreen.selectedWordChipColor);
      expect(chipFor(secondWord).backgroundColor, isNull);
    });
  });
}
