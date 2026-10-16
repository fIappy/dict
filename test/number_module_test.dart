import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_dict/core/audio/speech_clip_player.dart';
import 'package:local_dict/core/audio/speech_rate.dart';
import 'package:local_dict/core/audio/voice_choice.dart';
import 'package:local_dict/core/audio/pcm_audio.dart';
import 'package:archive/archive.dart';
import 'package:local_dict/core/audio/piper_model_store_native.dart';
import 'package:local_dict/core/audio/piper_voice.dart';
import 'package:path/path.dart' as p;
import 'package:local_dict/core/numbers/number_audio.dart';
import 'package:local_dict/core/numbers/number_data.dart';
import 'package:local_dict/core/numbers/number_model.dart';
import 'package:local_dict/core/numbers/number_speaker.dart';
import 'package:local_dict/core/numbers/sentence_engine.dart';
import 'package:local_dict/core/numbers/number_speller.dart';
import 'package:local_dict/core/numbers/number_training.dart';
import 'package:local_dict/providers/numbers_provider.dart';
import 'package:local_dict/ui/screens/numbers_screen.dart';
import 'package:local_dict/ui/widgets/numbers_sections.dart';

/// Reads the number spellings the module produces, without touching audio.
String uk(String input) => NumberSpeller.read(input)!.ukText;
String us(String input) => NumberSpeller.read(input)!.usText;

/// A resolver for tests that must not fall back to clips: any word resolves to
/// null, so a missing voice would be visible instead of silent.
Future<String?> _noClips(String word, String accent) async => null;

/// Records what the speaker asked for, so the sequencing can be asserted.
/// A Piper voice that always has a model: the engine's own loading is not what
/// these tests are about, its place in the fallback order is.
class _StubPiper extends PiperVoice {
  _StubPiper() : super(finder: (accent) async => null);

  /// Every sentence the stub was asked to render, in order.
  final List<String> rendered = [];

  @override
  Future<bool> isReady(String accent) async => true;

  @override
  Future<PcmClip?> synthesize(String text, {required String accent, required double rate}) async {
    rendered.add(text);
    return PcmClip(Int16List.fromList(List.filled(22050, 3)), 22050);
  }
}

/// A player whose clip playback can be parked, so a run can be stopped while it
/// sits mid-await — the window in which a shared "cancelled" flag let an
/// abandoned run resume and talk over the run that replaced it.
class _GatedPlayer implements SpeechClipPlayer {
  final List<String> played = [];
  Completer<void>? _gate;

  /// Park every following [playSpeechClip] until [release].
  void hold() => _gate = Completer<void>();

  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {
    played.add(assetPath);
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {}

  @override
  Future<bool> speakSentence(String sentence,
          {String accent = 'us', double rate = 1.0}) async =>
      false;

  @override
  Future<String?> sentenceVoiceLabel(String accent) async => null;

  @override
  Future<void> stop() async {}
}

class _RecordingPlayer implements SpeechClipPlayer {
  _RecordingPlayer({this.supportsSentences = false});

  /// Whether the platform claims to have a speech voice. False (the default)
  /// makes the speaker fall back to the recorded words, which is what the web
  /// build and any machine without an English voice do.
  final bool supportsSentences;

  final List<String> played = [];
  final List<double> rates = [];
  final List<String> sentences = [];
  final List<String> sentenceAccents = [];
  /// WAV buffers handed over by the engines that build their audio themselves.
  final List<Uint8List> buffers = [];
  int stops = 0;

  /// Called with the index of the clip about to play (used to cancel mid-run).
  void Function(int index)? onPlay;

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {
    onPlay?.call(played.length);
    played.add(assetPath);
    rates.add(rate);
  }

  @override
  Future<void> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    onPlay?.call(played.length);
    buffers.add(bytes);
    played.add('bytes:${bytes.length}');
    rates.add(rate);
  }


  @override
  Future<bool> speakSentence(
    String sentence, {
    String accent = 'us',
    double rate = 1.0,
  }) async {
    sentences.add(sentence);
    sentenceAccents.add(accent);
    rates.add(rate);
    return supportsSentences;
  }

  @override
  Future<String?> sentenceVoiceLabel(String accent) async =>
      supportsSentences ? 'Test Voice' : null;

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  // rootBundle-backed asset resolution needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Number module', () {
    test('cardinals follow the British/American and-rule', () {
      expect(uk('7'), 'seven');
      expect(uk('13'), 'thirteen');
      expect(uk('21'), 'twenty-one');
      expect(uk('100'), 'one hundred');
      expect(uk('101'), 'one hundred and one');
      expect(us('101'), 'one hundred one');
      expect(uk('1,234'), 'one thousand two hundred and thirty-four');
      expect(us('1,234'), 'one thousand two hundred thirty-four');
      // The British `and` also crosses scales; American drops it everywhere.
      expect(uk('1,023'), 'one thousand and twenty-three');
      expect(us('1,023'), 'one thousand twenty-three');
      expect(uk('-5'), 'minus five');
      expect(uk('1,000,000'), 'one million');
      expect(uk('2,500,000'), 'two million five hundred thousand');
    });

    test('ordinals change only the last spoken word', () {
      expect(uk('1st'), 'the first');
      expect(uk('2nd'), 'the second');
      expect(uk('3rd'), 'the third');
      expect(uk('4th'), 'the fourth');
      expect(uk('21st'), 'the twenty-first');
      expect(uk('100th'), 'the one hundredth');
      expect(uk('105th'), 'the one hundred and fifth');
      expect(us('105th'), 'the one hundred fifth');
    });

    test('decimals spell every digit and differ on zero', () {
      expect(uk('3.14'), 'three point one four');
      expect(uk('0.5'), 'nought point five');
      expect(us('0.5'), 'zero point five');
      expect(uk('0.05'), 'nought point nought five');
      expect(us('0.05'), 'zero point zero five');
      expect(uk('-1.5'), 'minus one point five');
    });

    test('fractions use ordinals up to ten and "over" beyond', () {
      expect(uk('1/2'), 'one half');
      expect(uk('3/4'), 'three quarters');
      expect(uk('2/5'), 'two fifths');
      expect(uk('1 1/2'), 'one and a half');
      expect(uk('12/7'), 'twelve over seven');
      expect(uk('1/0'), ''); // division by zero cannot be spoken
    });

    test('percentages and money read the way shops say them', () {
      expect(uk('25%'), 'twenty-five percent');
      expect(uk('99.9%'), 'ninety-nine point nine percent');
      expect(uk(r'$12.50'), 'twelve dollars fifty');
      expect(uk('£3.99'), 'three pounds ninety-nine');
      expect(uk('€20'), 'twenty euros');
      expect(uk(r'$0.99'), 'ninety-nine cents');
      expect(uk(r'$12.05'), 'twelve dollars and five cents');
    });

    test('years are read in pairs, with the two thousand special case', () {
      expect(uk('1999'), 'nineteen ninety-nine');
      expect(uk('1905'), 'nineteen oh five');
      expect(uk('1900'), 'nineteen hundred');
      expect(uk('2005'), 'two thousand and five');
      expect(us('2005'), 'two thousand five');
      expect(uk('2026'), 'twenty twenty-six');
      // A four-digit number can still be a quantity when the user says so.
      expect(NumberSpeller.read('1999', as: NumberCategory.cardinal)!.ukText,
          'one thousand nine hundred and ninety-nine');
    });

    test('clock time uses past/to for the quarters and half', () {
      expect(uk('3:00'), "three o'clock");
      expect(uk('3:15'), 'quarter past three');
      expect(uk('3:30'), 'half past three');
      expect(uk('3:45'), 'quarter to four');
      expect(uk('7:05'), 'seven oh five');
      expect(uk('3:23'), 'three twenty-three');
      expect(uk('15:30'), 'half past three in the afternoon');
    });

    test('phone numbers read digit by digit with group pauses', () {
      // `007` is only a phone number when the user says so: on its own three
      // digits are a plain quantity, which is why the cards carry the override.
      String phone(String input, {bool british = true}) =>
          NumberSpeller.read(input, as: NumberCategory.phone)!
              .textFor(british ? 'uk' : 'us');
      expect(phone('007'), 'double oh seven');
      expect(phone('007', british: false), 'oh oh seven');
      expect(phone('0755-1234-5678'), 'oh seven double five, one two three four, five six seven eight');
      expect(phone('+44 20 7946 0958'), 'plus four four, two oh, seven nine four six, oh nine five eight');
      // A plain integer is never mistaken for a phone number.
      expect(NumberSpeller.read('07551234567')!.category, isNot(NumberCategory.phone));
    });

    test('dates differ in word order between the accents', () {
      expect(uk('2026-10-08'), 'the eighth of October twenty twenty-six');
      expect(us('2026-10-08'), 'October eighth, twenty twenty-six');
    });

