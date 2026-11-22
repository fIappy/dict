import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:local_dict/core/ai/ai_config.dart';
import 'package:local_dict/core/ai/openai_client.dart';
import 'package:local_dict/core/ai/theme_agent.dart';
import 'package:local_dict/core/api/api_config.dart';
import 'package:local_dict/core/audio/speech_clip_player.dart';
import 'package:local_dict/core/audio/speech_engine.dart';
import 'package:local_dict/core/database/app_database.dart';
import 'package:local_dict/core/mdx/entry_speech.dart';
import 'package:local_dict/core/mdx/mdd_reader_native.dart';
import 'package:local_dict/core/mdx/mdict_crypto.dart';
import 'package:local_dict/core/mdx/mdx_entry.dart';
import 'package:local_dict/core/mdx/mdx_reader_native.dart';
import 'package:local_dict/core/models/favorite_group.dart';
import 'package:local_dict/core/numbers/number_speller.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/widgets/speakable_selection.dart';
import 'package:local_dict/ui/widgets/word_definition_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List _encodeUtf16Le(String value) {
  final out = BytesBuilder(copy: false);
  for (final unit in value.codeUnits) {
    out.addByte(unit & 0xFF);
    out.addByte((unit >> 8) & 0xFF);
  }
  return out.toBytes();
}

Uint8List _u16Be(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.big);

Uint8List _u32Be(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

Uint8List _u64Be(int value) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.big);

Uint8List _fastEncrypt(Uint8List data, Uint8List key) {
  final out = Uint8List(data.length);
  var previous = 0x36;
  for (var i = 0; i < data.length; i++) {
    final plain = data[i] ^ previous ^ (i & 0xFF) ^ key[i % key.length];
    final cipher = ((plain >> 4) | (plain << 4)) & 0xFF;
    out[i] = cipher;
    previous = cipher;
  }
  return out;
}

typedef _KeyBlockInput = List<({int offset, String key})>;

