import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/custom/passage_reflow.dart';

void main() {
  test('subtitle cues become punctuated sentences', () {
    const body = 'Promo (part 1)\n'
        'Welcome to LOGUS for beginners\n'
        'the first part of the bestselling English course on Udemy\n'
        'You think it’s impossible?\n'
        'We’ll prove you wrong';
    expect(reflowPassage(body), 'Promo (part 1)\n'
        'Welcome to LOGUS for beginners the first part of the bestselling English course on Udemy.\n'
        'You think it’s impossible?\n'
        'We’ll prove you wrong.');
  });

  test('a capital after a cue that cannot end the sentence continues it', () {
    const body = 'Lesson 01\n'
        'You will learn over 1000 of the most important English words\n'
        'And phrases\n'
        'And by learning\n'
        'I don’t mean memorizing';
    final out = reflowPassage(body);
    expect(out, contains('words and phrases.'));
    expect(out, contains('And by learning I don’t mean memorizing.'));
  });

  test('a fragment group collapses into one sentence', () {
    const body = 'Lesson 03\n'
        'is a question\n'
        'And in negative\n'
        'we add “not”\n'
        'after “are”\n'
        'and after “am”\n'
        'For example\n'
        'These cars are not cheap';
    expect(reflowPassage(body), 'Lesson 03\n'
        'Is a question.\n'
        'And in negative we add “not” after “are” and after “am”.\n'
        'For example.\n'
        'These cars are not cheap.');
  });

  test('a clause joined by "and" gets a comma; a list does not', () {
    const body = 'Lesson 09\n'
        'I turned on my computer and opened Chrome\n'
        'and started browsing\n'
        'and the best part is you start speaking instantly';
    final out = reflowPassage(body);
    expect(out, contains('and started browsing'));
    expect(out, contains(', and the best part is'));
  });

  test('questions keep the mark the script wrote and gain none', () {
    const body = 'Lesson 02\n'
        'Where it’s necessary you’ll be given very clear and simple explanations';
    final out = reflowPassage(body);
    expect(out, isNot(contains('?')));
    expect(out, endsWith('.'));
  });

  test('i becomes I and the first letter is capitalised', () {
    const body = 'Lesson 03\n'
        'and i said this is a chair';
    expect(reflowPassage(body), 'Lesson 03\nAnd I said this is a chair.');
  });

  test('hand-written passages are recognised and left alone', () {
    const punctuated = '家庭场景\n'
        'I’m home.\n'
        'I just got back.\n'
        'My building has an elevator.';
    expect(looksLikeSubtitleCues(punctuated), isFalse);
    expect(reflowPassage(punctuated), punctuated);

    const cues = 'Lesson 01\nThis is a chair\nThis is a table';
    expect(looksLikeSubtitleCues(cues), isTrue);
  });
}
