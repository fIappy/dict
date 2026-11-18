import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/custom/passage_cleanup.dart';

void main() {
  test('a single word or an unclosed short phrase is a fragment', () {
    for (final line in ['Well', 'tenth', 'An exam', 'Not really', 'I mean', 'Why?']) {
      expect(isFragmentLine(line), isTrue, reason: line);
    }
  });

  test('a short line the transcript closed is a sentence', () {
    for (final line in ['Are you nervous?', 'Why not?', 'I am a teacher.', '---------']) {
      expect(isFragmentLine(line), isFalse, reason: line);
    }
  });

  test('the closing mark does not make two lines different sentences', () {
    expect(sentenceKey('Why not?'), sentenceKey('why not.'));
    expect(sentenceKey('  What   is this? '), sentenceKey('what is this'));
    expect(sentenceKey('“does”.'), sentenceKey('does'));
  });

  test('a sentence said in an earlier chapter is kept only there', () {
    final cleaned = cleanPassages([
      passageFromBody('Lesson 1\nWhy not?\nI am a teacher.\nAn exam'),
      passageFromBody('Lesson 2\nI am a teacher.\nThat’s a long sentence.'),
    ]);

    expect(cleaned.first.sentences, ['Why not?', 'I am a teacher.']);
    expect(cleaned.last.sentences, ['That’s a long sentence.']);
  });

  test('a chapter left with nothing comes back empty', () {
    final cleaned = cleanPassages([
      passageFromBody('Lesson 1\nI am a teacher.'),
      passageFromBody('Lesson 2\nI am a teacher.\nWell'),
    ]);

    expect(cleaned.last.isEmpty, isTrue);
    expect(cleaned.last.body, 'Lesson 2');
  });

  test('dividers survive the cleanup and are not treated as sentences', () {
    final cleaned = cleanPassages([
      passageFromBody('Work\n-----------\nI walked in.\n-----------'),
    ]);

    expect(cleaned.single.sentences, ['-----------', 'I walked in.', '-----------']);
  });
}