Uint8List _buildSyntheticMdict({
  required String headerXml,
  required bool utf16Header,
  required bool utf16Keys,
  required bool encryptKeyInfo,
  required List<_KeyBlockInput> keyBlocks,
  required List<Uint8List> recordBlocks,
}) {
  final out = BytesBuilder(copy: false);

  final headerBytes =
      utf16Header ? _encodeUtf16Le(headerXml) : utf8.encode(headerXml);
  out.add(_u32Be(headerBytes.length));
  out.add(headerBytes);
  out.add(const [0, 0, 0, 0]);

  final rawKeyBlocks = <Uint8List>[];
  final kbMeta = BytesBuilder(copy: false);
  var totalEntries = 0;
  var totalDecompKeySize = 0;

  for (final block in keyBlocks) {
    totalEntries += block.length;
    final kbPayload = BytesBuilder(copy: false);
    for (final entry in block) {
      kbPayload.add(_u64Be(entry.offset));
      if (utf16Keys) {
        kbPayload.add(_encodeUtf16Le(entry.key));
        kbPayload.add(const [0, 0]);
      } else {
        kbPayload.add(utf8.encode(entry.key));
        kbPayload.addByte(0);
      }
    }
    final decompKb = kbPayload.toBytes();
    totalDecompKeySize += decompKb.length;
    final wrappedKb = Uint8List.fromList([
      0, 0, 0, 0, // uncompressed, unencrypted
      0, 0, 0, 0,
      ...decompKb,
    ]);
    rawKeyBlocks.add(wrappedKb);

    final firstKey = block.first.key;
    final lastKey = block.last.key;
    kbMeta.add(_u64Be(block.length));
    if (utf16Keys) {
      kbMeta.add(_u16Be(firstKey.length));
      kbMeta.add(_encodeUtf16Le(firstKey));
      kbMeta.add(const [0, 0]);
      kbMeta.add(_u16Be(lastKey.length));
      kbMeta.add(_encodeUtf16Le(lastKey));
      kbMeta.add(const [0, 0]);
    } else {
      final k1Bytes = utf8.encode(firstKey);
      final k2Bytes = utf8.encode(lastKey);
      kbMeta.add(_u16Be(k1Bytes.length));
      kbMeta.add(k1Bytes);
      kbMeta.addByte(0);
      kbMeta.add(_u16Be(k2Bytes.length));
      kbMeta.add(k2Bytes);
      kbMeta.addByte(0);
    }
    kbMeta.add(_u64Be(wrappedKb.length));
    kbMeta.add(_u64Be(decompKb.length));
  }

  final decompKbInfo = kbMeta.toBytes();
  final compressedKbInfo = Uint8List.fromList(zlib.encode(decompKbInfo));
  const kbInfoChecksum = [0x11, 0x22, 0x33, 0x44];
  final kbInfoBody = encryptKeyInfo
      ? _fastEncrypt(
          compressedKbInfo,
          MdictCrypto.ripemd128(
            Uint8List.fromList([...kbInfoChecksum, 0x95, 0x36, 0x00, 0x00]),
          ),
        )
      : compressedKbInfo;
  final compKbInfo = Uint8List.fromList([
    2, 0, 0, 0, // zlib info header
    ...kbInfoChecksum,
    ...kbInfoBody,
  ]);

  out.add(_u64Be(keyBlocks.length));
  out.add(_u64Be(totalEntries));
  out.add(_u64Be(decompKbInfo.length));
  out.add(_u64Be(compKbInfo.length));
  out.add(_u64Be(totalDecompKeySize));
  out.add(const [0, 0, 0, 0]);
  out.add(compKbInfo);
  for (final kb in rawKeyBlocks) {
    out.add(kb);
  }

  final rawRecBlocks = <Uint8List>[];
  final recInfo = BytesBuilder(copy: false);
  var totalDecompRec = 0;
  for (final payload in recordBlocks) {
    final wrapped = Uint8List.fromList([
      0, 0, 0, 0,
      0, 0, 0, 0,
      ...payload,
    ]);
    rawRecBlocks.add(wrapped);
    totalDecompRec += payload.length;
    recInfo.add(_u64Be(wrapped.length));
    recInfo.add(_u64Be(payload.length));
  }
  final recInfoBytes = recInfo.toBytes();
  out.add(_u64Be(recordBlocks.length));
  out.add(_u64Be(totalEntries));
  out.add(_u64Be(recInfoBytes.length));
  out.add(_u64Be(totalDecompRec));
  out.add(recInfoBytes);
  for (final rb in rawRecBlocks) {
    out.add(rb);
  }

  return out.toBytes();
}

class _NoopSpeechPlayer implements SpeechClipPlayer {
  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async =>
      true;

  @override
  Future<bool> playOnlineClip(Uint8List bytes, {double rate = 1.0}) async =>
      true;

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {}

  @override
  Future<String?> sentenceVoiceLabel(String accent) async => null;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<bool> speakSentence(
    String sentence, {
    String accent = 'us',
    double rate = 1.0,
  }) async =>
      true;

  @override
  Future<void> stop() async {}
}

class _RecordingEntrySpeechProvider extends EntrySpeechProvider {
  _RecordingEntrySpeechProvider()
      : super(player: _NoopSpeechPlayer(), ownsKokoro: false);

  String? lastText;
  EntryUtterance? lastUtterance;
  SpeechEngine? lastEngine;
  double? lastVolume;
  double? lastRate;

