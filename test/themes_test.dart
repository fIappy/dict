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

    test('a long scene is paged 300 words at a time', () async {
      final provider = ThemesProvider();
      await provider.initialize();

      final big = provider.scenes.reduce((a, b) => a.count >= b.count ? a : b);
      expect(big.count, greaterThan(ThemesProvider.pageWordThreshold));
      provider.select(big.id);

      int shownWords() =>
          provider.visibleGroups.fold(0, (n, group) => n + group.words.length);

      expect(shownWords(), ThemesProvider.pageSize);
      expect(provider.pageCount,
          (big.count + ThemesProvider.pageSize - 1) ~/ ThemesProvider.pageSize);
      expect(provider.visibleWordCount, big.count,
          reason: 'the scene header reports the whole scene, not the page');

      final head = provider.visibleGroups.first;
      expect(provider.groupTotalWords(head.id), greaterThan(head.words.length),
          reason: 'a facet longer than one page keeps reporting its full size');

      final firstPageHead = provider.visibleGroups.first.words.first;
      provider.setPage(1);
      expect(provider.page, 1);
      expect(shownWords(), ThemesProvider.pageSize);
      expect(provider.visibleGroups.first.words.first, isNot(firstPageHead));

      provider.setQuery('zzzznotaword');
      expect(provider.page, 0, reason: 'a new query restarts at page 1');
      expect(provider.pageCount, 1);
      expect(provider.visibleGroups, isEmpty);

      provider.setQuery('');
      expect(provider.page, 0);
    });

    test('a short scene stays on one page', () async {
      final provider = ThemesProvider();
      await provider.initialize();

      final small = provider.scenes.reduce((a, b) => a.count <= b.count ? a : b);
      expect(small.count, lessThanOrEqualTo(ThemesProvider.pageWordThreshold));
      provider.select(small.id);
      expect(provider.pageCount, 1);
      expect(provider.visibleGroups.fold(0, (n, group) => n + group.words.length),
          small.count);
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
      expect(find.text(facet.words.first), findsWidgets);
    });

    testWidgets('the pager walks a long scene in 300-word pages', (tester) async {
      final provider = ThemesProvider();
      await provider.initialize();
      final big = provider.scenes.reduce((a, b) => a.count >= b.count ? a : b);
      provider.select(big.id);
      provider.setPage(1);
      final secondPageHead = provider.visibleGroups.first.words.first;
      provider.setPage(0);
      final pages = provider.pageCount;

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

      expect(find.text('第 1 / $pages 页'), findsOneWidget);

      final head = provider.visibleGroups.first;
      expect(find.text('${head.words.length} / ${provider.groupTotalWords(head.id)}'),
          findsOneWidget,
          reason: 'a facet cut by the page boundary shows "shown / total"');

      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();

      expect(provider.page, 1);
      expect(find.text('第 2 / $pages 页'), findsOneWidget);
      expect(find.text(secondPageHead), findsWidgets,
          reason: 'page 2 starts where page 1 stopped');

      await tester.tap(find.byTooltip('上一页'));
      await tester.pumpAndSettle();
      expect(provider.page, 0);
    });
  });
}
