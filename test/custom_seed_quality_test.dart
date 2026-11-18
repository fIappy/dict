import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/custom/passage_cleanup.dart';

/// Whether [sentence] closes with a sentence mark, quotes and brackets aside.
bool _endsWithMark(String sentence) {
  var text = sentence.trimRight();
  const closers = {'"', "'", '”', '’', ')', ']'};
  while (text.isNotEmpty && closers.contains(text[text.length - 1])) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  return text.isNotEmpty && '.!?…'.contains(text[text.length - 1]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the shipped Udemy passages have no repeats and no half sentences',
      () async {
    final raw = await rootBundle.loadString('assets/seed/custom_home.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final groups = (seed['groups'] as List).cast<Map<String, dynamic>>();
    final udemyId = groups
        .firstWhere((group) =>
            (group['name'] as String? ?? '').startsWith('Udemy'))['id'];
    final texts = (seed['texts'] as List)
        .cast<Map<String, dynamic>>()
        .where((text) => text['groupId'] == udemyId);

    final seen = <String>{};
    final repeated = <String>[];
    final fragments = <String>[];
    final unclosed = <String>[];
    for (final text in texts) {
      final body = text['body'] as String? ?? '';
      for (final line in body.split('\n').skip(1)) {
        final sentence = line.trim();
        if (sentence.isEmpty) continue;
        if (isFragmentLine(sentence)) {
          fragments.add(sentence);
          continue;
        }
        if (!_endsWithMark(sentence)) unclosed.add(sentence);
        if (!seen.add(sentenceKey(sentence))) repeated.add(sentence);
      }
    }

    expect(repeated, isEmpty, reason: 'a sentence is said twice');
    expect(fragments, isEmpty, reason: 'a line is not a sentence');
    expect(unclosed, isEmpty, reason: 'a line has no closing mark');
  });
}
