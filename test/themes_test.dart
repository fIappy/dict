import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:local_dict/core/themes/theme_service.dart';
import 'package:local_dict/providers/dictionary_provider.dart';
import 'package:local_dict/providers/themes_provider.dart';
import 'package:local_dict/ui/screens/themes_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The frequency file's line order is the rank the generator sorts by.
  Map<String, int> cocaRanks() {
    final ranks = <String, int>{};
    final lines = File('coca-20000.txt').readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final word = lines[i].trim().toLowerCase();
      if (word.isNotEmpty) ranks.putIfAbsent(word, () => i + 1);
    }
    return ranks;
  }

  group('Theme data', () {
    test('the asset loads with usable scenes and facets', () async {
      final service = ThemeService();
      await service.init();

      expect(service.isLoaded, isTrue);
      expect(service.scenes.length, greaterThanOrEqualTo(20),
          reason: 'the module is meant to cover modern life end to end');
      expect(service.totalWords, greaterThan(1000));
      expect(
        service.facets.map((f) => f.label),
        containsAll(<String>['人', '事', '物', '动作', '情况', '虚拟']),
      );
      for (final scene in service.scenes) {
        expect(scene.label, isNotEmpty);
        expect(scene.groups, isNotEmpty, reason: '${scene.id} has no facets');
        for (final group in scene.groups) {
          expect(group.words, isNotEmpty, reason: '${scene.id}/${group.id}');
          expect(
            group.words.every((w) => w.isNotEmpty && w == w.toLowerCase()),
            isTrue,
            reason: '${scene.id}/${group.id} has a malformed word',
          );
        }
      }
    });

    test('each scene count matches its facets', () async {
      final service = ThemeService();
      await service.init();
      for (final scene in service.scenes) {
        final actual = scene.groups.fold<int>(0, (sum, g) => sum + g.words.length);
        expect(scene.count, actual, reason: '${scene.id} count drifted');
        expect(scene.words.length, actual);
      }
    });

    test('every word exists in COCA and is ordered by its rank', () async {
      final ranks = cocaRanks();
      final service = ThemeService();
      await service.init();

      for (final scene in service.scenes) {
        for (final group in scene.groups) {
          var previous = 0;
          for (final word in group.words) {
            final rank = ranks[word];
            expect(rank, isNotNull, reason: '${scene.id}/${group.id}: "$word" is not COCA');
            expect(rank!, greaterThan(previous),
                reason: '${scene.id}/${group.id}: "$word" is out of frequency order');
            previous = rank;
          }
        }
      }
    });

    test('every COCA word is placed', () async {
      // The acceptance criterion for full coverage: the 17,634 de-duplicated
      // COCA headwords are all reachable from a scene. Adding a COCA word
      // without classifying it fails here.
      final ranks = cocaRanks();
      final service = ThemeService();
      await service.init();
      final placed = <String>{for (final scene in service.scenes) ...scene.words};

      // totalWords counts *placements* (a word may sit in up to 3 scenes), so
      // it is >= the distinct count, not equal to it.
      expect(placed.length, ranks.length);
      expect(service.totalWords, greaterThanOrEqualTo(ranks.length));
      final missing =
          ranks.keys.where((word) => !placed.contains(word)).toList()..sort();
      expect(missing, isEmpty, reason: 'unclassified: ${missing.take(20).toList()}');
    });

    test('no facet repeats a word', () async {
      final service = ThemeService();
      await service.init();
      for (final scene in service.scenes) {
        for (final group in scene.groups) {
          expect(group.words.toSet().length, group.words.length,
              reason: '${scene.id}/${group.id} lists a word twice');
        }
      }
    });
  });

  group('Themes provider', () {
    test('opening a scene filters its words and going back clears it', () async {
      final provider = ThemesProvider();
      await provider.initialize();
      expect(provider.isLoading, isFalse);
      expect(provider.selectedScene, isNull);

      final scene = provider.scenes.first;
      provider.select(scene.id);
      expect(provider.selectedScene?.id, scene.id);
      expect(provider.visibleGroups, isNotEmpty);
      expect(provider.visibleWordCount, scene.count);

      provider.select(scene.id);
      provider.backToScenes();
      expect(provider.selectedScene, isNull);
    });

    test('the search box narrows scenes, then words inside one', () async {
      final provider = ThemesProvider();
      await provider.initialize();

      provider.setQuery('zzzznotaword');
      expect(provider.visibleScenes, isEmpty);

      provider.setQuery('hospital');
      expect(provider.visibleScenes, isNotEmpty,
          reason: 'a word should find the scenes that hold it');

      final scene = provider.visibleScenes.first;
      provider.select(scene.id);
      expect(provider.query, isEmpty, reason: 'opening a scene clears the query');

      provider.setQuery('zzzznotaword');
      expect(provider.visibleGroups, isEmpty);
      expect(provider.visibleWordCount, 0);
    });

    test('facets start folded and toggle open', () async {
      final provider = ThemesProvider();
      await provider.initialize();
      final scene = provider.scenes.first;
      provider.select(scene.id);

      expect(provider.visibleGroups.length, greaterThan(1));
      for (final group in provider.visibleGroups) {
        expect(provider.isFacetExpanded(group.id), isFalse,
            reason: 'a scene opens with its facet headers, not a wall of words');
      }

      final first = provider.visibleGroups.first;
      provider.toggleFacet(first.id);
      expect(provider.isFacetExpanded(first.id), isTrue);
      provider.toggleFacet(first.id);
      expect(provider.isFacetExpanded(first.id), isFalse);

      provider.toggleFacet(first.id);
      provider.backToScenes();
      provider.select(scene.id);
      expect(provider.isFacetExpanded(first.id), isFalse,
          reason: 'a fresh scene starts folded again');
    });

    test('a long facet pages at 50 words, a short one does not', () async {
      final provider = ThemesProvider();
      await provider.initialize();
      provider.select(provider.scenes.first.id);

      final groups = provider.visibleGroups;
      final long = groups.reduce((a, b) => a.words.length >= b.words.length ? a : b);
      final short = groups.reduce((a, b) => a.words.length <= b.words.length ? a : b);
      const size = ThemesProvider.facetPageSize;

      expect(long.words.length, greaterThan(ThemesProvider.facetPageThreshold));
      expect(provider.facetPageCount(long), (long.words.length + size - 1) ~/ size);
      expect(provider.facetWords(long).length, size);
      expect(provider.visibleGroups.firstWhere((g) => g.id == long.id).words.length,
          long.words.length, reason: 'the facet header keeps the full count');

      expect(provider.facetPageCount(short), 1);
      expect(provider.facetWords(short), short.words);

      final head = provider.facetWords(long).first;
      provider.setFacetPage(long, 1);
      expect(provider.facetPage(long), 1);
      expect(provider.facetWords(long).first, isNot(head));
      expect(provider.facetWords(long).first, long.words[size]);
    });

    test('searching a scene opens the facets that matched', () async {
      final provider = ThemesProvider();
      await provider.initialize();
      provider.select(provider.scenes.first.id);
      final probe = provider.visibleGroups.first.words.first;
      provider.setQuery(probe.substring(0, 3));

      expect(provider.visibleGroups, isNotEmpty);
      for (final group in provider.visibleGroups) {
        expect(provider.isFacetExpanded(group.id), isTrue,
            reason: 'a hit hidden behind a folded header reads as no hit');
      }
    });
  });

  group('Themes screen', () {
    testWidgets('lists scenes, then shows facets and words', (tester) async {
      final provider = ThemesProvider();
      await provider.initialize();
      final first = provider.scenes.first;

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

      expect(find.text(first.label), findsWidgets);
      await tester.tap(find.text(first.label).first);
      await tester.pumpAndSettle();

      expect(provider.selectedScene, isNotNull);
      final facet = provider.visibleGroups.first;
      expect(find.text(facet.label), findsWidgets);
      await tester.tap(find.text(facet.label).first);
      await tester.pumpAndSettle();
      expect(find.text(facet.words.first), findsWidgets);
    });

    testWidgets('facets fold, and a long facet pages in place', (tester) async {
      final provider = ThemesProvider();
      await provider.initialize();
      provider.select(provider.scenes.first.id);
      final groups = provider.visibleGroups;
      final long = groups.reduce((a, b) => a.words.length >= b.words.length ? a : b);

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

      for (final group in groups) {
        expect(find.text(group.label), findsWidgets);
      }
      expect(find.byType(ActionChip), findsNothing, reason: 'all facets start folded');

      await tester.tap(find.text(long.label).first);
      await tester.pumpAndSettle();
      expect(provider.isFacetExpanded(long.id), isTrue);
      expect(find.byType(ActionChip), findsWidgets);
      expect(find.text('第 1 / ${provider.facetPageCount(long)} 页'), findsOneWidget);

      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(provider.facetPage(long), 1);
      expect(find.text('第 2 / ${provider.facetPageCount(long)} 页'), findsOneWidget);

      await tester.tap(find.text(long.label).first);
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNothing, reason: 'folding hides the words');
    });

    testWidgets('the page label jumps to a typed page', (tester) async {
      final provider = ThemesProvider();
      await provider.initialize();
      provider.select(provider.scenes.first.id);
      final long = provider.visibleGroups
          .reduce((a, b) => a.words.length >= b.words.length ? a : b);
      final pages = provider.facetPageCount(long);
      expect(pages, greaterThan(5), reason: 'needs a facet long enough to jump in');

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

      await tester.tap(find.text(long.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 1 / $pages 页'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '5');
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();

      expect(provider.facetPage(long), 4);
      expect(find.text('第 5 / $pages 页'), findsOneWidget);
      expect(provider.facetWords(long).first, long.words[ThemesProvider.facetPageSize * 4]);
    });
  });
}
