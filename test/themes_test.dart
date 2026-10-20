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
  });
}
