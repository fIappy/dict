import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/frequency/frequency_service.dart';
import 'package:local_dict/core/lexicon/coca_lexicon_service.dart';
import 'package:local_dict/providers/dictionary_provider.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/favorites_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/screens/word_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const dbPath = 'content/coca-ai/pack/coca_learn.db';

  group('CocaLexiconService (53,925 words)', () {
    late CocaLexiconService lexicon;

    setUpAll(() async {
      lexicon = CocaLexiconService.forPath(dbPath);
      await lexicon.initialize();
    });

    tearDownAll(() async {
      await lexicon.close();
    });

    test('loads all 53,925 cleaned COCA lexemes', () {
      expect(lexicon.isReady, isTrue);
      expect(lexicon.entryCount, 53925);
    });

    test('looks up headwords across the full 5.4w rank span with structured fields',
        () async {
      final aEntry = await lexicon.lookup('a');
      expect(aEntry, isNotNull);
      expect(aEntry!.rank, 5);
      expect(aEntry.pos, ['article']);

      final abandon = await lexicon.lookup('Abandon');
      expect(abandon, isNotNull);
      expect(abandon!.rank, 2275);
      expect(abandon.meaningZh, isNotEmpty);
      expect(abandon.usageZh, isNotEmpty);
      expect(abandon.collocations, isNotEmpty);
      expect(abandon.sentences, isNotEmpty);
      expect(abandon.passage, isNotNull);
      expect(abandon.toUtterances(), isNotEmpty);

      final tail = await lexicon.lookup('dustbuster');
      expect(tail, isNotNull);
      expect(tail!.rank, 53925);
    });

    test('falls back cleanly for UK spellings and simple inflections', () async {
      final uk = await lexicon.lookup('behaviour');
      expect(uk, isNotNull);
      expect(uk!.word, 'behavior');
      expect(uk.matchedFrom, 'behaviour');

      final glamour = await lexicon.lookup('glamour');
      expect(glamour, isNotNull);
      expect(glamour!.word, 'glamor');

      final closest = await lexicon.lookup('closest');
      expect(closest, isNotNull);
      expect(closest!.word, 'close');

      final dumplings = await lexicon.lookup('dumplings');
      expect(dumplings, isNotNull);
      expect(dumplings!.word, 'dumpling');
    });

    test('supports English prefix, chunk phrase, and Chinese meaning search',
        () async {
      final enHits = await lexicon.search('aband', limit: 20);
      expect(enHits.map((r) => r.word), contains('abandon'));
      expect(enHits.first.frequencyBadge, startsWith('COCA #'));

      final chunkHits = await lexicon.search('in charge of', limit: 20);
      expect(chunkHits, isNotEmpty);
      expect(chunkHits.map((r) => r.word), contains('charge'));

      final zhHits = await lexicon.search('放弃', limit: 20);
      expect(zhHits, isNotEmpty);
      expect(zhHits.map((r) => r.word), contains('abandon'));
    });

    testWidgets(
        'WordDetailScreen renders native AI card for LexemeEntry and toggles translations',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final lexeme = await tester.runAsync(() async {
        await FrequencyService().init();
        return lexicon.lookup('abandon');
      });
      expect(lexeme, isNotNull);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => DictionaryProvider()),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
          ],
          child: MaterialApp(
            home: WordDetailScreen(word: lexeme!.word, lexeme: lexeme),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listScrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(find.text('COCA #2275'), findsOneWidget);
      expect(find.text('核心释义'), findsOneWidget);
      expect(find.text('用法与避坑'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('高频搭配词组'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('高频搭配词组'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('情景例句'),
        250,
        scrollable: listScrollable,
      );
      expect(find.text('情景例句'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(lexeme.sentences.first.translation),
        120,
        scrollable: listScrollable,
      );
      expect(find.text(lexeme.sentences.first.translation), findsOneWidget);

      await tester.ensureVisible(find.text('隐藏译文'));
      await tester.tap(find.text('隐藏译文'));
      await tester.pumpAndSettle();
      expect(find.text('显示译文'), findsOneWidget);
      expect(find.text(lexeme.sentences.first.translation), findsNothing);
    });
  });
}
