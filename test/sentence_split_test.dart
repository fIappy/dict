import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/custom/sentence_split.dart';

void main() {
  test('two sentences on one line become two lines', () {
    expect(splitSentenceLine('Ok? Let’s go!'), ['Ok?', 'Let’s go!']);
    expect(
      splitSentenceLine('Thank you, Josh. This restaurant is awesome.'),
      ['Thank you, Josh.', 'This restaurant is awesome.'],
    );
  });

  test('abbreviations and decimals do not split', () {
    expect(splitSentenceLine('I met Mr. Smith yesterday.'), ['I met Mr. Smith yesterday.']);
    expect(splitSentenceLine('It costs 3.50 dollars.'), ['It costs 3.50 dollars.']);
    expect(
      splitSentenceLine('The class starts at 11.30 in the morning.'),
      ['The class starts at 11.30 in the morning.'],
    );
  });

  test('a quoted question stays inside its sentence', () {
    expect(
      splitSentenceLine('…is a statement “Is this a man?” is a question.'),
      ['…is a statement “Is this a man?” is a question.'],
    );
  });

  test('a long run-on splits at the next capital subject and its clauses', () {
    const line = 'He is trying to make her think that he is taking an exam tomorrow, '
        'because he doesn’t want to go to the concert with her '
        'He doesn’t want to go with her so he says nothing.';
    final parts = splitSentenceLine(line);
    expect(parts.length, 3);
    expect(parts.first.endsWith('.'), isTrue);
    expect(parts[1], startsWith('Because he doesn’t want'));
    expect(parts.last, startsWith('He doesn’t want to go with her'));
  });

  test('a drill question at the end of a long line gets its own line', () {
    const line = 'She doesn’t agree to go to the art gallery with Michael '
        'because the art galleries are so boring for her '
        'Does she want to hang out at some boring place with Michael?';
    final parts = splitSentenceLine(line);
    expect(parts.length, 3);
    expect(parts[1], startsWith('Because the art galleries'));
    expect(parts.last, startsWith('Does she want to hang out'));
  });

  test('an unpunctuated wh-question splits and gains its capital', () {
    const line = 'I think he is trying to find a way to refuse her '
        'so he says that now he is working on a project '
        'why is he trying to make her think that he is taking an exam tomorrow?';
    final parts = splitSentenceLine(line);
    expect(parts.length, 3);
    expect(parts[1], startsWith('So he says'));
    expect(parts.last, startsWith('Why is he trying'));
  });

  test('"I" mid-sentence is not a split point', () {
    const line = 'I think he is trying to find a way to refuse her '
        'because I don’t want to go with him to the party tonight.';
    final parts = splitSentenceLine(line);
    // The conjunction is a real clause boundary; the pronoun inside it is not.
    expect(parts.length, 2);
    expect(parts.last, startsWith('Because I don’t want'));
  });

  test('a clause chain from a transcript becomes separate lines', () {
    const line = 'Subject "Lisa" before it we have the indicative word “does”, '
        'because Lisa is a she and after it we have our verb “drink” '
        'without the ending “s”.';
    expect(splitSentenceLine(line), [
      'Subject "Lisa" before it we have the indicative word “does”.',
      'Because Lisa is a she.',
      'And after it we have our verb “drink” without the ending “s”.',
    ]);
  });

  test('a lead-in keeps its colon instead of gaining a full stop', () {
    expect(splitSentenceLine('Or example:'), ['Or example:']);
    expect(splitSentenceLine('Or example:.'), ['Or example:']);
    expect(splitSentenceLine('But we ask in the following way:'), ['But we ask in the following way:']);
  });

  test('a long clause without a conjunction gains its pauses', () {
    const line = 'Okay next one number four in the society people live longer '
        'so this is comparison right because we’re saying longer longer than '
        'what well if we think about it in society nowadays.';
    final parts = splitSentenceLine(line);
    expect(parts.length, greaterThan(1));
    expect(parts.first.endsWith('.'), isTrue);
  });
}
