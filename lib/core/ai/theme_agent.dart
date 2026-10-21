import 'dart:convert';

import '../frequency/frequency_service.dart';
import 'openai_client.dart';

/// How hard the generated English should be.
enum PracticeLevel { easy, medium, hard }

extension PracticeLevelLabel on PracticeLevel {
  String get label => switch (this) {
    PracticeLevel.easy => '易',
    PracticeLevel.medium => '中',
    PracticeLevel.hard => '难',
  };

  /// The word the model is given; prompts are written in English.
  String get promptName => switch (this) {
    PracticeLevel.easy => 'easy',
    PracticeLevel.medium => 'medium',
    PracticeLevel.hard => 'hard',
  };
}

/// A word with its COCA rank; 1 is the most frequent.
class RankedWord {
  const RankedWord(this.word, this.rank);

  final String word;
  final int rank;
}

class GeneratedSentence {
  const GeneratedSentence({required this.text, this.translation});

  final String text;
  final String? translation;

  Map<String, dynamic> toJson() => {
    'text': text,
    if (translation != null) 'translation': translation,
  };

  factory GeneratedSentence.fromJson(Map<String, dynamic> json) =>
      GeneratedSentence(
        text: (json['text'] ?? '').toString().trim(),
        translation: (json['translation'] ?? '').toString().trim().isEmpty
            ? null
            : (json['translation'] as String).trim(),
      );
}

class GeneratedPassage {
  const GeneratedPassage({required this.title, required this.text});

  final String title;
  final String text;

  Map<String, dynamic> toJson() => {'title': title, 'text': text};

  factory GeneratedPassage.fromJson(Map<String, dynamic> json) =>
      GeneratedPassage(
        title: (json['title'] ?? '').toString().trim(),
        text: (json['text'] ?? '').toString().trim(),
      );
}

/// Words too grammatical to make an interesting practice sentence. They are the
/// only thing the head of a frequency list contains, so a theme whose "easy"
/// band is taken literally would be handed `the / of / and` to write a passage
/// around.
const Set<String> _stopwords = {
  'a',
  'an',
  'the',
  'be',
  'is',
  'am',
  'are',
  'was',
  'were',
  'been',
  'being',
  'of',
  'to',
  'in',
  'on',
  'at',
  'by',
  'for',
  'with',
  'from',
  'into',
  'onto',
  'as',
  'and',
  'or',
  'but',
  'nor',
  'so',
  'yet',
  'if',
  'than',
  'then',
  'that',
  'this',
  'these',
  'those',
  'it',
  'its',
  'he',
  'she',
  'they',
  'them',
  'his',
  'her',
  'their',
  'we',
  'us',
  'our',
  'you',
  'your',
  'i',
  'me',
  'my',
  'not',
  'no',
  'do',
  'does',
  'did',
  'have',
  'has',
  'had',
  'will',
  'would',
  'can',
  'could',
  'may',
  'might',
  'must',
  'shall',
  'should',
  'there',
  'here',
  'who',
  'whom',
  'whose',
  'which',
  'what',
  'when',
  'where',
  'why',
  'how',
  'all',
  'any',
  'both',
  'each',
  'few',
  'more',
  'most',
  'other',
  'some',
  'such',
  'only',
  'own',
  'same',
  'too',
  'very',
  'just',
  'also',
  'up',
  'down',
  'out',
  'off',
  'over',
  'under',
  'again',
  'once',
  'about',
  'after',
  'before',
};

/// Turns a theme's vocabulary into a prompt and the answer into text.
///
/// The theme side is what makes this more than a generic chat box: the words
/// the passage has to use are chosen from the scene by COCA rank, so "easy"
/// really is frequent vocabulary and "hard" really is the tail of the list.
class ThemeAgent {
  ThemeAgent({required OpenAiClient client, FrequencyService? frequency})
    : _client = client,
      _frequency = frequency ?? FrequencyService();

  final OpenAiClient _client;
  final FrequencyService _frequency;

  /// Rank given to a word the frequency list does not know: rarer than anything
  /// in it, which is exactly what the hard band wants.
  static const int unknownRank = 30000;

