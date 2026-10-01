import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:local_dict/core/frequency/frequency_service.dart';
import 'package:local_dict/core/mdx/mdd_reader.dart';
import 'package:local_dict/core/mdx/mdx_entry.dart';
import 'package:local_dict/core/mdx/mdx_reader.dart';
import 'package:local_dict/ui/widgets/word_definition_view.dart';
import 'package:local_dict/ui/screens/home_screen.dart';
import 'package:local_dict/providers/dictionary_provider.dart';
import 'package:local_dict/providers/favorites_provider.dart';
import 'package:local_dict/providers/history_provider.dart';
import 'package:local_dict/providers/frequency_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/core/services/dictionary_service_native.dart';
import 'package:local_dict/providers/ipa_provider.dart';
import 'package:local_dict/core/ipa/ipa_data.dart';
import 'package:local_dict/core/ipa/ipa_model.dart';
import 'package:local_dict/providers/alphabet_provider.dart';
import 'package:local_dict/core/alphabet/alphabet_data.dart';
import 'package:local_dict/core/alphabet/alphabet_model.dart';
import 'package:local_dict/core/services/dictionary_service_native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
void main() {
  group('Core Unit Tests', () {
    test('FrequencyService loads built-in vocabulary and examination tags', () {
      final freq = FrequencyService();
      freq.init();

      final helloFreq = freq.getFrequency('hello');
      expect(helloFreq, isNotNull);
      expect(helloFreq!.cefr, equals('A1'));

      final abandonFreq = freq.getFrequency('abandon');
      expect(abandonFreq, isNotNull);
      expect(abandonFreq!.examTags, contains('CET4'));
      expect(abandonFreq.examTags, contains('考研'));
      expect(abandonFreq.frequencyLabel, equals('Top 5000'));
    });

    test('MdxEntry parses headword, phonetics, tabs, and examples from HTML', () {
      const sampleHtml = '''
        <link rel='stylesheet' href='dcom-mdx-style.css'>
        <div class='dc'>
          <h1 class='hw'>hello</h1>
          <a class='sound' href='sound://hello.mp3'>speaker</a>
          <span class='pron'>[he-loh] / hɛˈloʊ /</span>
          <div class='tabs'>
            <button type='button' class='tab active' data-t='g-american'>American</button>
            <button type='button' class='tab' data-t='s-etym'>Etymology</button>
            <button type='button' class='tab' data-t='s-explain'>Explanation</button>
            <button type='button' class='tab' data-t='s-exs'>Examples</button>
          </div>
          <div class='panel active' data-p='g-american'>
            <ol class='defs'>
              <li>used as a greeting or to begin a phone conversation.<span class='ex'>Hello there, how are you?</span></li>
            </ol>
          </div>
          <div class='panel' data-p='s-etym'>
            <p>First recorded in 1865-70.</p>
          </div>
          <div class='panel' data-p='s-explain'>
            <p>Hello is a salutation or greeting commonly used.</p>
          </div>
          <div class='panel' data-p='s-exs'>
            <p>More examples here.</p>
          </div>
        </div>
      ''';

      final entry = MdxEntry.parse('hello', sampleHtml);
      expect(entry.word, equals('hello'));
      expect(entry.phonetic, contains('hɛˈloʊ'));
      expect(entry.soundKey, equals('hello.mp3'));
      expect(entry.tabs.length, equals(4));
      expect(entry.tabs[0].tag, equals('g-american'));
      expect(entry.tabs[1].tag, equals('s-etym'));
      expect(entry.tabs[2].tag, equals('s-explain'));
      expect(entry.tabs[3].tag, equals('s-exs'));
      expect(entry.exampleSentences, contains('Hello there, how are you?'));
      expect(entry.panels.containsKey('g-american'), isTrue);
      expect(entry.panels.containsKey('s-etym'), isTrue);
      expect(entry.panels.containsKey('s-explain'), isTrue);
      expect(entry.panels.containsKey('s-exs'), isTrue);
    });

    testWidgets('WordDefinitionView tab switching works seamlessly without tickers', (tester) async {
      const sampleHtml = '''
        <div class='dc'>
          <h1 class='hw'>hello</h1>
          <div class='tabs'>
            <button type='button' class='tab active' data-t='g-american'>American</button>
            <button type='button' class='tab' data-t='s-etym'>Etymology</button>
            <button type='button' class='tab' data-t='s-explain'>Explanation</button>
            <button type='button' class='tab' data-t='s-exs'>Examples</button>
          </div>
          <div class='panel active' data-p='g-american'>
            <p>American English definition content</p>
          </div>
          <div class='panel' data-p='s-etym'>
            <p>Origin and Etymology historical record</p>
          </div>
          <div class='panel' data-p='s-explain'>
            <p>Explanation of usage and context</p>
          </div>
          <div class='panel' data-p='s-exs'>
            <p>Selected Example sentences</p>
          </div>
        </div>
      ''';

      final entry = MdxEntry.parse('hello', sampleHtml);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordDefinitionView(entry: entry),
          ),
        ),
      );

      // Verify all tab buttons exist
      expect(find.text('American'), findsOneWidget);
      expect(find.text('Etymology'), findsOneWidget);
      expect(find.text('Explanation'), findsOneWidget);
      expect(find.text('Examples'), findsOneWidget);
      expect(find.text('全部展开'), findsOneWidget);
      expect(find.byType(HtmlWidget), findsOneWidget);

      // Tap Etymology tab
      await tester.tap(find.text('Etymology'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hello_1')), findsOneWidget);

      // Tap Explanation tab
      await tester.tap(find.text('Explanation'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hello_2')), findsOneWidget);

      // Tap Examples tab
      await tester.tap(find.text('Examples'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hello_3')), findsOneWidget);

      // Tap 全部展开 tab
      await tester.tap(find.text('全部展开'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hello_4')), findsOneWidget);
    });

    testWidgets('Draggable divider in desktop layout responds to mouse drag', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => DictionaryProvider()),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider(create: (_) => HistoryProvider()),
            ChangeNotifierProvider(create: (_) => FrequencyProvider()),
            ChangeNotifierProvider(create: (_) => IpaProvider()),
            ChangeNotifierProvider(create: (_) => AlphabetProvider()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find draggable divider
      final dividerFinder = find.byType(MouseRegion);
      expect(dividerFinder, findsWidgets);

      // Drag rightward
      final splitter = find.descendant(
        of: find.byType(Row),
        matching: find.byType(GestureDetector),
      ).first;

      await tester.drag(splitter, const Offset(60, 0));
      await tester.pumpAndSettle();
    });

    test('MdxReader parses real Dictionary.com 20260913.mdx and performs fast lookups', () async {
      const mdxPath = 'Dictionary.com 20260913_hahaya/Dictionary.com 20260913.mdx';
      if (!File(mdxPath).existsSync()) return;

      final reader = await MdxReader.open(mdxPath);
      expect(reader.numEntries, greaterThan(400000));

      final helloHtml = reader.getEntry('hello');
      expect(helloHtml, isNotNull);
      final helloEntry = MdxEntry.parse('hello', helloHtml!);
      expect(helloEntry.word, equals('hello'));
      expect(helloEntry.soundKey, equals('hello.mp3'));
      expect(helloEntry.tabs.isNotEmpty, isTrue);

      final prefixMatches = reader.search('tele', limit: 10, prefixOnly: true);
      expect(prefixMatches, isNotEmpty);
      expect(prefixMatches.first.toLowerCase(), startsWith('tele'));

      final subMatches = reader.search('graph', limit: 10, prefixOnly: false);
      expect(subMatches, isNotEmpty);
      expect(subMatches.any((m) => m.toLowerCase().contains('graph')), isTrue);

      reader.close();
    });

    test('MddReader retrieves pronunciation audio bytes from Dictionary.com 20260913.mdd', () async {
      const mddPath = 'Dictionary.com 20260913_hahaya/Dictionary.com 20260913.mdd';
      if (!File(mddPath).existsSync()) return;

      final mdd = await MddReader.open(mddPath);
      final audioBytes = mdd.getResource('hello.mp3');
      expect(audioBytes, isNotNull);
      expect(audioBytes!.length, greaterThan(1000));
      expect(audioBytes[0], equals(0x49));
      expect(audioBytes[1], equals(0x44));
      expect(audioBytes[2], equals(0x33));

      mdd.close();
    });

    test('FrequencyProvider range, pagination and persistence', () async {
      // 1. Test simulated saved range 400 - 1000
      SharedPreferences.setMockInitialValues({
        'frequency_range_start': 400,
        'frequency_range_end': 1000,
      });

      final provider = FrequencyProvider();
      await provider.initialize();

      // Range should be restored from preferences, not default 1-100
      expect(provider.startRank, equals(400));
      expect(provider.endRank, equals(1000));
      expect(provider.totalItems, equals(601));
      expect(provider.totalPages, equals(31)); // ceil(601 / 20)
      expect(provider.currentPage, equals(1));

      // Exactly 20 items per page
      expect(provider.currentPageItems.length, equals(20));
      expect(provider.currentPageItems.first.rank, equals(400));

      // Pagination: next page
      provider.nextPage();
      expect(provider.currentPage, equals(2));
      expect(provider.currentPageItems.length, equals(20));
      expect(provider.currentPageItems.first.rank, equals(420));

      // Pagination: jump to page 31 (last page)
      provider.setPage(31);
      expect(provider.currentPage, equals(31));
      // Last page has 1 item (601 - 30 * 20 = 1)
      expect(provider.currentPageItems.length, equals(1));
      expect(provider.currentPageItems.first.rank, equals(1000));

      // 2. Change range to 1 - 100 and verify persistence
      await provider.setRange(1, 100);
      expect(provider.startRank, equals(1));
      expect(provider.endRank, equals(100));
      expect(provider.totalItems, equals(100));
      expect(provider.totalPages, equals(5));
      expect(provider.currentPageItems.length, equals(20));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('frequency_range_start'), equals(1));
      expect(prefs.getInt('frequency_range_end'), equals(100));

      // 3. Test setting range 5000 to 6000 (previously clamped to 5000-5000)
      await provider.setRange(5000, 6000);
      expect(provider.startRank, equals(5000));
      expect(provider.endRank, equals(6000));
      expect(provider.totalItems, equals(1001));
      expect(provider.totalPages, equals(51));
      expect(provider.currentPageItems.length, equals(20));
      expect(provider.currentPageItems.first.rank, equals(5000));
      expect(provider.currentPageItems.last.rank, equals(5019));
    });

    test('IpaData covers all 48 phonemes with examples and combinations', () {
      expect(IpaData.allPhonemes.length, equals(48));

      // Monophthongs: 12, paired in rows of (long, short)
      final monos = IpaData.getByCategory(IpaCategory.monophthong);
      expect(monos.length, equals(12));
      expect(monos[0].symbol, equals('/iː/'));
      expect(monos[1].symbol, equals('/ɪ/'));
      expect(monos[2].symbol, equals('/uː/'));
      expect(monos[3].symbol, equals('/ʊ/'));
      expect(monos[4].symbol, equals('/ɔː/'));
      expect(monos[5].symbol, equals('/ɒ/'));
      expect(monos[6].symbol, equals('/ɜː/'));
      expect(monos[7].symbol, equals('/ə/'));
      expect(monos[8].symbol, equals('/ɑː/'));
      expect(monos[9].symbol, equals('/ʌ/'));
      expect(monos[10].symbol, equals('/e/'));
      expect(monos[11].symbol, equals('/æ/'));
      expect(IpaData.getByCategory(IpaCategory.diphthong).length, equals(8));
      // Plosives: 6
      expect(IpaData.getByCategory(IpaCategory.plosive).length, equals(6));
      // Fricatives: 9
      expect(IpaData.getByCategory(IpaCategory.fricative).length, equals(9));
      // Affricates: 6
      expect(IpaData.getByCategory(IpaCategory.affricate).length, equals(6));
      // Nasals: 3
      expect(IpaData.getByCategory(IpaCategory.nasal).length, equals(3));
      // Approximants: 4
      expect(IpaData.getByCategory(IpaCategory.approximant).length, equals(4));

      // Verify /iː/
      final iLong = IpaData.findBySymbol('/iː/');
      expect(iLong.symbol, equals('/iː/'));
      expect(iLong.examples, isNotEmpty);
      expect(iLong.combinations, isNotEmpty);

      // Verify provider
      final ipaProvider = IpaProvider();
      expect(ipaProvider.selectedSymbol, equals('/iː/'));
      expect(ipaProvider.filteredPhonemes.length, equals(48));

      ipaProvider.selectCategory(IpaCategory.plosive);
      expect(ipaProvider.filteredPhonemes.length, equals(6));
      expect(ipaProvider.selectedSymbol, equals('/p/'));
    });

    test('every IPA phoneme has a bundled audio clip', () {
      // The grid plays these by asset key; a phoneme added without regenerating
      // its clip (tool/generate_ipa_audio.py) would otherwise fail silently.
      final missing = <String>[];
      final stubs = <String>[];
      for (final phoneme in IpaData.allPhonemes) {
        final file = File('assets/audio/ipa/${phoneme.audioAssetKey}.mp3');
        if (!file.existsSync()) {
          missing.add(phoneme.audioAssetKey);
          continue;
        }
        // a real clip is 0.3-0.5 s of 64 kbps mono: ~1.1-5 KB
        if (file.lengthSync() < 1000) {
          stubs.add('${phoneme.audioAssetKey} (${file.lengthSync()} B)');
        }
      }
      expect(missing, isEmpty, reason: 'phonemes with no clip: $missing');
      expect(stubs, isEmpty, reason: 'truncated clips: $stubs');
    });

    test('requiresDurableImport adopts only transient Android picker paths', () {
      const pickerCache =
          '/data/user/0/com.example.local_dict/cache/file_picker/1727/X.mdx';
      const appDicts =
          '/data/user/0/com.example.local_dict/files/local_dict/dicts';

      // Desktop archives are the user's own files: reference in place, never
      // duplicate a multi-gigabyte .mdd.
      expect(
        requiresDurableImport(isAndroid: false, path: r'D:\dicts\X.mdx', appDictDir: null),
        isFalse,
      );

      // Android's SAF copy is evictable and has no sibling .mdd beside it.
      expect(
        requiresDurableImport(isAndroid: true, path: pickerCache, appDictDir: appDicts),
        isTrue,
      );

      // Already inside app storage: do not copy onto itself.
      expect(
        requiresDurableImport(isAndroid: true, path: '$appDicts/X.mdx', appDictDir: appDicts),
        isFalse,
      );
    });

    test('AlphabetData covers all 26 letters A-Z with phonics and audio keys', () {
      expect(AlphabetData.allLetters.length, equals(26));

      // Vowels: 5
      final vowels = AlphabetData.allLetters.where((l) => l.isVowel).toList();
      expect(vowels.length, equals(5));
      expect(vowels.map((v) => v.upper).toList(), equals(['A', 'E', 'I', 'O', 'U']));

      // Consonants: 21
      final consonants = AlphabetData.allLetters.where((l) => !l.isVowel).toList();
      expect(consonants.length, equals(21));

      // Z has US zee vs UK zed
      final z = AlphabetData.findByLetter('Z');
      expect(z.usNameIpa, contains('zee'));
      expect(z.ukNameIpa, contains('zed'));

      // Provider test
      final provider = AlphabetProvider();
      expect(provider.selectedChar, equals('A'));
      expect(provider.filteredLetters.length, equals(26));

      provider.selectCategory(LetterCategory.vowel);
      expect(provider.filteredLetters.length, equals(6)); // A, E, I, O, U, Y
      expect(provider.selectedChar, equals('A'));

      provider.selectLetter('b');
      expect(provider.selectedChar, equals('B'));
    });
  });
}
