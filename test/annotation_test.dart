import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ai/annotation.dart';

List<AnnotatedSpan> _annotate(
  String text, {
  Set<String> words = const {},
  List<String> phrases = const [],
}) =>
    annotateText(text, themeWords: words, phrases: phrases);

String _marked(List<AnnotatedSpan> spans) => spans.map((s) => s.toString()).join(' ');

void main() {
  group('theme words', () {
    test('marks whole words and leaves the rest alone', () {
      final spans = _annotate('The coach called the team.', words: {'coach'});
      expect(_marked(spans), '"The " "coach" theme " called the team."');
    });

    test('a plural or simple inflection still counts', () {
      final spans = _annotate(
        'The coaches were coaching.',
        words: {'coach'},
      );
      expect(spans.where((s) => s.isThemeWord).map((s) => s.text),
          ['coaches', 'coaching']);
    });

    test('a word containing the theme word is not marked', () {
      final spans = _annotate('The coachman waited.', words: {'coach'});
      expect(spans.every((s) => !s.isThemeWord), isTrue);
    });

    test('matching ignores case', () {
      final spans = _annotate('COACH shouts.', words: {'coach'});
      expect(spans.singleWhere((s) => s.isThemeWord).text, 'COACH');
    });

    test('a trailing apostrophe does not break the token', () {
      final spans = _annotate("The coach's whistle.", words: {'coach'});
      expect(spans.singleWhere((s) => s.isThemeWord).text, "coach's");
    });
  });

  group('phrases', () {
    test('marks a multiword collocation', () {
      final spans = _annotate(
        'She takes care of the team.',
        phrases: ['takes care of'],
      );
      expect(spans.singleWhere((s) => s.isPhrase).text, 'takes care of');
    });

    test('a phrase must sit on word boundaries', () {
      final spans = _annotate('Scarecrowish.', phrases: ['care']);
      expect(spans.every((s) => !s.isPhrase), isTrue);
    });

    test('a theme word inside a phrase carries both marks', () {
      final spans = _annotate(
        'She takes care of the coach.',
        words: {'coach'},
        phrases: ['takes care of'],
      );
      final both = spans.where((s) => s.isThemeWord && s.isPhrase);
      expect(both, isEmpty, reason: 'the theme word is outside the phrase');
      final phraseOnly = spans.singleWhere((s) => s.isPhrase);
      expect(phraseOnly.isThemeWord, isFalse);

      final overlap = _annotate(
        'In charge of it.',
        words: {'charge'},
        phrases: ['in charge of'],
      );
      expect(overlap.where((s) => s.isThemeWord && s.isPhrase).map((s) => s.text),
          ['charge']);
    });

    test('spans always reassemble into the original text', () {
      const text = 'The coaches take care of the 6 trainees, day and night.';
      final spans = _annotate(
        text,
        words: {'coach', 'trainee'},
        phrases: ['take care of', 'day and night'],
      );
      expect(spans.map((s) => s.text).join(), text);
    });

    test('no marks at all still yields the text', () {
      final spans = _annotate('Plain words.', words: {'apple'});
      expect(spans, hasLength(1));
      expect(spans.single.text, 'Plain words.');
    });
  });
}
