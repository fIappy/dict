import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ai/vocabulary_band.dart';

void main() {
  group('rankByFrequency', () {
    test('orders by COCA rank and puts unknown words last', () {
      final ranked = rankByFrequency(
        ['suture', 'ward', 'the', 'stethoscope'],
        (w) => switch (w) {
          'the' => 1,
          'ward' => 300,
          'suture' => 9000,
          _ => null,
        },
      );
      expect(ranked, ['the', 'ward', 'suture', 'stethoscope']);
    });

    test('drops duplicates and blank entries', () {
      final ranked = rankByFrequency(
        ['ward', 'Ward', ' ', 'nurse'],
        (w) => w == 'ward' ? 10 : 20,
      );
      expect(ranked, ['ward', 'nurse']);
    });
  });

  group('wordsInBand', () {
    final ranked = [for (var i = 1; i <= 600; i++) 'w$i'];

    test('counts from one, the way the reader counts ranks', () {
      expect(
        wordsInBand(ranked, from: 200, to: 205, length: 140),
        ['w200', 'w201', 'w202', 'w203', 'w204', 'w205'],
      );
    });

    test('a band wider than the passage can hold is sampled evenly', () {
      // 1001 words of passage allows 100 required words (one per ten words).
      final picked = wordsInBand(ranked, from: 200, to: 300, length: 1000);
      expect(picked, hasLength(100));
      expect(picked.first, 'w200');
      expect(picked.last, isNot('w300'),
          reason: 'even spacing never lands on the very last member');
      expect(picked.toSet(), hasLength(100), reason: 'no duplicates');
      final indices = [for (final w in picked) int.parse(w.substring(1))];
      expect(indices, orderedEquals([...indices]..sort()));
      for (final index in indices) {
        expect(index, inInclusiveRange(200, 300));
      }
    });

    test('a short passage still asks for a few words', () {
      expect(wordsInBand(ranked, from: 1, to: 50, length: 20), hasLength(3),
          reason: 'three is the floor below one per ten words');
    });

    test('bounds are clamped instead of throwing', () {
      expect(wordsInBand(ranked, from: 0, to: 2, length: 200), ['w1', 'w2']);
      expect(wordsInBand(ranked, from: 590, to: 9000, length: 200),
          ['w590', 'w591', 'w592', 'w593', 'w594', 'w595', 'w596', 'w597',
           'w598', 'w599', 'w600']);
      expect(wordsInBand(ranked, from: 5, to: 3, length: 200), ['w5']);
    });

    test('an empty theme has nothing to ask for', () {
      expect(wordsInBand(const [], from: 1, to: 10, length: 500), isEmpty);
    });
  });
}
