import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_dict/core/audio/kokoro_voice.dart';
import 'package:local_dict/core/audio/speech_clip_player.dart';
import 'package:local_dict/core/audio/pcm_audio.dart';
import 'package:local_dict/core/numbers/number_data.dart';
import 'package:local_dict/core/numbers/number_model.dart';
import 'package:local_dict/core/numbers/number_speaker.dart';
import 'package:local_dict/core/numbers/number_speller.dart';
import 'package:local_dict/core/numbers/number_training.dart';
import 'package:local_dict/providers/numbers_provider.dart';

/// Reads the number spellings the module produces, without touching audio.
String uk(String input) => NumberSpeller.read(input)!.ukText;
String us(String input) => NumberSpeller.read(input)!.usText;

/// Records what the speaker asked for, so the sequencing can be asserted.
/// A Kokoro voice that always has a model: the engine's own loading is not what
/// these tests are about.
class _StubKokoro extends KokoroVoice {
  _StubKokoro() : super(finder: () async => null);

  /// Every sentence the stub was asked to render, in order.
  final List<String> rendered = [];

  /// The speed each render was asked for (`speed` = multiplier of natural).
  final List<double> rates = [];

  @override
  Future<bool> isReady() async => true;

  @override
  Future<PcmClip?> synthesize(String text, {required String accent, required double rate}) async {
    rendered.add(text);
    rates.add(rate);
    return PcmClip(Int16List.fromList(List.filled(24000, 3)), 24000);
  }
}

/// A player whose clip playback can be parked, so a run can be stopped while it
/// sits mid-await — the window in which a shared "cancelled" flag let an
/// abandoned run resume and talk over the run that replaced it. Gates are
/// released individually, so one run can be resumed while another stays parked.
class _GatedPlayer implements SpeechClipPlayer {
  final List<String> played = [];
  final List<Uint8List> buffers = [];
  final List<Completer<void>> _gates = [];
  bool _hold = false;

  /// Park every following [playSpeechClip] until its gate is released.
  void hold() => _hold = true;

  /// Let the parked playback that has been waiting longest continue.
  void releaseFirst() {
    if (_gates.isEmpty) return;
    final gate = _gates.removeAt(0);
    if (!gate.isCompleted) gate.complete();
  }