    test('the contexts that decide how zero is said', () {
      expect(NumberSpeller.zeroReading('phone').ukText, 'oh');
      expect(NumberSpeller.zeroReading('decimal').ukText, 'nought');
      expect(NumberSpeller.zeroReading('decimal').usText, 'zero');
      expect(NumberSpeller.zeroReading('score').ukText, 'three nil');
      expect(NumberSpeller.zeroReading('tennis').ukText, 'forty love');
      expect(NumberSpeller.zeroReading('temperature').ukText, 'zero degrees');
    });

    test('every teaching card can be read, except the rule cards', () {
      for (final example in NumberData.allExamples) {
        final reading = NumberData.readingOf(example);
        if (example.kind == NumberCardKind.pattern) {
          // A rule card teaches a range, not a sentence; its samples are what
          // get spoken, and each of them must be readable.
          expect(reading, isNull, reason: '${example.input} should have no sentence');
          expect(example.samples, isNotEmpty, reason: '${example.input} has no sample');
          for (final sample in example.samples) {
            final spoken = NumberData.sampleReading(example, sample);
            expect(spoken.ukText, isNotEmpty, reason: 'cannot speak sample $sample');
          }
          continue;
        }
        expect(reading, isNotNull, reason: 'no reading for ${example.input}');
        expect(reading!.ukText, isNotEmpty, reason: 'no reading for ${example.input}');
        expect(reading.usText, isNotEmpty, reason: 'no US reading for ${example.input}');
      }
    });

    test('clock time accepts a.m./p.m. and reads the part of the day', () {
      expect(uk('7:05 a.m.'), 'seven oh five in the morning');
      expect(uk('7:05 am'), 'seven oh five in the morning');
      expect(uk('3 pm'), "three o'clock in the evening");
      expect(uk('3:00 p.m.'), "three o'clock in the evening");
      expect(uk('12:00'), "twelve o'clock");
      expect(uk('0:00'), "twelve o'clock");
      // The 24-hour form still derives the part of the day by itself.
      expect(uk('15:30'), 'half past three in the afternoon');
      expect(uk('9:23'), 'nine twenty-three');
    });

    test('decades and eras are read the way people say them', () {
      expect(uk('1990s'), 'the nineteen nineties');
      expect(uk('80s'), 'the eighties');
      expect(uk('2010s'), 'the twenty tens');
      expect(uk('2000s'), 'the twenty thousands');
      expect(uk('1900s'), 'the nineteen hundreds');
      expect(uk('500 BC'), 'five hundred BC');
      expect(uk('AD 800'), 'AD eight hundred');
      expect(uk('800 AD'), 'eight hundred AD');
      // 1066 and 1100 are years, not quantities.
      expect(NumberSpeller.read('1066')!.category, NumberCategory.year);
      expect(uk('1066'), 'ten sixty-six');
      expect(uk('1100'), 'eleven hundred');
    });

    test('phone numbers read their 800 blocks as numbers', () {
      String phone(String input) =>
          NumberSpeller.read(input, as: NumberCategory.phone)!.ukText;
      expect(phone('1-800-555-0199'), 'one, eight hundred, triple five, oh one double nine');
      expect(phone('0800 123 456'), 'oh eight hundred, one two three, four five six');
      expect(phone('203'), 'two oh three');
      expect(phone('1001'), 'one double oh one');
    });

    test('temperatures read the scale, the plural and below zero', () {
      expect(uk('25°C'), 'twenty-five degrees Celsius');
      expect(uk('1°C'), 'one degree Celsius');
      expect(uk('0°C'), 'zero degrees Celsius');
      expect(uk('-5°C'), 'minus five degrees Celsius');
      expect(uk('98.6°F'), 'ninety-eight point six degrees Fahrenheit');
      // The scale is optional, and a bare number is never a temperature.
      expect(uk('30°'), 'thirty degrees');
      expect(uk('25 degrees'), 'twenty-five degrees');
      expect(NumberSpeller.read('25')!.category, NumberCategory.cardinal);
      expect(NumberSpeller.read('25°C')!.category, NumberCategory.temperature);
    });

    test('multiples use once/twice and "a half"', () {
      expect(uk('1x'), 'once');
      expect(uk('2x'), 'twice');
      expect(uk('3x'), 'three times');
      expect(uk('10x'), 'ten times');
      expect(uk('1.5x'), 'one and a half times');
      expect(uk('2.5x'), 'two and a half times');
      expect(uk('0.5x'), 'half');
    });

    test('ratios read "to" and "out of"', () {
      expect(uk('2:1'), 'two to one');
      expect(uk('3:2'), 'three to two');
      expect(uk('1 in 10'), 'one in ten');
      expect(uk('9 out of 10'), 'nine out of ten');
      // A clock time still wins the two-digit-minute form.
      expect(NumberSpeller.read('3:30')!.category, NumberCategory.clock);
      expect(NumberSpeller.read('2:1')!.category, NumberCategory.ratio);
    });

    test('every category teaches its rules, not only examples', () {
      // The audit behind this test: each of the nine categories had gaps — the
      // forms were there, the *rules* (and a few fixed expressions) were not.
      const expectedRules = {
        NumberCategory.decimal: ['0 的读法', '逐位读'],
        NumberCategory.fraction: ['分母的规律', 'over 的用法', 'of 搭配与弱读'],
        NumberCategory.percent: ['per cent / percent', 'X percent of'],
        NumberCategory.year: ['2010 起两种读法', '年代', 'BC / AD'],
        NumberCategory.clock: ['past / to 规则', 'a.m. / p.m.'],
        NumberCategory.money: ['符号与单位', '口语省略单位', '复数位置'],
        NumberCategory.phone: ['分组与停顿', 'double / triple', '800 号段'],
        NumberCategory.date: ['英美写法不同', '星期与介词', '世纪与年代'],
        NumberCategory.zero: ['五套读法'],
        NumberCategory.temperature: ['摄氏度 / 华氏度', '零下的说法'],
        NumberCategory.multiple: ['once / twice / N times', '倍数比较', '频率表达'],
        NumberCategory.ratio: ['「:」读 to', 'in / out of'],
      };
      for (final entry in expectedRules.entries) {
        final rules = NumberData.getByCategory(entry.key)
            .where((card) => card.kind == NumberCardKind.pattern)
            .map((card) => card.input)
            .toSet();
        for (final expected in entry.value) {
          expect(rules, contains(expected),
              reason: '${entry.key.labelZh} is missing the rule card «$expected»');
        }
      }

      // And the fixed expressions those rules need have their own cards.
      final inputs = NumberData.allExamples.map((card) => card.input).toSet();
      for (final expected in ['1066', '1100', '12:00', '0:00', '0.007', '1,234.56', '7/8',
        '0.5%', '150%', r'$1', '£0.50', '£1.50', r'$2,000,000', '203', '1001', '1-800-555-0199',
        '0°C', '25°C', '1°C', '-5°C', '37°C', '98.6°F', '1x', '2x', '3x', '1.5x',
        'once a week', 'twice a day', 'three times a week', 'once every two weeks',
        '2:1', '3:2', '4:3', '1 in 10', '9 out of 10']) {
        expect(inputs, contains(expected), reason: 'missing card $expected');
      }
    });

    test('the vocabulary lists the irregular forms and keeps the regular ranges as rules', () {
      // Irregular cardinals: 0–12 one by one, then the -teen and -ty families.
      const irregular = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
        'eight', 'nine', 'ten', 'eleven', 'twelve'];
      const teens = ['thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
      const tens = ['twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
      final words = NumberData.wordCards.map((card) => card.input).toSet();
      for (final word in [...irregular, ...teens, ...tens]) {
        expect(words, contains(word), reason: '$word is irregular and must be listed');
      }
      // Irregular ordinals, the -teenth and -tieth families, and the scale forms.
      for (final word in ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh',
        'eighth', 'ninth', 'tenth', 'eleventh', 'twelfth']) {
        expect(words, contains(word), reason: '$word is irregular and must be listed');
      }
      for (final word in ['thirteenth', 'eighteenth', 'twentieth', 'fortieth', 'ninetieth']) {
        expect(words, contains(word), reason: '$word must be listed');
      }
      for (final word in ['hundredth', 'thousandth', 'millionth']) {
        expect(words, contains(word), reason: '$word must be listed');
      }

      // Regular ranges are one card each, and no member of them is enumerated.
      final cardinalPatterns = NumberData.patternCards
          .where((card) => card.category == NumberCategory.cardinal)
          .map((card) => card.input)
          .toList();
      expect(cardinalPatterns, contains('21–99'));
      expect(cardinalPatterns, contains('hundred 以上'));
      expect(
        NumberData.patternCards
            .where((card) => card.category == NumberCategory.ordinal)
            .map((card) => card.input),
        contains('21st–99th'),
      );
      for (final enumerated in ['twenty-one', 'thirty-four', 'ninety-nine', 'twenty-first', 'forty-two']) {
        expect(words.contains(enumerated), isFalse,
            reason: '$enumerated is regular and must not get its own card');
      }

      // Every listed word must be one the module can actually play. A few cards
      // are short phrases ("once a week"), so every word of them is checked.
      for (final card in NumberData.wordCards) {
        for (final word in NumberAudio.words(card.input)) {
          expect(NumberAudio.hasClip(word), isTrue,
              reason: 'no clip for "$word" (${card.input})');
        }
        expect(card.value, isNotNull, reason: '${card.input} has no value');
      }
    });

