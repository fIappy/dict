import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:local_dict/core/audio/ipa_asset.dart';
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
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/core/services/dictionary_service_native.dart';
import 'package:local_dict/providers/ipa_provider.dart';
import 'package:local_dict/core/ipa/ipa_data.dart';
import 'package:local_dict/core/ipa/ipa_model.dart';
import 'package:local_dict/providers/alphabet_provider.dart';
import 'package:local_dict/providers/numbers_provider.dart';
import 'package:local_dict/providers/themes_provider.dart';
import 'package:local_dict/core/alphabet/alphabet_data.dart';
import 'package:local_dict/core/alphabet/alphabet_model.dart';
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
        // The view tints the line being read, so it watches the speech player.
        ChangeNotifierProvider(
          create: (_) => EntrySpeechProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: WordDefinitionView(entry: entry),
            ),
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
            ChangeNotifierProvider(create: (_) => NumbersProvider()),
            ChangeNotifierProvider(create: (_) => ThemesProvider()),
            ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
            ChangeNotifierProvider(create: (_) => CustomTextProvider()),
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

    test('MdxReader merges every record stored under one headword', () async {
      final dir = Directory.systemTemp.createTempSync('mdx_merge');
      addTearDown(() => dir.deleteSync(recursive: true));
      final archive = File(p.join(dir.path, 'merged.mdx'))
        ..writeAsBytesSync(_buildMdx(<String, List<String>>{
          // SIO-style: one headword, several records (audio bar, entry,
          // phrases, examples). A reader that keeps only the first record shows
          // nothing but the audio bar.
          'alpha': ['first record of alpha', 'second record of alpha'],
          'beta': ['@@@LINK=alpha'],
          'gamma': ['@@@LINK=nowhere'],
          'delta': ['@@@LINK=epsilon'],
          'epsilon': ['@@@LINK=delta'],
        }));

      final reader = await MdxReader.open(archive.path);
      addTearDown(reader.close);

      expect(reader.numEntries, 6);
      expect(
        reader.getEntries('alpha'),
        ['first record of alpha', 'second record of alpha'],
      );
      expect(reader.getEntry('ALPHA'), 'first record of alpha\nsecond record of alpha');
      // A redirect pulls in every record of its target, not just the first.
      expect(reader.getEntry('beta'), 'first record of alpha\nsecond record of alpha');
      // Dangling and circular redirects resolve to nothing instead of hanging.
      expect(reader.getEntry('gamma'), isNull);
      expect(reader.getEntry('delta'), isNull);
      expect(reader.getEntry('missing'), isNull);
      // Duplicate records are one search hit, not two.
      expect(reader.search('alpha'), ['alpha']);
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

    test('IpaData covers every Cambridge phoneme with examples and combinations', () {
      // 44 rows on Cambridge's phonetics page that this app lists in the base
      // grid; /tr/ /dr/ /ts/ /dz/ are not Cambridge symbols and were removed.
      expect(IpaData.allPhonemes.length, equals(44));

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
      // Affricates: 2 (/tʃ/ /dʒ/; /tr/ /dr/ /ts/ /dz/ are not IPA phonemes)
      expect(IpaData.getByCategory(IpaCategory.affricate).length, equals(2));
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
      expect(ipaProvider.filteredPhonemes.length, equals(44));

      ipaProvider.selectCategory(IpaCategory.plosive);
      expect(ipaProvider.filteredPhonemes.length, equals(6));
      expect(ipaProvider.selectedSymbol, equals('/p/'));
    });

    test('the IPA asset set is exactly the reference clips the data asks for', () {
      // Cards play `<key>_uk` / `<key>_us` (AudioManager.playIpaPhoneme). Anything
      // else in the directory is a leftover from an older generator, and a
      // missing entry means a phoneme added without running
      // tool/fetch_cambridge_ipa_audio.py would play nothing.
      final expected = <String>{};
      for (final phoneme in IpaData.allWithCambridgeVariants) {
        if (phoneme.accent != IpaAccent.usOnly) {
          expected.add('${phoneme.audioAssetKey}_uk.mp3');
        }
        if (phoneme.accent != IpaAccent.ukOnly) {
          expected.add('${phoneme.audioAssetKey}_us.mp3');
        }
      }
      final onDisk = Directory('assets/audio/ipa')
          .listSync()
          .whereType<File>()
          .map((file) => file.path.split(RegExp(r'[\\/]')).last)
          .where((name) => name.endsWith('.mp3'))
          .toSet();

      expect(onDisk.difference(expected), isEmpty,
          reason: 'stale clips: ${onDisk.difference(expected).toList()..sort()}');
      expect(expected.difference(onDisk), isEmpty,
          reason: 'missing clips: ${expected.difference(onDisk).toList()..sort()}');

      // Cambridge reference sounds are ~20-27 KB at 48 kHz stereo; a word-level
      // TTS clip is ~2-3 KB, which is how the "plays the example word" regression
      // looked. UK and US must not be the same recording either.
      final stubs = <String>[];
      final sameAccent = <String>[];
      for (final phoneme in IpaData.allWithCambridgeVariants) {
        final bytes = <String, List<int>>{};
        for (final accent in const ['uk', 'us']) {
          final file = File('assets/audio/ipa/${phoneme.audioAssetKey}_$accent.mp3');
          if (!file.existsSync()) continue;
          if (file.lengthSync() < 8000) {
            stubs.add('${file.path.split(RegExp(r'[\\/]')).last} (${file.lengthSync()} B)');
          }
          bytes[accent] = file.readAsBytesSync();
        }
        final uk = bytes['uk'];
        final us = bytes['us'];
        if (uk != null && us != null && uk.length == us.length) {
          var identical = true;
          for (var i = 0; i < uk.length; i++) {
            if (uk[i] != us[i]) {
              identical = false;
              break;
            }
          }
          if (identical) sameAccent.add(phoneme.audioAssetKey);
        }
      }
      expect(stubs, isEmpty, reason: 'clips too small to be a reference sound: $stubs');
      expect(sameAccent, isEmpty,
          reason: 'UK and US clip are the same recording: $sameAccent');

      // The UK-only rows' US button plays the counterpart entry instead of the
      // missing US sound, so that entry must carry a US clip.
      final counterpartProblems = <String>[];
      for (final phoneme in IpaData.allWithCambridgeVariants) {
        if (phoneme.accent != IpaAccent.ukOnly) continue;
        final counterpart = IpaData.counterpartPhoneme(phoneme);
        if (counterpart == null) continue;
        final file = File('assets/audio/ipa/${counterpart.audioAssetKey}_us.mp3');
        if (!file.existsSync() || file.lengthSync() < 8000) {
          counterpartProblems.add('${phoneme.symbol} -> ${counterpart.symbol}');
        }
      }
      expect(counterpartProblems, isEmpty,
          reason: 'counterpart without a US clip: $counterpartProblems');
    });

    test('asset resolution picks the requested accent and reports gaps', () async {
      // AudioManager plays whatever resolveIpaAsset() returns, so this covers the
      // real lookup instead of only the files on disk.
      for (final phoneme in IpaData.allWithCambridgeVariants) {
        if (phoneme.accent != IpaAccent.both) continue;
        for (final accent in const ['uk', 'us']) {
          expect(
            await resolveIpaAsset(phoneme.audioAssetKey, accent),
            equals('audio/ipa/${phoneme.audioAssetKey}_$accent.mp3'),
            reason: '${phoneme.symbol} ($accent) should not fall back',
          );
        }
      }
      expect(await resolveIpaAsset('no_such_phoneme', 'uk'), isNull);
    });

    test('Cambridge IPA system distinguishes UK and US accents and pronunciations', () {
      // 1. UK-only phonemes
      final oShort = IpaData.findBySymbol('/ɒ/');
      expect(oShort.accent, equals(IpaAccent.ukOnly));
      expect(oShort.cambridgeExampleWord, equals('sock'));
      expect(oShort.counterpartSymbol, contains('/ɑː/'));

      final erLong = IpaData.findBySymbol('/ɜː/');
      expect(erLong.accent, equals(IpaAccent.ukOnly));
      expect(erLong.counterpartSymbol, contains('/ɝː/'));

      // 2. Both accents
      final iLong = IpaData.findBySymbol('/iː/');
      expect(iLong.accent, equals(IpaAccent.both));
      expect(iLong.cambridgeExampleWord, equals('sheep'));

      // 3. Cambridge specials
      final erUs = IpaData.findBySymbol('/ɝː/');
      expect(erUs.accent, equals(IpaAccent.usOnly));
      expect(erUs.audioAssetKey, equals('er_long_us'));

      final flapT = IpaData.findBySymbol('/t̬/');
      expect(flapT.accent, equals(IpaAccent.usOnly));
      expect(flapT.cambridgeExampleWord, equals('cutting'));

      // 4. Accent filtering via IpaProvider
      final provider = IpaProvider();
      provider.selectAccent(IpaAccent.ukOnly);
      expect(provider.filteredPhonemes.any((p) => p.symbol == '/ɒ/'), isTrue);
      expect(provider.filteredPhonemes.any((p) => p.symbol == '/t̬/'), isFalse);

      provider.selectAccent(IpaAccent.usOnly);
      expect(provider.filteredPhonemes.any((p) => p.symbol == '/t̬/'), isTrue);
      expect(provider.filteredPhonemes.any((p) => p.symbol == '/ɒ/'), isFalse);

      // 5. Example word has UK & US phonetics
      expect(iLong.examples.first.ukPhonetic, isNotEmpty);
      expect(iLong.examples.first.usPhonetic, isNotEmpty);
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

    test('dictionary probing covers DICT_DIR, the working and the program folder', () {
      final cwd = p.join('a', 'work');
      final exeDir = p.join('a', 'work', 'build', 'Release');
      final dictDir = p.join('d', 'dicts');

      final dirs = DictionaryService.probeDirectories(
        cwd: cwd,
        exeDir: exeDir,
        dictDirEnv: ' $dictDir ; ; ',
      );

      // DICT_DIR wins, so the folder the user points at is scanned first.
      expect(dirs.first, endsWith(dictDir));
      // …then the working directory, the executable's folder and its parents,
      // which is how a portable build finds archives dropped next to it.
      expect(dirs.any((d) => d.endsWith(cwd)), isTrue);
      expect(dirs.any((d) => d.endsWith(exeDir)), isTrue);
      expect(dirs.any((d) => d.endsWith(p.join('a', 'work', 'build'))), isTrue);

      // The same folder given twice is scanned once, and ancestors of the
      // program folder never repeat a folder already added.
      final deduped = DictionaryService.probeDirectories(
        cwd: cwd,
        exeDir: cwd,
        dictDirEnv: cwd,
      );
      expect(deduped.where((d) => d.endsWith(cwd)), hasLength(1));
      expect(deduped.toSet(), hasLength(deduped.length));
    });

    test('a detected archive keeps its identity across scans', () {
      // Case-only differences are the same file on Windows…
      expect(
        DictionaryService.autoDictionaryId(r'C:\dicts\SIO v3.3.mdx'),
        DictionaryService.autoDictionaryId(r'c:\DICTS\SIO v3.3.MDX'),
      );
      // …and different archives stay different, so neither replaces the other.
      expect(
        DictionaryService.autoDictionaryId(r'C:\dicts\A.mdx'),
        isNot(DictionaryService.autoDictionaryId(r'C:\dicts\B.mdx')),
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

/// Writes a minimal MDict v2 archive: UTF-8 keys and records, one key block and
/// one record block. Checksums stay zero because the reader never verifies them.
///
/// Layout, in file order: header length, header, key-block info, compressed
/// key-block info, key blocks, record-block info, record blocks. Every
/// compressed block on disk is 8 bytes of bookkeeping plus a zlib stream.
Uint8List _buildMdx(Map<String, List<String>> entries) {
  final keyNames = <String>[];
  final recordOffsets = <int>[];
  final records = BytesBuilder();

  for (final name in entries.keys.toList()..sort()) {
    for (final record in entries[name]!) {
      keyNames.add(name);
      recordOffsets.add(records.length);
      records.add(utf8.encode(record));
      records.addByte(0); // Records are null terminated.
    }
  }
  final recordBytes = records.toBytes();

  final keyBlock = BytesBuilder();
  for (var i = 0; i < keyNames.length; i++) {
    keyBlock
      ..add(_beUint64(recordOffsets[i]))
      ..add(utf8.encode(keyNames[i]))
      ..addByte(0);
  }
  final keyBytes = keyBlock.toBytes();
  final keyBlockOnDisk = _block(keyBytes);
  final recordBlock = _block(recordBytes);

  final keyInfo = BytesBuilder()
    ..add(_beUint64(keyNames.length)) // Keys in this block.
    ..add(_beUint16(utf8.encode(keyNames.first).length))
    ..add(utf8.encode(keyNames.first))
    ..addByte(0)
    ..add(_beUint16(utf8.encode(keyNames.last).length))
    ..add(utf8.encode(keyNames.last))
    ..addByte(0)
    ..add(_beUint64(keyBlockOnDisk.length)) // Compressed size on disk.
    ..add(_beUint64(keyBytes.length));
  final keyInfoBlock = _block(keyInfo.toBytes());

  final header = utf8.encode('<Dictionary Encoding="UTF-8" />');
  final headerInfo = ByteData(40)
    ..setUint64(0, 1, Endian.big) // Key blocks.
    ..setUint64(8, keyNames.length, Endian.big) // Entries.
    ..setUint64(16, keyBytes.length, Endian.big)
    ..setUint64(24, keyInfoBlock.length, Endian.big) // Compressed key-block info.
    ..setUint64(32, keyBytes.length, Endian.big);
  final recordInfo = ByteData(32)
    ..setUint64(0, 1, Endian.big) // Record blocks.
    ..setUint64(8, keyNames.length, Endian.big)
    ..setUint64(16, 16, Endian.big) // Bytes of the per-block table below.
    ..setUint64(24, recordBytes.length, Endian.big);

  return (BytesBuilder()
        ..add(_beUint32(header.length))
        ..add(header)
        ..add(_beUint32(0))
        ..add(headerInfo.buffer.asUint8List())
        ..add(_beUint32(0))
        ..add(keyInfoBlock)
        ..add(keyBlockOnDisk)
        ..add(recordInfo.buffer.asUint8List())
        ..add(_beUint64(recordBlock.length))
        ..add(_beUint64(recordBytes.length))
        ..add(recordBlock))
      .toBytes();
}

/// On disk, each block starts with the info word MDict writes: little-endian,
/// low nibble 2 = zlib, next nibble 0 = not encrypted. Then the block's adler32
/// (the reader does not verify it) and the zlib stream.
Uint8List _block(List<int> decompressed) {
  final builder = BytesBuilder()
    ..add(const [0x02, 0x00, 0x00, 0x00])
    ..add(_beUint32(0))
    ..add(zlib.encode(decompressed));
  return builder.toBytes();
}

Uint8List _beUint16(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _beUint32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _beUint64(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}