  @override
  Future<void> speakText(
    String text, {
    required double rate,
    required String accent,
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    lastText = text;
    lastRate = rate;
    lastEngine = engine;
    lastVolume = volume;
  }

  @override
  Future<void> playOne(
    EntryUtterance item, {
    required double rate,
    required String accent,
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    lastUtterance = item;
    lastRate = rate;
    lastEngine = engine;
    lastVolume = volume;
  }
}

void main() {
  group('NumberSpeller P0/P1 fixes', () {
    test('US quarter clock & money/decimal edge cases', () {
      expect(NumberSpeller.read('3:15')!.usText, 'quarter after three');
      expect(NumberSpeller.read('3:45')!.usText, 'quarter of four');
      expect(NumberSpeller.read('£0.01')!.ukText, 'one penny');
      expect(
        NumberSpeller.read('0.0000001°C')!.ukText,
        'nought point nought nought nought nought nought nought one degrees Celsius',
      );
    });
  });

  group('MDX / MDD UTF-16LE & boundary regressions', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mdict_audit_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('MdxReader decodes UTF-16LE records with odd and split-NUL boundaries',
        () async {
      // Total stream:
      // [0..6)   alpha: "hi\0"  (UTF-16LE)
      // [6..12)  beta:  "AB\0"  (UTF-16LE) -> split at byte 9 (odd parity)
      // [12..18) gamma: "XY\0"  (UTF-16LE) -> split at byte 17 (split 0x00 0x00)
      // [18..22) zeta:  "Z\0"   (UTF-16LE)
      final full = Uint8List.fromList([
        0x68, 0x00, 0x69, 0x00, 0x00, 0x00, // alpha
        0x41, 0x00, 0x42, 0x00, 0x00, 0x00, // beta
        0x58, 0x00, 0x59, 0x00, 0x00, 0x00, // gamma
        0x5A, 0x00, 0x00, 0x00, // zeta
      ]);
      final bytes = _buildSyntheticMdict(
        headerXml: '<Dictionary Encoding="UTF-16LE" Title="SplitTest"/>',
        utf16Header: true,
        utf16Keys: true,
        encryptKeyInfo: false,
        keyBlocks: [
          [
            (offset: 0, key: 'alpha'),
            (offset: 6, key: 'beta'),
            (offset: 12, key: 'gamma'),
            (offset: 18, key: 'zeta'),
          ],
        ],
        recordBlocks: [
          Uint8List.fromList(full.sublist(0, 9)),
          Uint8List.fromList(full.sublist(9, 17)),
          Uint8List.fromList(full.sublist(17, 22)),
        ],
      );
      final mdxFile =
          File('${tempDir.path}${Platform.pathSeparator}split.mdx');
      mdxFile.writeAsBytesSync(bytes);

      final reader = await MdxReader.open(mdxFile.path);
      try {
        expect(reader.getEntry('alpha'), 'hi');
        expect(reader.getEntry('beta'), 'AB');
        expect(reader.getEntry('gamma'), 'XY');
        expect(reader.getEntry('zeta'), 'Z');
      } finally {
        reader.close();
      }
    });

    test('MddReader decodes UTF-16LE Encrypted=2 header & multi-block tail',
        () async {
      final bytes = _buildSyntheticMdict(
        headerXml: '<Dictionary Encoding="UTF-16LE" Encrypted="2"/>',
        utf16Header: true,
        utf16Keys: true,
        encryptKeyInfo: true,
        keyBlocks: [
          [(offset: 0, key: r'\a.spx')],
          [(offset: 3, key: r'\b.spx')],
        ],
        recordBlocks: [
          Uint8List.fromList([1, 2, 3, 4]),
          Uint8List.fromList([5, 6]),
        ],
      );
      final mddFile = File('${tempDir.path}${Platform.pathSeparator}audio.mdd');
      mddFile.writeAsBytesSync(bytes);

      final reader = await MddReader.open(mddFile.path);
      try {
        expect(reader.getResource('/a.spx'), Uint8List.fromList([1, 2, 3]));
        expect(reader.getResource('/b.spx'), Uint8List.fromList([4, 5, 6]));
      } finally {
        reader.close();
      }
    });
  });

  group('Core database & models', () {
    setUpAll(() {
      if (!Platform.isAndroid && !Platform.isIOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
    });

    test('AppDatabase isolates tests in memory & handles close/reopen/concurrency',
        () async {
      final dbHelper = AppDatabase();
      await dbHelper.close();
      final pair = await Future.wait([
        dbHelper.database,
        dbHelper.database,
      ]);
      expect(identical(pair[0], pair[1]), isTrue);
      await dbHelper.close();
      final reopened = await dbHelper.database;
      expect(reopened.isOpen, isTrue);
      await dbHelper.close();
    });

    test('FavoriteGroup.fromMap honors explicit wordCount: 0 over stale column',
        () {
      final overridden = FavoriteGroup.fromMap(
        {
          'id': 'g1',
          'name': 'Core',
          'created_at': 1000,
          'word_count': 42,
        },
        wordCount: 0,
      );
      expect(overridden.wordCount, 0);

      final fallback = FavoriteGroup.fromMap({
        'id': 'g1',
        'name': 'Core',
        'created_at': 1000,
        'word_count': 42,
      });
      expect(fallback.wordCount, 42);
    });
  });

  group('ApiConfig & OpenAiClient & ThemeAgent', () {
    test('ApiConfig preserves base subpaths and validates URL scheme', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiConfig.setBaseUrl('https://example.com/dict/');
      expect(
        ApiConfig.endpoint('/api/search', {'q': 'hi'}).toString(),
        'https://example.com/dict/api/search?q=hi',
      );
      await expectLater(
        () => ApiConfig.setBaseUrl('javascript:alert(1)'),
        throwsArgumentError,
      );
      await ApiConfig.resetBaseUrl();
      await ApiConfig.resolve();
      expect(ApiConfig.baseUrl, 'http://127.0.0.1:8080');
    });

    test('OpenAiClient redacts apiKey from error messages', () async {
      const secret = 'sk-supersecret12345';
      final client = OpenAiClient(
        config: const AiConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: secret,
          model: 'gpt-4o-mini',
        ),
        httpClient: http_testing.MockClient((_) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Rejected key $secret on server'},
            }),
            401,
          );
        }),
      );
      try {
        await expectLater(
          () => client.complete(system: 'sys', user: 'usr'),
          throwsA(
            isA<AiException>().having(
              (e) => e.message,
              'message',
              allOf(isNot(contains(secret)), contains('***')),
            ),
          ),
        );
      } finally {
        client.close();
      }
    });

    test('GeneratedSentence.fromJson converts non-String translation safely',
        () {
      final sentence = GeneratedSentence.fromJson({
        'text': 'Look it up.',
        'translation': 123,
      });
      expect(sentence.text, 'Look it up.');
      expect(sentence.translation, '123');
    });
  });

  group('Speech settings forwarding in widgets', () {
    testWidgets('speakSelection forwards engine and volume from SettingsProvider',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.setSpeechEngine(SpeechEngine.baidu);
      await settings.setSpeechVolume(0.45);
      final speech = _RecordingEntrySpeechProvider();
      late BuildContext captured;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<EntrySpeechProvider>.value(value: speech),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                captured = ctx;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      speakSelection(captured, 'sample phrase');
      expect(speech.lastText, 'sample phrase');
      expect(speech.lastEngine, SpeechEngine.baidu);
      expect(speech.lastVolume, 0.45);
    });

    testWidgets(
        'WordDefinitionView speaker tap forwards engine and volume from SettingsProvider',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.setSpeechEngine(SpeechEngine.edge);
      await settings.setSpeechVolume(0.35);
      final speech = _RecordingEntrySpeechProvider();

      final entry = MdxEntry.parse(
        'hello',
        '<div class="defs"><span class="ex">Hello world example sentence.</span></div>',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<EntrySpeechProvider>.value(value: speech),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WordDefinitionView(entry: entry),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var tapped = false;
      for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
        widget.text.visitChildren((span) {
          if (span is TextSpan &&
              (span.text?.contains('🔊') ?? false) &&
              span.recognizer is TapGestureRecognizer) {
            (span.recognizer! as TapGestureRecognizer).onTap?.call();
            tapped = true;
            return false;
          }
          return true;
        });
        if (tapped) break;
      }
      expect(tapped, isTrue);
      await tester.pump();

      expect(speech.lastUtterance?.text, 'Hello world example sentence.');
      expect(speech.lastEngine, SpeechEngine.edge);
      expect(speech.lastVolume, 0.35);
    });
  });
}