    test('every word a reading can produce has a bundled clip', () {
      // The speaker stays silent for words without a clip, so a missing word
      // would be a hole in the middle of a spoken number.
      final inputs = <String>[
        for (final example in NumberData.allExamples) example.input,
        for (var i = 0; i <= 120; i++) '$i',
        for (var i = 100; i <= 9999; i += 37) '$i',
        for (final time in ['0:00', '3:15', '3:30', '3:45', '7:05', '9:23', '12:00', '15:30', '23:59'])
          time,
        for (final day in ['2026-01-01', '2026-02-28', '2026-12-31']) day,
        for (final fraction in ['1/2', '2/3', '3/4', '4/5', '5/6', '6/7', '7/8', '8/9', '9/10', '11/12'])
          fraction,
        r'$0.01', r'$99.99', '£0.50', '€1', '25%', '99.9%', '-3.5', '007', '0755-1234-5678',
        // forms added by the coverage audit
        '7:05 a.m.', '3 pm', '12:00', '0:00', '1990s', '80s', '2000s', '2010s', '1900s',
        '500 BC', 'AD 800', '800 AD', '1-800-555-0199', '0800 123 456', '203', '1001',
        '0.007', '1,234.56', '3/12', '12/7', '23/100', '7/8', '150%', '0.5%',
        r'$2,000,000', r'$1,500', '£1.50', 'on Monday',
        // temperature, multiples/frequency and ratios
        '25°C', '-5°C', '98.6°F', '30°', '25 degrees', '1x', '2x', '3x', '10x', '1.5x', '2.5x',
        '2:1', '4:3', '1 in 10', '9 out of 10',
      ];

      final missing = <String>{};
      for (final input in inputs) {
        for (final category in [null, NumberCategory.cardinal, NumberCategory.decimal]) {
          final reading = NumberSpeller.read(input, as: category);
          if (reading == null) continue;
          for (final text in [reading.ukText, reading.usText]) {
            for (final word in NumberAudio.words(text)) {
              if (!NumberAudio.hasClip(word)) missing.add(word);
            }
          }
        }
      }
      // Phrases whose audio is the words themselves (frequency expressions).
      for (final phrase in ['once a week', 'twice a day', 'three times a week',
        'once every two weeks', 'on Monday']) {
        for (final word in NumberAudio.words(phrase)) {
          if (!NumberAudio.hasClip(word)) missing.add(word);
        }
      }
      // Years, clock times and the drill's own output are covered by the examples
      // above; the random generator is swept in its own test.
      for (final kind in TrainingKind.values) {
        for (final item in NumberTraining.generate(
          kind: kind,
          digits: 7,
          count: 20,
          random: Random(11),
        )) {
          for (final text in [item.ukText, item.usText]) {
            for (final word in NumberAudio.words(text)) {
              if (!NumberAudio.hasClip(word)) missing.add(word);
            }
          }
        }
      }
      expect(missing, isEmpty, reason: 'words without a clip: ${missing.join(', ')}');
    });

    test('every vocabulary word ships both accents', () {
      final missing = <String>[];
      final stubs = <String>[];
      for (final word in NumberAudio.vocabulary) {
        for (final accent in ['uk', 'us']) {
          final file = File('assets/${NumberAudio.assetPath(word, accent)}');
          if (!file.existsSync()) {
            missing.add(NumberAudio.assetPath(word, accent));
            continue;
          }
          if (file.lengthSync() < 1000) stubs.add('$word ($accent)');
        }
      }
      expect(missing, isEmpty, reason: 'missing clips: ${missing.join(', ')}');
      expect(stubs, isEmpty, reason: 'stub clips: ${stubs.join(', ')}');
    });

    test('the running bundle resolves the clips the speaker asks for', () async {
      // The file check above proves the clips exist on disk; this proves the
      // player can find them in the *bundle*, which is what playback uses.
      expect(await NumberAudio.resolve('one', 'uk'), 'audio/numbers/one_uk.wav');
      expect(await NumberAudio.resolve('one', 'us'), 'audio/numbers/one_us.wav');
      // A word with no clip resolves to nothing rather than to the wrong accent.
      expect(await NumberAudio.resolve('xyzzy', 'uk'), isNull);
      for (final word in NumberAudio.vocabulary) {
        expect(await NumberAudio.resolve(word, 'uk'), isNotNull, reason: word);
        expect(await NumberAudio.resolve(word, 'us'), isNotNull, reason: word);
      }
    });

    test('the Dart vocabulary and the generator agree', () {
      // Two halves of one contract: the generator writes exactly the clips the
      // speaker can ask for. Renaming a word on one side must fail here.
      final script = File('tool/generate_number_audio.py').readAsStringSync();
      final block = RegExp(r'NUMBER_WORDS[^{]*\{([^}]*)\}').firstMatch(script);
      expect(block, isNotNull, reason: 'NUMBER_WORDS not found in the generator');
      final generated = RegExp("'([a-z]+)':").allMatches(block!.group(1)!).map((m) => m.group(1)!).toSet();

      expect(
        generated.difference(NumberAudio.vocabulary),
        isEmpty,
        reason: 'generated but unused',
      );
      expect(
        NumberAudio.vocabulary.difference(generated),
        isEmpty,
        reason: 'used but never generated',
      );
    });