  /// Picks the words a passage must use. Pure over [ranked] so the banding can
  /// be tested without loading the frequency asset.
  static List<String> pickWords(
    List<RankedWord> ranked,
    PracticeLevel level,
    int count,
  ) {
    final usable = <RankedWord>[];
    final seen = <String>{};
    for (final entry in ranked) {
      final word = entry.word.trim().toLowerCase();
      if (word.length < 3) continue;
      if (_stopwords.contains(word)) continue;
      if (!seen.add(word)) continue;
      usable.add(RankedWord(word, entry.rank));
    }
    if (usable.isEmpty) return const [];
    usable.sort((a, b) => a.rank.compareTo(b.rank));

    final take = count < usable.length ? count : usable.length;
    switch (level) {
      case PracticeLevel.easy:
        return [for (final w in usable.take(take)) w.word];
      case PracticeLevel.hard:
        return [for (final w in usable.reversed.take(take)) w.word]..sort();
      case PracticeLevel.medium:
        final start = ((usable.length - take) / 2).floor();
        return [for (final w in usable.skip(start).take(take)) w.word];
    }
  }

  /// The band for [sceneWords] under [level], as the real COCA ranks see it.
  List<String> pickSceneWords(
    Iterable<String> sceneWords,
    PracticeLevel level,
    int count,
  ) {
    final ranked = <RankedWord>[];
    for (final word in sceneWords) {
      final rank = _frequency.getFrequency(word)?.rank ?? unknownRank;
      ranked.add(RankedWord(word, rank));
    }
    return pickWords(ranked, level, count);
  }

  Future<({List<GeneratedSentence> items, String reasoning})> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async {
    final reply = await _client.complete(
      system: _sentenceSystem,
      user: _sentenceUser(
        word: word,
        count: count,
        level: level,
        sceneLabel: sceneLabel,
      ),
      temperature: 0.6,
      maxTokens: 1200,
    );
    final parsed = parseSentences(reply.text);
    if (parsed.isEmpty) {
      throw const AiException('模型没有返回可用的句子');
    }
    return (items: parsed, reasoning: reply.reasoning ?? '');
  }

  Future<({GeneratedPassage passage, String reasoning})> passage({
    required String sceneLabel,
    required String sceneHint,
    required List<String> words,
    required PracticeLevel level,
  }) async {
    if (words.isEmpty) {
      throw const AiException('这个主题里没有可用于生成短文的词');
    }
    final reply = await _client.complete(
      system: _passageSystem,
      user: _passageUser(
        sceneLabel: sceneLabel,
        sceneHint: sceneHint,
        words: words,
        level: level,
      ),
      temperature: 0.75,
      maxTokens: 1600,
    );
    final parsed = parsePassage(reply.text);
    if (parsed.text.isEmpty) {
      throw const AiException('模型没有返回可用的短文');
    }
    return (passage: parsed, reasoning: reply.reasoning ?? '');
  }

  // ------------------------------------------------------------------ prompts

  static const String _sentenceSystem =
      'You are an experienced English teacher and lexicographer writing '
      'example sentences for Chinese learners of English.\n'
      'Rules:\n'
      '- Every sentence must be idiomatic modern English with correct grammar, '
      'punctuation and logic.\n'
      '- Never invent a meaning the target word does not have.\n'
      '- Reply with JSON only: no prose, no code fences.';

