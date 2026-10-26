import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('Theme data', () {
    test('the asset loads as one flat group per theme', () async {
      final service = ThemeService();
      await service.init();

      expect(service.isLoaded, isTrue);
      expect(service.scenes.length, 39,
          reason: 'the curated taxonomy has 39 themes');
      expect(service.totalWords, 17630);
      for (final scene in service.scenes) {
        expect(scene.label, isNotEmpty);
        expect(scene.id, matches(RegExp(r'^t\d{2}$')));
        expect(scene.groups, hasLength(1),
            reason: '${scene.id} is flat: one group of words');
        expect(scene.count, scene.groups.single.words.length,
            reason: '${scene.id} count drifted');
        expect(scene.words.length, scene.count);
        for (final word in scene.groups.single.words) {
          expect(word, isNotEmpty);
          expect(word, word.toLowerCase(),
              reason: '${scene.id}: "$word" is not lower case');
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
      // 器物与材料 holds 1099 words — the longest theme.
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
      // The smallest theme (天文与宇宙, 75 words) still exceeds one page — every
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
  });
}