    test('the drill hides its numbers until asked, and speaks at the set speed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider();
      await provider.initialize();

      expect(provider.training, isEmpty);

      await provider.setKind(TrainingKind.year);
      await provider.setDigits(4);
      await provider.setCount(6);
      provider.generateTraining();

      expect(provider.training.length, 6);
      expect(provider.revealed, isFalse, reason: 'generated numbers start hidden');
      for (final item in provider.training) {
        final year = int.parse(item.input);
        expect(year, inInclusiveRange(1000, 2099));
        expect(item.ukText, isNotEmpty);
      }

      provider.toggleReveal();
      expect(provider.revealed, isTrue);

      // Speed and interval survive a restart: the two knobs the drill is
      // specified with must not reset every launch.
      await provider.setRate(0.75);
      await provider.setGapMs(2200);
      final reloaded = NumbersProvider();
      await reloaded.initialize();
      expect(reloaded.rate, 0.75);
      expect(reloaded.gapMs, 2200);
      expect(reloaded.kind, TrainingKind.year);
      expect(reloaded.count, 6);
    });

    test('every drill kind generates unique, readable items', () {
      for (final kind in TrainingKind.values) {
        final items = NumberTraining.generate(
          kind: kind,
          digits: 4,
          count: 8,
          random: Random(5),
        );
        expect(items, isNotEmpty, reason: '${kind.labelZh} generated nothing');
        final inputs = items.map((item) => item.input).toList();
        expect(inputs.toSet().length, inputs.length,
            reason: '${kind.labelZh} repeated a number: $inputs');
        for (final item in items) {
          expect(item.ukText, isNotEmpty, reason: '${kind.labelZh}: ${item.input}');
          expect(item.usText, isNotEmpty, reason: '${kind.labelZh}: ${item.input}');
        }
        // No repeats even when the same seed is asked for a second batch of the
        // same size: the drill never asks a number twice in a row.
        final again = NumberTraining.generate(
          kind: kind,
          digits: 4,
          count: 8,
          random: Random(5),
        );
        expect(again.map((i) => i.input).toList(), inputs);
      }
    });

    test('the drill covers each requested category with a real reading', () {
      const expectations = {
        TrainingKind.ordinal: NumberCategory.ordinal,
        TrainingKind.fraction: NumberCategory.fraction,
        TrainingKind.percent: NumberCategory.percent,
        TrainingKind.temperature: NumberCategory.temperature,
        TrainingKind.clock: NumberCategory.clock,
        TrainingKind.money: NumberCategory.money,
        TrainingKind.date: NumberCategory.date,
        TrainingKind.phone: NumberCategory.phone,
        TrainingKind.year: NumberCategory.year,
        TrainingKind.decimal: NumberCategory.decimal,
        TrainingKind.integer: NumberCategory.cardinal,
        TrainingKind.large: NumberCategory.cardinal,
      };
      for (final entry in expectations.entries) {
        final items = NumberTraining.generate(
          kind: entry.key,
          digits: 5,
          count: 6,
          random: Random(11),
        );
        for (final item in items) {
          expect(item.category, entry.value, reason: entry.key.labelZh);
        }
      }
      // The shapes are recognisable: a suffix on ordinals, a slash in fractions,
      // a percent sign, a scale on temperatures, a colon on clock times, a
      // currency symbol, ISO dates, grouped phone numbers.
      final ordinal = NumberTraining.generate(
          kind: TrainingKind.ordinal, digits: 3, count: 5, random: Random(3));
      expect(ordinal.every((i) => RegExp(r'^\d+(st|nd|rd|th)$').hasMatch(i.input)), isTrue);
      final fraction = NumberTraining.generate(
          kind: TrainingKind.fraction, digits: 3, count: 5, random: Random(3));
      expect(fraction.every((i) => i.input.contains('/')), isTrue);
      final percent = NumberTraining.generate(
          kind: TrainingKind.percent, digits: 3, count: 5, random: Random(3));
      expect(percent.every((i) => i.input.endsWith('%')), isTrue);
      final temperature = NumberTraining.generate(
          kind: TrainingKind.temperature, digits: 3, count: 5, random: Random(3));
      expect(temperature.every((i) => i.input.contains('°')), isTrue);
      final clock = NumberTraining.generate(
          kind: TrainingKind.clock, digits: 3, count: 5, random: Random(3));
      expect(clock.every((i) => RegExp(r'^\d{2}:\d{2}$').hasMatch(i.input)), isTrue);
      final money = NumberTraining.generate(
          kind: TrainingKind.money, digits: 3, count: 5, random: Random(3));
      expect(money.every((i) => RegExp(r'^[£€¥$]').hasMatch(i.input)), isTrue);
      final date = NumberTraining.generate(
          kind: TrainingKind.date, digits: 3, count: 5, random: Random(3));
      expect(date.every((i) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(i.input)), isTrue);
      final phone = NumberTraining.generate(
          kind: TrainingKind.phone, digits: 3, count: 5, random: Random(3));
      expect(phone.every((i) => i.input.contains('-') && i.input.length >= 11), isTrue);
    });

    test('the drill accepts a custom count and still never repeats', () {
      // The slider stops at 100; the field goes to NumbersLimits.maxTrainingCount.
      final large = NumberTraining.generate(
        kind: TrainingKind.integer,
        digits: 4,
        count: 300,
        random: Random(21),
      );
      expect(large.length, 300);
      expect(large.map((i) => i.input).toSet().length, 300);

      final capped = NumberTraining.generate(
        kind: TrainingKind.decimal,
        digits: 3,
        count: NumbersLimits.maxTrainingCount + 500,
        random: Random(22),
      );
      expect(capped.length, NumbersLimits.maxTrainingCount);
      expect(capped.map((i) => i.input).toSet().length, NumbersLimits.maxTrainingCount);
    });

    test('the gap may be zero and the count is clamped to the shared limits', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider();
      await provider.initialize();

      await provider.setGapMs(-400);
      expect(provider.gapMs, NumbersLimits.minGapMs);
      await provider.setGapMs(250);
      expect(provider.gapMs, 250);

      await provider.setCount(0);
      expect(provider.count, NumbersLimits.minTrainingCount);
      await provider.setCount(640);
      expect(provider.count, 640);
      await provider.setCount(999999);
      expect(provider.count, NumbersLimits.maxTrainingCount);
      await provider.setCount(640);
      provider.generateTraining();
      expect(provider.training.length, 640);

      // Both survive a restart.
      final reloaded = NumbersProvider();
      await reloaded.initialize();
      expect(reloaded.count, 640);
      expect(reloaded.gapMs, 250);
    });

    test('整数 多组连读 draws runs of the requested length range', () {
      final rows = NumberTraining.generateRuns(
        digits: 4,
        count: 6,
        minLength: 3,
        maxLength: 7,
        random: Random(31),
      );

      expect(rows.length, 6);
      for (final row in rows) {
        expect(row.isRun, isTrue);
        expect(row.numbers.length, inInclusiveRange(3, 7));
        for (final number in row.numbers) {
          expect(number.input.replaceAll(',', '').length, 4);
          expect(number.category, NumberCategory.cardinal);
        }
        // The drill reads the run fast, so the same number must not come twice in
        // a row inside it.
        for (var i = 1; i < row.numbers.length; i++) {
          expect(row.numbers[i].input, isNot(row.numbers[i - 1].input),
              reason: 'back-to-back repeat inside a run');
        }
      }

      // Rows hold different numbers, the length really varies across the range, and
      // the row reads as one sentence with its numbers in order.
      expect(rows.map((row) => row.input).toSet().length, rows.length);
      expect(rows.map((row) => row.numbers.length).toSet().length, greaterThan(1),
          reason: 'a 3–7 range must not always come out the same length');
      final first = rows.first;
      expect(first.ukText, first.numbers.map((number) => number.ukText).join(', '));
      expect(first.input.split(NumberTrainingItem.separator).length, first.numbers.length);

      // Same seed, same batch.
      final again = NumberTraining.generateRuns(
        digits: 4, count: 6, minLength: 3, maxLength: 7, random: Random(31));
      expect(again.map((row) => row.input).toList(), rows.map((row) => row.input).toList());
    });

    test('a run batch keeps its row count even when the integers run out', () {
      // Nine one-digit integers cannot fill 40 distinct runs of two; the batch is
      // still 40 rows long, and no row repeats the row before it.
      final rows = NumberTraining.generateRuns(
        digits: 1, count: 40, minLength: 2, maxLength: 2, random: Random(32));
      expect(rows.length, 40);
      for (final row in rows) {
        expect(row.numbers.length, 2);
        expect(row.numbers[0].input, isNot(row.numbers[1].input));
      }
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].input, isNot(rows[i - 1].input));
      }
    });

    test('the provider drills runs in integer mode only', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider();
      await provider.initialize();

      expect(provider.runBatch, isFalse, reason: 'off by default');
      await provider.setRunMode(true);
      await provider.setRunRange(4, 6);
      await provider.setRunGapMs(40);
      await provider.setCount(7);
      provider.generateTraining();
      expect(provider.runBatch, isTrue);
      expect(provider.training.length, 7);
      for (final row in provider.training) {
        expect(row.numbers.length, inInclusiveRange(4, 6));
      }
      expect(provider.gapMs, isNot(0), reason: 'between runs is the ordinary gap');

      // 多组 is an integer option: another kind falls back to single numbers…
      await provider.setKind(TrainingKind.money);
      provider.generateTraining();
      expect(provider.runBatch, isFalse);
      expect(provider.training.every((row) => !row.isRun), isTrue);

      // …and switching back brings the runs back, range and all.
      await provider.setKind(TrainingKind.integer);
      expect(provider.runBatch, isTrue);
      await provider.setRunRange(9, 4);
      expect(provider.runMin, 9);
      expect(provider.runMax, 9, reason: 'the range cannot be inverted');
      expect(provider.runGapMs, 40);

      final reloaded = NumbersProvider();
      await reloaded.initialize();
      expect(reloaded.runMode, isTrue);
      expect(reloaded.runMin, 9);
      expect(reloaded.runMax, 9);
      expect(reloaded.runGapMs, 40);
    });

    test('a run goes to the machine voice as one sentence, or word by word', () async {
      final rows = NumberTraining.generateRuns(
        digits: 2, count: 3, minLength: 3, maxLength: 3, random: Random(33));

      // 组内间隔 = 0 is 连读: one utterance per row, the commas carrying the rhythm.
      final voiced = _RecordingPlayer(supportsSentences: true);
      final voice = NumberSpeaker(player: voiced, resolver: _noClips);
      final seen = <int>[];
      await voice.speakRuns(
        [for (final row in rows) row.textsFor('us')],
        accent: 'us',
        innerGap: Duration.zero,
        gap: const Duration(milliseconds: 5),
        onIndex: seen.add,
      );
      expect(seen, [0, 1, 2], reason: 'the UI marks one row at a time');
      expect(voiced.sentences, [for (final row in rows) row.usText]);

      // Without a voice the recorded words are played one number at a time, so the
      // 组内 interval is what paces them.
      final clips = _RecordingPlayer();
      final recorded = NumberSpeaker(
        player: clips,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );
      final only = rows.first;
      await recorded.speakRuns(
        [only.textsFor('uk')],
        accent: 'uk',
        innerGap: const Duration(milliseconds: 5),
        mode: SpeechMode.clips,
      );
      expect(clips.sentences, isEmpty,
          reason: '逐词拼读 never asks the machine voice');
      final expected = <String>[
        for (final number in only.numbers)
          for (final group in NumberAudio.pauseGroups(number.ukText))
            for (final word in NumberAudio.words(group)) 'audio/numbers/${word}_uk.wav',
      ];
      expect(clips.played, expected,
          reason: 'the run is played word by word, its numbers in order');
    });

    test('a batch keeps the requested length and repeats only once the pool runs out', () {
      // One-digit integers: nine values. Thirty numbers means the nine come round
      // again — the batch is not cut short, and the same number never lands twice
      // in a row.
      final items = NumberTraining.generate(
        kind: TrainingKind.integer,
        digits: 1,
        count: 30,
        random: Random(7),
      );
      expect(items.length, 30);
      expect(items.map((i) => i.input).toSet().length, 9);
      for (final item in items) {
        expect(item.input.length, 1);
      }
      for (var i = 1; i < items.length; i++) {
        expect(items[i].input, isNot(items[i - 1].input),
            reason: 'repeat at $i-${i - 1} lands back to back');
      }

      // Each of the nine shows up a fair number of times rather than one carrying
      // the whole batch.
      final counts = <String, int>{};
      for (final item in items) {
        counts.update(item.input, (value) => value + 1, ifAbsent: () => 1);
      }
      expect(counts.values.every((value) => value >= 2 && value <= 5), isTrue,
          reason: 'uneven spread: $counts');
    });

    test('the provider reports how many of a batch were distinct', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider();
      await provider.initialize();

      await provider.setKind(TrainingKind.integer);
      await provider.setDigits(1);
      await provider.setCount(25);
      provider.generateTraining();
      expect(provider.training.length, 25);
      expect(provider.trainingDistinctCount, 9);

      // A roomy kind stays a set.
      await provider.setKind(TrainingKind.money);
      await provider.setCount(25);
      provider.generateTraining();
      expect(provider.trainingDistinctCount, 25);
    });

    test('the drill generates the requested kind and length', () {
      final integers = NumberTraining.generate(
        kind: TrainingKind.integer,
        digits: 5,
        count: 8,
        random: Random(3),
      );
      for (final item in integers) {
        final digits = item.input.replaceAll(',', '');
        expect(digits.length, 5);
        expect(digits.startsWith('0'), isFalse);
        expect(item.category, NumberCategory.cardinal);
      }

      final decimals = NumberTraining.generate(
        kind: TrainingKind.decimal,
        digits: 3,
        count: 5,
        random: Random(4),
      );
      for (final item in decimals) {
        expect(item.input, contains('.'));
        expect(item.input.split('.')[1].length, 2, reason: 'two decimal places');
        expect(item.category, NumberCategory.decimal);
      }

      // Same seed, same drill: a rerun of the test is reproducible.
      final a = NumberTraining.generate(kind: TrainingKind.mixed, digits: 4, count: 6, random: Random(9));
      final b = NumberTraining.generate(kind: TrainingKind.mixed, digits: 4, count: 6, random: Random(9));
      expect(a.map((i) => i.input).toList(), b.map((i) => i.input).toList());
    });

    test('the input box reads whatever is typed, in the requested interpretation', () {
      final provider = NumbersProvider();
      expect(provider.parseInput('1,234'), isTrue);
      expect(provider.lookup!.ukText, 'one thousand two hundred and thirty-four');
      expect(provider.lookup!.category, NumberCategory.cardinal);

      // Typing again replaces the previous reading.
      expect(provider.parseInput('3.5'), isTrue);
      expect(provider.lookup!.ukText, 'three point five');

      expect(provider.parseInput('1999'), isTrue);
      expect(provider.lookup!.category, NumberCategory.year);
      expect(provider.parseInput('1999', override: NumberCategory.cardinal), isTrue);
      expect(provider.lookup!.category, NumberCategory.cardinal);

      expect(provider.parseInput('abc'), isFalse);
      expect(provider.lookup, isNull);
    });

    test('the speaker plays one clip per word, in order, at the chosen speed', () async {
      // The audible contract: a generated sentence is assembled word by word,
      // so the order of the clip list *is* the sentence.
      final player = _RecordingPlayer();
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );

      await speaker.speak(
        "one thousand two hundred and thirty-four",
        accent: 'uk',
        rate: 0.75,
        mode: SpeechMode.clips,
      );

      expect(player.played, [
        'audio/numbers/one_uk.wav',
        'audio/numbers/thousand_uk.wav',
        'audio/numbers/two_uk.wav',
        'audio/numbers/hundred_uk.wav',
        'audio/numbers/and_uk.wav',
        'audio/numbers/thirty_uk.wav',
        'audio/numbers/four_uk.wav',
      ]);
      expect(player.rates, everyElement(0.375),
          reason: 'the speed knob reaches the player, converted once: 0.75 on the '
              'slider is 0.375 of the voice\'s natural rate');

      // The other accent is a different set of recordings, not a different word.
      await speaker.speak('one', accent: 'us', mode: SpeechMode.clips);
      expect(player.played.last, 'audio/numbers/one_us.wav');
    });

    test('phone groups are spoken as separate chunks', () async {
      final player = _RecordingPlayer();
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );
      final reading = NumberSpeller.read('+44 20 7946 0958', as: NumberCategory.phone)!;
      await speaker.speak(reading.ukText, accent: 'uk', mode: SpeechMode.clips);

      expect(player.played, [
        'audio/numbers/plus_uk.wav',
        'audio/numbers/four_uk.wav',
        'audio/numbers/four_uk.wav',
        'audio/numbers/two_uk.wav',
        'audio/numbers/oh_uk.wav',
        'audio/numbers/seven_uk.wav',
        'audio/numbers/nine_uk.wav',
        'audio/numbers/four_uk.wav',
        'audio/numbers/six_uk.wav',
        'audio/numbers/oh_uk.wav',
        'audio/numbers/nine_uk.wav',
        'audio/numbers/five_uk.wav',
        'audio/numbers/eight_uk.wav',
      ]);
    });

    test('the drill speaks every number, reporting progress, and stops on command', () async {
      final player = _RecordingPlayer();
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );

      final seen = <int>[];
      await speaker.speakAll(
        ['one', 'two', 'three'],
        accent: 'us',
        rate: 1.0,
        gap: const Duration(milliseconds: 10),
        onIndex: seen.add,
        mode: SpeechMode.clips,
      );
      expect(seen, [0, 1, 2]);
      expect(player.played, [
        'audio/numbers/one_us.wav',
        'audio/numbers/two_us.wav',
        'audio/numbers/three_us.wav',
      ]);

      // 停止 must silence the current clip and drop the rest of the run.
      player.played.clear();
      final stopping = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );
      player.onPlay = (index) {
        if (index == 1) stopping.cancel();
      };
      await stopping.speakAll(['one', 'two', 'three', 'four'], gap: const Duration(milliseconds: 10));
      expect(player.played.length, 2, reason: 'playback stops after the clip in progress');
      expect(player.stops, 1);
    });

    test('a word without a clip is skipped instead of mispronounced', () async {
      final player = _RecordingPlayer();
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => word == 'one' ? 'audio/numbers/one_$accent.wav' : null,
      );
      await speaker.speak('one xyzzy two', accent: 'uk', mode: SpeechMode.clips);
      expect(player.played, ['audio/numbers/one_uk.wav']);
    });

    test('the machine voice is chosen off the best engine that fits the accent', () {
      const zira = SentenceVoice(
          name: 'Zira Desktop', language: 'en-US', engine: VoiceEngine.sapi);
      const mark = SentenceVoice(
          name: 'Microsoft Mark', language: 'en-US', engine: VoiceEngine.oneCore);
      const hazel = SentenceVoice(
          name: 'Microsoft Hazel', language: 'en-GB', engine: VoiceEngine.oneCore);
      const huihui = SentenceVoice(
          name: 'Microsoft Huihui', language: 'zh-CN', engine: VoiceEngine.oneCore);

      // The accent's own voice wins — but a modern engine wins over an old one.
      expect(chooseSentenceVoice([zira, mark], 'us')?.name, 'Microsoft Mark');
      expect(chooseSentenceVoice([zira, hazel], 'uk')?.name, 'Microsoft Hazel');
      expect(chooseSentenceVoice([zira, hazel], 'us')?.name, 'Zira Desktop');

      // No voice for the accent? Any English one, modern engine first, and the UI
      // says the timbre differs while the wording stays accent-correct.
      expect(chooseSentenceVoice([zira], 'uk')?.name, 'Zira Desktop');
      final description = sentenceVoiceDescription(zira, 'uk');
      expect(description, contains('本机没有英音语音'));
      expect(description, contains('设置')); // how to install a better voice

      // No English voice at all: nothing to speak with, the recordings take over.
      expect(chooseSentenceVoice([huihui], 'us'), isNull);
      expect(chooseSentenceVoice(const [], 'us'), isNull);
    });

    test('browser and Android voices follow the same accent rules, offline first', () {
      const cloudUs = SentenceVoice(
        name: 'Google US English',
        language: 'en-US',
        engine: VoiceEngine.browser,
        offline: false,
      );
      const localGb = SentenceVoice(
        name: 'Daniel',
        language: 'en-GB',
        engine: VoiceEngine.browser,
      );
      const localUs = SentenceVoice(
        name: 'en-us-x-sfg#female_1-local',
        language: 'en-US',
        engine: VoiceEngine.androidTts,
      );

      expect(chooseSentenceVoice([cloudUs, localGb, localUs], 'us')?.name,
          'en-us-x-sfg#female_1-local');
      expect(chooseSentenceVoice([cloudUs, localGb, localUs], 'uk')?.name, 'Daniel');

      // A cloud voice would go silent with the network unplugged, so the local
      // voice wins even when it is not the accent the card asked for…
      expect(chooseSentenceVoice([cloudUs, localGb], 'us')?.name, 'Daniel');
      // …and it is only used when nothing local can speak English at all.
      expect(chooseSentenceVoice([cloudUs], 'us')?.name, 'Google US English');
      expect(sentenceVoiceDescription(cloudUs, 'uk'), contains('这条语音要联网'));
    });

    test('a sentence handed to an engine reads as one sentence', () {
      // Engines take their prosody from punctuation, so a bare card value would
      // be read flat.
      expect(sentenceForSpeech('twenty-four'), 'Twenty-four.');
      expect(sentenceForSpeech('  24  '), '24.');
      expect(sentenceForSpeech('one hundred and five.'), 'One hundred and five.');
      expect(sentenceForSpeech(''), '');
    });

    test('a spliced sentence is one clip, with the pauses inside it', () async {
      final player = _RecordingPlayer(supportsSentences: true);
      // Two words per group, 10 ms each, so the buffer alone proves the order,
      // the pause a comma stands for, and that it is all one playback.
      Uint8List clip(int marker) =>
          encodeWav(Int16List.fromList(List.filled(240, marker)), sampleRate: 24000);
      final splicer = SplicedSentence(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        loader: (path) async => clip(path.contains('twenty') ? 100 : 200),
      );

      expect(await splicer.speak('twenty-four', accent: 'uk', rate: 1.0), isTrue);
      expect(player.played, hasLength(1), reason: 'one clip, not one per word');
      expect(player.buffers, hasLength(1));

      final joined = decodeWav(player.buffers.single);
      expect(joined.sampleRate, 24000);
      // 240 + 240 samples, no pause: no comma in this sentence.
      expect(joined.samples.length, 480);
      expect(joined.samples.first, 100);
      expect(joined.samples.last, 200);

      // A comma becomes 200 ms of real silence *inside* the same clip.
      expect(await splicer.speak('twenty, four', accent: 'uk', rate: 1.0), isTrue);
      final withPause = decodeWav(player.buffers.last);
      expect(withPause.samples.length, 480 + 4800);
      expect(withPause.samples[240], 0, reason: 'silence where the comma was');
      expect(withPause.samples[480 + 4799], 200);
    });

    test('a sentence without any clip is handed back to the recorded words', () async {
      // No engine can read it — the player has no voice, there is no model, and
      // this splicer has nothing to splice — so the words are played singly.
      final player = _RecordingPlayer();
      final splicer = SplicedSentence(
        player: player,
        resolver: (word, accent) async => null,
        loader: (path) async => null,
      );

      expect(await splicer.speak('twenty-four', accent: 'uk', rate: 1.0), isFalse);
      expect(player.played, isEmpty, reason: 'nothing to splice, nothing played');

      // The speaker then says it word by word, which is the standing fallback.
      final speaker = NumberSpeaker(
        player: player,
        engine: SentenceEngine.spliced,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        splicer: splicer,
      );
      await speaker.speak('twenty-four', accent: 'uk');
      expect(player.played, [
        'audio/numbers/twenty_uk.wav',
        'audio/numbers/four_uk.wav',
      ]);
    });

    test('the selected engine is the one that speaks', () async {
      final player = _RecordingPlayer(supportsSentences: true);
      final splicer = SplicedSentence(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        loader: (path) async =>
            encodeWav(Int16List.fromList([7, 7, 7]), sampleRate: 24000),
      );
      final speaker = NumberSpeaker(
        player: player,
        engine: SentenceEngine.spliced,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        splicer: splicer,
      );

      await speaker.speak('twenty-four', accent: 'uk');
      expect(player.buffers, hasLength(1));
      expect(player.sentences, isEmpty, reason: 'the system voice is not asked');

      // Switching the engine at runtime switches the path.
      speaker.engine = SentenceEngine.system;
      await speaker.speak('twenty-four', accent: 'uk');
      expect(player.sentences, ['twenty-four']);
    });

    test('the PCM helpers keep 16-bit mono audio intact', () {
      final samples = Int16List.fromList([-32768, -1, 0, 1, 32767]);
      final decoded = decodeWav(encodeWav(samples, sampleRate: 24000));
      expect(decoded.sampleRate, 24000);
      expect(decoded.samples, samples);
      expect(decoded.duration, const Duration(microseconds: 208));

      // A model's float output clamps instead of wrapping around.
      final clamped = fromFloat32([-2.0, -1.0, 0.0, 0.5, 1.0, 2.0], 22050);
      expect(clamped.samples.first, -32768);
      expect(clamped.samples.last, 32767);
      expect(clamped.samples[3], 16384);

      // Joining inserts exactly the silence asked for.
      final joined = joinClips(
        [decoded, decoded],
        gaps: const [Duration(milliseconds: 100)],
      );
      expect(joined.samples.length, 5 + 2400 + 5);
      expect(joined.samples[5], 0);

      expect(PcmClip.silence(const Duration(milliseconds: 200), 24000).sampleCount, 4800);
    });

    test('importing a Piper voice copies it in, whatever layout it arrives in', () async {
      final root = Directory.systemTemp.createTempSync('piper_import');
      addTearDown(() => root.deleteSync(recursive: true));

      /// One voice, as the fetch tool writes it (plus a second accent's folder
      /// which must be ignored when only one is asked for).
      void voice(String accent, String modelName) {
        final folder = Directory(p.join(root.path, 'source', 'piper', accent))
          ..createSync(recursive: true);
        File(p.join(folder.path, modelName)).writeAsBytesSync([1, 2, 3]);
        File(p.join(folder.path, 'tokens.txt')).writeAsStringSync('a 1\n');
        Directory(p.join(folder.path, 'espeak-ng-data')).createSync();
        File(p.join(folder.path, 'espeak-ng-data', 'en_dict')).writeAsBytesSync([9]);
      }

      voice('uk', 'en_GB-alan-medium.onnx');
      voice('us', 'en_US-lessac-medium.onnx');

      final destination = Directory(p.join(root.path, 'store'));
      final installed = await copyPiperModels(
        source: p.join(root.path, 'source'),
        destination: destination.path,
      );

      expect(installed, ['uk', 'us']);
      for (final accent in ['uk', 'us']) {
        final folder = Directory(p.join(destination.path, 'piper', accent));
        // The canonical names, so every platform addresses the same paths.
        expect(File(p.join(folder.path, 'model.onnx')).existsSync(), isTrue);
        expect(File(p.join(folder.path, 'tokens.txt')).existsSync(), isTrue);
        expect(Directory(p.join(folder.path, 'espeak-ng-data')).existsSync(), isTrue);
        // …and the manifest the browser fetches.
        expect(File(p.join(folder.path, 'files.txt')).readAsStringSync(),
            contains('model.onnx'));
      }

      // A folder holding one voice directly: the accent comes from the file name.
      final single = Directory(p.join(root.path, 'single'))..createSync();
      File(p.join(single.path, 'en_GB-alan-medium.onnx')).writeAsBytesSync([1]);
      File(p.join(single.path, 'tokens.txt')).writeAsStringSync('a 1\n');
      Directory(p.join(single.path, 'espeak-ng-data')).createSync();
      expect(
        await copyPiperModels(source: single.path, destination: destination.path),
        ['uk'],
      );

      // Nothing usable: no voice, no import.
      final empty = Directory(p.join(root.path, 'empty'))..createSync();
      expect(
        await copyPiperModels(source: empty.path, destination: destination.path),
        isEmpty,
      );
    });

    test('a picked archive installs the voices it holds', () async {
      final root = Directory.systemTemp.createTempSync('piper_zip_test');
      addTearDown(() => root.deleteSync(recursive: true));

      // Built the way tool/fetch_piper_models.py packs it: one folder per accent.
      List<int> zipOf(List<String> entries) {
        final archive = Archive();
        for (final path in entries) {
          archive.addFile(ArchiveFile(path, 4, utf8.encode('data')));
        }
        return ZipEncoder().encode(archive);
      }

      final installed = await installPiperArchiveIn(
        zipOf([
          'uk/en_GB-alan-medium.onnx',
          'uk/tokens.txt',
          'uk/espeak-ng-data/en_dict',
          'us/en_US-lessac-medium.onnx',
          'us/tokens.txt',
          'us/espeak-ng-data/en_dict',
          'readme.txt',
        ]),
        root.path,
      );

      expect(installed, ['uk', 'us']);
      for (final accent in ['uk', 'us']) {
        final folder = Directory(p.join(root.path, 'piper', accent));
        expect(File(p.join(folder.path, 'model.onnx')).existsSync(), isTrue,
            reason: 'the model keeps its canonical name');
        expect(File(p.join(folder.path, 'tokens.txt')).existsSync(), isTrue);
        expect(File(p.join(folder.path, 'espeak-ng-data', 'en_dict')).existsSync(), isTrue);
      }

      // An archive with no voice in it installs nothing.
      expect(
        await installPiperArchiveIn(zipOf(['readme.txt']), root.path),
        isEmpty,
      );
    });

    test('a number is not split into words when the chosen engine cannot read it', () async {
      // The Android case: the phone's TTS has no English voice, so the engine the
      // user picked answers false. Two-digit numbers must still come out as one
      // clip — that is what regression-testing this is for.
      final player = _RecordingPlayer(); // supportsSentences: false
      final speaker = NumberSpeaker(
        player: player,
        engine: SentenceEngine.system,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        splicer: SplicedSentence(
          player: player,
          resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
          loader: (path) async =>
              encodeWav(Int16List.fromList(List.filled(240, 7)), sampleRate: 24000),
        ),
      );

      await speaker.speak('twenty-four', accent: 'uk');

      expect(speaker.spokenBy, SentenceEngine.spliced);
      expect(player.buffers, hasLength(1), reason: 'one clip for the whole number');
      expect(
        player.played.where((entry) => entry.endsWith('.wav')),
        isEmpty,
        reason: 'no single-word playback: that is the bug this guards',
      );
    });

    test('the chosen engine speaks first, the fallbacks only when it cannot', () async {
      final player = _RecordingPlayer(supportsSentences: true);
      final splicer = SplicedSentence(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        loader: (path) async =>
            encodeWav(Int16List.fromList(List.filled(240, 7)), sampleRate: 24000),
      );
      final speaker = NumberSpeaker(
        player: player,
        engine: SentenceEngine.system,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        splicer: splicer,
      );

      await speaker.speak('twenty-four', accent: 'uk');
      expect(speaker.spokenBy, SentenceEngine.system);
      expect(player.sentences, hasLength(1));
      expect(player.buffers, isEmpty, reason: 'nothing else was tried');

      // The neural engine sits between the host voice and the recordings.
      final mute = _RecordingPlayer();
      final neutered = NumberSpeaker(
        player: mute,
        engine: SentenceEngine.system,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        splicer: splicer,
        piper: _StubPiper(),
      );
      await neutered.speak('twenty-four', accent: 'uk');
      expect(neutered.spokenBy, SentenceEngine.piper);
      expect(mute.buffers, hasLength(1), reason: 'the model spoke, not the clips');
      expect(mute.played.where((entry) => entry.endsWith('.wav')), isEmpty);
    });

    test('组内间隔 paces the numbers inside a row, and 0 keeps the row joined', () async {
      final rows = NumberTraining.generateRuns(
        digits: 2, count: 1, minLength: 3, maxLength: 3, random: Random(7));
      final row = rows.first.textsFor('us');
      final player = _RecordingPlayer(supportsSentences: true);
      final voice = NumberSpeaker(player: player, resolver: _noClips);

      await voice.speakRuns([row], accent: 'us', innerGap: Duration.zero);
      expect(player.sentences, [row.join(', ')],
          reason: '0 = 连读: the engine reads the whole row as one sentence');

      player.sentences.clear();
      final watch = Stopwatch()..start();
      await voice.speakRuns(
        [row],
        accent: 'us',
        innerGap: const Duration(milliseconds: 200),
      );
      final elapsed = watch.elapsed;
      expect(player.sentences, row, reason: 'a gap means one utterance per number');
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(200 * (row.length - 1)),
          reason: 'the slider has to be audible — this is the bug it had');
    });

    test('a Piper row is rendered up front so the 组内 gap is the gap', () async {
      // The model is slow (about a second per number on a phone) and synthesizing
      // between two numbers would stretch every pause by that cost. The row is
      // therefore one clip whose silence is exactly the setting.
      final player = _RecordingPlayer();
      final piper = _StubPiper();
      final speaker = NumberSpeaker(
        player: player,
        engine: SentenceEngine.piper,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
        piper: piper,
      );

      await speaker.speakRuns(
        [
          ['twenty-four', 'thirty-one'],
        ],
        accent: 'uk',
        innerGap: const Duration(milliseconds: 200),
      );

      expect(player.buffers, hasLength(1), reason: 'the whole row is one clip');
      expect(piper.rendered, ['Twenty-four.', 'Thirty-one.']);
      // 22050 samples per part (the stub) + 200 ms of silence between them.
      final clip = decodeWav(player.buffers.single);
      expect(clip.sampleCount, 22050 * 2 + (22050 * 0.2).round());
    });

    test('a sentence goes to the system voice as one utterance', () async {
      final player = _RecordingPlayer(supportsSentences: true);
      final speaker = NumberSpeaker(player: player, resolver: _noClips);

      await speaker.speak('one thousand two hundred and thirty-four', accent: 'us', rate: 0.8);

      // One call, the whole sentence — not seven recorded words.
      expect(player.sentences, ['one thousand two hundred and thirty-four']);
      expect(player.sentenceAccents, ['us']);
      expect(player.rates, [0.4],
          reason: 'the engine is handed the anchored rate, not the slider value');
      expect(player.played, isEmpty, reason: 'no clip playback when a voice exists');
    });

    test('a device without a voice reads the number continuously, not word by word', () async {
      // The web build and phones whose TTS has no English answer false. The
      // number must still come out as one clip — reading "twenty … one" instead
      // is the bug this guards.
      final player = _RecordingPlayer();
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );

      await speaker.speak('twenty-one', accent: 'uk');

      expect(player.sentences, ['twenty-one'], reason: 'the voice was tried first');
      expect(speaker.spokenBy, SentenceEngine.spliced);
      expect(player.buffers, isNotEmpty);
      expect(player.played.where((entry) => entry.endsWith('.wav')), isEmpty);
    });

    test('日期 teaches every month and weekday as its own word', () {
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
        'September', 'October', 'November', 'December',
      ];
      const weekdays = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
      ];

      final dateCards = NumberData.getByCategory(NumberCategory.date);
      final words = <String, NumberExample>{
        for (final card in dateCards)
          if (card.kind == NumberCardKind.word) card.input: card,
      };

      for (final word in [...months, ...weekdays]) {
        final card = words[word];
        expect(card, isNotNull, reason: '$word is missing from 日期');
        expect(card!.value, isNotEmpty, reason: '$word teaches nothing');
        expect(card.hint, isNotEmpty, reason: '$word has no note');
        // A word card is spoken as the word itself, and that word ships as a clip in
        // both accents — otherwise the card would teach a word it cannot say.
        final reading = NumberData.readingOf(card)!;
        expect(reading.ukText, word);
        expect(reading.usText, word);
        expect(NumberAudio.hasClip(word), isTrue, reason: 'no clip for $word');
        for (final accent in ['uk', 'us']) {
          expect(
            File('assets/${NumberAudio.assetPath(word, accent)}').existsSync(),
            isTrue,
            reason: '$word has no $accent recording',
          );
        }
      }

      // Months first, then the weekdays, each in calendar order: the list is what
      // a learner recites.
      expect(
        dateCards
            .where((card) => card.kind == NumberCardKind.word)
            .map((card) => card.input)
            .toList(),
        [...months, ...weekdays],
      );
    });

    test('the drill speaks each number as a sentence and reports progress', () async {
      final player = _RecordingPlayer(supportsSentences: true);
      final speaker = NumberSpeaker(player: player, resolver: _noClips);

      final seen = <int>[];
      await speaker.speakAll(
        ['one', 'twice two', 'three times'],
        accent: 'uk',
        gap: const Duration(milliseconds: 10),
        onIndex: seen.add,
      );

      expect(seen, [0, 1, 2]);
      expect(player.sentences, ['one', 'twice two', 'three times']);
      expect(player.played, isEmpty);

      // 停止 must cut the sentence in flight.
      player.onPlay = (_) {};
      final stopping = NumberSpeaker(player: player, resolver: _noClips);
      await stopping.speakAll(['one', 'two'], gap: const Duration(milliseconds: 10));
      stopping.cancel();
      expect(player.stops, greaterThan(0));
    });

    test('clips mode never asks the voice, even when one exists', () async {
      final player = _RecordingPlayer(supportsSentences: true);
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );

      await speaker.speak('two', accent: 'us', mode: SpeechMode.clips);

      expect(player.sentences, isEmpty);
      expect(player.played, ['audio/numbers/two_us.wav']);
    });

    testWidgets('the numbers screen teaches, listens and drills', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<NumbersProvider>.value(
          value: provider,
          child: const MaterialApp(home: NumbersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 分类展示 is the landing section and carries the inventory.
      expect(find.text('数字表达方式分类'), findsOneWidget);
      expect(find.text('twelve'), findsWidgets); // 1–12 are listed one by one

      // 自由输入 turns any number into a sentence.
      await tester.tap(find.text('自由输入'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2026-10-08');
      await tester.pumpAndSettle();
      expect(find.textContaining('the eighth of October twenty twenty-six'), findsOneWidget);

      // 数字训练 generates numbers that stay hidden until revealed.
      await tester.tap(find.text('数字训练'));
      await tester.pumpAndSettle();
      // Every kind is offered as a chip, including the new listening drills.
      for (final label in ['整数', '小数', '年份', '序数词', '分数', '百分数', '温度', '时刻', '货币', '日期', '电话号码', '混合']) {
        expect(find.text(label), findsWidgets, reason: 'missing drill kind chip: $label');
      }
      await tester.tap(find.text('生成一组'));
      await tester.pumpAndSettle();
      expect(provider.training, isNotEmpty);
      expect(find.textContaining('数字已隐藏'), findsOneWidget);

      await tester.tap(find.text('显示数字'));
      await tester.pumpAndSettle();
      expect(find.textContaining('数字已显示'), findsOneWidget);

      // 整数 mode offers 多组连读: turning it on makes every row a run, and the
      // batch is counted in 组, with a 组间 pause instead of a plain 间隔.
      expect(find.text('多组连读'), findsOneWidget);
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(provider.runBatch, isTrue);
      expect(find.text('组间'), findsOneWidget);
      await tester.tap(find.text('生成一组'));
      await tester.pumpAndSettle();
      expect(provider.training, isNotEmpty);
      expect(
        provider.training.every((row) =>
            row.numbers.length >= provider.runMin && row.numbers.length <= provider.runMax),
        isTrue,
      );
      expect(find.textContaining('组 · 每组'), findsOneWidget);

      // Another kind has no runs to offer, so the switch is not there at all.
      final moneyChip = find.descendant(
        of: find.byType(NumbersTrainingSection),
        matching: find.text('货币'),
      );
      await tester.ensureVisible(moneyChip);
      await tester.pumpAndSettle();
      await tester.tap(moneyChip);
      await tester.pumpAndSettle();
      expect(find.text('多组连读'), findsNothing);
      expect(provider.runBatch, isFalse);
    });
  });

  group('Speech rate', () {
    test('x1.0 on the slider is the teaching pace, not the voice native rate', () {
      // A native speaker says the calibration phrase in 1548 ms; the drill runs
      // it at 3100 ms because you are doing arithmetic in a second language.
      expect(engineRateFor(1.0), 0.5);
      expect(engineRateFor(NumbersLimits.minRate), closeTo(0.25, 1e-9));
      expect(engineRateFor(NumbersLimits.maxRate), closeTo(0.75, 1e-9));
      expect(engineRateFor(NumbersLimits.maxRate), lessThan(1.0),
          reason: 'native speed must stay out of the drill range');
    });

    test('the teaching pace is the prosody floor, with no pauses needed', () {
      // Anchoring regression: the old mapping asked for prosody 95-100% here.
      final plan = speechPlanFor(engineRateFor(1.0), wordCount: 7);
      expect(plan.prosodyPercent, oneCoreSteps.first.setting);
      expect(plan.wordGapMs, 0);
    });

    test('below the prosody floor the shortfall is carried by pauses', () {
      final slow = speechPlanFor(engineRateFor(NumbersLimits.minRate), wordCount: 7);
      expect(slow.prosodyPercent, oneCoreSteps.first.setting,
          reason: 'articulation is already at the floor');
      expect(slow.wordGapMs, greaterThan(0));
      expect(slow.wordGapMs, lessThanOrEqualTo(1200));
    });

    test('the pause makes up the missing time', () {
      // floor = 2.0x the 1548 ms calibration phrase = 3096 ms; 0.25x asks for
      // 6192 ms, so 3096 ms across 6 gaps = ~516 ms each.
      expect(speechPlanFor(0.25, wordCount: 7).wordGapMs, inInclusiveRange(450, 580));
    });

    test('nothing gets faster as the slider rises', () {
      var lastProsody = -1;
      var lastGap = 1 << 30;
      for (var ui = NumbersLimits.minRate;
          ui <= NumbersLimits.maxRate + 1e-9;
          ui += 0.05) {
        final plan = speechPlanFor(engineRateFor(ui), wordCount: 7);
        expect(plan.prosodyPercent, greaterThanOrEqualTo(lastProsody),
            reason: 'rate $ui');
        expect(plan.wordGapMs, lessThanOrEqualTo(lastGap), reason: 'rate $ui');
        lastProsody = plan.prosodyPercent;
        lastGap = plan.wordGapMs;
      }
    });

    test('a one-word utterance has no gap to slow down with', () {
      final plan = speechPlanFor(0.25, wordCount: 1);
      expect(plan.wordGapMs, 0);
      expect(plan.prosodyPercent, oneCoreSteps.first.setting);
    });

    test('SAPI runs off the same engine rate', () {
      expect(sapiRate(0.5), -6);
      expect(sapiRate(0.75), -2);
      expect(sapiRate(0.25), sapiSteps.first.setting); // clamped at its floor
    });

    test('a stored zero rate cannot break the mapping', () {
      expect(speechPlanFor(0, wordCount: 7).prosodyPercent, oneCoreSteps.first.setting);
      expect(sapiRate(-2), sapiSteps.first.setting);
    });

    test('the speaker converts the slider value exactly once', () async {
      // Every engine must receive the engine rate. Converting inside one engine
      // instead leaves the others playing at native speed for the same slider
      // position, which is what the Windows-only fix originally did.
      final player = _RecordingPlayer(supportsSentences: true);
      final speaker = NumberSpeaker(player: player, resolver: _noClips);

      await speaker.speak('two', accent: 'us', rate: 1.0);
      expect(player.rates.single, 0.5, reason: 'x1.0 is half the natural rate');

      player.rates.clear();
      await speaker.speak('two', accent: 'us', rate: NumbersLimits.minRate);
      expect(player.rates.single, closeTo(0.25, 1e-9));
    });

    test('clips mode receives the engine rate too', () async {
      final player = _RecordingPlayer(supportsSentences: true);
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );

      await speaker.speak('two', accent: 'us',
          rate: NumbersLimits.maxRate, mode: SpeechMode.clips);

      expect(player.played, ['audio/numbers/two_us.wav']);
      expect(player.rates.single, closeTo(0.75, 1e-9));
    });

    test('a rate stored before the re-anchoring keeps its pace', () async {
      // 0.5 under the old meaning is the same pace x1.0 means now, so the stored
      // value is doubled — and only once.
      SharedPreferences.setMockInitialValues(<String, Object>{'numbers_rate': 0.5});
      final first = NumbersProvider();
      await first.initialize();
      expect(first.rate, 1.0);

      final second = NumbersProvider();
      await second.initialize();
      expect(second.rate, 1.0, reason: 'must not be doubled twice');
    });

    test('a stale fast setting is clamped into the new range', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'numbers_rate': 1.5});
      final provider = NumbersProvider();
      await provider.initialize();
      expect(provider.rate, NumbersLimits.maxRate);
    });
  });

  group('Playback cancellation', () {
    test('a stopped run does not resume once the next one starts', () async {
      // The bug: `cancel()` set a shared bool, the next run cleared it, and the
      // abandoned run — parked inside `playSpeechClip` — woke up, read "not
      // cancelled" and read its remaining words over the top of the new run.
      final player = _GatedPlayer();
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );

      player.hold();
      final first = speaker.speak('one thousand', accent: 'us', mode: SpeechMode.clips);
      await pumpEventQueue();
      expect(player.played, ['audio/numbers/one_us.wav'],
          reason: 'the first run should be parked on its first word');

      speaker.cancel();
      final second = speaker.speak('two', accent: 'us', mode: SpeechMode.clips);
      await pumpEventQueue();
      expect(player.played, contains('audio/numbers/two_us.wav'));

      player.release();
      await Future.wait([first, second]);

      expect(player.played, isNot(contains('audio/numbers/thousand_us.wav')),
          reason: 'the cancelled run carried on instead of dropping out');
    });

    test('words still play in order when nothing is cancelled', () async {
      // Guards the fix itself: staleness must not be confused with "a later word".
      final player = _GatedPlayer();
      final speaker = NumberSpeaker(
        player: player,
        resolver: (word, accent) async => 'audio/numbers/${word}_$accent.wav',
      );

      await speaker.speak('one thousand', accent: 'us', mode: SpeechMode.clips);

      expect(player.played, [
        'audio/numbers/one_us.wav',
        'audio/numbers/thousand_us.wav',
      ]);
    });
  });
}
