import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/frequency/frequency_service.dart';
import 'package:local_dict/providers/dictionary_provider.dart';
import 'package:local_dict/providers/frequency_provider.dart';
import 'package:local_dict/ui/screens/frequency_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the 词频表 hides obsolete English without renumbering', () async {
    final service = FrequencyService();
    await service.init();

    for (final obsolete in ['thou', 'thee', 'thy', 'thine', 'ye',
        'whence', 'whither', 'hither', 'thither', 'wherefore']) {
      expect(service.getFrequency(obsolete), isNull,
          reason: '$obsolete is archaic');
    }
    // The slot is still there, so nothing after it moved: true COCA ranks.
    expect(service.getWordsByRange(4455, 4455), isEmpty,
        reason: 'thou is hidden, its rank stays');
    expect(service.getFrequency('abandon')!.rank, 2275);
    expect(service.getFrequency('stethoscope')!.rank, 19046);

    // Modern look-alikes stay: plants wilt, art is a noun, wrought iron.
    for (final kept in ['wilt', 'art', 'wrought', 'behold', 'ere', 'aye']) {
      expect(service.getFrequency(kept), isNotNull, reason: kept);
    }
  });

  test('every listed word ships both accents', () async {
    final raw = await rootBundle.loadString('assets/data/frequency_ipa.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (data['words'] as Map).cast<String, dynamic>();
    expect(entries.length, greaterThan(53000));

    for (final entry in entries.entries) {
      final pair = (entry.value as List).cast<String>();
      expect(pair, hasLength(2), reason: entry.key);
      expect(pair[0], isNotEmpty, reason: '${entry.key} has no US IPA');
      expect(pair[1], isNotEmpty, reason: '${entry.key} has no UK IPA');
    }

    // The accents have to differ where the languages do.
    final water = (entries['water'] as List).cast<String>();
    expect(water[0], contains('r'), reason: 'American water is rhotic');
    expect(water[1], isNot(contains('r')), reason: 'British water is not');
    final grass = (entries['grass'] as List).cast<String>();
    expect(grass[0], contains('æ'));
    expect(grass[1], contains('ɑː'), reason: 'RP has the long BATH vowel');
  });

  test('the service hands both accents to the list rows', () async {
    final service = FrequencyService();
    await service.init();

    expect(service.totalRankedWords, greaterThan(53000));

    final water = service.getFrequency('water');
    expect(water, isNotNull);
    expect(water!.usIpa, isNotEmpty);
    expect(water.ukIpa, isNotEmpty);
    expect(water.usIpa, isNot(water.ukIpa));

    final page = service.getWordsByRange(1, 20);
    expect(page, hasLength(20));
    final withIpa = page.where((item) => item.hasIpa).length;
    expect(withIpa, greaterThanOrEqualTo(18),
        reason: 'the first page is ordinary vocabulary');
  });

  testWidgets('the 词频 rows print both accents', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final frequency = FrequencyProvider();
    await frequency.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FrequencyProvider>.value(value: frequency),
          ChangeNotifierProvider(create: (_) => DictionaryProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FrequencyScreen(isPaneView: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('美 /'), findsWidgets,
        reason: 'each row carries the American transcription');
    expect(find.textContaining('英 /'), findsWidgets,
        reason: 'and the British one');
  });
}