  /// Let every parked playback continue, and stop parking new ones.
  void release() {
    _hold = false;
    final gates = List<Completer<void>>.of(_gates);
    _gates.clear();
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {
    played.add(assetPath);
    if (!_hold) return;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
  }

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    // Kokoro plays through here, so it parks too — otherwise a run would never
    // be caught mid-await.
    buffers.add(bytes);
    if (!_hold) return true;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    return true;
  }


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
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    onPlay?.call(played.length);
    buffers.add(bytes);
    played.add('bytes:${bytes.length}');
    rates.add(rate);
    return true;
  }


  @override
  Future<bool> speakSentence(String sentence,
      {String accent = 'us', double rate = 1.0}) async {
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

      // Every listed card must teach a value; the words themselves are rendered
      // by the engine now, so there is no clip list to check.
      for (final card in NumberData.wordCards) {
        expect(card.value, isNotNull, reason: '${card.input} has no value');
      }
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

    test('组内间隔 paces the numbers inside a row, and 0 keeps the row joined', () async {
      final rows = NumberTraining.generateRuns(
        digits: 2, count: 1, minLength: 3, maxLength: 3, random: Random(7));
      final row = rows.first.textsFor('us');
      final player = _RecordingPlayer(supportsSentences: true);
      final voice = NumberSpeaker(player: player, kokoro: _StubKokoro());

      await voice.speakRuns([row], accent: 'us', innerGap: Duration.zero);
      expect(player.buffers, hasLength(1),
          reason: '0 = 连读: the engine reads the whole row as one clip');

      player.buffers.clear();
      final watch = Stopwatch()..start();
      await voice.speakRuns(
        [row],
        accent: 'us',
        innerGap: const Duration(milliseconds: 200),
      );
      final elapsedMs = watch.elapsedMilliseconds;
      // One clip per number, with exactly the requested silence between them —
      // the wall clock is where that silence now lives (the clips themselves are
      // the stub's one-second tone).
      expect(player.buffers, hasLength(row.length));
      expect(elapsedMs, greaterThanOrEqualTo(200 * (row.length - 1) - 20),
          reason: 'the slider has to be audible — this is the bug it had');
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
        // A word card is spoken as the word itself.
        final reading = NumberData.readingOf(card)!;
        expect(reading.ukText, word);
        expect(reading.usText, word);
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
      final speaker = NumberSpeaker(player: player, kokoro: _StubKokoro());

      final seen = <int>[];
      await speaker.speakAll(
        ['one', 'twice two', 'three times'],
        accent: 'uk',
        gap: const Duration(milliseconds: 10),
        onIndex: seen.add,
      );

      expect(seen, [0, 1, 2]);
      expect(player.buffers, hasLength(3));

      // 停止 must cut the sentence in flight.
      player.onPlay = (_) {};
      final stopping = NumberSpeaker(player: player, kokoro: _StubKokoro());
      await stopping.speakAll(['one', 'two'], gap: const Duration(milliseconds: 10));
      stopping.cancel();
      expect(player.stops, greaterThan(0));
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
      final speaker = NumberSpeaker(player: player, kokoro: _StubKokoro());

      player.hold();
      final first = speaker.speak('one thousand', accent: 'us');
      await pumpEventQueue();
      expect(player.buffers, hasLength(1),
          reason: 'the first run should be parked in its playback');

      speaker.cancel();
      final second = speaker.speak('two', accent: 'us');
      await pumpEventQueue();

      player.release();
      await Future.wait([first, second]);

      expect(player.buffers, hasLength(2),
          reason: 'the cancelled run dropped out instead of carrying on');
    });

    test('the loop repeats the list until stopped', () async {
      final player = _RecordingPlayer(supportsSentences: false);
      final speaker = NumberSpeaker(player: player, kokoro: _StubKokoro());
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider(speaker: speaker);
      await provider.initialize();
      await provider.setDigits(1);
      await provider.setCount(1);
      await provider.setLoop(true);
      provider.generateTraining();

      // One pass is one clip here, so a third clip can only come from a repeat.
      // Stopping from inside the playback is the same path the button takes.
      player.onPlay = (_) {
        if (player.played.length >= 3) provider.stopPlayback();
      };

      await provider.playTraining();

      expect(player.played.length, greaterThanOrEqualTo(3),
          reason: 'the drill must go round again');
      expect(provider.isPlaying, isFalse, reason: 'stop must win over the loop');
    });

    test('暂停 silences the drill and 继续 starts again from that row', () async {
      final player = _GatedPlayer();
      final speaker = NumberSpeaker(player: player, kokoro: _StubKokoro());
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider(speaker: speaker);
      await provider.initialize();
      await provider.setDigits(1);
      await provider.setCount(3);
      await provider.setGapMs(NumbersLimits.minGapMs);
      provider.generateTraining();

      player.hold();
      final run = provider.playTraining();
      await pumpEventQueue();
      expect(provider.isPlaying, isTrue);
      final pausedAt = provider.playingIndex;
      final playedBefore = player.buffers.length;

      provider.pausePlayback();
      expect(provider.isPaused, isTrue);
      expect(provider.isPlaying, isFalse);

      player.release();
      await run;
      expect(provider.isPaused, isTrue,
          reason: 'the abandoned run must not clear the pause');

      player.hold();
      final resumed = provider.resumePlayback();
      await pumpEventQueue();
      expect(provider.isPlaying, isTrue);
      expect(provider.playingIndex, pausedAt,
          reason: 'picks up at the row that was interrupted');
      expect(player.buffers.length, greaterThan(playedBefore),
          reason: 'that row is said again');

      player.release();
      await resumed;
      expect(provider.isPlaying, isFalse);
      expect(provider.isPaused, isFalse);
    });

    test('without the loop the drill plays one pass and ends', () async {
      final player = _RecordingPlayer(supportsSentences: false);
      final speaker = NumberSpeaker(player: player, kokoro: _StubKokoro());
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider(speaker: speaker);
      await provider.initialize();
      await provider.setDigits(1);
      await provider.setCount(1);
      provider.generateTraining();

      await provider.playTraining();

      expect(player.played, hasLength(1), reason: 'one number, one pass');
      expect(provider.isPlaying, isFalse);
    });

    test('the loop switch is remembered', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final first = NumbersProvider();
      await first.initialize();
      expect(first.loop, isFalse);
      await first.setLoop(true);

      final second = NumbersProvider();
      await second.initialize();
      expect(second.loop, isTrue);
    });

    test('the stop button stays live while a restarted run speaks', () async {
      // The bug: an abandoned run un-parks once a newer one starts, then clears
      // the shared "playing" flag — so the stop button greys out while the new
      // run is still speaking, i.e. exactly when you need to press it.
      final player = _GatedPlayer();
      final speaker = NumberSpeaker(player: player, kokoro: _StubKokoro());
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NumbersProvider(speaker: speaker);
      await provider.initialize();

      final reading = NumberSpeller.read('1234')!;

      player.hold();
      final first = provider.playReading(reading);
      await pumpEventQueue();
      expect(provider.isPlaying, isTrue);

      provider.stopPlayback();
      expect(provider.isPlaying, isFalse);

      final second = provider.playReading(reading);
      await pumpEventQueue();
      expect(provider.isPlaying, isTrue, reason: 'the new run is speaking');

      // Resume the abandoned run while the new one is still parked.
      player.releaseFirst();
      await pumpEventQueue();
      expect(provider.isPlaying, isTrue,
          reason: 'the abandoned run cleared the flag the stop button reads');

      player.release();
      await Future.wait([first, second]);
      expect(provider.isPlaying, isFalse);
    });
  });
}