  static String _sentenceUser({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) {
    final theme = sceneLabel == null ? '' : '\nLearner\'s theme: $sceneLabel';
    return 'Target word: "$word"$theme\n'
        'Write exactly $count example sentences that use "$word" in its real '
        'senses; inflected forms are fine.\n'
        'Order them from easiest to hardest and from shortest to longest '
        '(level: ${level.promptName}).\n'
        'Each sentence: 6-22 words, self-contained, natural collocations, and a '
        'different grammatical pattern from the others.\n'
        'No two sentences may be paraphrases of each other.\n'
        'Return this JSON shape:\n'
        '{"sentences":[{"text":"<English sentence>","translation":"<简体中文翻译>"}]}';
  }

  static const String _passageSystem =
      'You are an experienced English teacher writing short reading passages '
      'for Chinese learners of English.\n'
      'Rules:\n'
      '- The passage must be coherent: one topic, a logical progression, no '
      'contradictions or non sequiturs.\n'
      '- Grammar, collocations and punctuation must be flawless, and the English '
      'must sound native rather than translated.\n'
      '- Reply with JSON only: no prose, no code fences.';

  static String _passageUser({
    required String sceneLabel,
    required String sceneHint,
    required List<String> words,
    required PracticeLevel level,
  }) {
    final length = switch (level) {
      PracticeLevel.easy => '90-120',
      PracticeLevel.medium => '130-160',
      PracticeLevel.hard => '170-220',
    };
    final levelRules = switch (level) {
      PracticeLevel.easy =>
        '- easy: mostly one-clause sentences, only common vocabulary besides the '
            'required words (they are the most frequent members of this theme).',
      PracticeLevel.medium =>
        '- medium: a mix of simple and complex sentences, everyday vocabulary.',
      PracticeLevel.hard =>
        '- hard: complex sentences (subordinate clauses, participial phrases, '
            'nominalisation); the required words are the rarest members of this '
            'theme, so use them precisely.',
    };
    return 'Theme: $sceneLabel — $sceneHint\n'
        'Level: ${level.promptName}\n'
        'Required words (from this theme): ${words.join(', ')}\n\n'
        'Write ONE passage of about $length words.\n'
        '$levelRules\n'
        'Content rules:\n'
        '- Use at least 80% of the required words, each in a correct and natural '
        'sense.\n'
        '- Keep exactly one topic.\n'
        '- No grammar, collocation or logic errors.\n'
        'Return this JSON shape:\n'
        '{"title":"<short English title>","text":"<the passage>"}';
  }

  // ------------------------------------------------------------------ parsing

  /// Decodes the model's answer.
  ///
  /// Servers are far less obedient than the prompt: reasoning models narrate
  /// before answering, some wrap the JSON in code fences, some answer with two
  /// objects, and prose can hold braces of its own. Every balanced `{…}` /
  /// `[…]` span is tried in order instead of the old "first brace to last
  /// brace" guess, which fell over the moment a brace appeared in the intro.
  static Object? _decode(String raw) {
    for (final candidate in _candidates(raw)) {
      try {
        return jsonDecode(candidate);
      } on FormatException {
        continue;
      }
    }
    throw AiException('模型返回的内容不是合法 JSON（开头：${_snippet(raw)}）');
  }

  /// Ordered guesses: the whole text, each fenced block, then every balanced
  /// brace/bracket span. Full-width punctuation is mapped first — a model that
  /// writes `｛` is not giving us JSON, whatever else it got right.
  static Iterable<String> _candidates(String raw) sync* {
    final text = raw
        .replaceAll('｛', '{')
        .replaceAll('｝', '}')
        .replaceAll('［', '[')
        .replaceAll('］', ']')
        .replaceAll('＂', '"')
        .trim();
    if (text.isEmpty) return;
    yield text;
    for (final match in RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').allMatches(text)) {
      final inner = match.group(1)!.trim();
      if (inner.isNotEmpty) yield inner;
    }
    var tried = 0;
    for (var i = 0; i < text.length && tried < 200; i++) {
      final c = text[i];
      if (c != '{' && c != '[') continue;
      final end = _balancedEnd(text, i);
      if (end <= i) continue;
      tried++;
      yield text.substring(i, end + 1);
    }
  }

  /// The index of the brace that closes the one at [start], skipping braces
  /// inside string literals and their escapes; -1 when it never closes.
  static int _balancedEnd(String text, int start) {
    final open = text[start];
    final close = open == '{' ? '}' : ']';
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// The start of whatever came back, so the reader (and a bug report) can see
  /// what the endpoint actually said instead of only that parsing failed.
  static String _snippet(String raw) {
    final flat = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return '（空）';
    return flat.length <= 180 ? flat : '${flat.substring(0, 180)}…';
  }


  /// Reads a list of sentences out of the model's answer.
  ///
  /// Accepts the asked-for `{"sentences":[…]}` shape, a bare array, and a
  /// single `{"text":…}` object — local models drift between all three.
  static List<GeneratedSentence> parseSentences(String raw) {
    final decoded = _decode(raw);
    final candidates = switch (decoded) {
      final List<Object?> list => list,
      final Map<Object?, Object?> map => switch (map['sentences']) {
        final List<Object?> list => list,
        _ => map['text'] != null ? <Object?>[map] : const <Object?>[],
      },
      _ => const <Object?>[],
    };

    final out = <GeneratedSentence>[];
    final seen = <String>{};
    for (final item in candidates) {
      final sentence = item is String
          ? GeneratedSentence(text: item.trim())
          : item is Map
              ? GeneratedSentence.fromJson(item.cast<String, dynamic>())
              : null;
      if (sentence == null || sentence.text.isEmpty) continue;
      if (!seen.add(sentence.text.toLowerCase())) continue;
      out.add(sentence);
    }
    return out;
  }

  static GeneratedPassage parsePassage(String raw) {
    final decoded = _decode(raw);
    if (decoded is! Map) {
      throw const AiException('模型返回的短文不是 JSON 对象');
    }
    final json = decoded.cast<String, dynamic>();
    final text = (json['text'] ?? json['passage'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    return GeneratedPassage(
      title: title.isEmpty ? 'Untitled' : title,
      text: text,
    );
  }
}
